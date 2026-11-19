#!/usr/bin/env python3
"""Prepare local native HUD fonts and sprites from the archived client resources.

The derivative game files and extracted browser font tables stay in ignored
local-only/. No game texture or font data is embedded in the iOS source tree.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib
import json
import re

from PIL import Image, ImageOps
from tools.assets.prepare_native_models import textures

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'local-only/site/reference/hud'
CHUNK = ROOT / 'local-only/site/_next/static/chunks/9737.c81ad6ccfd85b371.js'
OUTPUT = ROOT / 'local-only/site/game/native/hud'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    for path in [SOURCE / 'font1.png', SOURCE / 'font2.png', CHUNK]:
        if not path.is_file():
            raise SystemExit(f'Missing local HUD resource: {path}')
    # The browser's `L.l` tables describe advances in the original 32-pixel
    # grid. Alpha bounding boxes are not advances: using them changes spacing,
    # particularly for the HUD's alternate bold digits and dollar glyph.
    source = CHUNK.read_text(encoding='utf-8')
    match = re.search(r"let L=JSON\.parse\('(\{\"l\":\[.*?\})'\);", source)
    if not match:
        raise SystemExit('Archived browser font width tables were not found')
    tables = json.loads(match.group(1))['l']
    if len(tables) != 2 or any(len(row['widths']) < 190 for row in tables):
        raise SystemExit('Archived browser font width tables are invalid')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ['font1', 'font2']:
        original = Image.open(SOURCE / f'{name}.png').convert('RGBA')
        alpha = original.getchannel('A')
        white = Image.new('RGBA', original.size, (255, 255, 255))
        white.putalpha(alpha)
        white.save(OUTPUT / f'{name}-white.png', optimize=True)
        if name == 'font1':
            white.save(OUTPUT / 'font-white.png', optimize=True)
            green = Image.new('RGBA', original.size, (54, 104, 44))
            green.putalpha(alpha)
            green.save(OUTPUT / 'font-green.png', optimize=True)
            # Keep this legacy output for older local app builds.
            metrics = {}
            for code in range(32, 128):
                index = code - 32
                x, y = index % 16 * 64, index // 16 * 80
                box = alpha.crop((x, y, x + 64, y + 80)).getbbox()
                if code == 32 or box is None:
                    metrics[str(code)] = [0, 0, 0, 0, 18]
                else:
                    left, top, right, bottom = box
                    metrics[str(code)] = [left, top, right-left, bottom-top,
                                          tables[1]['widths'][index] * 2]
            (OUTPUT / 'font-metrics.json').write_text(json.dumps(metrics, separators=(',', ':')))
    layout = {'version': 2, 'font1': tables[1], 'font2': tables[0],
              'source': {path.name: digest(path) for path in [CHUNK, SOURCE/'font1.png', SOURCE/'font2.png']}}
    (OUTPUT / 'font-layout.json').write_text(json.dumps(layout, separators=(',', ':')))
    hud = ROOT / 'local-only/site/game/hud.txd'
    sprites = textures(hud)
    required = ['radardisc', 'radar_centre', 'radar_north', 'radar_waypoint']
    if any(name not in sprites for name in required):
        raise SystemExit('The local HUD TXD is missing required radar sprites')
    # The client's owned-property icon recolours bright source pixels while
    # preserving its black outline (tt(..., [74,144,226], 174)).
    owned = sprites['radar_propertyg'].copy()
    recoloured = []
    for r, g, b, a in owned.getdata():
        bright = max(r, g, b)
        recoloured.append((min(255, round(74 * bright / 174)),
                          min(255, round(144 * bright / 174)),
                          min(255, round(226 * bright / 174)), a)
                         if a and bright > 40 else (r, g, b, a))
    owned.putdata(recoloured)
    sprites['radar_propertyowned'] = owned
    # radardisc is one quarter in the TXD. The archived browser mirrors it to
    # produce the four-sided radar rim; preserve that transform here.
    quarter = sprites['radardisc']
    rim = Image.new('RGBA', (quarter.width * 2, quarter.height * 2))
    rim.paste(quarter, (0, 0))
    rim.paste(ImageOps.mirror(quarter), (quarter.width, 0))
    rim.paste(ImageOps.flip(quarter), (0, quarter.height))
    rim.paste(ImageOps.flip(ImageOps.mirror(quarter)), (quarter.width, quarter.height))
    sprites['radar_rim'] = rim
    columns, tile = 10, 128
    atlas = Image.new('RGBA', (columns * tile, ((len(sprites)+columns-1)//columns) * tile))
    rectangles = {}
    for index, (name, image) in enumerate(sorted(sprites.items())):
        x, y = index % columns * tile, index // columns * tile
        atlas.paste(image, (x, y))
        rectangles[name] = [x, y, image.width, image.height]
    atlas.save(OUTPUT / 'sprites.png', optimize=True)
    (OUTPUT / 'sprites.json').write_text(json.dumps({'version': 1, 'rectangles': rectangles,
        'source': {'hud.txd': digest(hud)}}, separators=(',', ':')))
    catalog_path = ROOT / 'local-only/selfhost/client-catalog.json'
    if catalog_path.is_file():
        catalog = json.loads(catalog_path.read_text())
        places = []
        for home in catalog.get('homes', []):
            point = home.get('out') or home.get('door')
            if point and len(point) >= 2:
                places.append({'id': 'home-' + home['key'], 'name': home['name'],
                               'x': point[0], 'y': point[1], 'icon': 'radar_propertyg'})
        for dealer in catalog.get('dealers', []):
            point = dealer.get('stand')
            if point and len(point) >= 2:
                places.append({'id': 'dealer-' + dealer['key'], 'name': dealer['name'],
                               'x': point[0], 'y': point[1],
                               'icon': 'radar_airyard' if dealer.get('air') else 'radar_modgarage'})
        (OUTPUT / 'places.json').write_text(json.dumps({'places': places,
            'source': {catalog_path.name: digest(catalog_path)}}, separators=(',', ':')))
    print(f'Prepared two archived font tables and {len(sprites)} HUD sprites in {OUTPUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
