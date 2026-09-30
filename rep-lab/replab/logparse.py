"""Parse the capture log written by the watch (APPS/LOGS/WODWRIST.TXT).

Line formats (see watch-app/source/rep/RepCounter.mc and WorkoutSession.mc):
  S,<t_ms>,<wod name>            session start
  B,<t_ms>,<movement id>         block (movement) start
  A,<t_ms>,x0,y0,z0,x1,y1,z1...  accelerometer batch, 25 Hz, milli-g, t = batch arrival
  M,<t_ms>,<delta>               manual rep marker (+1 / -1) from a button press
  R,<t_ms>,<delta>               rep detected by the on-watch counter
  L,<t_ms>,<lap reps>            lap closed
t_ms is System.getTimer() (ms since boot, same clock for every line).
Unknown lines are ignored so the format can grow.
"""
from __future__ import annotations

from dataclasses import dataclass, field

PERIOD_MS = 40


@dataclass
class Capture:
    samples: list[tuple[int, int, int, int]] = field(default_factory=list)  # (t, x, y, z)
    markers: list[tuple[int, int]] = field(default_factory=list)  # (t, delta)
    detected: list[int] = field(default_factory=list)
    blocks: list[tuple[int, str]] = field(default_factory=list)  # (t, movement)
    laps: list[tuple[int, int]] = field(default_factory=list)
    sessions: list[tuple[int, str]] = field(default_factory=list)

    def segment(self, movement: str) -> "Capture":
        """Keep only the time ranges where `movement` was the active block."""
        ranges = []
        for i, (t, mv) in enumerate(self.blocks):
            if mv == movement:
                end = self.blocks[i + 1][0] if i + 1 < len(self.blocks) else 1 << 62
                ranges.append((t, end))
        if not ranges:
            return Capture()

        def inside(t):
            return any(a <= t < b for a, b in ranges)

        return Capture(
            samples=[s for s in self.samples if inside(s[0])],
            markers=[m for m in self.markers if inside(m[0])],
            detected=[d for d in self.detected if inside(d)],
            blocks=[b for b in self.blocks if b[1] == movement],
            laps=[l for l in self.laps if inside(l[0])],
            sessions=self.sessions,
        )

    def rep_marks(self) -> list[int]:
        """Manual +1 presses as rep times, a -1 removes the previous +1."""
        out: list[int] = []
        for t, d in self.markers:
            if d > 0:
                out.extend([t] * d)
            elif out:
                del out[d:]
        return out


def parse_lines(lines) -> Capture:
    cap = Capture()
    for raw in lines:
        line = raw.strip()
        # Garmin may prefix nothing, but tolerate "timestamp: " style prefixes.
        for tag in ("A,", "M,", "R,", "B,", "L,", "S,"):
            k = line.find(tag)
            if k >= 0 and (k == 0 or not line[k - 1].isalnum()):
                line = line[k:]
                break
        parts = line.split(",")
        if len(parts) < 3:
            continue
        kind = parts[0]
        try:
            t = int(parts[1])
        except ValueError:
            continue
        try:
            if kind == "A":
                vals = [int(v) for v in parts[2:]]
                n = len(vals) // 3
                for i in range(n):
                    ts = t - (n - 1 - i) * PERIOD_MS
                    cap.samples.append((ts, vals[3 * i], vals[3 * i + 1], vals[3 * i + 2]))
            elif kind == "M":
                cap.markers.append((t, int(parts[2])))
            elif kind == "R":
                cap.detected.append(t)
            elif kind == "B":
                cap.blocks.append((t, parts[2]))
            elif kind == "L":
                cap.laps.append((t, int(parts[2])))
            elif kind == "S":
                cap.sessions.append((t, ",".join(parts[2:])))
        except ValueError:
            continue
    cap.samples.sort()
    return cap


def parse_file(path) -> Capture:
    with open(path, encoding="utf-8", errors="replace") as f:
        return parse_lines(f)
