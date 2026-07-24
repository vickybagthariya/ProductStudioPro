#!/usr/bin/env python3
"""Install premium P icon: #D1D1D6 background, logo fills ~90% of canvas."""
from __future__ import annotations

import os
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    print("PYTHONPATH=.build_pillow python3 scripts/install_premium_icon_from_asset.py", file=sys.stderr)
    raise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")
DEFAULT = os.path.join(ROOT, "scripts", "premium_p_icon_source.png")

# Brand light border / icon plate
BG_RGB = (0xD1, 0xD1, 0xD6)
# Logo occupies this fraction of the square (5% margin each side)
FILL_RATIO = 0.90
# Treat near-black plate as background when finding content bounds
BLACK_KEY = 28


def content_bbox(rgba: Image.Image) -> tuple[int, int, int, int]:
    w, h = rgba.size
    pixels = rgba.load()
    min_x, min_y, max_x, max_y = w, h, 0, 0
    found = False
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 12:
                continue
            if r <= BLACK_KEY and g <= BLACK_KEY and b <= BLACK_KEY:
                continue
            found = True
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
    if not found:
        return (0, 0, w, h)
    return (min_x, min_y, max_x + 1, max_y + 1)


def render_icon(im: Image.Image, size: int) -> Image.Image:
    rgba = im.convert("RGBA")
    bbox = content_bbox(rgba)
    subject = rgba.crop(bbox)

    target = int(size * FILL_RATIO)
    cw, ch = subject.size
    scale = min(target / cw, target / ch)
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    subject = subject.resize((nw, nh), Image.Resampling.LANCZOS)

    bg = Image.new("RGBA", (size, size), (*BG_RGB, 255))
    bg.paste(subject, ((size - nw) // 2, (size - nh) // 2), subject)
    return bg.convert("RGB")


def sips_resize(src: str, out: str, px: int) -> None:
    subprocess.run(["sips", "-z", str(px), str(px), src, "--out", out], check=True, capture_output=True)


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.isfile(src):
        sys.exit(f"Missing: {src}")
    os.makedirs(ICONSET, exist_ok=True)

    source = Image.open(src)
    master = os.path.join(ICONSET, "AppIcon-1024-tmp.png")
    # Use native resolution when source is already 1024; never shrink before export.
    master_px = max(1024, source.size[0], source.size[1])
    render_icon(source, master_px).resize((1024, 1024), Image.Resampling.LANCZOS).save(master, "PNG")

    sizes = {
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
    for name, dim in sizes.items():
        out = os.path.join(ICONSET, name)
        if dim == 1024:
            render_icon(source, 1024).save(out, "PNG")
        else:
            sips_resize(master, out, dim)

    os.remove(master)
    print(f"Installed icon from {src} (bg #{BG_RGB[0]:02X}{BG_RGB[1]:02X}{BG_RGB[2]:02X}, fill {int(FILL_RATIO * 100)}%)")


if __name__ == "__main__":
    main()
