"""Alignment between clocks, and rep detection scoring."""
from __future__ import annotations

from dataclasses import dataclass


def match(detected: list[int], truth: list[int], tol_ms: int) -> int:
    """Greedy one-to-one matching of sorted timestamps. Returns true positives."""
    i = j = tp = 0
    while i < len(detected) and j < len(truth):
        d = detected[i] - truth[j]
        if abs(d) <= tol_ms:
            tp += 1
            i += 1
            j += 1
        elif d < 0:
            i += 1
        else:
            j += 1
    return tp


@dataclass
class Score:
    n_true: int
    n_detected: int
    tp: int

    @property
    def precision(self) -> float:
        return self.tp / self.n_detected if self.n_detected else 0.0

    @property
    def recall(self) -> float:
        return self.tp / self.n_true if self.n_true else 0.0

    @property
    def f1(self) -> float:
        p, r = self.precision, self.recall
        return 2 * p * r / (p + r) if p + r else 0.0

    @property
    def count_accuracy(self) -> float:
        """What the athlete sees: 1 - |counted - real| / real."""
        if not self.n_true:
            return 0.0
        return max(0.0, 1 - abs(self.n_detected - self.n_true) / self.n_true)

    def __str__(self) -> str:
        return (
            f"true={self.n_true} detected={self.n_detected} tp={self.tp} "
            f"P={self.precision:.3f} R={self.recall:.3f} F1={self.f1:.3f} "
            f"count_acc={self.count_accuracy:.3f}"
        )


def score(detected: list[int], truth: list[int], tol_ms: int = 600) -> Score:
    return Score(len(truth), len(detected), match(sorted(detected), sorted(truth), tol_ms))


def best_offset(
    video_ms: list[int],
    watch_ms: list[int],
    lo: int,
    hi: int,
    step: int = 20,
    tol_ms: int = 300,
) -> int:
    """Offset such that video_ms + offset lines up with watch_ms.

    watch_ms is usually the manual markers (M lines) or the watch-detected reps.
    Search range [lo, hi] in ms; coarse grid then refine around the best value.
    """
    def hits(off):
        return match(sorted(v + off for v in video_ms), sorted(watch_ms), tol_ms)

    best, best_h = lo, -1
    for off in range(lo, hi + 1, step * 10):
        h = hits(off)
        if h > best_h:
            best, best_h = off, h
    # Refine, then take the middle of the plateau of equally good offsets:
    # its edges are only as good as the tolerance.
    fine = [(off, hits(off)) for off in range(best - step * 20, best + step * 20 + 1, step)]
    top = max(h for _, h in fine)
    plateau = [off for off, h in fine if h == top]
    off = plateau[len(plateau) // 2]
    # Final touch: median residual of the matched pairs (robust to a few outliers).
    v = sorted(x + off for x in video_ms)
    w = sorted(watch_ms)
    res = []
    i = j = 0
    while i < len(v) and j < len(w):
        d = w[j] - v[i]
        if abs(d) <= tol_ms:
            res.append(d)
            i += 1
            j += 1
        elif d > 0:
            i += 1
        else:
            j += 1
    if res:
        res.sort()
        off += res[len(res) // 2]
    return off
