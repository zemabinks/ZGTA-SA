#!/usr/bin/env python3
"""Prepare native HUD color atlases from the archived local San Andreas font.

The derived images remain in ignored local-only/ and are never added to GitHub.
"""
from pathlib import Path
import json

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "local-only/site/reference/hud/font1.png"
OUTPUT = ROOT / "local-only/site/game/native/hud"


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing local font atlas: {SOURCE}")
    original = Image.open(SOURCE).convert("RGBA")
    alpha = original.getchannel("A")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, color in (("font-white.png", (255, 255, 255)),
                        ("font-green.png", (107, 209, 87))):
        result = Image.new("RGBA", original.size, color)
        result.putalpha(alpha)
        path = OUTPUT / name
        result.save(path, optimize=True)
        print(path.relative_to(ROOT))
    metrics = {}
    for code in range(32, 128):
        index = code - 32
        tile_x, tile_y = index % 16 * 64, index // 16 * 80
        bounds = alpha.crop((tile_x, tile_y, tile_x + 64, tile_y + 80)).getbbox()
        if code == 32 or bounds is None:
            metrics[str(code)] = [0, 0, 0, 0, 15]
        else:
            left, top, right, bottom = bounds
            metrics[str(code)] = [left, top, right - left, bottom - top, right - left + 3]
    path = OUTPUT / "font-metrics.json"
    path.write_text(json.dumps(metrics, separators=(",", ":")), encoding="utf-8")
    print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
