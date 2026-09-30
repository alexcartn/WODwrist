#!/usr/bin/env python3
"""Draw the web editor (PWA) icons, no deps: stopwatch on the dark app color.

Writes web-editor/icons/: icon-192.png, icon-512.png, maskable-512.png
(safe zone: drawing inside the central 80 %), apple-touch-icon.png (180).
Run: python3 tools/make_web_icons.py
"""
import math
import pathlib
import struct
import zlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "web-editor/icons"
BG = (17, 19, 23)
Y = (240, 168, 0)
W = (236, 234, 228)
SS = 3


def shade(u, v, scale):
    """Color at (u, v) in [0,1], drawing scaled by `scale` around the center."""
    x = (u - 0.5) / scale
    y = (v - 0.5) / scale + 0.03
    r = math.hypot(x, y)
    if 0.29 <= r <= 0.37:
        return Y
    if abs(x) <= 0.06 and -0.47 <= y <= -0.39:          # crown
        return Y
    a = math.radians(-50)
    ux, uy = math.cos(a), math.sin(a)
    t = x * ux + y * uy
    d = abs(-x * uy + y * ux)
    if 0 <= t <= 0.24 and d <= 0.03:                     # hand
        return W
    if r <= 0.05:
        return W
    return BG


def draw(n, scale):
    rows = []
    for py in range(n):
        row = bytearray([0])
        for px in range(n):
            acc = [0, 0, 0]
            for sy in range(SS):
                for sx in range(SS):
                    c = shade((px + (sx + 0.5) / SS) / n, (py + (sy + 0.5) / SS) / n, scale)
                    for i in range(3):
                        acc[i] += c[i]
            row += bytes(v // (SS * SS) for v in acc)
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, n, scale in [("icon-192.png", 192, 0.92), ("icon-512.png", 512, 0.92),
                           ("maskable-512.png", 512, 0.78), ("apple-touch-icon.png", 180, 0.9)]:
        (OUT / name).write_bytes(draw(n, scale))
        print("wrote", name)


if __name__ == "__main__":
    main()
