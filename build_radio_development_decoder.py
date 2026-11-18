#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Link the small Mac radio exporter against an already verified native library.

No dependencies are installed, downloaded or rebuilt. Output must be a new
regular directory beneath this checkout's ignored local-only directory.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, platform, subprocess, sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('radio_build', ROOT / 'native-audio/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--library-root', type=Path, default=ROOT / 'local-only/native-audio/targets')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = build.private_output(args.output)
    if output.exists():
        parser.error('Choose a new output directory')
    host = 'macos-arm64' if platform.machine() == 'arm64' else 'macos-x86_64'
    folder = build.private_output(args.library_root) / host
    library = folder / 'libzgtasa_native_audio.a'
    metadata = folder / 'source-stamp.json'
    for file in (library, metadata):
        build.check_regular(file)
    stamp = json.loads(metadata.read_text())
    sources = build.source_hashes()
    identity = hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if stamp['sourceHashes'] != sources or stamp['sourceStamp'] != identity or stamp['target'] != build.TARGETS[host][1] or stamp['sanitizers'] or build.sha(library) != stamp['librarySHA256']:
        raise ValueError('Native audio library does not match the current verified host sources')
    tool = ROOT / 'native-audio/tools/radio_wav.c'
    build.check_regular(tool)
    before = build.sha(tool)
    output.mkdir(parents=True)
    executable = output / 'radio-wav'
    command = ['xcrun', 'clang', '-std=gnu11', '-O2', '-Wall', '-Wextra', '-Werror',
               '-DEXPECTED_SOURCE_STAMP="' + identity + '"', '-I', str(ROOT / 'native-audio/include'),
               str(tool), str(library), '-lm', '-o', str(executable)]
    result = subprocess.run(command, capture_output=True, timeout=120)
    (output / 'build.log').write_bytes(result.stdout + result.stderr)
    result.check_returncode()
    if before != build.sha(tool) or sources != build.source_hashes():
        raise ValueError('Radio decoder sources changed while linking')
    report = dict(passed=True, host=host, sourceStamp=identity, toolSHA256=before,
                  executable=str(executable), executableSHA256=build.sha(executable), librarySHA256=build.sha(library),
                  scope='One host executable link; existing verified native library reused; no server or audio device')
    (output / 'build-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))

if __name__ == '__main__':
    main()
