#!/usr/bin/env python3
"""Generate opaque Product Studio Pro–style AppIcon PNGs (1024 master + derived sizes)."""
from __future__ import annotations

import os
import subprocess
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Run with PYTHONPATH pointing to workspace .build_pillow (pip install pillow --target .build_pillow).", file=sys.stderr)
    raise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")


def draw_master(size: int = 1024) -> Image.Image:
    w = size
    img = Image.new("RGB", (w, w), (36, 40, 46))
    d = ImageDraw.Draw(img)
    margin = max(28, w // 32)
    gold = (232, 178, 52)
    gold_deep = (168, 124, 28)
    panel = (244, 245, 248)
    inset = margin + w // 28
    radius = w // 4
    d.rounded_rectangle((margin, margin, w - margin - 1, w - margin - 1), radius=radius, fill=(32, 35, 40), outline=gold, width=max(6, w // 90))
    d.rounded_rectangle((inset, inset, w - inset - 1, w - inset - 1), radius=radius - 18, outline=(68, 74, 82), width=max(2, w // 220))

    cx = int(w * 0.38)
    cy = int(w * 0.48)
    r = int(w * 0.15)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=gold, width=max(5, w // 110))
    d.ellipse((cx - int(r * 0.72), cy - int(r * 0.72), cx + int(r * 0.72), cy + int(r * 0.72)), fill=(24, 26, 30), outline=(56, 62, 70), width=max(2, w // 340))
    d.ellipse((cx - int(r * 0.45), cy - int(r * 0.55), cx + int(r * 0.25), cy - int(r * 0.12)), fill=(88, 96, 108))

    tw = int(w * 0.28)
    th = int(w * 0.30)
    tx = cx + r + int(w * 0.04)
    ty = cy - th // 2 - int(w * 0.02)
    corner = max(10, w // 36)
    d.rounded_rectangle((tx, ty, tx + tw, ty + th), radius=corner, fill=panel, outline=gold_deep, width=max(3, w // 220))
    pad = tw // 5
    d.rounded_rectangle((tx + pad, ty + pad, tx + tw - pad, ty + th - pad), radius=corner // 2, fill=(222, 225, 232))
    return img


def sips_resize(src: str, out: str, px: int) -> None:
    subprocess.run(
        ["sips", "-z", str(px), str(px), src, "--out", out],
        check=True,
        capture_output=True,
    )


def main() -> None:
    os.makedirs(ICONSET, exist_ok=True)
    master_path = os.path.join(ICONSET, "AppIcon-1024-tmp.png")
    m = draw_master(1024)
    m.save(master_path, format="PNG")

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
        out = os.path.join(ICONSET, name)
        sips_resize(master_path, out, dim)

    os.remove(master_path)
    print("Wrote", len(targets), "icons to", ICONSET)


if __name__ == "__main__":
    main()
