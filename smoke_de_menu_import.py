#!/usr/bin/env python3
"""Synthetic format/integrity gates; optional actual owner-IPA import comparison."""
import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile, ZIP_DEFLATED
import zlib

sys.dont_write_bytecode = True
import import_de_menu as importer
from de_menu_resources import (MenuImportError, Pak, Reader, canonical_path,
                               font_info, texture_png, validate_wave)

ROOT = Path(__file__).resolve().parent


def string(value):
    data = value.encode() + b"\0"
    return struct.pack("<i", len(data)) + data


def texture(color=31):
    asset = bytes.fromhex("c1832a9e") + bytes(60)
    pixels = bytes([color, 80, 170, 0, 20, 40, 60, 128, 1, 2, 3, 255, 9, 8, 7, 255])
    data = (struct.pack("<4i", 2, 2, 1, 12) + b"PF_B8G8R8A8\0" +
            struct.pack("<6iq", 0, 1, 1, 0x48, 16, 16, len(asset) + 60) +
            pixels + struct.pack("<3i", 2, 2, 1) + bytes(12) + bytes.fromhex("c1832a9e"))
    return asset, data


def font(name, opentype=False):
    value = name.encode("utf-16be")
    names = struct.pack(">3H6H", 0, 1, 18, 3, 1, 0x409, 6, len(value), 0) + value
    return struct.pack(">4s4H", b"OTTO" if opentype else b"\0\1\0\0", 1, 0, 0, 0) + struct.pack(">4sIII", b"name", 0, 28, len(names)) + names


def wave():
    fmt = struct.pack("<HHIIHHHHHhh", 2, 1, 22050, 11025, 8, 4, 8, 4, 1, 256, 0)
    body = b"WAVEfmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", 8) + bytes(8)
    return b"RIFF" + struct.pack("<I", len(body)) + body


def pak(rows, mount="../../../", fault=None):
    """Build our own tiny v11 archive data; contains no game bytes."""
    payload, encoded, directories = bytearray(), bytearray(), {}
    for n, (name, original) in enumerate(rows):
        method = 1 if n % 2 else 0
        data = zlib.compress(original) if method else original
        size = len(original) + (1 if fault == "decoded-size" and n == 1 else 0)
        header_size = 73 if method else 53
        sha = hashlib.sha1(data).digest()
        header = struct.pack("<QQQI", 0, len(data), size, method) + sha
        if method:
            header += struct.pack("<IQQ", 1, header_size, header_size + len(data))
        header += struct.pack("<BI", 1 if fault == "entry-encrypted" and n == 0 else 0, size if method else 0)
        start = len(payload)
        payload.extend(header + data)
        if n == 0 and fault == "payload-hash":
            payload[header_size] ^= 1
        if n == 0 and fault == "header-size":
            struct.pack_into("<Q", payload, 16, size + 1)
        index = len(encoded)
        bits = (1 << 31) | (1 << 30) | ((1 << 29) | (1 << 23) | (1 << 6) if method else 0)
        if fault == "entry-encrypted" and n == 0:
            bits |= 1 << 22
        encoded.extend(struct.pack("<III", bits, start, size))
        if method:
            encoded.extend(struct.pack("<I", len(data)))
        folder, _, file = name.rpartition("/")
        directories.setdefault(folder + "/" if folder else "", []).append((file, index))
    directory = struct.pack("<i", len(directories))
    for folder, files in directories.items():
        directory += string(folder) + struct.pack("<i", len(files))
        for name, index in files:
            directory += string(name) + struct.pack("<i", index)
    hashes = b"synthetic path-hash region"

    def primary(path_offset, dir_offset):
        result = string(mount) + struct.pack("<iQ", len(rows), 0)
        for offset, data in [(path_offset, hashes), (dir_offset, directory)]:
            result += struct.pack("<iQQ", 1, offset, len(data)) + hashlib.sha1(data).digest()
        return result + struct.pack("<i", len(encoded)) + encoded + struct.pack("<i", 0)

    index_offset = len(payload)
    size = len(primary(0, 0))
    index = primary(index_offset + size, index_offset + size + len(hashes))
    payload.extend(index + hashes + directory)
    footer = (bytes(16) + bytes([1 if fault == "index-encrypted" else 0]) +
              struct.pack("<IIQQ", 0x5a6f12e1, 12 if fault == "version" else 11, index_offset, len(index)) +
              hashlib.sha1(index).digest() + b"Zlib".ljust(32, b"\0") + b"Oodle".ljust(32, b"\0") + bytes(96))
    if fault == "primary-hash":
        payload[index_offset] ^= 1
    if fault == "secondary-hash":
        payload[index_offset + size] ^= 1
    return bytes(payload) + footer


