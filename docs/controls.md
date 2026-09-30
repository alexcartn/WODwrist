# Watch controls

## During the workout

| Input | Action |
| --- | --- |
| START (top right) | pause menu: Resume / Finish / Discard |
| BACK short press | +1 rep. On a run / row / hold block: "done", next movement |
| BACK long press (0.7 s) | -1 rep |
| DOWN / UP (5-button Forerunners) | +1 / -1 rep |
| tap screen | +1 rep (same rule as BACK short) |
| hold screen | -1 rep |
| swipe left | next movement, crediting the missing target reps |
| other swipes | ignored, so a sweaty swipe does not leave the workout |

The next movement starts automatically when the target reps are reached
(auto count or manual). In EMOM / Tabata, once the interval's work is done the
screen shows `DONE, WAIT` until the next interval.

To check on the device (M0/M1): some firmwares keep the BACK long press for
system shortcuts. If it never reaches the app, use hold-screen or UP for -1.

## Screen

```
      WORK            <- state (GET READY / WORK / REST / PAUSED)
   Round 2/3  -0:08   <- round or interval, "Rounds 4" for AMRAP;
                         AMRAP / For time: ahead (green) or behind (red)
                         your best at the same round
      7:42            <- big clock
   Wall balls         <- current movement
     7/10  ●          <- reps / target, dot = rep counter confidence
  Reps 57  HR 162     <- total reps, heart rate
```

Coach mode (class timer): bigger clock, movement line under it, no footer,
longer vibrations, no activity saved unless "Record activity in coach mode"
is on.

## Coach menu (main menu > Coach)

| Item | What it does |
| --- | --- |
| Class timer | on/off: big clock, strong vibrations, no recording |
| Run class plan | runs every part of the coach file back to back (warm-up, strength, metcon). In the web editor, separate parts with a line `---`, publish, then Sync WOD on the watch |
| Start | tap to cycle: now (10 s countdown), next full minute, next :00/:15/:30/:45, in 2 min, in 5 min. Applies to class timer starts and to the plan |
| Rest between parts | tap to cycle: 0:30, 1:00, 1:30, 2:00, 3:00, none. Countdown before each next part, showing `2/3 Strength` |
| Halfway alert / 1 min left alert | double long vibration + `HALFWAY` / `1 MIN LEFT` on screen for 2 s (also in athlete mode) |

In a plan, the pause menu's Finish goes to the next part and End class stops
the plan. Countdowns over a minute show `m:ss`.

## Score memory

Each saved workout stores last + best per WOD (same structure = same WOD,
whatever its name; 30 WODs kept). The preview shows `Best 8 + 3  Last 7 + 12`,
the summary shows `NEW BEST` or your best. Logic: `web-editor/js/score-history.js`
(tested) and its port `watch-app/source/session/ScoreHistory.mc`.

## My stats (main menu)

All computed on the watch from the saved workouts, nothing to export.

- Overall: workouts, active time, reps, number of different WODs.
- Movements: seconds per rep for each movement, over all saved workouts
  (time from the start to the end of the block, so short breaks count: it is
  a work rate, not a pure rep speed). Custom movements are skipped.
- One page per WOD: best, last (green when it equals or beats the best),
  fade of the last attempt (last round vs first round, orange above +10 %:
  probably started too fast), HR avg / max. Scroll down: round times best vs last.

## Summary

START saves the activity to Garmin Connect, BACK asks to discard.
Scroll down for the splits: `R3  1:02  12r  151` = lap, time, reps, avg HR.
