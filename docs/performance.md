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

## Session RPE (after each workout)

`How hard was it?` 1 to 10 right after the workout (START to confirm, BACK to
skip). Load = RPE x minutes (Foster's session-RPE). With a grip-heavy sport
and a wrist sensor this is the most reliable load measure, so the training
load screens use it as soon as there is some in the last 4 weeks, and fall
back on the HR load (TRIMP) otherwise. The screen title says which: `(RPE)` or `(HR)`.

## Heart rate recovery

Drop in bpm 60 s after the end, measured while you answer the RPE question.
Details page: green from 30 bpm (good), orange under 20. Weekly report:
average of the week vs the week before. Rising over the weeks = fitter.

## Readiness (WOD preview)

Garmin Body Battery and stress, newest sample (`Battery 64  Stress 22`),
orange when Body Battery < 25 or stress > 60. Only on devices that expose
them to apps.

## Loads, RX / scaled, tonnage

Loads written in the WOD are read: `21 thrusters (43/30kg)`, `12 kb swings @24kg`,
`5 cleans (135/95 lb)`, `1.5 pood` (converted to kg). Without a unit, loads are kg:
`thrusters 43/30`, `@100`, and any number in brackets `(24)`. Setting `My load in "43/30kg"`: first or second value.
After a WOD with loads the watch asks RX or Scaled: scaled results get their own
best / last and add no tonnage. Details page: `Moved 2340 kg`.

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

Second page (scroll): week pattern. Monotony (Foster) = average daily load /
standard deviation over the last 7 days (rest days count as 0). Above 2.0
every day looks the same: add easy and rest days. Strain = weekly load x monotony.

## Balance (My stats > Balance)

Share of active time over 4 weeks: gymnastics, weightlifting (barbell, KB,
DB, wall balls), monostructural (run, row, bike, ski, rope). Domains come from
`docs/movements.json`. `Little X lately` when a domain is under 15 %.

## Strong / weak (My stats)

Your pace per rep vs a reference pace (`refTenths` in `docs/movements.json`,
rough values for an intermediate athlete inside a WOD, edit them to your
box's standards). Movements with at least 30 reps, 3 best and 3 worst.

## This week (My stats)

Last 7 days vs the 7 before: workouts, time, load, kg moved, new bests,
HR recovery, and a neglected domain. `New report` shows on the menu during
the first days of a week when last week had workouts.

## Details page of a workout (after Analysis)

| Line | Meaning |
| --- | --- |
| RPE 8  load 96 | your effort and the session load |
| HR recovery -34 bpm | see above (a countdown while it is measured) |
| Unbroken 9/12, 5 breaks | sets without a pause; a break = a gap between reps longer than 3 s and 2.5 x your usual rep gap |
| Transitions 1:42 | time lost between movements (time to the first rep minus a normal rep) |
| Burpees +25% | the movement that slowed down the most from its first to its last set |
| Beats/round +18% | heartbeats per round, last vs first: cardiac drift |
| Moved 2340 kg | reps x your load, RX only |

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
