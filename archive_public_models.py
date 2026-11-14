#!/usr/bin/env python3
"""Fill local-only DFF/TXD vehicle and pedestrian gaps from the public site.

Only archived game assets are written, under ignored local-only/site/game/.
The source list comes from the archived public client catalogs.
"""
import argparse
import json
import struct
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import extract_client_catalog as catalog

ROOT = Path(__file__).resolve().parent
GAME = ROOT / 'local-only' / 'site' / 'game'
BASE = 'https://play.samp.directory/game/'


def wanted():
    _, js = catalog.bundle_with('"name":"Manana"')
    vehicles = catalog.json_literal(js, "e.exports=JSON.parse('", "')")
    peds = json.loads((GAME / 'world' / 'peds.json').read_text())['peds']
    names = set()
    for vehicle in vehicles:
        names.add((vehicle['model'].lower(), 'dff'))
        names.add((vehicle['txd'].lower(), 'txd'))
    for ped in peds:
        if ped[0].lower() != 'null':
            names.add((ped[0].lower(), 'dff'))
            names.add((ped[1].lower(), 'txd'))
    return sorted(names)


def fetch(item):
    name, extension = item
    if not name.replace('_', '').isalnum():
        return name, extension, 'invalid name'
    path = GAME / f'{name}.{extension}'
    if path.is_file():
        return name, extension, 'already local'
    request = urllib.request.Request(BASE + name + '.' + extension,
                                     headers={'User-Agent': 'ZGTA-SA-local-archive/1.0'})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            length = response.headers.get('Content-Length')
            if length and int(length) > 20_000_000:
                return name, extension, 'too large'
            data = response.read(20_000_001)
    except (urllib.error.URLError, TimeoutError) as error:
        return name, extension, str(error)
    if len(data) > 20_000_000 or len(data) < 12:
        return name, extension, 'invalid length'
    header = struct.unpack_from('<I', data)[0]
    if header != (0x10 if extension == 'dff' else 0x16):
        return name, extension, 'invalid RenderWare header'
    temporary = path.with_suffix(path.suffix + '.partial')
    temporary.write_bytes(data)
    temporary.replace(path)
    return name, extension, f'saved {len(data)} bytes'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    missing = [item for item in wanted() if not (GAME / f'{item[0]}.{item[1]}').is_file()]
    print(f'{len(missing)} public model files are missing locally', flush=True)
    results = []
    with ThreadPoolExecutor(max_workers=max(1, min(8, args.workers))) as pool:
        for future in as_completed([pool.submit(fetch, item) for item in missing]):
            result = future.result()
            results.append(result)
            print(' '.join(result), flush=True)
    saved = sum(result[2].startswith('saved') for result in results)
    print(f'Saved {saved}/{len(missing)} missing files under {GAME}', flush=True)


if __name__ == '__main__':
    main()
