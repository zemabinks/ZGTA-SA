#!/usr/bin/env python3
"""Prepare and run a separate ZGTA:SA community server on macOS or Linux."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
LOCAL = ROOT / 'local-only'
SITE = LOCAL / 'site'
REQUIRED = ('index.html', 'game/world/index.json', 'game/world/collision.json')


def node():
    executable = shutil.which('node')
    if not executable:
        raise ValueError('Install Node.js 22 or later, then run this command again.')
    version = subprocess.check_output([executable, '-p', 'process.versions.node'], text=True).strip()
    if int(version.split('.')[0]) < 22:
        raise ValueError('Node.js 22 or later is required; found ' + version)
    return executable


def run(script, *arguments):
    executable = node() if script.endswith('.js') else sys.executable
    environment = dict(os.environ, PYTHON=sys.executable)
    subprocess.run([executable, str(ROOT / script), *arguments], cwd=ROOT,
                   env=environment, check=True)


def import_site(source):
    """Import assets only. Never copy another host's accounts or credentials."""
    source = Path(source).expanduser().resolve()
    if not (source / 'index.html').is_file() or not (source / 'game/world/index.json').is_file():
        raise ValueError('--import-site must point to an archived site directory containing index.html and game/world/index.json.')
    if source == SITE.resolve() or source in SITE.resolve().parents or SITE.resolve() in source.parents:
        raise ValueError('Import source must be separate from this project\'s local-only/site directory.')
    paths = sorted(source.rglob('*'))
    # Validate before copying any file, including directory symlinks.
    if any(path.is_symlink() for path in paths):
        raise ValueError('Asset imports must contain regular files and directories, without symlinks.')
    for path in paths:
        if path.is_file():
            target = SITE / path.relative_to(source)
            if target.exists():
                import hashlib
                if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(target.read_bytes()).digest():
                    raise ValueError('An existing local asset differs: ' + str(target.relative_to(ROOT)))
    for path in paths:
        if path.is_file():
            target = SITE / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                shutil.copy2(path, target)


def missing_assets():
    missing = [name for name in REQUIRED if not (SITE / name).is_file()]
    if not any((SITE / '_next/static/chunks').glob('*.js')):
        missing.append('_next/static/chunks/*.js')
    return missing


def require_assets():
    missing = missing_assets()
    if missing:
        raise ValueError('Local game content is missing: ' + ', '.join(missing) +
                         '\nRun python3 host.py setup --download, or setup --import-site /path/to/site.')


def setup(args):
    node()
    if args.import_site:
        import_site(args.import_site)
    if args.download:
        for script in ('archive_site.py', 'archive_public_models.py',
                       'archive_public_audio.py', 'archive_public_interiors.py'):
            run(script)
    require_assets()
    run('extract_client_catalog.py')
    if args.native:
        try:
            import PIL  # noqa: F401
        except ImportError:
            raise ValueError('Native asset conversion needs Pillow. Use the virtual-environment steps in HOSTING.md.')
        scripts = [
            ('prepare_native_assets.py', '--all-details'),
            ('prepare_native_models.py', '--all'),
            ('prepare_native_skeletons.py', '--all', '--archive-all-blocks'),
            ('prepare_native_hud.py',), ('prepare_native_weapons.py',),
            ('prepare_native_audio.py',), ('prepare_native_contact_audio.js',),
            ('prepare_native_environment.py',), ('prepare_native_atmosphere.py',),
            ('prepare_native_water_waves.py',), ('prepare_native_camera.py',),
            ('prepare_native_effects.py',), ('prepare_native_particle_effects.js',),
            ('prepare_native_physics.js',),
            ('prepare_native_vehicle_rigs.js', '--all', '--if-needed'),
            ('prepare_native_riders.py',), ('prepare_native_seating.py',),
            ('prepare_native_foot_animation.js',),
            ('prepare_native_flight_assets.js', '--archive-missing'),
            ('prepare_native_radio.js',),
        ]
        for command in scripts:
            run(*command)
    print('Setup complete. Game content and generated data are under local-only/.')
    print('Start with: python3 host.py serve')


