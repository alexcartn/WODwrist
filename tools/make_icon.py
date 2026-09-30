#!/usr/bin/env python3
"""Write the watch launcher icon (80 x 80, transparent) from the logo in
tools/logo_kettlebell.py. Run: python3 tools/make_icon.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from logo_kettlebell import render  # noqa: E402

out = pathlib.Path(__file__).resolve().parent.parent / "watch-app/resources/drawables/launcher_icon.png"
out.write_bytes(render(80, None, zoom=1.6, center=(256.0, 236.0), ss=4))
print("wrote", out)
