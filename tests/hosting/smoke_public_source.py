#!/usr/bin/env python3
"""Prove a deleted private file remains caught by the public-history check."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess
import sys
import tempfile
import importlib.util
import contextlib
import io

CHECK = Path(__file__).resolve().parents[2] / 'tests/hosting/check_public_source.py'


def main():
    spec = importlib.util.spec_from_file_location('release_guard', CHECK)
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    assert not guard.allowed('smoke_selfhost_vehicle_seats_browser.js')
    assert not guard.allowed('tests/smoke_selfhost_vehicle_seats_browser.js')
    assert guard.allowed('native-audio/vendor/libvorbis-1.3.7/COPYING')
    assert guard.allowed('native-audio/vendor/libvorbis-1.3.7/lib/sharedbook.c')
    assert guard.allowed('native-audio/vendor/provenance.json')
    assert guard.allowed('native-audio/tools/radio_wav.c')
    assert guard.allowed('native-audio/patches/vorbis-sharedbook-unsigned.json')
    for name in ['native-audio/tools/recording.wav', 'native-audio/tools/owner.json',
                 'native-audio/tools/original.c', 'native-audio/owner.json', 'native-audio/recording.ogg',
                 'native-audio/vendor/libvorbis-1.3.7/recording.c',
                 'native-audio/tests/original-track.bin', 'local-only/native-audio/source-stamp.json']:
        assert not guard.allowed(name), name
    with tempfile.TemporaryDirectory(prefix='zgta-release-nested-server-') as temporary:
        root = Path(temporary)
        (root / 'README.md').write_text('# Authored source fixture\n')
        server = root / 'server/population'
        server.mkdir(parents=True)
        (server / 'tasks.js').write_text('module.exports = {};\n')
        found = {path.relative_to(root).as_posix() for path in guard.source_files(root)}
        assert 'server/population/tasks.js' in found, 'Directory audit skipped nested server source'
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            assert guard.audit(root, directory=True) == 0
            hidden = server / 'hidden.js'
            hidden.write_bytes(b'authored binary sentinel\x00')
            assert guard.audit(root, directory=True) == 1, 'Nested binary source escaped release guard'
            hidden.unlink()
            private = server / 'players.json'
            private.write_text('{}')
            assert guard.audit(root, directory=True) == 1, 'Nested private file escaped release guard'
            private.unlink()
            outside = root / 'outside.js'
            outside.write_text('module.exports = {};\n')
            linked = server / 'linked.js'
            linked.symlink_to(outside)
            assert guard.audit(root, directory=True) == 1, 'Nested symbolic link escaped release guard'
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