def resources():
    base, patch_rows = {}, {}
    for path in importer.IMAGE_RESOURCES.values():
        asset, data = texture()
        base[path + ".uasset"], base[path + ".uexp"] = asset, data
    logo = importer.IMAGE_RESOURCES["logo"]
    patch_rows[logo + ".uasset"], patch_rows[logo + ".uexp"] = texture(231)
    for role, (path, name) in importer.FONT_RESOURCES.items():
        patch_rows[path] = font(name)
    base[importer.FONT_RESOURCES["menu"][0]] = font("WrongBaseFont")
    for number in importer.SOUND_RESOURCES.values():
        patch_rows[importer.SOUND_PREFIX + number + ".m.ubulk"] = wave()
    return base, patch_rows


class ImportTests(unittest.TestCase):
    def setUp(self):
        private = ROOT / "local-only/menu-import-tests"
        private.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="synthetic-", dir=private)
        self.folder = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def ipa(self, fault=None, missing=False):
        base, patched = resources()
        if missing:
            del patched[importer.FONT_RESOURCES["body"][0]]
        # Faults must affect selected bytes, rather than the base logo that
        # correctly gets ignored when the patch overrides it.
        ordered = sorted(base.items(), key=lambda row: not row[0].startswith(importer.IMAGE_RESOURCES["background"]))
        first = pak([("Gameface/Content/" + path, data) for path, data in ordered], fault=fault)
        second = pak(list(patched.items()), "../../../Gameface/Content/")
        file = self.folder / "synthetic.ipa"
        with ZipFile(file, "w", compression=ZIP_DEFLATED) as archive:
            prefix = "Payload/Gameface.app/cookeddata/gameface/content/paks/"
            archive.writestr(prefix + "pakchunk0-ios.pak", first)
            archive.writestr(prefix + "pakchunk1-ios.pak", second)
            archive.writestr("Payload/Gameface.app/Gameface", b"UNREAD synthetic executable carrier")
        return file

    def run_import(self, ipa=None, output=None):
        args = importer.parser().parse_args(["--ipa", str(ipa or self.ipa()), "--output", str(output or self.folder / "OwnerMenu"), "--no-build-codec"])
        with contextlib.redirect_stdout(io.StringIO()):
            return importer.import_menu(args)

    def test_end_to_end_override_and_pixels(self):
        report = self.run_import()
        output = self.folder / "OwnerMenu"
        manifest = json.loads((output / "manifest.json").read_text())
        self.assertEqual(len(report["resources"]), 18)
        self.assertEqual(set(manifest["images"]), set(importer.IMAGE_RESOURCES))
        self.assertEqual(set(manifest["sounds"]), set(importer.SOUND_RESOURCES))
        self.assertEqual(manifest["fonts"]["menu"]["postScriptName"], "PricedownGTAVInt")
        self.assertEqual((output / "menu.ttf").read_bytes(), font("PricedownGTAVInt"))
        png = (output / "logo.png").read_bytes()
        position, idat = 8, b""
        while position < len(png):
            size, tag = struct.unpack_from(">I4s", png, position)
            data = png[position + 8:position + 8 + size]
            self.assertEqual(struct.unpack_from(">I", png, position + 8 + size)[0], zlib.crc32(tag + data))
            if tag == b"IDAT": idat += data
            position += 12 + size
        pixels = zlib.decompress(idat)
        self.assertEqual(pixels[:9], bytes([0, 170, 80, 231, 0, 60, 40, 20, 128]))
        self.assertEqual((output / "start.wav").read_bytes(), wave())
        self.assertEqual(len(list(output.iterdir())), 14)
        self.assertEqual(next(r["pak"] for r in report["resources"] if r["path"].endswith("PRICEDOWN.ufont")), "pakchunk1-ios.pak")

    def test_integrity_and_unsupported_boundaries(self):
        for fault, message in [("primary-hash", "primary index SHA1"), ("secondary-hash", "path hash index SHA1"),
                               ("payload-hash", "payload SHA1"), ("header-size", "physical header disagrees"),
                               ("index-encrypted", "encrypted Pak index"), ("entry-encrypted", "encrypted resource"),
                               ("version", "version 12"), ("decoded-size", "decoded block differs")]:
            with self.subTest(fault=fault):
                output = self.folder / ("OwnerMenu-" + fault)
                with self.assertRaisesRegex(MenuImportError, message):
                    self.run_import(self.ipa(fault), output=output)
                self.assertFalse(output.exists())
                self.assertFalse(list(self.folder.glob(".owner-menu-staging-*")))

    def test_missing_resource(self):
        with self.assertRaisesRegex(MenuImportError, "arialbd.ufont"):
            self.run_import(self.ipa(missing=True))

    def test_output_and_paths(self):
        for value in [ROOT / "OwnerMenu", ROOT / "local-only"]:
            with self.assertRaisesRegex(MenuImportError, "--output"):
                importer.validate_output(value)
        output = self.folder / "existing"
        output.mkdir(); (output / "keep").write_text("untouched")
        with self.assertRaisesRegex(MenuImportError, "already exists"):
            self.run_import(output=output)
        self.assertEqual((output / "keep").read_text(), "untouched")
        link = self.folder / "escape"
        link.symlink_to(ROOT, target_is_directory=True)
        with self.assertRaisesRegex(MenuImportError, "--output"):
            importer.validate_output(link / "OwnerMenu")
        for path in ["../x", "/x", "Common/../x", "Common\\x", "Common//x"]:
            with self.assertRaises(MenuImportError): canonical_path("../../../", path)

    def test_bounded_fields(self):
        for data in [struct.pack("<i", 5000), struct.pack("<i", 4) + b"abc", struct.pack("<i", -2) + b"a\0b\0"]:
            with self.assertRaises(MenuImportError): Reader(data).string()
        with self.assertRaises(MenuImportError): Reader(b"\2\0\0\0").boolean()

    def test_texture_font_wave_fail_closed(self):
        asset, data = texture()
        for broken in [data[:-5], data.replace(b"PF_B8G8R8A8", b"PF_Unknown"), data[:52] + struct.pack("<q", 0) + data[60:]]:
            with self.assertRaises(MenuImportError): texture_png(asset, broken)
        with self.assertRaises(MenuImportError): texture_png(b"bad", data)
        with self.assertRaises(MenuImportError): font_info(font("Other"), "PricedownGTAVInt")
        with self.assertRaises(MenuImportError): font_info(font("OK")[:-1], "OK")
        self.assertEqual(font_info(font("OK", True), "OK")["extension"], ".otf")
        for broken in [wave()[:-1], b"not wave", wave().replace(b"WAVE", b"NOPE")]:
            with self.assertRaises(MenuImportError): validate_wave(broken)

    def test_decoder_unavailable_and_invalid_output(self):
        args = importer.parser().parse_args(["--ipa", "unused", "--output", "unused", "--no-build-codec"])
        with patch.object(importer, "ROOT", self.folder):
            decoder = importer.Decoder(args)
            with self.assertRaisesRegex(MenuImportError, "decoder unavailable"): decoder.decode(b"fake", 4)
        tool = self.folder / "bad-decoder"
        tool.write_text("#!/usr/bin/env python3\nimport pathlib,sys\npathlib.Path(sys.argv[2]).write_bytes(b'bad')\n")
        tool.chmod(0o700)
        args.decoder = str(tool)
        decoder = importer.Decoder(args)
        try:
            with self.assertRaisesRegex(MenuImportError, "incorrect decoded byte count"): decoder.decode(b"fake", 4)
        finally: decoder.close()


