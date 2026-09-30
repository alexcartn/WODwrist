#!/usr/bin/env python3
"""Draw the watch icons (movement pictograms, menu icons) as PNGs, no deps.

Shapes are drawn at 4x and averaged down (anti-aliasing). White on
transparent: the app draws them on black. Writes
watch-app/resources/drawables/icons/*.png and drawables.xml.
Run: python3 tools/make_icons.py
"""
import math
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "watch-app/resources/drawables"
N = 36          # icon size on the watch
SS = 4          # supersampling
S = N * SS


class Canvas:
    def __init__(self):
        self.a = [[0.0] * S for _ in range(S)]

    def _plot(self, fn):
        for y in range(S):
            for x in range(S):
                if fn(x / SS, y / SS):
                    self.a[y][x] = 1.0

    def line(self, x0, y0, x1, y1, w=3.0):
        def f(x, y):
            dx, dy = x1 - x0, y1 - y0
            L = dx * dx + dy * dy
            t = 0 if L == 0 else max(0, min(1, ((x - x0) * dx + (y - y0) * dy) / L))
            px, py = x0 + t * dx, y0 + t * dy
            return (x - px) ** 2 + (y - py) ** 2 <= (w / 2) ** 2
        self._plot(f)

    def disc(self, cx, cy, r):
        self._plot(lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r)

    def ring(self, cx, cy, r, w=3.0, a0=0, a1=360):
        def f(x, y):
            d = math.hypot(x - cx, y - cy)
            if abs(d - r) > w / 2:
                return False
            ang = math.degrees(math.atan2(-(y - cy), x - cx)) % 360
            return a0 <= ang <= a1 if a0 <= a1 else (ang >= a0 or ang <= a1)
        self._plot(f)

    def rect(self, x0, y0, x1, y1):
        self._plot(lambda x, y: x0 <= x <= x1 and y0 <= y <= y1)

    def poly(self, pts):
        def inside(x, y):
            c = False
            for i in range(len(pts)):
                (xa, ya), (xb, yb) = pts[i], pts[i - 1]
                if (ya > y) != (yb > y) and x < (xb - xa) * (y - ya) / (yb - ya) + xa:
                    c = not c
            return c
        self._plot(inside)

    def png(self, color=(255, 255, 255)):
        rows = []
        for y in range(N):
            row = b"\x00"
            for x in range(N):
                s = sum(self.a[y * SS + j][x * SS + i] for j in range(SS) for i in range(SS)) / (SS * SS)
                row += bytes(color) + bytes([int(round(s * 255))])
            rows.append(row)
        raw = b"".join(rows)

        def chunk(t, d):
            return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def figure(c, head, hip, hands, feet, w=3.0):
    """Stick figure: head center, hip point, hand points, foot points."""
    hx, hy = head
    c.disc(hx, hy, 3.6)
    # shoulders a bit below the head so arms do not swallow it
    neck = (hx + (hip[0] - hx) * 0.42, hy + (hip[1] - hy) * 0.42)
    c.line(*neck, *hip, w)
    for p in hands:
        c.line(*neck, *p, w)
    for p in feet:
        c.line(*hip, *p, w)


ICONS = {}


def icon(name):
    def deco(fn):
        ICONS[name] = fn
        return fn
    return deco


@icon("ball")        # wall ball
def _(c):
    c.ring(18, 18, 12, 3)
    c.ring(18, 30, 14, 2.2, 55, 125)
    c.ring(18, 6, 14, 2.2, 235, 305)


@icon("kb")          # kettlebell
def _(c):
    c.disc(18, 22, 10)
    c.ring(18, 10, 7, 3.2, 0, 180)
    c.line(11, 10, 11, 15, 3.2)
    c.line(25, 10, 25, 15, 3.2)


@icon("db")          # dumbbell
def _(c):
    c.line(9, 18, 27, 18, 3)
    c.rect(5, 11, 10, 25)
    c.rect(26, 11, 31, 25)


@icon("barbell")
def _(c):
    c.line(2, 18, 34, 18, 2.5)
    c.rect(6, 8, 10, 28)
    c.rect(26, 8, 30, 28)
    c.rect(11, 12, 13, 24)
    c.rect(23, 12, 25, 24)


@icon("burpee")      # jump with arms up
def _(c):
    figure(c, (18, 7), (18, 21), [(9, 4), (27, 4)], [(12, 33), (24, 33)])


@icon("pull")        # hanging from a bar
def _(c):
    c.line(3, 4, 33, 4, 2.5)
    figure(c, (18, 11), (18, 26), [(9, 4), (27, 4)], [(15, 35), (21, 35)])


