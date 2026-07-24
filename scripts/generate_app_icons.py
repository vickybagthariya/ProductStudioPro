#!/usr/bin/env python3
"""Generate text-free Product Studio Pro app icons (gradient + camera motif, no wording)."""
from __future__ import annotations

import math
import os
import struct

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("Install Pillow: pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")

# Deep navy → warm gold (no text in design)
C0 = (18, 28, 52)
C1 = (245, 196, 72)
C2 = (255, 236, 200)


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    cx, cy = size / 2.0, size / 2.0
    r = size * 0.72
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / r
            d = max(0.0, min(1.0, d))
            # smooth gradient center bright
            t = d ** 0.85
            rcol = int(C0[0] * t + C1[0] * (1 - t) * 0.7 + C2[0] * (1 - t) * 0.3)
            gcol = int(C0[1] * t + C1[1] * (1 - t) * 0.7 + C2[1] * (1 - t) * 0.3)
            bcol = int(C0[2] * t + C1[2] * (1 - t) * 0.7 + C2[2] * (1 - t) * 0.3)
            px[x, y] = (rcol, gcol, bcol, 255)
    draw = ImageDraw.Draw(img)
    # Subtle lens circle (camera motif)
    margin = int(size * 0.18)
    outline_w = max(2, size // 64)
    draw.ellipse(
        [margin, margin, size - margin, size - margin],
        outline=(255, 255, 255, 110),
        width=outline_w,
    )
    inner = int(size * 0.14)
    draw.ellipse(
        [inner, inner, size - inner, size - inner],
        outline=(255, 255, 255, 75),
        width=max(1, outline_w // 2),
    )
    return img


def main() -> None:
    sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
    os.makedirs(OUT, exist_ok=True)
    for s in sizes:
        name = f"AppIcon-{s}.png"
        path = os.path.join(OUT, name)
        im = draw_icon(s)
        im.save(path, "PNG")
        print("wrote", path)


if __name__ == "__main__":
    main()
