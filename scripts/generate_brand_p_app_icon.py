#!/usr/bin/env python3
"""Recolor P + aperture icon to brand palette and scale artwork to fill the square."""
from __future__ import annotations

import os
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    print("Run: PYTHONPATH=.build_pillow python3 scripts/generate_brand_p_app_icon.py", file=sys.stderr)
    raise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")
DEFAULT_SOURCE = os.path.join(
    ROOT,
    "scripts",
    "brand_p_icon_source.png",
)

# Brand palette
CHARCOAL = (0x28, 0x3F, 0x3B)
MINT = (0x99, 0xDD, 0xC8)
WHITE = (255, 255, 255)

# Target fill inside the 1024 master (smaller = larger artwork)
PADDING_FRACTION = 0.045


def lerp(a: int, b: int, t: float) -> int:
    return int(max(0, min(255, a + (b - a) * t)))


def is_white(r: int, g: int, b: int, a: int) -> bool:
    return a > 200 and r > 238 and g > 238 and b > 238


def is_dark(r: int, g: int, b: int) -> bool:
    return max(r, g, b) < 72


def is_brand_green(r: int, g: int, b: int, a: int) -> bool:
    if a < 16:
        return False
    if is_white(r, g, b, a) or is_dark(r, g, b):
        return False
    # Teal / green family from the reference artwork
    return g >= r - 8 and g >= b - 6 and (g - min(r, b)) > 12


def recolor_artwork(im: Image.Image) -> Image.Image:
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()

    # Content bounds for vertical gradient on the P
    ymin, ymax = h, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if is_brand_green(r, g, b, a):
                ymin = min(ymin, y)
                ymax = max(ymax, y)
    if ymax <= ymin:
        ymin, ymax = 0, h - 1
    span = max(1, ymax - ymin)

    out = Image.new("RGBA", (w, h), (*WHITE, 255))
    opx = out.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            if is_white(r, g, b, a):
                opx[x, y] = (r, g, b, a)
                continue
            if is_dark(r, g, b):
                # Keep aperture depth; slight cool tint
                opx[x, y] = (
                    min(255, int(r * 0.92 + CHARCOAL[0] * 0.08)),
                    min(255, int(g * 0.92 + CHARCOAL[1] * 0.08)),
                    min(255, int(b * 0.92 + CHARCOAL[2] * 0.08)),
                    a,
                )
                continue
            if is_brand_green(r, g, b, a):
                t = (y - ymin) / span
                # Preserve highlight/shadow from source luminance
                lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                base_r = lerp(CHARCOAL[0], MINT[0], t)
                base_g = lerp(CHARCOAL[1], MINT[1], t)
                base_b = lerp(CHARCOAL[2], MINT[2], t)
                shade = 0.78 + 0.32 * lum
                nr = min(255, int(base_r * shade))
                ng = min(255, int(base_g * shade))
                nb = min(255, int(base_b * shade))
                opx[x, y] = (nr, ng, nb, a)
                continue
            opx[x, y] = (r, g, b, a)

    return out


def content_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    min_x, min_y, max_x, max_y = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 20 and not is_white(r, g, b, a):
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x <= min_x:
        return 0, 0, w, h
    return min_x, min_y, max_x + 1, max_y + 1


def fit_to_square(im: Image.Image, size: int) -> Image.Image:
    cropped = im.crop(content_bbox(im))
    pad = int(size * PADDING_FRACTION)
    inner = size - 2 * pad
    cw, ch = cropped.size
    scale = min(inner / cw, inner / ch)
    nw = max(1, int(cw * scale))
    nh = max(1, int(ch * scale))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (*WHITE, 255))
    ox = (size - nw) // 2
    oy = (size - nh) // 2
    canvas.paste(resized, (ox, oy), resized)
    return canvas.convert("RGB")


def sips_resize(src: str, out: str, px: int) -> None:
    subprocess.run(["sips", "-z", str(px), str(px), src, "--out", out], check=True, capture_output=True)


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not os.path.isfile(src):
        print("Source not found:", src, file=sys.stderr)
        sys.exit(1)

    os.makedirs(ICONSET, exist_ok=True)
    im = Image.open(src)
    recolored = recolor_artwork(im)
    master_img = fit_to_square(recolored, 1024)

    master_path = os.path.join(ICONSET, "AppIcon-1024-tmp.png")
    master_img.save(master_path, "PNG")

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
        sips_resize(master_path, os.path.join(ICONSET, name), dim)
    os.remove(master_path)
    print("Wrote", len(targets), "brand P icons to", ICONSET)


if __name__ == "__main__":
    main()