@icon("squat")       # body weight: squat
def _(c):
    figure(c, (15, 8), (14, 22), [(27, 13), (27, 15)], [])
    c.line(14, 22, 24, 23, 3)
    c.line(24, 23, 22, 32, 3)
    c.line(20, 32, 27, 32, 3)


@icon("box")         # box jump
def _(c):
    c.rect(8, 22, 28, 33)
    c.disc(18, 27.5, 0)  # keep the box solid
    c.line(18, 18, 18, 4, 3)
    c.poly([(12, 9), (24, 9), (18, 2)])


@icon("rope")        # jump rope
def _(c):
    figure(c, (18, 10), (18, 22), [(10, 18), (26, 18)], [(14, 31), (22, 31)], 2.6)
    c.ring(18, 17, 15, 2, 200, 340)


@icon("climb")       # rope climb
def _(c):
    c.line(18, 1, 18, 35, 3)
    for y in (8, 16, 24, 32):
        c.line(15, y, 21, y - 3, 2)


@icon("row")         # rower
def _(c):
    c.disc(8, 20, 7)
    c.line(8, 31, 34, 31, 3)
    c.line(15, 20, 30, 29, 2.5)
    c.rect(24, 25, 32, 29)


@icon("run")
def _(c):
    figure(c, (21, 6), (16, 20), [(28, 13), (9, 12)], [(24, 28), (7, 25)])
    c.line(24, 28, 22, 34, 3)


@icon("bike")
def _(c):
    c.ring(9, 24, 7, 2.5)
    c.ring(27, 24, 7, 2.5)
    c.line(9, 24, 17, 12, 2.5)
    c.line(17, 12, 27, 24, 2.5)
    c.line(17, 12, 14, 7, 2.5)
    c.line(11, 7, 17, 7, 2.5)


@icon("ski")         # ski erg handles
def _(c):
    c.rect(8, 3, 28, 7)
    c.line(12, 7, 10, 30, 2.5)
    c.line(24, 7, 26, 30, 2.5)
    c.rect(7, 28, 13, 33)
    c.rect(23, 28, 29, 33)


@icon("hold")        # plank / static
def _(c):
    c.disc(7, 17, 3.2)
    c.line(9, 19, 31, 24, 3)
    c.line(11, 20, 11, 28, 3)
    c.line(31, 24, 33, 28, 3)


# ---- menu icons ----
@icon("m_play")
def _(c):
    c.poly([(11, 6), (11, 30), (30, 18)])


@icon("m_list")
def _(c):
    for y in (9, 18, 27):
        c.disc(7, y, 2.5)
        c.line(13, y, 31, y, 3)


@icon("m_stats")
def _(c):
    c.rect(5, 20, 11, 32)
    c.rect(15, 12, 21, 32)
    c.rect(25, 5, 31, 32)


@icon("m_coach")     # stopwatch
def _(c):
    c.ring(18, 21, 12, 3)
    c.line(18, 21, 18, 13, 3)
    c.line(18, 21, 24, 24, 3)
    c.rect(15, 3, 21, 6)


@icon("m_sync")
def _(c):
    c.ring(18, 18, 11, 3, 30, 170)
    c.ring(18, 18, 11, 3, 210, 350)
    c.poly([(3, 17), (13, 17), (8, 24)])
    c.poly([(23, 19), (33, 19), (28, 12)])


@icon("m_star")
def _(c):
    pts = []
    for i in range(10):
        r = 15 if i % 2 == 0 else 6.5
        a = math.radians(90 + i * 36)
        pts.append((18 + r * math.cos(a), 19 - r * math.sin(a)))
    c.poly(pts)


def main():
    (OUT / "icons").mkdir(parents=True, exist_ok=True)
    entries = ['    <bitmap id="LauncherIcon" filename="launcher_icon.png" />']
    for name, fn in ICONS.items():
        c = Canvas()
        fn(c)
        (OUT / "icons" / f"{name}.png").write_bytes(c.png())
        entries.append(f'    <bitmap id="Icon_{name}" filename="icons/{name}.png" />')
    (OUT / "drawables.xml").write_text("<drawables>\n" + "\n".join(entries) + "\n</drawables>\n")
    # icon name -> resource id, for Icons.mc
    mc = ["// GENERATED by tools/make_icons.py. Do not edit.", "", "import Toybox.Lang;", "", "module IconRes {", "",
          "    function id(name as String) as ResourceId? {"]
    for name in ICONS:
        mc.append(f'        if (name.equals("{name}")) {{ return Rez.Drawables.Icon_{name}; }}')
    mc += ["        return null;", "    }", "}", ""]
    (ROOT / "watch-app/source/ui/IconRes.mc").write_text("\n".join(mc))
    print("wrote", len(ICONS), "icons")


if __name__ == "__main__":
    main()
