"""Grid-search rep-counter parameters for one movement.

Usage (from rep-lab/):
  python -m replab.tune --movement wall_ball data/wb_session1 data/wb_session2
  python -m replab.tune --movement wall_ball data/wb_* --write   # updates docs/movements.json

A session directory contains:
  watch.txt     the capture log copied from the watch (APPS/LOGS/WODWRIST.TXT)
  labels.csv    optional WODvision rep times (see labels.py). Without it the
                manual button markers from the log are used as ground truth.
  meta.json     optional {"movement": "wall_ball", "offset_ms": 12345}
                offset_ms = watch_ms - video_ms. Estimated from markers if absent.
"""
from __future__ import annotations

import argparse
import itertools
import json
import math
import pathlib
import sys
from dataclasses import dataclass

from .counter import BASE_SHIFT, Profile, _toward, _toward_shift
from .evaluate import best_offset, score
from .labels import load_labels
from .logparse import parse_file

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "docs" / "movements.json"

GRID = {
    "alphaQ8": [32, 48, 64, 96, 128],
    "hiMg": list(range(200, 1001, 50)),
    "loMg": [50, 100, 150, 200],
    "minGapMs": list(range(500, 2001, 100)),
}


@dataclass
class Session:
    name: str
    samples: list  # (t, x, y, z)
    truth: list  # rep times, watch clock


def load_session(path: pathlib.Path, movement: str) -> Session:
    meta = {}
    if (path / "meta.json").exists():
        meta = json.loads((path / "meta.json").read_text())
    cap = parse_file(path / "watch.txt")
    if cap.blocks:
        cap = cap.segment(movement)
    marks = cap.rep_marks()
    label_file = next((p for p in (path / "labels.csv", path / "labels.json") if p.exists()), None)
    if label_file is None:
        if not marks:
            sys.exit(f"{path}: no labels file and no manual markers")
        truth = marks
    else:
        video = load_labels(label_file, movement)
        if "offset_ms" in meta:
            off = int(meta["offset_ms"])
        else:
            anchor = marks or cap.detected
            if not anchor:
                sys.exit(f"{path}: need offset_ms in meta.json or markers in the log")
            guess = anchor[0] - video[0]
            off = best_offset(video, anchor, guess - 60_000, guess + 60_000)
            print(f"{path.name}: estimated offset {off} ms")
        truth = [v + off for v in video]
    return Session(path.name, cap.samples, truth)


def dev_series(samples, alpha_q8: int) -> list[int]:
    """Same filter as counter.RepCounter, fixed alpha, returns dev per sample."""
    out = []
    lp = base = -1
    for _, x, y, z in samples:
        m = int(math.sqrt(x * x + y * y + z * z))
        if lp < 0:
            lp = m
        if base < 0:
            base = m
        lp = _toward(lp, m, alpha_q8)
        base = _toward_shift(base, lp, BASE_SHIFT)
        out.append(lp - base)
    return out


def candidates(ts, dev, hi: int, lo: int) -> list[int]:
    """Peak times before the minGap filter (the gap filter does not change arming)."""
    out = []
    high = False
    pv = pt = 0
    for t, d in zip(ts, dev):
        if not high:
            if d > hi:
                high, pv, pt = True, d, t
            continue
        if d > pv:
            pv, pt = d, t
        if d < lo:
            high = False
            out.append(pt)
    return out


def gap_filter(cands, gap: int) -> list[int]:
    out = []
    last = -(10**9)
    for t in cands:
        if t - last >= gap:
            out.append(t)
            last = t
    return out


def evaluate_profile(sessions, p: Profile, tol_ms: int = 600):
    res = []
    for s in sessions:
        ts = [x[0] for x in s.samples]
        dev = dev_series(s.samples, p.alphaQ8)
        det = gap_filter(candidates(ts, dev, p.hiMg, p.loMg), p.minGapMs)
        res.append(score(det, s.truth, tol_ms))
    return res


def search(sessions, grid=GRID, tol_ms: int = 600):
    best = None
    for alpha in grid["alphaQ8"]:
        per_session = []
        for s in sessions:
            per_session.append(([x[0] for x in s.samples], dev_series(s.samples, alpha)))
        for hi, lo in itertools.product(grid["hiMg"], grid["loMg"]):
            if lo >= hi:
                continue
            cands = [candidates(ts, dev, hi, lo) for ts, dev in per_session]
            for gap in grid["minGapMs"]:
                scores = [score(gap_filter(c, gap), s.truth, tol_ms) for c, s in zip(cands, sessions)]
                f1 = sum(x.f1 for x in scores) / len(scores)
                acc = sum(x.count_accuracy for x in scores) / len(scores)
                key = (round(f1, 4), round(acc, 4))
                if best is None or key > best[0]:
                    best = (key, Profile(alpha, hi, lo, gap), scores)
    return best


def write_catalog(movement: str, p: Profile) -> None:
    data = json.loads(CATALOG.read_text())
    for m in data["movements"]:
        if m["id"] == movement:
            m["counter"] = {**p.to_dict(), "tuned": True}
            break
    else:
        sys.exit(f"movement {movement} not in catalog")
    CATALOG.write_text(json.dumps(data, indent=2) + "\n")
    print(f"updated {CATALOG.relative_to(ROOT)}; now run: python3 tools/gen_movements.py")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--movement", required=True)
    ap.add_argument("--tol", type=int, default=600, help="match tolerance in ms")
    ap.add_argument("--write", action="store_true", help="write best params to docs/movements.json")
    ap.add_argument("sessions", nargs="+", type=pathlib.Path)
    a = ap.parse_args(argv)

    sessions = [load_session(p, a.movement) for p in a.sessions]
    catalog = {m["id"]: m for m in json.loads(CATALOG.read_text())["movements"]}
    cur = catalog.get(a.movement, {}).get("counter")
    if cur:
        print("current params:", cur)
        for s, sc in zip(sessions, evaluate_profile(sessions, Profile.from_dict(cur), a.tol)):
            print(f"  {s.name}: {sc}")

    (f1, acc), p, scores = search(sessions, tol_ms=a.tol)
    print("best params:", p.to_dict(), f"mean F1={f1} mean count_acc={acc}")
    for s, sc in zip(sessions, scores):
        print(f"  {s.name}: {sc}")
    if acc < 0.95:
        print("warning: below the 95 % count accuracy target, collect more data or keep manual counting")
    if a.write:
        write_catalog(a.movement, p)


if __name__ == "__main__":
    main()
