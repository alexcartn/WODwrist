#!/usr/bin/env python3
"""Draw the launcher icon (stopwatch + rep tick) without external deps."""
import math, pathlib, struct, zlib

N = 80
BG = (0, 0, 0, 0)
Y = (255, 196, 0, 255)
W = (255, 255, 255, 255)

px = [[BG for _ in range(N)] for _ in range(N)]
c = N / 2
for y in range(N):
    for x in range(N):
        dx, dy = x + 0.5 - c, y + 0.5 - (c + 4)
        r = math.hypot(dx, dy)
        if 24 <= r <= 31:
            px[y][x] = Y
        # crown
        if abs(x + 0.5 - c) <= 5 and 4 <= y <= 9:
            px[y][x] = Y
        # hand pointing to ~2 o'clock
        a = math.radians(-50)
        ux, uy = math.cos(a), math.sin(a)
        t = dx * ux + dy * uy
        d = abs(-dx * uy + dy * ux)
        if 0 <= t <= 20 and d <= 2.5:
            px[y][x] = W
        if r <= 4:
            px[y][x] = W

def png(pixels):
    raw = b"".join(b"\x00" + bytes(v for p in row for v in p) for row in pixels)
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

out = pathlib.Path(__file__).resolve().parent.parent / "watch-app/resources/drawables/launcher_icon.png"
out.write_bytes(png(px))
print("wrote", out)
