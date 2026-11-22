#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Prepare local original population tables; this does not activate population AI."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import stat
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.assets.original_population import MAX_TEXT_BYTES, parse_cycle, parse_groups, parse_zones

SOURCES = ('data/pedgrp.dat', 'data/cargrp.dat', 'data/popcycle.dat', 'data/info.zon', 'data/map.zon')


def source_path(root, name):
    result = root
    for component in name.split('/'):
        matches = [p for p in result.iterdir() if p.name.lower() == component]
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous population source: ' + name)
        result = matches[0]
    return result


def read_source(path):
    with path.open('rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size > MAX_TEXT_BYTES:
            raise ValueError('Population source file size/type')
        data = stream.read(MAX_TEXT_BYTES + 1)
        after = os.fstat(stream.fileno())
    if (len(data) != before.st_size or (before.st_size, before.st_mtime_ns, before.st_ino) !=
            (after.st_size, after.st_mtime_ns, after.st_ino)):
        raise ValueError('Population source changed during reading')
    return data


def prepare(game_dir, output):
    root, output = Path(game_dir).resolve(strict=True), Path(output).absolute()
    destination = output.resolve()
    if destination.is_relative_to(ROOT) and not destination.is_relative_to(ROOT / 'local-only'):
        raise ValueError('Original-derived population data must stay under local-only/ in this repository')
    paths = {name: source_path(root, name) for name in SOURCES}
    if output.resolve() in {p.resolve() for p in paths.values()}:
        raise ValueError('Output cannot replace an original source')
    raw = {name: read_source(path) for name, path in paths.items()}
    text = {name: value.decode('utf-8') for name, value in raw.items()}
    document = dict(version=1, profile='zgta-original-population-tables-v1',
                    sourceSHA256={name: hashlib.sha256(value).hexdigest() for name, value in raw.items()},
                    pedestrianGroups=parse_groups(text['data/pedgrp.dat'], 'pedestrian'),
                    vehicleGroups=parse_groups(text['data/cargrp.dat'], 'vehicle'),
                    cycleRows=parse_cycle(text['data/popcycle.dat']),
                    navigationZones=parse_zones(text['data/info.zon']),
                    mapZones=parse_zones(text['data/map.zon']))
    encoded = (json.dumps(document, sort_keys=True, indent=2) + '\n').encode()
    if any(read_source(paths[name]) != value for name, value in raw.items()):
        raise ValueError('Population sources changed during preparation')
    if output.exists() or output.is_symlink():
        if output.is_symlink() or not output.is_file() or output.read_bytes() != encoded:
            raise ValueError('Existing population output differs; choose a new output')
        reused = True
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name('.' + output.name + '.' + uuid.uuid4().hex + '.partial')
        try:
            with temporary.open('xb') as stream:
                stream.write(encoded)
                stream.flush()
                os.fsync(stream.fileno())
            os.link(temporary, output)  # Exclusive publication, never replacement.
        finally:
            temporary.unlink(missing_ok=True)
        reused = False
    return dict(status='REUSED' if reused else 'PREPARED', output=str(output),
                sha256=hashlib.sha256(encoded).hexdigest(), pedestrianGroups=57, vehicleGroups=34,
                cycleRows=480, navigationZones=len(document['navigationZones']), mapZones=len(document['mapZones']),
                scope='Decoded original tables only; zone population-type assignments, model admission and runtime AI remain separate.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='Local-only generated JSON; keep original data off GitHub')
    args = parser.parse_args()
    print(json.dumps(prepare(args.game_dir, args.output), indent=2))


if __name__ == '__main__':
    main()
