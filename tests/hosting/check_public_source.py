#!/usr/bin/env python3
"""Check release paths and credentials in every reachable Git tree/blob."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

TEXT = {'.md', '.py', '.js', '.swift', '.metal', '.plist', '.h', '.c', '.cpp', '.hpp', '.pwn', '.rs', '.sh',
        '.command', '.yml', '.yaml', '.toml', '.lock', '.modulemap', '.pbxproj',
        '.xcworkspacedata', '.xcscheme', '.txt', '.go', '.mod'}
# This owner-only carrier executes archived client code and stays outside releases.
PRIVATE_SOURCE_NAMES = {'CORE_PED_SAMPLING_120.md','CORE_PED_SAMPLING_CONSUMER_120.md','CORE_SAMPLER_GPU_120.md','CORE_STOCK_SAMPLER_120.md',
                        'smoke_selfhost_vehicle_seats_browser.js',
                        'test_native_actor_resources.py', 'test_native_prepared_runtime.py',
                        'test_native_vehicle_occupants.py'}
BAD_PARTS = {'local-only', '_next', 'node_modules', 'DerivedData', 'build',
             '__pycache__', 'xcuserdata', '.venv', '.git'}
# Keep this independently authored bridge and its pinned MIT subset explicit.
# In particular, admitting its two provenance/patch JSON files must not admit
# archive inventories, owner fixtures, assets or additional vendored payloads.
NATIVE_INSTALLER_SOURCE = {
    'README.md', 'NOTICE.md',
    'include/module.modulemap', 'include/zgtasa_installer.h',
    'src/zgtasa_installer.c', 'src/md5/global.h', 'src/md5/md5.h',
    'swift/NativeISOExtraction.swift', 'swift/NativeRawResourceSelection.swift',
    'tests/link.swift', 'tests/main.swift', 'tests/sanitize.c', 'tests/split.swift',
    'patches/unsigned-le32.json',
    'vendor/unshield/LICENSE', 'vendor/unshield/PROVENANCE.json',
    'vendor/unshield/lib/cabfile.h', 'vendor/unshield/lib/component.c',
    'vendor/unshield/lib/converter.c', 'vendor/unshield/lib/converter.h',
    'vendor/unshield/lib/directory.c', 'vendor/unshield/lib/file.c',
    'vendor/unshield/lib/file_group.c', 'vendor/unshield/lib/helper.c',
    'vendor/unshield/lib/internal.h', 'vendor/unshield/lib/libunshield.c',
    'vendor/unshield/lib/libunshield.h', 'vendor/unshield/lib/log.c',
    'vendor/unshield/lib/log.h',
}
# Explicit independent decoder, pinned BSD source/licenses and authored tests.
# The two JSON paths are source provenance/one upstream patch, not audio data.
NATIVE_AUDIO_SOURCE = {
    'README.md',
    'THIRD_PARTY_NOTICES.md',
    'build.py',
    'include/module.modulemap',
    'include/zgtasa_native_audio.h',
    'patches/vorbis-sharedbook-unsigned.json',
    'src/codec_alloc.h',
    'src/zgtasa_native_audio.c',
    'tools/radio_wav.c',
    'tests/api.c',
    'tests/archive.swift',
    'tests/fixtures.py',
    'tests/window.c',
    'vendor/libogg-1.3.6/COPYING',
    'vendor/libogg-1.3.6/include/ogg/ogg.h',
    'vendor/libogg-1.3.6/include/ogg/os_types.h',
    'vendor/libogg-1.3.6/src/bitwise.c',
    'vendor/libogg-1.3.6/src/crctable.h',
    'vendor/libogg-1.3.6/src/framing.c',
    'vendor/libvorbis-1.3.7/COPYING',
    'vendor/libvorbis-1.3.7/include/vorbis/codec.h',
    'vendor/libvorbis-1.3.7/include/vorbis/vorbisfile.h',
    'vendor/libvorbis-1.3.7/lib/analysis.c',
    'vendor/libvorbis-1.3.7/lib/backends.h',
    'vendor/libvorbis-1.3.7/lib/bitrate.c',
    'vendor/libvorbis-1.3.7/lib/bitrate.h',
    'vendor/libvorbis-1.3.7/lib/block.c',
    'vendor/libvorbis-1.3.7/lib/codebook.c',
    'vendor/libvorbis-1.3.7/lib/codebook.h',
    'vendor/libvorbis-1.3.7/lib/codec_internal.h',
    'vendor/libvorbis-1.3.7/lib/envelope.c',
    'vendor/libvorbis-1.3.7/lib/envelope.h',
    'vendor/libvorbis-1.3.7/lib/floor0.c',
    'vendor/libvorbis-1.3.7/lib/floor1.c',
    'vendor/libvorbis-1.3.7/lib/highlevel.h',
    'vendor/libvorbis-1.3.7/lib/info.c',
    'vendor/libvorbis-1.3.7/lib/lookup.c',
    'vendor/libvorbis-1.3.7/lib/lookup.h',
    'vendor/libvorbis-1.3.7/lib/lookup_data.h',
    'vendor/libvorbis-1.3.7/lib/lpc.c',
    'vendor/libvorbis-1.3.7/lib/lpc.h',
    'vendor/libvorbis-1.3.7/lib/lsp.c',
    'vendor/libvorbis-1.3.7/lib/lsp.h',
    'vendor/libvorbis-1.3.7/lib/mapping0.c',
    'vendor/libvorbis-1.3.7/lib/masking.h',
    'vendor/libvorbis-1.3.7/lib/mdct.c',
    'vendor/libvorbis-1.3.7/lib/mdct.h',
    'vendor/libvorbis-1.3.7/lib/misc.h',
    'vendor/libvorbis-1.3.7/lib/os.h',
    'vendor/libvorbis-1.3.7/lib/psy.c',
    'vendor/libvorbis-1.3.7/lib/psy.h',
    'vendor/libvorbis-1.3.7/lib/registry.c',
    'vendor/libvorbis-1.3.7/lib/registry.h',
    'vendor/libvorbis-1.3.7/lib/res0.c',
    'vendor/libvorbis-1.3.7/lib/scales.h',
    'vendor/libvorbis-1.3.7/lib/sharedbook.c',
    'vendor/libvorbis-1.3.7/lib/smallft.c',
    'vendor/libvorbis-1.3.7/lib/smallft.h',
    'vendor/libvorbis-1.3.7/lib/synthesis.c',
    'vendor/libvorbis-1.3.7/lib/vorbisfile.c',
    'vendor/libvorbis-1.3.7/lib/window.c',
    'vendor/libvorbis-1.3.7/lib/window.h',
    'vendor/provenance.json',
}
PATTERNS = [
    ('private key', re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')),
    ('GitHub token', re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{30,})\b')),
    ('AWS access key', re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b')),
    ('Discord token', re.compile(r'\b(?:mfa\.[A-Za-z0-9_-]{50,}|[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,})\b')),
    ('literal credential', re.compile(r'''(?:client_secret|clientSecret|api_key|apiKey|access_token)\s*[:=]\s*["'][A-Za-z0-9+/_=-]{24,}["']''')),
]


def allowed(name):
    path = PurePosixPath(name)
    if path.name in PRIVATE_SOURCE_NAMES:
        return False
    if path.is_absolute() or '..' in path.parts or any(part in BAD_PARTS for part in path.parts):
        return False
    if path.parts and path.parts[0] == 'native-installer':
        return path.relative_to('native-installer').as_posix() in NATIVE_INSTALLER_SOURCE
    if path.parts and path.parts[0] == 'native-audio':
        return path.relative_to('native-audio').as_posix() in NATIVE_AUDIO_SOURCE
    if path.name in ('.gitignore', 'LICENSE'):
        return True
    if any(part.startswith('.env') for part in path.parts):
        return False
    if path.suffix in ('.png', '.jpg', '.json'):
        return (str(path).startswith('ios/App/Assets.xcassets/') or
                str(path) == 'test-fixtures/native-menu/core84-responder-handlers.json')
    if path.suffix == '.txt':
        return path.name == 'requirements-native.txt'
    return path.suffix in TEXT


def problems(name, data):
    if not allowed(name):
        return ['non-source or private path']
    if name.endswith(('.png', '.jpg')):
        # Only project-authored menu/icon assets in the explicit Xcode folder.
        return [] if len(data) <= 2_000_000 else ['unexpectedly large app image']
    if b'\x00' in data:
        return ['binary data in source file']
    try:
        source = data.decode('utf-8')
    except UnicodeDecodeError:
        return ['source is not UTF-8']
    return [label for label, pattern in PATTERNS if pattern.search(source)]


def source_files(root):
    """The release allowlist never walks the local archive or toolchain."""
    for path in sorted(root.iterdir()):
        if path.is_file() and allowed(path.name):
            yield path
    if (root / 'ios').is_dir():
        for path in sorted((root / 'ios').iterdir()):
            if path.is_file() and allowed(path.relative_to(root).as_posix()):
                yield path
    for directory in ('ios/App', 'ios/ZGTASA.xcodeproj', 'native-physics', 'native-samp', 'native-menu-codec', 'native-installer', 'native-audio', 'tests', 'tools', 'docs', 'test-fixtures/native-menu', '.github'):
        base = root / directory
        if base.is_dir():
            for path in sorted(base.rglob('*')):
                if path.is_file() and not any(part in BAD_PARTS for part in path.relative_to(root).parts):
                    yield path


def git(root, *arguments):
    return subprocess.check_output(['git', '-C', str(root), *arguments])


def audit(root, directory=False):
    failures = []
    count = 0
    if directory:
        for path in source_files(root):
            name = path.relative_to(root).as_posix()
            found = ['symbolic link'] if path.is_symlink() else problems(name, path.read_bytes())
            failures.extend((name, reason) for reason in found)
            count += 1
    else:
        if not (root / '.git').exists():
            raise ValueError('Choose the repository root, or use --directory for a source-only workspace check.')
        trees = set(git(root, 'log', '--format=%T', '--all').decode().splitlines())
        objects = {}
        for tree in trees:
            for record in git(root, 'ls-tree', '-r', '-z', tree).split(b'\0'):
                if not record:
                    continue
                metadata, raw_name = record.split(b'\t', 1)
                mode, kind, sha = metadata.decode().split()
                name = raw_name.decode('utf-8')
                if mode == '120000' or kind != 'blob':
                    failures.append((name, 'symbolic link or submodule'))
                elif not allowed(name):
                    failures.append((name, 'non-source or private path in history'))
                else:
                    objects[(sha, name)] = True
        cache = {}
        for sha, name in objects:
            if sha not in cache:
                cache[sha] = git(root, 'cat-file', 'blob', sha)
            failures.extend((name, reason) for reason in problems(name, cache[sha]))
        count = len(cache)
    for name, reason in sorted(set(failures)):
        # Never print a credential's value.
        print('FAIL ' + name + ': ' + reason, file=sys.stderr)
    print(('FAIL' if failures else 'PASS') + ': checked ' + str(count) + ' source blobs')
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--directory', action='store_true', help='Check local release source without traversing Git history.')
    args = parser.parse_args()
    try:
        return audit(args.repository.resolve(), args.directory)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('Audit error: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
