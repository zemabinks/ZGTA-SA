#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Prepare opt-in independent road traffic from existing owner-local resources.

This verifies prepared metadata and required file presence, not exhaustive GPU
or retail behavior. Generated model dimensions/colors remain local game data.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import stat
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[2]

def read(path, maximum):
    path = Path(path).resolve(strict=True)
    with os.fdopen(os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)), 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= maximum:
            raise ValueError('Prepared resource size/type budget')
        data = stream.read(maximum + 1)
        after = os.fstat(stream.fileno())
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns) or len(data) != before.st_size:
            raise ValueError('Prepared resource changed during read')
    return data

def prepare(site, selected=None, maximum=32, per_observer=6):
    site = Path(site).resolve(strict=True)
    if not 0 <= maximum <= 64 or not 0 <= per_observer <= 16:
        raise ValueError('Traffic population budget')
    files = {}
    def resource(relative, limit):
        file = (site / relative).resolve(strict=True)
        # Existing prepared development sites use owner-created cache links.
        # All logical names below are fixed or derived from a bounded basename;
        # metadata never supplies an arbitrary filesystem path to this reader.
        data = read(file, limit)
        files[relative] = hashlib.sha256(data).hexdigest()
        return data
    index = json.loads(resource('game/native/models/index.json', 2 * 1048576))
    physics = json.loads(resource('game/native/vehicles.physics.json', 64 * 1048576))
    roads = resource('game/world/roads.bin', 8 * 1048576)
    if roads[:8] != b'SDRD\x01\x00\x00\x00':
        raise ValueError('Expected prepared SDRDv1 roads')
    # Exercise the same complete bounded reader used by the server, over the
    # exact bytes already captured above. No original script is executed.
    validate = subprocess.run(['node', '-e',
        'const fs=require("node:fs"),{TrafficRoads}=require(process.argv[1]);new TrafficRoads(fs.readFileSync(0),process.argv[2]);',
        str(ROOT/'server/population/traffic_roads.js'), f'{zlib.crc32(roads):08x}'],
        input=roads, capture_output=True, timeout=20)
    if validate.returncode:
        raise ValueError('Prepared road graph failed production-reader validation')
    if not isinstance(index.get('vehicles'), dict) or not isinstance(physics.get('models'), dict):
        raise ValueError('Prepared vehicle metadata required')
    requested = set(selected) if selected is not None else None
    models = []
    for key, name in sorted(index['vehicles'].items(), key=lambda item: item[0]):
        if not re.fullmatch(r'\d{3}', key) or not isinstance(name, str) or not re.fullmatch(r'[a-zA-Z0-9_]{1,32}', name):
            continue
        identity = int(key)
        if requested is not None and identity not in requested:
            continue
        row = physics['models'].get(key)
        if not isinstance(row, dict) or row.get('kind') != 'car' or row.get('id') != identity or row.get('model') != name:
            continue
        box = row.get('bounds', {}).get('box', {})
        lower, upper = box.get('min'), box.get('max')
        if not all(isinstance(v, list) and len(v) == 3 and all(type(n) in [int, float] and math.isfinite(n) for n in v) for v in [lower, upper]):
            continue
        width, length = upper[0] - lower[0], upper[1] - lower[1]
        if not 0.5 <= width <= 5 or not 1 <= length <= 25:
            continue
        required = ['game/native/models/' + name + suffix for suffix in ['.rig.json', '.rig.bin', '.rig.png', '.bin', '.png']]
        if not all((site / relative).is_file() for relative in required):
            continue
        rig = json.loads(resource(required[0], 16 * 1048576))
        if rig.get('version') not in [2, 3] or rig.get('id') != identity or rig.get('model') != name or rig.get('kind') != 'car' or rig.get('dffSHA256') != row.get('dffSHA256') or not re.fullmatch(r'[0-9a-f]{64}', str(rig.get('dffSHA256'))):
            raise ValueError('Prepared vehicle rig/source identity mismatch')
        paint = rig.get('paint', {})
        variants = paint.get('colorVariants', [])
        if not isinstance(variants, list):
            raise ValueError('Prepared vehicle color variants')
        variants = [*variants, paint.get('defaults')]
        colors = []
        for variant in variants:
            if isinstance(variant, list) and len(variant) >= 2 and all(type(n) is int and 0 <= n <= 255 for n in variant[:2]):
                pair = variant[:2]
                if pair not in colors:
                    colors.append(pair)
        if not colors:
            continue
        models.append(dict(id=identity, length=length, width=width, colors=colors[:32]))
    if not models or (requested is not None and {m['id'] for m in models} != requested):
        raise ValueError('Requested traffic models lack complete supported prepared metadata/files')
    return dict(version=1, profile='zgta-prepared-road-traffic-v1', roadsCRC32=f'{zlib.crc32(roads):08x}',
                maximum=maximum, perObserver=per_observer, models=models, sourceHashes=files)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site', type=Path, default=ROOT/'local-only/site')
    parser.add_argument('--models', type=int, nargs='+')
    parser.add_argument('--maximum', type=int, default=32)
    parser.add_argument('--per-observer', type=int, default=6)
    parser.add_argument('--out', type=Path, default=ROOT/'local-only/selfhost/traffic.json')
    args = parser.parse_args()
    out = args.out.resolve()
    if out.is_relative_to(ROOT) and not out.is_relative_to(ROOT/'local-only'):
        parser.error('Derived original resource metadata inside the repository must stay local-only')
    if out.exists():
        parser.error('Output exists; choose a new private path and review it before activation')
    config = prepare(args.site, args.models, args.maximum, args.per_observer)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=out.name+'.', suffix='.partial', dir=out.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write((json.dumps(config, indent=2)+'\n').encode())
    try:
        os.replace(temporary, out)
    finally:
        if temporary.exists():
            temporary.unlink()
    print(json.dumps(dict(status='PREPARED_NOT_RUNTIME_ACCEPTED', models=len(config['models']),
                         roadsCRC32=config['roadsCRC32'], configurationSHA256=hashlib.sha256(out.read_bytes()).hexdigest(),
                         scope='Private original-derived configuration. Activation, full graph validation, App gameplay and retail accuracy remain separate.')))

if __name__ == '__main__':
    main()
