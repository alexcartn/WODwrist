# rep-lab

Offline tuning of the watch rep counter. Pure Python (stdlib), tests with pytest.

```
replab/counter.py    reference counter, same integer math as RepCounter.mc
replab/logparse.py   reads the watch capture log (APPS/LOGS/WODWRIST.TXT)
replab/labels.py     reads WODvision rep labels (CSV / JSON)
replab/evaluate.py   clock alignment + precision / recall / count accuracy
replab/tune.py       grid search per movement, writes docs/movements.json
replab/synth.py      synthetic signals for tests
```

## 1. Capture

1. Build and sideload the app (see the root README).
2. On the watch USB drive create an empty file `GARMIN/APPS/LOGS/WODWRIST.TXT`
   (the name must match the .prg name). Without it `System.println` writes nothing.
3. In Garmin Connect > WODwrist settings turn on **Data capture mode**.
4. Film the set on the phone. Start the video before the countdown and press
   BACK once in view of the camera at the start: it is the sync mark.
5. During the set press BACK (+1) on every rep. These presses are the fallback
   ground truth and the clock anchor. In capture mode the auto-detected reps are
   logged but not added to the score.
6. Copy `WODWRIST.TXT` from the watch. Accel logging writes about 400 bytes
   per second and the firmware caps / rotates the log file (size depends on
   the device, check yours at M4), so keep capture sets short (1-2 min) and
   copy the file after each set.

Log lines (all times are `System.getTimer()` ms):

```
S,<t>,<wod name>           session start
B,<t>,<movement id>        current movement changed
A,<t>,x0,y0,z0,...         1 s of accelerometer at 25 Hz, milli-g
M,<t>,<+1|-1|next>         button / tap
R,<t>,1                    rep detected on the watch (time of the peak)
L,<t>,<reps>               lap closed
E,<t>,<score>              end
```

## 2. Label with WODvision

Run WODvision on the video and export rep timestamps (seconds from video
start). `labels.py` reads `labels.csv` with a `t` column (plus an optional
`movement` column) or JSON `[1.2, 3.4]` / `{"reps": [{"t": 1.2}]}`. Adapt
`labels.py` if WODvision's export changes; nothing else depends on the format.

## 3. Tune

One directory per set:

```
data/wb_2026-10-02_a/
    watch.txt      the log
    labels.csv     WODvision output (optional: markers are used without it)
    meta.json      optional {"offset_ms": 1234567}  (watch_ms - video_ms)
```

```bash
cd rep-lab
pip install -r requirements.txt
python -m replab.tune --movement wall_ball data/wb_*            # report
python -m replab.tune --movement wall_ball data/wb_* --write    # save to docs/movements.json
python3 ../tools/gen_movements.py                                # regenerate the watch catalog
```

Without `offset_ms` the clocks are aligned by sliding the video labels over
the button markers (±60 s around the first mark).

The score that matters is `count_acc` (what the athlete sees: 1 - |counted -
real| / real). Target: 95 %+ on every set, not only on average. Keep a
movement on manual counting (`"counter": null`) until it gets there.

## 4. Port

Nothing to port by hand: `tune.py --write` updates the 4 parameters in
`docs/movements.json`, `tools/gen_movements.py` regenerates
`watch-app/source/model/MovementCatalog.mc`. If the algorithm itself changes,
change `counter.py` and `RepCounter.mc` together and keep
`test_deterministic_vector_shared_with_monkey_c` and
`watch-app/test/RepCounterTest.mc` in agreement.

## Tests

```bash
python -m pytest -q
```
