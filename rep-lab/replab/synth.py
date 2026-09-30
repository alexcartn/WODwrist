"""Synthetic wrist signals, for tests and for sanity-checking the pipeline
before real captures exist. Not a substitute for real data."""
from __future__ import annotations

import math
import random

PERIOD_MS = 40


def synth_session(
    n_reps: int = 30,
    period_ms: int = 2000,
    jitter_ms: int = 200,
    main_mg: int = 900,
    catch_mg: int = 350,
    noise_mg: int = 60,
    seed: int = 1,
    t0: int = 100_000,
):
    """Returns (samples, rep_times). Each rep = a big throw pulse + a smaller
    catch pulse 500 ms later (the double peak that makes wall balls tricky)."""
    rnd = random.Random(seed)
    reps = []
    t = t0 + 3000
    for _ in range(n_reps):
        reps.append(t)
        t += period_ms + rnd.randint(-jitter_ms, jitter_ms)
    end = t + 3000

    def pulse(dt, width, amp):
        if 0 <= dt <= width:
            return amp * math.sin(math.pi * dt / width)
        return 0.0

    samples = []
    for ts in range(t0, end, PERIOD_MS):
        extra = 0.0
        for r in reps:
            extra += pulse(ts - (r - 150), 300, main_mg)
            extra += pulse(ts - (r + 450), 250, catch_mg)
        # gravity mostly on z, slowly tilting wrist
        tilt = 0.3 * math.sin(ts / 4000.0)
        gx = 1000 * math.sin(tilt)
        gz = 1000 * math.cos(tilt) + extra
        samples.append(
            (
                ts,
                int(gx + rnd.randint(-noise_mg, noise_mg)),
                int(rnd.randint(-noise_mg, noise_mg)),
                int(gz + rnd.randint(-noise_mg, noise_mg)),
            )
        )
    return samples, reps


def to_log_lines(samples, batch: int = 25) -> list[str]:
    """Render samples the way the watch logs them (one A line per 1 s batch)."""
    lines = []
    for i in range(0, len(samples), batch):
        chunk = samples[i : i + batch]
        vals = []
        for _, x, y, z in chunk:
            vals += [x, y, z]
        lines.append("A," + str(chunk[-1][0]) + "," + ",".join(str(v) for v in vals))
    return lines


def deterministic_pulses(n_reps: int = 10) -> list[tuple[int, int, int, int]]:
    """No randomness, integer only: shared with the Monkey C unit test
    (watch-app/test/RepCounterTest.mc) so both implementations must agree."""
    samples = []
    t = 0
    for _ in range(40):  # 1.6 s still
        samples.append((t, 0, 0, 1000))
        t += PERIOD_MS
    for _ in range(n_reps):
        for k in range(50):  # 2 s per rep
            z = 1000
            if 5 <= k < 12:
                z = 1000 + (k - 4) * 150 if k < 9 else 1000 + (12 - k) * 200
            samples.append((t, 0, 0, z))
            t += PERIOD_MS
    for _ in range(40):
        samples.append((t, 0, 0, 1000))
        t += PERIOD_MS
    return samples
