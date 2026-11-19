#!/usr/bin/env python3
"""Inspect local original WASM provenance without executing or uploading it.

Embedded Rust panic paths identify physical math dependencies even though the
publisher did not ship Cargo.lock. Optional --check-lock checks those recovered
native dependencies against our reproducible native build lockfile.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def inspect(data):
    if data[:8] != b'\0asm\1\0\0\0':
        raise ValueError('Not a version-one WebAssembly module')

    def integer(offset):
        value, shift = 0, 0
        while True:
            byte = data[offset]
            offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value, offset
            shift += 7
            if shift > 35:
                raise ValueError('Invalid module integer')

    offset, functions, vector_types, vector_locals = 8, 0, 0, 0
    while offset < len(data):
        kind = data[offset]
        length, start = integer(offset + 1)
        end = start + length
        if end > len(data):
            raise ValueError('Truncated module section')
        if kind == 1:
            count, cursor = integer(start)
            for _ in range(count):
                form = data[cursor]
                cursor += 1
                if form != 0x60:
                    raise ValueError('Unexpected function-type encoding')
                for _ in range(2):
                    count_values, cursor = integer(cursor)
                    vector_types += data[cursor:cursor + count_values].count(0x7b)
                    cursor += count_values
        elif kind == 10:
            functions, cursor = integer(start)
            for _ in range(functions):
                body_length, cursor = integer(cursor)
                body_end = cursor + body_length
                count, cursor = integer(cursor)
                for _ in range(count):
                    locals_count, cursor = integer(cursor)
                    value_type = data[cursor]
                    cursor += 1
                    if value_type == 0x7b:
                        vector_locals += locals_count
                cursor = body_end
        offset = end
    paths = sorted(set(match.decode('ascii') for match in re.findall(
        rb'/registry/src/[^/\0]+/([^/\0]+-[0-9][^/\0]*)/', data)))
    crates = {}
    for path in paths:
        match = re.fullmatch(r'(.+)-(\d+\.\d+\.\d+(?:[-+][\w.]+)?)', path)
        if match:
            crates[match[1]] = match[2]
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'functions': functions, 'v128FunctionTypeEntries': vector_types,
            'v128Locals': vector_locals, 'embeddedCrates': crates}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wasm', type=Path, default=ROOT / 'local-only/reverse-engineering/vehicle-physics/archived-rapier.wasm')
    parser.add_argument('--check-lock', action='store_true')
    args = parser.parse_args()
    result = inspect(args.wasm.read_bytes())
    if args.check_lock:
        locked = {}
        for package in (ROOT / 'native-physics/Cargo.lock').read_text().split('[[package]]'):
            name = re.search(r'^name = "([^"]+)"', package, re.M)
            version = re.search(r'^version = "([^"]+)"', package, re.M)
            if name and version:
                locked.setdefault(name[1], []).append(version[1])
        shared = ['ena', 'glam', 'glamx', 'hashbrown', 'nalgebra', 'parry3d', 'smallvec']
        result['nativeRecoveredVersionsMatch'] = all(
            result['embeddedCrates'][name] in locked.get(name, []) for name in shared)
        if not result['nativeRecoveredVersionsMatch']:
            raise ValueError('Native lock differs from recovered physical dependency versions: ' + json.dumps(result))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
