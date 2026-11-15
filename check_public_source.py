#!/usr/bin/env python3
"""Check release paths and credentials in every reachable Git tree/blob."""
import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

TEXT = {'.md', '.py', '.js', '.swift', '.metal', '.plist', '.h', '.c', '.rs', '.sh',
        '.command', '.yml', '.yaml', '.toml', '.lock', '.modulemap', '.pbxproj',
        '.xcworkspacedata', '.xcscheme', '.txt'}
BAD_PARTS = {'local-only', '_next', 'node_modules', 'DerivedData', 'build',
             '__pycache__', 'xcuserdata', '.venv', '.git'}
PATTERNS = [
    ('private key', re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----')),
    ('GitHub token', re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9_]{30,}|github_pat_[A-Za-z0-9_]{30,})\b')),
    ('AWS access key', re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b')),
    ('Discord token', re.compile(r'\b(?:mfa\.[A-Za-z0-9_-]{50,}|[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,})\b')),
    ('literal credential', re.compile(r'''(?:client_secret|clientSecret|api_key|apiKey|access_token)\s*[:=]\s*["'][A-Za-z0-9+/_=-]{24,}["']''')),
]


def allowed(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or any(part in BAD_PARTS for part in path.parts):
        return False
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
    for directory in ('ios/App', 'ios/ZGTASA.xcodeproj', 'native-physics', 'native-menu-codec', 'test-fixtures/native-menu', '.github'):
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
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--directory', action='store_true', help='Check local release source without traversing Git history.')
    args = parser.parse_args()
    try:
        return audit(args.repository.resolve(), args.directory)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('Audit error: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
