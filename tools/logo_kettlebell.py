"""The WODwrist logo (option A, "kettlebell chrono"), no deps.

A yellow kettlebell whose bell is a stopwatch dial. Coordinates are in a
512 x 512 design space (same as tools/logo/index.html, option A).
shade(x, y) -> (r, g, b) or None (background). png() writes RGB or RGBA.
Used by make_web_icons.py (web app / home screen) and make_icon.py (watch).
"""
import math
import struct
import zlib

Y = (240, 168, 0)
W = (236, 234, 228)
GREY = (138, 141, 147)
DIAL = (17, 19, 23)

CX, CY, S = 256.0, 250.0, 190.0
DX, DY = 256.0, 273.0          # dial center


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
    return math.hypot(px - ax - t * vx, py - ay - t * vy)


def shade(x, y):
    # dial (drawn over the bell)
    r = math.hypot(x - DX, y - DY)
    if r <= 78:
        if r <= 12 or seg_dist(x, y, DX, DY, 300, 225) <= 8:
            return W
        for i in range(12):
            a = i * math.pi / 6
            major = i % 3 == 0
            if seg_dist(x, y, DX + math.cos(a) * 58, DY + math.sin(a) * 58,
                        DX + math.cos(a) * 70, DY + math.sin(a) * 70) <= (4.5 if major else 2.5):
                return W if major else GREY
        return DIAL
    # bell
    if math.hypot(x - CX, y - (CY + 0.12 * S)) <= 0.62 * S:
        return Y
    # base
    if CX - 0.6 * S <= x <= CX + 0.6 * S and CY + 0.62 * S <= y <= CY + 0.70 * S:
        return Y
    # handle: upper half of an ellipse, stroke 0.16 S
    a, b, hy = 0.36 * S, 0.47 * S, CY - 0.32 * S
    if y <= hy + 0.02 * S:
        rho = math.hypot((x - CX) / a, (y - hy) / b)
        if abs(rho - 1) * (a + b) / 2 <= 0.08 * S:
            return Y
    return None


def render(n, bg, zoom=1.0, center=(256.0, 234.0), ss=3):
    """n x n pixels. bg: RGB tuple, or None for transparent. zoom > 1 = bigger logo."""
    span = 512.0 / zoom
    x0, y0 = center[0] - span / 2, center[1] - span / 2
    rows = []
    for py in range(n):
        row = bytearray([0])
        for px in range(n):
            acc = [0, 0, 0, 0]
            for sy in range(ss):
                for sx in range(ss):
                    c = shade(x0 + (px + (sx + 0.5) / ss) * span / n, y0 + (py + (sy + 0.5) / ss) * span / n)
                    if c is None:
                        if bg is None:
                            continue
                        c = bg
                    acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; acc[3] += 255
            k = ss * ss
            if bg is None:
                cov = acc[3] // 255
                if cov == 0:
                    row += bytes([0, 0, 0, 0])
                else:
                    row += bytes([acc[0] // cov, acc[1] // cov, acc[2] // cov, acc[3] // k])
            else:
                row += bytes(v // k for v in acc[:3])
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    color_type = 6 if bg is None else 2
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, color_type, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
