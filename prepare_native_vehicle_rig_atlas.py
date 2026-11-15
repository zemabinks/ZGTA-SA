#!/usr/bin/env python3
"""Pack original decoded local TXD RGBA into the native WRL2 atlas."""
import base64
import json
import math
from pathlib import Path
import sys
from PIL import Image

def main():
    rows = json.load(sys.stdin)
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

if __name__ == '__main__':
    main()