def authority(value):
    # Match the request's Host header, without schemes, credentials or paths.
    if not re.fullmatch(r'(?:[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:]+\])(?::[0-9]{1,5})?', value):
        raise argparse.ArgumentTypeError('Use a hostname/IP with optional port, such as 192.168.1.20:8766.')
    port = value.rsplit(':', 1)[-1] if ':' in value and not value.endswith(']') else None
    if port and not 1 <= int(port) <= 65535:
        raise argparse.ArgumentTypeError('Host port must be between 1 and 65535.')
    return value


def serve(args):
    executable = node()
    require_assets()
    if not (LOCAL / 'selfhost/client-catalog.json').is_file():
        raise ValueError('The server catalog is missing. Run python3 host.py setup first.')
    if not 1024 <= args.port <= 65535:
        raise ValueError('--port must be between 1024 and 65535.')
    network = args.bind not in ('127.0.0.1', '::1')
    if network and not args.host:
        raise ValueError('Network hosting needs --host for each address players use, including its port.')
    environment = dict(os.environ)
    # This entry point always runs our independent server, even in a shell
    # previously used for the publisher-connected mirror.
    for key in ('ZGTA_CONNECTED', 'ZGTA_JOIN_CODE', 'ZGTA_JOIN_CODE_FILE',
                'ZGTA_ALLOWED_HOSTS', 'ZGTA_DEBUG_SELFHOST', 'ZGTA_DEBUG_MISSING'):
        environment.pop(key, None)
    environment.update(ZGTA_SELFHOST='1', PORT=str(args.port), BIND_HOST=args.bind,
                       ZGTA_ALLOWED_HOSTS=','.join(args.host), ZGTA_PYTHON=sys.executable)
    if network or args.code_file:
        file = Path(args.code_file).expanduser().resolve() if args.code_file else LOCAL / 'selfhost/join-code.txt'
        file.parent.mkdir(parents=True, exist_ok=True)
        try:
            descriptor = os.open(str(file), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            pass
        else:
            with os.fdopen(descriptor, 'w') as output:
                output.write(secrets.token_hex(24) + '\n')
        if file.is_symlink() or not file.is_file() or len(file.read_text().strip()) < 12:
            raise ValueError('Join-code file must be a regular file containing at least 12 characters.')
        file.chmod(0o600)
        environment['ZGTA_JOIN_CODE_FILE'] = str(file)
        print('Join code is stored in ' + str(file) + ' (share it privately).', flush=True)
    print('Starting ZGTA:SA independent server; Discord is optional.', flush=True)
    print('Local address: http://127.0.0.1:' + str(args.port) + '/', flush=True)
    if args.host:
        print('Allowed network hosts: ' + ', '.join(args.host), flush=True)
    os.chdir(ROOT)
    os.execve(executable, [executable, str(ROOT / 'serve_local.js')], environment)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('setup', help='Download or import local content and prepare the host.')
    prepare.add_argument('--download', action='store_true', help='Download discoverable public content into ignored local-only/.')
    prepare.add_argument('--import-site', metavar='PATH', help='Import an existing archived site directory, excluding host state.')
    prepare.add_argument('--native', action='store_true', help='Also convert data for native iOS clients; requires Pillow.')
    prepare.set_defaults(handler=setup)
    check = commands.add_parser('doctor', help='Check the runtime and browser content without changing files.')
    check.set_defaults(handler=lambda args: (node(), require_assets(), print('Host runtime and browser content are present.')))
    server = commands.add_parser('serve', help='Run the independent server in the foreground.')
    server.add_argument('--port', type=int, default=8766)
    server.add_argument('--bind', default='127.0.0.1', help='Use 0.0.0.0 for LAN, or 127.0.0.1 behind a reverse proxy.')
    server.add_argument('--host', type=authority, action='append', default=[], help='Allowed Host header; repeat for multiple addresses.')
    server.add_argument('--code-file', help='Private join-code file; generated if absent. Network hosting enables one automatically.')
    server.set_defaults(handler=serve)
    args = parser.parse_args()
    try:
        args.handler(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('Host setup error: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
