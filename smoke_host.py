#!/usr/bin/env python3
"""Exercise a fresh host with synthetic assets and private temporary saves."""
import http.client
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent


def request(port, path, method='GET', body=None, headers=None):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=2)
    try:
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()


def port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        return listener.getsockname()[1]


def main():
    spec = importlib.util.spec_from_file_location('zgta_host', ROOT / 'host.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for bad in ('https://host.example', 'host.example/path', 'user@host.example', 'host:99999'):
        try:
            module.authority(bad)
        except Exception:
            pass
        else:
            raise AssertionError('An invalid Host header was accepted')
    assert module.authority('play.example.com') == 'play.example.com'
    with tempfile.TemporaryDirectory(prefix='zgta-host-') as temporary:
        root = Path(temporary)
        for name in ('host.py', 'serve_local.js', 'native_resource_server.js', 'selfhost_backend.js',
                     'optional_discord.js', 'weapon_inventory.js', 'world_collision.js',
                     'local_projectiles.js', 'local_gameplay.js', 'native_radio_server.js',
                     'radio_streams.js', 'prepare_native_radio_audio.py',
                     'stock_native_assets.js', 'stock_img_assets.js'):
            shutil.copy2(ROOT / name, root / name)
        result = subprocess.run([sys.executable, str(root / 'host.py'), 'doctor'],
                                capture_output=True, text=True)
        assert result.returncode != 0 and 'Local game content is missing' in result.stderr
        site = root / 'local-only/site'
        (site / 'game/world').mkdir(parents=True)
        (site / '_next/static/chunks').mkdir(parents=True)
        (site / 'index.html').write_text('<!doctype html><html><body><h1>Synthetic test world</h1></body></html>')
        (site / 'game/world/index.json').write_text('{"water":[],"tiles":[]}')
        (site / 'game/world/collision.json').write_text('{"cells":[]}')
        (site / '_next/static/chunks/fixture.js').write_text('// synthetic fixture; no publisher code')
        state = root / 'local-only/selfhost'
        state.mkdir()
        (state / 'client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
        subprocess.run([sys.executable, str(root / 'host.py'), 'doctor'], check=True)
        environment = dict(os.environ, ZGTA_CONNECTED='1', ZGTA_JOIN_CODE='stale-shell-code',
                           ZGTA_SOURCE_URL='https://source.example/my-fork')

        def start(arguments):
            number = port()
            child = subprocess.Popen([sys.executable, str(root / 'host.py'), 'serve',
                                      '--port', str(number), *arguments], cwd=root,
                                     env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            for _ in range(60):
                if child.poll() is not None:
                    raise AssertionError(child.communicate()[1].decode())
                try:
                    if request(number, '/api/local/status')[0] == 200:
                        return number, child
                except OSError:
                    pass
                time.sleep(0.1)
            child.terminate()
            child.communicate(timeout=5)
            raise AssertionError('Host did not become ready')

        def stop(child):
            child.terminate()
            try:
                child.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.communicate()

        number, child = start([])
        try:
            code, _, body = request(number, '/api/local/status')
            status = json.loads(body)
            assert code == 200 and status['selfhost'] and not status['discordLoginAvailable']
            assert not status['joinCodeRequired'], 'Stale shell access codes must not change the launcher mode'
            code, headers, body = request(number, '/api/auth/me')
            assert code == 200 and json.loads(body)['loggedIn']
            assert headers['Set-Cookie'].startswith('zgta_local=')
            code, headers, body = request(number, '/')
            assert code == 200 and b'Synthetic test world' in body
            assert b'https://source.example/my-fork' in body and b'/local-gameplay.js' in body
            assert headers['Cross-Origin-Embedder-Policy'] == 'require-corp'
            assert request(number, '/api/local/status', headers={'Host':'unlisted.example'})[0] == 421
            assert request(number, '/api/local/status', headers={'Origin':'https://another.example'})[0] == 403
        finally:
            stop(child)
        number, child = start(['--host','public.example'])
        try:
            code, headers, body = request(number, '/api/auth/me', headers={
                'Host':'public.example', 'X-Forwarded-Proto':'https', 'X-Forwarded-For':'192.0.2.10'})
            assert code == 200 and json.loads(body)['loggedIn']
            assert '; Secure' in headers['Set-Cookie']
        finally:
            stop(child)
        number, child = start(['--bind','0.0.0.0','--host','lan.example'])
        try:
            key = state / 'join-code.txt'
            original = key.read_text().strip()
            assert len(original) >= 12 and stat.S_IMODE(key.stat().st_mode) == 0o600
            headers = {'Host':'lan.example'}
            assert request(number, '/api/auth/me', headers=headers)[0] == 401
            wrong = dict(headers, **{'Content-Type':'application/json'})
            assert request(number, '/api/local/join', 'POST', '{"code":"wrong"}', wrong)[0] == 403
            code, joined, _ = request(number, '/api/local/join', 'POST', json.dumps({'code':original}), wrong)
            assert code == 200
            headers['Cookie'] = joined['Set-Cookie'].split(';')[0]
            assert request(number, '/api/auth/me', headers=headers)[0] == 200
            # A loopback reverse proxy must not silently bypass its configured code.
            assert request(number, '/api/auth/me', headers={'X-Forwarded-For':'192.0.2.10'})[0] == 401
            assert key.read_text().strip() == original
        finally:
            stop(child)
        # Import copies only the site, never another host's saves or credentials.
        module.ROOT = root / 'imported'
        module.LOCAL = module.ROOT / 'local-only'
        module.SITE = module.LOCAL / 'site'
        module.import_site(site)
        assert (module.SITE / 'index.html').is_file()
        assert not (module.LOCAL / 'selfhost').exists()
        module.import_site(site)  # A matching import is resumable.
        (site / 'leak').symlink_to(state / 'players.json')
        try:
            module.import_site(site)
        except ValueError:
            pass
        else:
            raise AssertionError('Import must reject symlinks')
    print('PASS fresh host: guest play, stale-mode isolation, source link, LAN code, Host/Origin gates and private asset import')


if __name__ == '__main__':
    main()
