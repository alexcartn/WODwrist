"""Reference rep counter.

This is the exact algorithm that runs on the watch
(watch-app/source/rep/RepCounter.mc). Integer math only so both sides give
identical results: tune here, copy the 4 parameters into docs/movements.json.

Pipeline per sample (25 Hz, milli-g):
  1. magnitude m = int(sqrt(x^2 + y^2 + z^2))
  2. fast low-pass  lp   += (m - lp)   * alphaQ8 / 256
  3. slow baseline  base += (lp - base) / 2^BASE_SHIFT      (~5 s at 25 Hz)
  4. dev = lp - base
  5. hysteresis peak detector: arm when dev > hiMg, track the max,
     release when dev < loMg -> one rep at the time of the max,
     unless it is closer than minGapMs to the previous rep.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, asdict

BASE_SHIFT = 7
CONF_WINDOW = 5


@dataclass(frozen=True)
class Profile:
    alphaQ8: int
    hiMg: int
    loMg: int
    minGapMs: int

    @staticmethod
    def from_dict(d: dict) -> "Profile":
        return Profile(int(d["alphaQ8"]), int(d["hiMg"]), int(d["loMg"]), int(d["minGapMs"]))

    def to_dict(self) -> dict:
        return asdict(self)


def _toward(cur: int, target: int, alpha_q8: int) -> int:
    # Symmetric integer step so Monkey C and Python round the same way.
    d = target - cur
    if d >= 0:
        return cur + ((d * alpha_q8) >> 8)
    return cur - (((-d) * alpha_q8) >> 8)


def _toward_shift(cur: int, target: int, shift: int) -> int:
    d = target - cur
    if d >= 0:
        return cur + (d >> shift)
    return cur - ((-d) >> shift)


class RepCounter:
    def __init__(self, profile: Profile):
        self.p = profile
        self.base = -1
        self.reset()

    def reset(self) -> None:
        """New block: forget peaks, keep the gravity baseline."""
        self.lp = -1
        self.high = False
        self.peak_v = 0
        self.peak_t = 0
        self.last_rep_t = -(10**9)
        self.intervals: list[int] = []
        self.count = 0

    def feed(self, t: int, x: int, y: int, z: int) -> int | None:
        """Feed one sample. Returns the rep timestamp (ms) when a rep is detected."""
        m = int(math.sqrt(x * x + y * y + z * z))
        if self.lp < 0:
            self.lp = m
        if self.base < 0:
            self.base = m
        self.lp = _toward(self.lp, m, self.p.alphaQ8)
        self.base = _toward_shift(self.base, self.lp, BASE_SHIFT)
        dev = self.lp - self.base

        if not self.high:
            if dev > self.p.hiMg:
                self.high = True
                self.peak_v = dev
                self.peak_t = t
            return None
        if dev > self.peak_v:
            self.peak_v = dev
            self.peak_t = t
        if dev < self.p.loMg:
            self.high = False
            if self.peak_t - self.last_rep_t >= self.p.minGapMs:
                if self.count > 0:
                    self.intervals.append(self.peak_t - self.last_rep_t)
                    if len(self.intervals) > CONF_WINDOW:
                        self.intervals.pop(0)
                self.last_rep_t = self.peak_t
                self.count += 1
                return self.peak_t
        return None

    def feed_batch(self, t_end: int, xs, ys, zs, period_ms: int = 40) -> list[int]:
        """Feed a watch batch. Sample i is at t_end - (n - 1 - i) * period_ms."""
        n = len(xs)
        reps = []
        for i in range(n):
            r = self.feed(t_end - (n - 1 - i) * period_ms, xs[i], ys[i], zs[i])
            if r is not None:
                reps.append(r)
        return reps

    def confidence(self) -> int:
        """0-100: share of recent rep intervals within 30 % of their median."""
        iv = self.intervals
        if len(iv) < 2:
            return 50
        s = sorted(iv)
        med = s[len(s) // 2]
        ok = sum(1 for v in iv if abs(v - med) * 10 <= med * 3)
        return (ok * 100) // len(iv)


def count_reps(samples, profile: Profile) -> list[int]:
    """samples: iterable of (t_ms, x, y, z). Returns rep timestamps."""
    c = RepCounter(profile)
    out = []
    for t, x, y, z in samples:
        r = c.feed(t, x, y, z)
        if r is not None:
            out.append(r)
    return out
