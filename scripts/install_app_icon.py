#!/usr/bin/env python3
"""Copy master app icon into AppIcon.appiconset as real PNG files (all sizes)."""
from __future__ import annotations

import os
import sys

try:
    from PIL import Image
except ImportError:
    print("PYTHONPATH=.build_pillow python3 scripts/install_app_icon.py [master.png]", file=sys.stderr)
    raise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "ProductStudioPro", "Assets.xcassets", "AppIcon.appiconset")
DEFAULT = os.path.join(ROOT, "scripts", "app_icon_master.png")
SIZES = (20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024)


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.isfile(src):
        sys.exit(f"Missing: {src}")

    source = Image.open(src).convert("RGB")
    os.makedirs(ICONSET, exist_ok=True)

    for dim in SIZES:
        out = os.path.join(ICONSET, f"AppIcon-{dim}.png")
        if dim == source.width == source.height:
            img = source
        else:
            img = source.resize((dim, dim), Image.Resampling.LANCZOS)
        img.save(out, format="PNG", optimize=True)

    print(f"Installed {len(SIZES)} PNG icons from {src}")


if __name__ == "__main__":
    main()
