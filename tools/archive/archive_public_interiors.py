#!/usr/bin/env python3
"""Archive interior cells listed by the public world index into local-only/."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import concurrent.futures
import json
import urllib.request
import urllib.error
from pathlib import Path

WORLD = Path(__file__).resolve().parents[2] / 'local-only/site/game/world'

def fetch(name):
    target = WORLD / name
    if target.is_file(): return
    request = urllib.request.Request('https://play.samp.directory/game/world/' + name,
        headers={'User-Agent': 'Mozilla/5.0', 'Referer': 'https://play.samp.directory/'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read(30_000_001)
    except urllib.error.HTTPError as error:
        if error.code == 404 and name.endswith('.col.bin'): return 'missing collision'
        raise
    if not 16 <= len(data) <= 30_000_000: raise ValueError('Invalid file length: ' + name)
    if name.endswith('.bin') and data[:4] not in (b'WRL2', b'SCL2'): raise ValueError('Invalid mesh: ' + name)
    if name.endswith('.webp') and not (data[:4] == b'RIFF' and data[8:12] == b'WEBP'): raise ValueError('Invalid atlas: ' + name)
    temporary = target.with_suffix(target.suffix + '.partial')
    temporary.write_bytes(data); temporary.replace(target)

def main():
    cells = json.loads((WORLD / 'index.json').read_text())['inside']['cells']
    names = [f'i{cell["cell"]}.{extension}' for cell in cells for extension in ('bin', 'webp', 'col.bin')]
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(fetch, name): name for name in names}
        errors = []
        optional = []
        for future in concurrent.futures.as_completed(futures):
            try:
                if future.result() == 'missing collision': optional.append(futures[future])
            except Exception as error: errors.append((futures[future], str(error)))
    print(f'Interior cells: {len(cells)}; local files: {sum((WORLD/name).is_file() for name in names)}/{len(names)}')
    for name, error in errors: print(name, error)
    for name in optional: print(name, 'is not supplied by the public site; collision remains unavailable')
    if errors: raise SystemExit(1)

if __name__ == '__main__': main()
