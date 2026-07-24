#!/usr/bin/env python3
"""Remove bottom text from Product Studio Pro icon; scale artwork to fill the square."""
from __future__ import annotations

import os
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip install Pillow", file=sys.stderr)
    raise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DEFAULT_SOURCE = os.path.join(ROOT, "scripts", "source_app_icon.png")
ICONSET = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")

# Crop above the color dots + PRODUCT STUDIO PRO text (~bottom 30% of square icon).
CROP_BOTTOM_FRACTION = 0.30
PADDING_FRACTION = 0.06


def crop_and_fit(src_path: str, size: int) -> Image.Image:
    im = Image.open(src_path).convert("RGBA")
    w, h = im.size
    crop_h = int(h * (1.0 - CROP_BOTTOM_FRACTION))
    cropped = im.crop((0, 0, w, crop_h))

    # Trim near-white margins so camera + panels scale up.
    bg = cropped.convert("RGB")
    bbox = bg.getbbox()
    if bbox:
        cropped = cropped.crop(bbox)

    pad = int(size * PADDING_FRACTION)
    inner = size - 2 * pad
    cw, ch = cropped.size
    scale = min(inner / cw, inner / ch)
    nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)

    out = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    ox = (size - nw) // 2
    oy = (size - nh) // 2
    out.paste(resized, (ox, oy), resized)
    return out.convert("RGB")


def sips_resize(src: str, out: str, px: int) -> None:
    subprocess.run(["sips", "-z", str(px), str(px), src, "--out", out], check=True, capture_output=True)


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not os.path.isfile(src):
        print("Source icon not found:", src, file=sys.stderr)
        sys.exit(1)
    os.makedirs(ICONSET, exist_ok=True)
    master = os.path.join(ICONSET, "AppIcon-1024-tmp.png")
    crop_and_fit(src, 1024).save(master, "PNG")
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
        sips_resize(master, os.path.join(ICONSET, name), dim)
    os.remove(master)
    print("Wrote", len(targets), "icons from", src)


if __name__ == "__main__":
    main()
