# WOD text format

What coaches and athletes type. Parsed on the watch (settings text) and in the
web editor, by two implementations of the same algorithm:

- reference: `web-editor/js/wod-parser.js` (tested with `npm test`)
- watch port: `watch-app/source/model/WodParser.mc`

Both are checked against `docs/fixtures/*.txt` → `*.json`.

## Lines

Lines are separated by a newline, `;` or `|`. The Garmin Connect settings
field is single-line, so there you write `AMRAP 12; 10 wall balls; 10 burpees`.

| Line | Meaning |
| --- | --- |
| `# Fran` or `name: Fran` | WOD name (optional, defaults to the header line) |
| header (first other line) | WOD type and timing, see below |
| `21-15-9` | rep scheme (FOR TIME) |
| `10 wall balls` | a movement |
| `odd: ...`, `even: ...`, `min 3: ...` | EMOM slot prefix |
| `5 power cleans + 10 box jumps` | several movements in the same slot |

## Headers

| Text | Result |
| --- | --- |
| `AMRAP 12`, `12 min AMRAP`, `AMRAP 12:30` | AMRAP, cap 12 min |
| `EMOM 10` | 10 x 1 min |
| `E2MOM 20` | 10 x 2 min |
| `E3MOM x 5` | 5 x 3 min |
| `FOR TIME`, `RFT` | 1 round for time |
| `3 ROUNDS FOR TIME`, `5 RFT` | N rounds |
| `FOR TIME cap 15`, `For time (time cap 15:00)` | with a cap |
| `TABATA` | 8 x 20 s / 10 s |
| `TABATA 10x30/15` | rounds x work / rest |

Durations: `12` (minutes), `12min`, `12'`, `90s`, `12:30`.

## Movement lines

The first number is the target, an optional unit follows it:

| Text | reps | unit |
| --- | --- | --- |
| `10 wall balls`, `wall balls x 10`, `10x wall balls` | 10 | reps |
| `200m run`, `run 200 m` | 200 | m |
| `1.5 km run` | 1500 | m |
| `15 cal row` | 15 | cal |
| `30s plank`, `1 min plank` | 30 / 60 | sec |
| `air squats` | 0 (max, or from the rep scheme) | reps |

Loads are ignored: `(43/30kg)`, `[24kg]`, `20/14`, `@ 60kg`, `100 kg`.

The remaining words are looked up in `docs/movements.json` (normalized:
lowercase, `-` `_` `.` become spaces, a trailing `s`/`es` is tried). Unknown
names become `"movement": "custom"` and are counted by hand.

## Interval rotation (EMOM, TABATA)

Every movement line gets its own slot, and slots rotate each interval:

```
EMOM 12
15 wall balls      -> minutes 1, 4, 7, 10
12 alt db snatches -> minutes 2, 5, 8, 11
30s plank          -> minutes 3, 6, 9, 12
```

`odd:` = slot 0, `even:` = slot 1, `min N:` = slot N-1. `+` puts several
movements in the same interval. Tabata uses the same rule: two lines means
round 1 squats, round 2 push-ups, round 3 squats...

## Watch behaviour per type

| Type | Clock | Lap in Garmin Connect | Score |
| --- | --- | --- | --- |
| AMRAP | counts down the cap | each completed round | rounds + reps |
| FOR TIME | counts up (stops at cap) | each completed round | time, or `CAP + reps` |
| EMOM | counts down each interval | each interval | total reps |
| TABATA | counts down work / rest | each round (work + rest) | total reps |