def actual_reference(args):
    command = ["--ipa", args.ipa, "--output", args.output]
    for key in ("decoder", "cargo", "cargo_home"):
        if getattr(args, key): command += ["--" + key.replace("_", "-"), getattr(args, key)]
    if args.offline: command += ["--offline"]
    report = importer.import_menu(importer.parser().parse_args(command))
    if args.reference:
        reference = Path(args.reference)
        textures = json.loads((reference / "actual-texture-report.json").read_text())
        by_name = {Path(item["png_path"]).stem: item for item in textures}
        for role, path in importer.IMAGE_RESOURCES.items():
            old = by_name[Path(path).name]
            current = report["outputs"][role + ".png"]
            assert current["sha256"] == old["png_sha256"], role
            assert current["sourcePixelSHA256"] == old["pixel_sha256"], role
        fonts = {Path(item["path"]).name: item for item in json.loads((reference / "actual-font-report.json").read_text())}
        for role, (path, _) in importer.FONT_RESOURCES.items():
            assert report["outputs"][role + ".ttf"]["sha256"] == fonts[Path(path).name]["sha256"], role
        sounds = {Path(item["virtual_path"]).name: item for item in json.loads((reference / "frontend-wave-report.json").read_text())}
        for role, number in importer.SOUND_RESOURCES.items():
            assert report["outputs"][role + ".wav"]["sha256"] == sounds["S_" + number + ".m.ubulk"]["sha256"], role
        print("PASS actual owner IPA: six PNG+pixel hashes, two byte-identical SFNT fonts and four unchanged ADPCM WAVs match prior independent evidence")
    else:
        print("PASS actual owner IPA structural/integrity/size gates; SKIP prior-evidence comparison (no --reference)")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--ipa"); cli.add_argument("--output"); cli.add_argument("--reference")
    cli.add_argument("--decoder"); cli.add_argument("--cargo"); cli.add_argument("--cargo-home")
    cli.add_argument("--offline", action="store_true")
    options = cli.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ImportTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful(): raise SystemExit(1)
    if options.ipa:
        cli.error("--output is required with --ipa") if not options.output else actual_reference(options)
    else:
        print("SKIP owner IPA gate: provide --ipa and a new local-only --output; synthetic tests always run")
