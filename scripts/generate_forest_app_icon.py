#!/usr/bin/env python3
"""Forest Emerald + Soft Gold app icon — abstract aperture ring, gold framing lines."""
from __future__ import annotations

import math
import os
import subprocess
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Install Pillow: pip install Pillow", file=sys.stderr)
    raise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")

# Brand tokens
BG_TOP = (4, 28, 21)
BG_MID = (6, 78, 59)
BG_BOTTOM = (6, 95, 70)
GOLD = (212, 160, 23)
GOLD_BRIGHT = (234, 198, 92)
SAGE = (132, 169, 140)
CREAM = (254, 252, 232)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_icon(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), BG_TOP)
    px = img.load()
    cx = cy = size / 2
    r = size * 0.72
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / r
            t = max(0.0, min(1.0, d ** 0.9))
            col = lerp(lerp(BG_TOP, BG_MID, t * 0.6), BG_BOTTOM, t)
            px[x, y] = col

    d = ImageDraw.Draw(img)
    margin = int(size * 0.10)
    corner = int(size * 0.22)

    # Gold corner framing lines (minimal, not a camera)
    lw = max(2, size // 64)
    arm = int(size * 0.14)
    for ox, oy, hx, hy in [
        (margin, margin, 1, 1),
        (size - margin, margin, -1, 1),
        (margin, size - margin, 1, -1),
        (size - margin, size - margin, -1, -1),
    ]:
        d.line([(ox, oy), (ox + arm * hx, oy)], fill=GOLD, width=lw)
        d.line([(ox, oy), (ox, oy + arm * hy)], fill=GOLD, width=lw)

    # Emerald aperture ring
    ring_r = int(size * 0.26)
    ring_w = max(3, size // 48)
    d.ellipse(
        (cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r),
        outline=GOLD_BRIGHT,
        width=ring_w,
    )
    inner = int(ring_r * 0.62)
    d.ellipse(
        (cx - inner, cy - inner, cx + inner, cy + inner),
        outline=SAGE,
        width=max(2, ring_w // 2),
    )

    # Soft inner glow
    glow_r = int(ring_r * 0.38)
    d.ellipse(
        (cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r),
        fill=lerp(BG_MID, SAGE, 0.35),
    )

    # Abstract cube / product silhouette (minimal)
    cube = int(size * 0.11)
    d.rounded_rectangle(
        (cx - cube, cy - cube, cx + cube, cy + cube),
        radius=max(2, cube // 4),
        outline=CREAM,
        width=max(1, size // 128),
    )

    d.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=corner,
        outline=GOLD,
        width=max(2, size // 90),
    )
    return img


def sips_resize(src: str, out: str, px: int) -> None:
    subprocess.run(["sips", "-z", str(px), str(px), src, "--out", out], check=True, capture_output=True)


def main() -> None:
    os.makedirs(ICONSET, exist_ok=True)
    tmp = os.path.join(ICONSET, "AppIcon-1024-tmp.png")
    draw_icon(1024).save(tmp, "PNG")
    targets = {
        "AppIcon-1024.png": 1024,
        "AppIcon-180.png": 180,
        "AppIcon-167.png": 167,
        "AppIcon-152.png": 152,
        "AppIcon-120.png": 120,
        "AppIcon-87.png": 87,
        "AppIcon-80.png": 80,
        "AppIcon-76.png": 76,
        "AppIcon-60.png": 60,
        "AppIcon-58.png": 58,
        "AppIcon-40.png": 40,
        "AppIcon-29.png": 29,
        "AppIcon-20.png": 20,
    }
    for name, dim in targets.items():
        sips_resize(tmp, os.path.join(ICONSET, name), dim)
    os.remove(tmp)
    print("Wrote", len(targets), "forest brand icons to", ICONSET)


if __name__ == "__main__":
    main()
