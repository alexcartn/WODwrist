"""Ground-truth rep labels coming from WODvision (video analysis).

Accepted inputs (times in seconds from the start of the video):
  * CSV with a header containing `t` (or `time`, `timestamp`), optional `movement`
  * JSON: a list of numbers, a list of {"t": ...}, or {"reps": [...]}

If WODvision's export format differs, add a reader here: everything downstream
only needs a sorted list of rep times in ms (video clock).
"""
from __future__ import annotations

import csv
import json
import pathlib

TIME_KEYS = ("t", "time", "timestamp", "t_sec")


def _from_items(items, movement=None) -> list[int]:
    out = []
    for it in items:
        if isinstance(it, (int, float)):
            out.append(round(it * 1000))
            continue
        if movement and it.get("movement") not in (None, movement):
            continue
        for k in TIME_KEYS:
            if k in it:
                out.append(round(float(it[k]) * 1000))
                break
    return sorted(out)


def load_labels(path, movement: str | None = None) -> list[int]:
    p = pathlib.Path(path)
    if p.suffix.lower() == ".json":
        data = json.loads(p.read_text())
        if isinstance(data, dict):
            data = data.get("reps", [])
        return _from_items(data, movement)
    with p.open(newline="") as f:
        rows = list(csv.DictReader(f))
    return _from_items(rows, movement)
