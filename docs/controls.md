# Watch controls

## During the workout

| Input | Action |
| --- | --- |
| START (top right) | pause menu: Resume / Finish / Discard |
| BACK short press | +1 rep. On a run / row / hold block: "done", next movement |
| BACK long press (0.7 s) | -1 rep |
| DOWN / UP (5-button Forerunners) | +1 / -1 rep |
| tap screen | +1 rep (same rule as BACK short), unless the setting "Touch screen counts reps" is off |
| hold screen | -1 rep (same setting) |
| swipe left | next movement, crediting the missing target reps |
| swipe right | ignored, so a sweaty swipe does not leave the workout |

Timed rest block (`1:00 Rest` in a superset): `REST` in blue with the time left,
3-2-1 beeps, then the next movement by itself; BACK skips the rest.

Every-minute task (`Every minute, 8/6 cal ski` in a For time / AMRAP): at each
interval the screen shows `TASK` in orange, a high tone and the
task; count it like any movement (BACK = done for cal / m), then the main
movement comes back where you left it. `3 x AMRAP 4`: `Set 2/3` next to the
rounds, blue rest ring between sets, `SET 2/3` banner at each start.

The next movement starts automatically when the target reps are reached
(auto count or manual). In EMOM / Tabata, once the interval's work is done the
screen shows `DONE, WAIT` until the next interval.

To check on the device (M0/M1): some firmwares keep the BACK long press for
system shortcuts. If it never reaches the app, use hold-screen or UP for -1.

## Screen

The ring on the bezel fills with the current segment (countdown, time cap,
interval, Tabata phase) in the state color: yellow get ready, green work,
blue rest, orange paused. A short yellow arc at the bottom fills with the reps
of the current set. Each counted rep flashes `+1` (or `-1`) next to the count,
and a new movement shows in a green banner for 1.5 s. Each completed round
(AMRAP, For time) shows `ROUND 4`, its time and the gap with your best at the
same round for 1.5 s. The clock uses 7-segment "gym timer" digits drawn by
the app, identical on every watch. Movements show their pictogram.

```
      WORK            <- state (GET READY / WORK / REST / PAUSED)
   Round 2/3  -0:08   <- round or interval, "Rounds 4" for AMRAP;
                         AMRAP / For time: ahead (green) or behind (red)
                         your best at the same round
      7:42            <- big clock
   Wall balls         <- current movement
     7/10  ●          <- reps / target, dot = rep counter confidence
   57  |  162       <- one screen, no pages: total reps | heart rate
  REPS  | BPM Z4       (bpm colored by zone; the watch never vibrates)
```

Coach mode (class timer): bigger clock, movement line under it, no footer,
no activity saved unless "Record activity in coach mode"
is on.

## Today's plan (main menu)

Shown when the coach URL holds several parts (strength, metcon, bonus...).
Runs them back to back: each part is saved as its own activity, then a
countdown shows `2/3 Metcon` for the rest written after the part
(`Then rest 2:00`), or the "Rest between parts" setting. The RPE screen and
summary come after the last part.

## Quick timer (main menu > Quick timer)

A timer without a WOD, set up on the watch alone. Tap a row to go to its next
value (it wraps); the choices are remembered for next time. Start timer shows
what will run (`AMRAP 20`, `Chrono`, `EVERY 1:30 x 10`...).

| Type | Rows |
| --- | --- |
| AMRAP | duration 5 to 60 min |
| For time | rounds (Chrono = open stopwatch, or 1 to 20), time cap (none, 5 to 60 min) |
| EMOM | every 1:00 to 5:00, number of intervals |
| Tabata | work / rest (20/10, 30/15, 40/20, 45/15, 30/30, 60/30), rounds |

During the timer there is no movement on screen: BACK short (or a tap) closes
a round (AMRAP, For time: lap, round time, pace vs your best) or marks the
EMOM interval done. Tabata counts reps. Chrono runs until START > Finish, its
score is the time. The activity is saved and remembered like any WOD.
Logic: `web-editor/js/quick-timer.js` (tested), port `watch-app/source/model/QuickTimer.mc`.

## Coach menu (main menu > Coach)

| Item | What it does |
| --- | --- |
| Class timer | on/off: big clock, no recording |
| Run class plan | runs every part of the coach file back to back (warm-up, strength, metcon). In the web editor, separate parts with a line `---`, publish, then Sync WOD on the watch |
| Start | tap to cycle: now (10 s countdown), next full minute, next :00/:15/:30/:45, in 2 min, in 5 min. Applies to class timer starts and to the plan |
| Rest between parts | tap to cycle: 0:30, 1:00, 1:30, 2:00, 3:00, none. Countdown before each next part, showing `2/3 Strength` |
| Halfway alert / 1 min left alert | a tone + `HALFWAY` / `1 MIN LEFT` on screen for 2 s (also in athlete mode) |

In a plan, the pause menu's Finish goes to the next part and End class stops
the plan. Countdowns over a minute show `m:ss`.

## Score memory

Each saved workout stores last + best per WOD (same structure = same WOD,
whatever its name; 30 WODs kept). The preview shows `Best 8 + 3  Last 7 + 12`,
the summary shows `NEW BEST` or your best. Logic: `web-editor/js/score-history.js`
(tested) and its port `watch-app/source/session/ScoreHistory.mc`.

## My stats (main menu)

All computed on the watch from the saved workouts, nothing to export.

- HR zones: time in each heart rate zone (Z1 to Z5) over the last 7 days, and
  the total. Scroll down for the 3 weeks before. Saved with each workout from
  this version on, so older weeks show "No heart rate data".
- Overall: workouts, active time, reps.
- Movements: seconds per rep for each movement, over all saved workouts
  (time from the start to the end of the block, so short breaks count: it is
  a work rate, not a pure rep speed). Custom movements are skipped.
No per-WOD pages: a WOD is rarely done twice, so stats are per week, not per WOD.

Training load and the Analysis page of each workout: see [performance.md](performance.md).

## Summary

START saves the activity to Garmin Connect (green check next to the button),
BACK asks to discard (grey cross). Dots on the right edge show the pages.
Scroll down for the splits: `R3  1:02  12r  151` = lap, time, reps, avg HR.
