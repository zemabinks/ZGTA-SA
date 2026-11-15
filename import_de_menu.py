#!/usr/bin/env python3
"""Import only the owner's supported DE menu resources into ignored local-only."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
from zipfile import BadZipFile, ZipFile
import zlib

sys.dont_write_bytecode = True
from de_menu_resources import (MAX_RESOURCE, MenuImportError, Pak, font_info,
                               require, texture_png, validate_wave)

ROOT = Path(__file__).resolve().parent
CODEC_ROOT = ROOT / "native-menu-codec"
CODEC_VERSION = "zgta-menu-codec 0.1.0 oozextract 0.5.7"
IMAGE_RESOURCES = {
    "logo": "SanAndreas/UI/Materials/T_UI_Logo_SA_TDE_BC",
    "background": "SanAndreas/UI/Materials/T_UI_PauseMenu_bg_BC",
    "portrait": "SanAndreas/UI/Materials/T_UI_PauseMenu_girl_BC",
    "selectedPlay": "Common/UI/Materials/T_UI_Button_Resume_BC",
    "selectedGame": "Common/UI/Materials/T_UI_Button_Game_BC",
    "selectedOptions": "Common/UI/Materials/T_UI_Button_Options_BC",
}
FONT_RESOURCES = {
    "menu": ("Common/Fonts/PRICEDOWN.ufont", "PricedownGTAVInt"),
    "body": ("Common/Fonts/arialbd.ufont", "Arial-BoldMT"),
}
SOUND_RESOURCES = {"start": "000", "back": "004", "highlight": "009", "tab": "006"}
SOUND_PREFIX = "SanAndreas/Audio/SFX/GENRL/FRONTEND_MENU/S_"


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class Decoder:
    def __init__(self, args):
        self.args, self.binary, self.report = args, None, None
        self.cache = ROOT / "local-only/menu-import-codec"
        self.work = None
        if args.decoder:
            # Preserve argv[0]/symlinks: Rustup proxies select a tool by name.
            self.binary = Path(args.decoder).expanduser().absolute()
            require(self.binary.is_file() and os.access(self.binary, os.X_OK),
                    f"Decoder is missing or not executable: {self.binary}")

    def ensure_available(self):
        if self.report is not None:
            return
        supplied = self.binary is not None
        if not supplied:
            signature = hashlib.sha256(b"".join((CODEC_ROOT / file).read_bytes()
                                       for file in ("Cargo.toml", "Cargo.lock", "src/main.rs"))).hexdigest()
            binary = self.cache / "target/release" / ("zgta-menu-codec.exe" if os.name == "nt" else "zgta-menu-codec")
            marker = self.cache / "build.json"
            try:
                previous = json.loads(marker.read_text())
            except (OSError, ValueError):
                previous = {}
            cached = binary.is_file() and previous.get("sourceSHA256") == signature and previous.get("binarySHA256") == digest_file(binary)
            if not cached:
                cargo = self.args.cargo or shutil.which("cargo")
                require(cargo is not None and not self.args.no_build_codec,
                        "Independent Oodle decoder unavailable. Pass --decoder PATH to a compatible independent helper, "
                        "or --cargo PATH to an existing Rust/Cargo installation. No toolchain is installed by this importer.")
                self.cache.mkdir(parents=True, exist_ok=True)
                command = [str(cargo), "build", "--locked", "--release", "--manifest-path", str(CODEC_ROOT / "Cargo.toml"),
                           "--target-dir", str(self.cache / "target")]
                if self.args.offline:
                    command.append("--offline")
                environment = dict(os.environ)
                environment["CARGO_HOME"] = str(Path(self.args.cargo_home).expanduser().absolute() if self.args.cargo_home else self.cache / "cargo-home")
                cargo_path = Path(cargo).expanduser().absolute()
                if cargo_path.parent.is_dir():
                    environment["PATH"] = str(cargo_path.parent) + os.pathsep + environment.get("PATH", "")
                print("Building only the independent menu decoder (locked oozextract 0.5.7)…", flush=True)
                try:
                    subprocess.run(command, cwd=ROOT, env=environment, check=True, timeout=600)
                except (OSError, subprocess.SubprocessError) as error:
                    raise MenuImportError("Menu decoder build failed. Use an existing Rust toolchain and available locked Cargo dependencies, "
                                          "or pass --decoder PATH. Physics libraries are not built.") from error
                require(binary.is_file(), "Cargo succeeded but the expected menu decoder executable is missing.")
                marker.write_text(json.dumps({"sourceSHA256": signature, "binarySHA256": digest_file(binary)}, indent=2) + "\n")
            self.binary = binary
            try:
                version = subprocess.check_output([str(binary), "--version"], text=True, timeout=10).strip()
            except (OSError, subprocess.SubprocessError) as error:
                raise MenuImportError("Independent menu decoder could not report its version; rebuild its local cache.") from error
            require(version == CODEC_VERSION, "Cached menu decoder has an unexpected version; remove its local build cache and retry.")
        self.report = {"kind": "caller-provided independent helper" if supplied else CODEC_VERSION,
                       "binarySHA256": digest_file(self.binary), "pinnedDependency": "oozextract =0.5.7 (MIT)" if not supplied else None}
        self.cache.mkdir(parents=True, exist_ok=True)
        self.work = tempfile.TemporaryDirectory(prefix="selected-block-", dir=self.cache)

    def decode(self, block, expected):
        require(0 < len(block) <= MAX_RESOURCE and 0 < expected <= MAX_RESOURCE, "Oodle block exceeds the selected-resource limit.")
        self.ensure_available()
        folder = Path(self.work.name)
        source, destination = folder / "input", folder / "output"
        source.write_bytes(block)
        destination.unlink(missing_ok=True)
        try:
            subprocess.run([str(self.binary), str(source), str(destination), str(expected)],
                           check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (OSError, subprocess.SubprocessError) as error:
            raise MenuImportError("Independent Oodle decoder rejected a selected block or timed out; the IPA may use an unsupported codec variant.") from error
        require(destination.is_file() and destination.stat().st_size == expected, "Oodle helper returned an incorrect decoded byte count.")
        return destination.read_bytes()

    def close(self):
        if self.work is not None:
            self.work.cleanup()


def validate_output(path):
    output = Path(path).expanduser().resolve()
    private = (ROOT / "local-only").resolve()
    require(output != private and output.is_relative_to(private),
            "--output must be a new directory below this source checkout's ignored local-only/ directory.")
    require(not output.exists(), f"Output already exists: {output}. Choose a new local-only directory; existing owner resources are never overwritten.")
    return output


def required_resources():
    return ([path + suffix for path in IMAGE_RESOURCES.values() for suffix in (".uasset", ".uexp")] +
            [path for path, _ in FONT_RESOURCES.values()] +
            [SOUND_PREFIX + number + ".m.ubulk" for number in SOUND_RESOURCES.values()])


def import_menu(args):
    output = validate_output(args.output)
    ipa = Path(args.ipa).expanduser().resolve()
    require(ipa.is_file(), f"IPA was not found: {ipa}")
    output.parent.mkdir(parents=True, exist_ok=True)
    decoder = Decoder(args)
    try:
        with tempfile.TemporaryDirectory(prefix=".owner-menu-staging-", dir=output.parent) as folder:
            stage = Path(folder) / "OwnerMenu"
            stage.mkdir()
            with ZipFile(ipa) as archive:
                infos = archive.infolist()
                require(len(infos) <= 100_000, "IPA has excessive ZIP members (limit 100000).")
                names = [info.filename for info in infos]
                require(len(names) == len(set(names)), "IPA contains duplicate ZIP member names.")
                paks = []
                for name in ("pakchunk0-ios.pak", "pakchunk1-ios.pak"):
                    candidates = [info for info in infos if info.filename.casefold().endswith("/cookeddata/gameface/content/paks/" + name)]
                    require(len(candidates) == 1, f"Expected exactly one {name} in the Gameface cooked-data folder; found {len(candidates)}.")
                    print(f"Validating {name} indexes…", flush=True)
                    paks.append(Pak(archive, candidates[0]))
                # Pak1 is the observed patch override; normalize its different mount.
                resolved = {}
                for pak in paks:
                    for key, entry in pak.entries.items():
                        resolved[key] = (pak, entry)
                selected = []
                for path in required_resources():
                    require(path.casefold() in resolved, f"Required menu resource is missing: {path}. This IPA variant is unsupported.")
                    selected.append(resolved[path.casefold()])
                require(sum(entry.size for _, entry in selected) <= 32 * 1024 * 1024, "Selected resources exceed the 32-MiB total limit.")
                resources = {}
                for pak in paks:
                    resources.update(pak.extract([entry for owner, entry in selected if owner is pak], decoder))
                manifest = {"formatVersion": 1, "importer": "zgta-de-menu-1", "images": {}, "fonts": {}, "sounds": {}}
                report = {"scope": "Static selected menu data only; no game executable, engine, decryption or runtime execution",
                          "artifactSHA256": digest_file(ipa), "indexes": [pak.report for pak in paks],
                          "resources": [resources[key][1] for key in sorted(resources)], "outputs": {}}

                def write(name, data, details):
                    (stage / name).write_bytes(data)
                    report["outputs"][name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), **details}

                for role, path in IMAGE_RESOURCES.items():
                    asset = resources[(path + ".uasset").casefold()][0]
                    data = resources[(path + ".uexp").casefold()][0]
                    png, details = texture_png(asset, data)
                    name = role + ".png"
                    write(name, png, details)
                    manifest["images"][role] = name
                for role, (path, postscript) in FONT_RESOURCES.items():
                    data = resources[path.casefold()][0]
                    details = font_info(data, postscript)
                    name = role + details["extension"]
                    write(name, data, {"postScriptName": postscript})
                    manifest["fonts"][role] = {"file": name, "postScriptName": postscript}
                for role, number in SOUND_RESOURCES.items():
                    data = resources[(SOUND_PREFIX + number + ".m.ubulk").casefold()][0]
                    name = role + ".wav"
                    write(name, data, validate_wave(data))
                    manifest["sounds"][role] = name
                report["decoder"] = decoder.report
                manifest["sourceSHA256"] = report["artifactSHA256"]
                (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
                (stage / "import-report.json").write_text(json.dumps(report, indent=2) + "\n")
            require(not output.exists(), "Output appeared during import; refusing to overwrite it.")
            os.rename(stage, output)
        print(f"Imported {len(resources)} validated resources → {output}\nManifest: {output / 'manifest.json'}", flush=True)
        return report
    finally:
        decoder.close()


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--ipa", required=True, help="Owner-supplied compatible unencrypted GTA SA DE IPA")
    result.add_argument("--output", required=True, help="NEW directory under this checkout's local-only/ (e.g. local-only/menu-bundle/OwnerMenu)")
    result.add_argument("--decoder", "--codec", help="Existing independent INPUT OUTPUT EXACT_SIZE decoder; avoids Cargo builds")
    result.add_argument("--cargo", help="Existing Cargo executable; never installs a toolchain")
    result.add_argument("--cargo-home", help="Caller-selected Cargo registry cache (default: private local-only cache)")
    result.add_argument("--offline", action="store_true", help="Require cached locked dependencies when building the codec")
    result.add_argument("--no-build-codec", action="store_true", help="Fail instead of building a missing independent codec")
    return result


def main():
    args = parser().parse_args()
    try:
        import_menu(args)
    except (MenuImportError, BadZipFile, OSError, EOFError, zlib.error) as error:
        print(f"Menu import failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
