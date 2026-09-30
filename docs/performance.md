# Performance metrics (on the watch)

Everything is computed on the watch from the saved workouts. Reference
implementation with tests: `web-editor/js/perf.js`; watch port:
`watch-app/source/session/Perf.mc`.

## Heart rate zones

Your Garmin zones (`UserProfile.getHeartRateZones`, generic sport). Without
them: 220 - age, else 190 bpm, split 50/60/70/80/90 % like Garmin's default.
Sampled once per second while working or resting (pauses excluded).

## Load of a workout (TRIMP)

Edwards TRIMP: minutes in zone x zone number (Z1 = 1 ... Z5 = 5).
10 min in Z3 + 5 min in Z4 = 30 + 20 = 50. Shown as `Load 51` on the
Analysis page of the summary. Coach sessions are not counted.

## Training load (My stats > Training load)

- Acute = total load of the last 7 days.
- Chronic = weekly average of the last 28 days.
- Ratio = acute / chronic (ACWR).

| Ratio | Status |
| --- | --- |
| under 0.80 | Low: room for more |
| 0.80 to 1.30 | Optimal |
| 1.30 to 1.50 | High: watch recovery |
| over 1.50 | Very high: ease off |

Needs 3 weeks of history (`Building baseline` before). ACWR is a useful
trend signal, not a medical verdict: the injury-risk thresholds are debated
in the literature. Only workouts done with WODwrist count (a run recorded
with another app is invisible here).

## Analysis page of a workout

| Line | Meaning |
| --- | --- |
| zone bar | share of time in Z1 (grey) to Z5 (red) |
| Mostly Z4 (5 min) | dominant zone |
| Round var 6% | coefficient of variation of round times (AMRAP / For time). Under ~5 %: very even pacing |
| Fade +17% | last round vs first round. Orange above +10 %: you probably started too fast |
| Work 72% / interval | EMOM: share of each interval spent working. Orange above 85 %: almost no rest, scale down or it becomes a For time |
| Fitter: -6 bpm vs last | same WOD, score at least as good as last time, lower average HR |

Wrist heart rate lags and drops out on grip-heavy movements (pull-ups,
barbell work): read zones and TRIMP as trends over weeks, not exact numbers.
