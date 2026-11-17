#!/usr/bin/env python3
"""Prove a deleted private file remains caught by the public-history check."""
from pathlib import Path
import subprocess
import sys
import tempfile
import importlib.util

CHECK = Path(__file__).resolve().parent / 'check_public_source.py'


def main():
    spec = importlib.util.spec_from_file_location('release_guard', CHECK)
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    assert not guard.allowed('smoke_selfhost_vehicle_seats_browser.js')
    assert not guard.allowed('tests/smoke_selfhost_vehicle_seats_browser.js')
    with tempfile.TemporaryDirectory(prefix='zgta-release-history-') as temporary:
        root = Path(temporary)

        def git(*args):
            return subprocess.run(['git', '-C', str(root), *args], check=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        git('init')
        git('config', 'user.name', 'Release fixture')
        git('config', 'user.email', 'fixture@example.invalid')
        (root / 'README.md').write_text('# Synthetic release fixture\n')
        git('add', 'README.md')
        git('commit', '-m', 'Clean source')
        good = subprocess.run([sys.executable, str(CHECK), '--repository', str(root)], capture_output=True, text=True)
        assert good.returncode == 0, good.stderr
        private = root / 'local-only/selfhost/players.json'
        private.parent.mkdir(parents=True)
        private.write_text('{"players":{}}')
        git('add', '.')
        git('commit', '-m', 'Synthetic private file')
        git('rm', str(private.relative_to(root)))
        git('commit', '-m', 'Remove private file')
        bad = subprocess.run([sys.executable, str(CHECK), '--repository', str(root)], capture_output=True, text=True)
        assert bad.returncode == 1 and 'private path in history' in bad.stderr
        print('PASS release guard rejects private files even after deletion from the latest commit')


if __name__ == '__main__':
    main()
