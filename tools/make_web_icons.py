#!/usr/bin/env python3
"""Write the web editor (PWA) icons from the logo in tools/logo_kettlebell.py.

web-editor/icons/: icon-192.png, icon-512.png, maskable-512.png (logo inside
the central safe zone), apple-touch-icon.png (180).
Run: python3 tools/make_web_icons.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from logo_kettlebell import render  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent.parent / "web-editor/icons"
BG = (17, 19, 23)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, n, zoom in [("icon-192.png", 192, 1.3), ("icon-512.png", 512, 1.3),
                          ("maskable-512.png", 512, 1.05), ("apple-touch-icon.png", 180, 1.2)]:
        (OUT / name).write_bytes(render(n, BG, zoom))
        print("wrote", name)


if __name__ == "__main__":
    main()
