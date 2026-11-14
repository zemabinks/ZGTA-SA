#!/usr/bin/env python3
"""Convert local-only world atlas images for the native iOS Metal client.

The converted pixels stay in local-only/site/game/world and are never added to
the source repository. The original .bin geometry is streamed unchanged.
"""
from pathlib import Path
from PIL import Image
import json
import sys

ROOT = Path(__file__).resolve().parent / 'local-only' / 'site' / 'game' / 'world'


def main() -> None:
    if not (ROOT / 'index.json').is_file():
        raise SystemExit('Local world archive missing. Run archive_site.py first.')
    index = json.loads((ROOT / 'index.json').read_text())
    names = [entry['name'] for entry in index['tiles']]
    if '--all-details' in sys.argv:
        names.extend(f"c{entry['cell']}" for entry in index['detail']['cells'])
    elif '--detail-spawn' in sys.argv:
        # Also prepare the cell covering the independent server's spawn.
        detail = index['detail']
        x, y = 1480, -1738
        column = int((x - detail['origin']) // detail['size'])
        row = int((y - detail['origin']) // detail['size'])
        cell = row * detail['grid'] + column
        names.append(f'c{cell}')
    for name in names:
        source, target = ROOT / f'{name}.webp', ROOT / f'{name}.png'
        if target.is_file() and target.stat().st_mtime >= source.stat().st_mtime:
            try:
                with Image.open(target) as existing:
                    existing.verify()
                continue
            except Exception:
                pass
        temporary = target.with_suffix('.png.partial')
        with Image.open(source) as image:
            image.convert('RGBA').save(temporary, format='PNG', compress_level=1)
        temporary.replace(target)
        print(f'{name}: {target.stat().st_size // 1024} KiB')
    print(f'Prepared {len(names)} local-only native atlases.')


if __name__ == '__main__':
    main()
