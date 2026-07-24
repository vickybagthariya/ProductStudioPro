#!/usr/bin/env python3
"""Premium P app icon from artwork: brand gradient, white outline, scaled to fill frame."""
from __future__ import annotations

import os
import subprocess
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:
    print("Run: PYTHONPATH=.build_pillow python3 scripts/generate_premium_p_app_icon.py", file=sys.stderr)
    raise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")
DEFAULT_SOURCE = os.path.join(ROOT, "scripts", "brand_p_icon_source.png")

CHARCOAL = (0x28, 0x3F, 0x3B)
MINT = (0x99, 0xDD, 0xC8)
WHITE = (255, 255, 255)
PADDING_FRACTION = 0.038
OUTLINE_PX = 14  # at 1024


def lerp(a: int, b: int, t: float) -> int:
    return int(max(0, min(255, a + (b - a) * t)))


def is_white(r: int, g: int, b: int, a: int) -> bool:
    return a > 200 and r > 238 and g > 238 and b > 238


def is_dark(r: int, g: int, b: int) -> bool:
    return max(r, g, b) < 75


def is_brand_green(r: int, g: int, b: int, a: int) -> bool:
    if a < 16 or is_white(r, g, b, a) or is_dark(r, g, b):
        return False
    return g >= r - 10 and g >= b - 8 and (g - min(r, b)) > 10


def recolor_artwork(im: Image.Image) -> Image.Image:
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    ymin, ymax = h, 0
    for y in range(h):
        for x in range(w):
            if is_brand_green(*px[x, y]):
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
                lum = (r + g + b) / 765.0
                opx[x, y] = (
                    int(18 + 40 * lum),
                    int(22 + 44 * lum),
                    int(24 + 46 * lum),
                    a,
                )
                continue
            if is_brand_green(r, g, b, a):
                t = (y - ymin) / span
                lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                base = (
                    lerp(CHARCOAL[0], MINT[0], t),
                    lerp(CHARCOAL[1], MINT[1], t),
                    lerp(CHARCOAL[2], MINT[2], t),
                )
                shade = 0.72 + 0.38 * lum
                opx[x, y] = (
                    min(255, int(base[0] * shade)),
                    min(255, int(base[1] * shade)),
                    min(255, int(base[2] * shade)),
                    a,
                )
                continue
            opx[x, y] = (r, g, b, a)
    return out


def add_white_outline(im: Image.Image, size: int) -> Image.Image:
    """White stroke around non-white artwork."""
    rgba = im.convert("RGBA")
    w, h = rgba.size
    alpha = rgba.split()[3]
    # Mask of colored pixels
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    px = rgba.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 40 and not is_white(r, g, b, a):
                mp[x, y] = 255
    k = max(3, OUTLINE_PX)
    dilated = mask.filter(ImageFilter.MaxFilter(k * 2 + 1))
    ring = ImageChops.subtract(dilated, mask)
    outline = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = outline.load()
    rp = ring.load()
    for y in range(h):
        for x in range(w):
            if rp[x, y] > 0:
                op[x, y] = (*WHITE, min(255, rp[x, y]))
    return Image.alpha_composite(outline, rgba)


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
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (*WHITE, 255))
    ox, oy = (size - nw) // 2, (size - nh) // 2
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
    outlined = add_white_outline(recolored, recolored.size[0])
    master = fit_to_square(outlined, 1024)
    master_path = os.path.join(ICONSET, "AppIcon-1024-tmp.png")
    master.save(master_path, "PNG")
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
    print("Wrote premium P icons to", ICONSET)


if __name__ == "__main__":
    main()
