#!/usr/bin/env python3
"""Convert local-only world atlas images for the native iOS Metal client.

The converted pixels stay in local-only/site/game/world and are never added to
the source repository. The original .bin geometry is streamed unchanged.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
from PIL import Image
import json
import sys
import argparse

ROOT = Path(__file__).resolve().parents[2] / 'local-only' / 'site' / 'game' / 'world'


def prepare_image(source: Path, target: Path, expected=None) -> None:
    with Image.open(source) as original:
        if expected is not None and original.size != expected:
            raise ValueError(f'Unexpected high-resolution image dimensions: {source.name}')
        if target.is_file() and target.stat().st_mtime >= source.stat().st_mtime:
            try:
                with Image.open(target) as existing:
                    if existing.size != original.size or existing.mode != 'RGBA':
                        raise ValueError('Stale image profile')
                    existing.verify()
                return
            except (OSError, ValueError, SyntaxError):
                pass
        temporary = target.with_suffix('.png.partial')
        try:
            original.convert('RGBA').save(temporary, format='PNG', compress_level=1)
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    print(f'{target.name}: {target.stat().st_size // 1024} KiB')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--all-details', action='store_true')
    parser.add_argument('--detail-spawn', action='store_true')
    parser.add_argument('--root', type=Path, default=ROOT)
    args = parser.parse_args()
    root = args.root
    if not (root / 'index.json').is_file():
        raise SystemExit('Local world archive missing. Run tools/archive/archive_site.py first.')
    index = json.loads((root / 'index.json').read_text())
    entries = {f"{prefix}{row['cell']}": row for prefix, rows in [
        ('c', index['detail']['cells']), ('i', index.get('inside', {}).get('cells', []))] for row in rows}
    names = [entry['name'] for entry in index['tiles']]
    if args.all_details:
        names.extend(f"c{entry['cell']}" for entry in index['detail']['cells'])
        names.extend(f"i{entry['cell']}" for entry in index.get('inside', {}).get('cells', []))
    elif args.detail_spawn:
        # Also prepare the cell covering the independent server's spawn.
        detail = index['detail']
        x, y = 1480, -1738
        column = int((x - detail['origin']) // detail['size'])
        row = int((y - detail['origin']) // detail['size'])
        cell = row * detail['grid'] + column
        names.append(f'c{cell}')
    sharp_ready, sharp_missing = 0, 0
    for name in dict.fromkeys(names):
        prepare_image(root / f'{name}.webp', root / f'{name}.png')
        sharp = entries.get(name, {}).get('sharp', 0)
        if sharp:
            if type(sharp) is not int or not 1 <= sharp <= 384:
                raise ValueError('Unsupported world high-resolution layer count')
            source = root / f'{name}.hd.webp'
            if source.is_file():
                prepare_image(source, root / f'{name}.hd.png', (2048, (sharp + 7) // 8 * 256))
                sharp_ready += 1
            else:
                sharp_missing += 1
    print(f'Prepared {len(set(names))} local-only native base atlases; '
          f'{sharp_ready} high-resolution atlases; {sharp_missing} optional sources unavailable.')


if __name__ == '__main__':
    main()
