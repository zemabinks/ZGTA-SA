#!/usr/bin/env python3
"""Pack original decoded local TXD RGBA into the native WRL2 atlas."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import base64
import json
import math
from pathlib import Path
import sys
from PIL import Image

def pack_native(rows):
    """Copy original pixels into a bounded staging image, without resampling."""
    images = [Image.new('RGBA', (1, 1), (255, 255, 255, 255))]
    for row in rows:
        width, height = row['width'], row['height']
        if type(width) is not int or type(height) is not int or not (1 <= width <= 2048 and 1 <= height <= 2048):
            raise ValueError('Invalid native vehicle texture dimensions')
        raw = base64.b64decode(row['rgba'], validate=True)
        if len(raw) != width * height * 4:
            raise ValueError('Invalid native vehicle texture bytes')
        images.append(Image.frombytes('RGBA', (width, height), raw))
    if len(images) > 128 or sum(image.width * image.height * 4 for image in images) > 4 * 1024 * 1024:
        raise ValueError('Native vehicle texture budget exceeded')
    width = max(1024, max(image.width for image in images))
    x = y = row_height = 0
    rects = []
    for image in images:
        if x + image.width > width:
            x, y, row_height = 0, y + row_height, 0
        rects.append([x, y, image.width, image.height])
        x += image.width
        row_height = max(row_height, image.height)
    height = y + row_height
    if height > 4096:
        raise ValueError('Native vehicle staging image is too tall')
    atlas = Image.new('RGBA', (width, height))
    for image, rect in zip(images, rects):
        atlas.paste(image, tuple(rect[:2]))
    return atlas, rects

def main():
    rows = json.load(sys.stdin)
    native = '--native-textures' in sys.argv[2:]
    if native:
        atlas, rects = pack_native(rows)
    else:
        columns, cell = 8, 128
        atlas = Image.new('RGBA', (columns * cell, math.ceil((len(rows) + 1) / columns) * cell), (255, 255, 255, 255))
        for slot, row in enumerate(rows, 1):
            raw = base64.b64decode(row['rgba'], validate=True)
            image = Image.frombytes('RGBA', (row['width'], row['height']), raw)
            image = image.resize((cell, cell), Image.Resampling.LANCZOS)
            atlas.paste(image, ((slot % columns) * cell, (slot // columns) * cell))
    output = Path(sys.argv[1])
    temporary = output.with_suffix('.png.tmp')
    atlas.save(temporary, format='PNG')
    temporary.replace(output)
    if native:
        print(json.dumps(dict(version=1, width=atlas.width, height=atlas.height, rects=rects,
                              rgbaBytes=sum(r[2] * r[3] * 4 for r in rects))))

if __name__ == '__main__':
    main()
