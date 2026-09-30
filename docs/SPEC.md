# WODwrist: Garmin Connect IQ app for functional fitness WODs

Working name, easy to rename. Sibling project of WODvision (alexcartn/WODvision).

## 1. Goal

A Garmin watch app that runs any WOD without typing on the watch: the WOD is
pushed from phone/web, the watch runs the right timer, counts reps
automatically where possible, and saves a proper activity to Garmin Connect
with one lap per round and heart rate per round.

Two users:

- Athlete: runs the WOD, gets reps, splits, HR, saved activity.
- Coach: publishes the WOD of the day once, athletes load it on their watch;
  coach can run a class timer from their own watch.

Differentiation vs Garmin native HIIT profiles: WOD import (no manual setup),
automatic rep counting, coach broadcast, round data in Connect.

## 2. Target devices

- Venu family (Venu 2/2 Plus/3, Venu Sq 2), Vivoactive 5/6, Forerunner 165/265/965.
- Mostly AMOLED, round screens, touch + 2 buttons. Venu Sq is rectangular:
  layouts must be relative, never hardcoded pixels.
- Exact product IDs to be confirmed in manifest.xml against the installed SDK
  device list. Primary test device: Alexandre's own watch.

## 3. v1 scope (must-haves)

### 3.1 WOD import

- Contract: a JSON WOD schema (section 5) is the single source of truth.
- Source A (simplest, offline): WOD text pasted in the app settings via Garmin
  Connect Mobile, parsed on watch.
- Source B (coach flow): watch fetches JSON from a URL
  (Communications.makeWebRequest, via the phone). v1 URL = static JSON hosted
  on GitHub Pages, written by a small web editor.
- Watch caches the last WOD so it works without phone.

### 3.2 Timers

- AMRAP (time cap, count rounds + extra reps)
- EMOM / E2MOM / EXMOM (interval, total duration, alternating movements odd/even)
- For Time (optional time cap, rep schemes like 21-15-9)
- Tabata (work/rest/rounds, default 8 x 20/10)
- Common: 10 s countdown before start, vibration + tone on each interval,
  pause/resume, big readable clock, current movement + target reps on screen.

### 3.3 Automatic rep counting

- Accelerometer via Sensor.registerSensorDataListener (25 Hz, 1 s batches).
- Pipeline: magnitude or dominant axis, low-pass filter, peak detection with
  per-movement thresholds and minimum inter-rep time.
- v1 supported movements (wrist signal is strong): wall balls, thrusters, KB
  swings, burpees, dumbbell snatches. Others fall back to manual counting.
- Always correctable: button press = +1 rep, long press = -1. Confidence shown discreetly.
- Tuning done offline in Python first, then ported to Monkey C (section 7).

### 3.4 Recording and Garmin Connect

- ActivityRecording session, sport training / cardio training sub-sport.
- One lap per round (AMRAP, For Time) or per interval (EMOM, Tabata) via
  addLap(): Garmin Connect then shows time and HR per round natively.
- Custom FIT fields (FitContributor): reps per lap, total reps, rounds
  completed, WOD name. Session-level: final score (time or rounds+reps).
- End screen: score, rounds, splits, avg/max HR, save or discard.

### 3.5 Coach mode

- Watch: "Class timer" mode = same timers, no recording by default, max-size
  clock, stronger vibration.
- Web: minimal WOD editor page (text in, JSON out, publish to GitHub Pages).

## 4. Out of scope for v1

- Leaderboard, multi-athlete sync, accounts.
- Weight/load tracking per rep.
- Rep counting for squats, box jumps, double-unders, rowing, running (v2 candidates).
- Watch face, data field, widget variants.

## 5. WOD data model

Text format: see [wod-format.md](wod-format.md).
JSON: see [wod-schema.json](wod-schema.json). Movement IDs come from a fixed
catalog ([movements.json](movements.json)) that maps to display names and
rep-counter profiles.

## 6. Architecture (Monkey C)

- WodModel: data classes + JSON/text parser + validation.
- TimerEngine: state machine (Idle, Countdown, Work, Rest, Paused, Done),
  emits interval and round events. Pure logic, unit-tested.
- RepCounter: signal processing, one profile per movement, emits rep events.
- RecordingManager: session, laps, FIT custom fields.
- SyncService: settings read, web fetch, local cache (Application.Storage).
- Views: WodList, WodPreview, Running, Summary, CoachTimer.
- Delegates: button + touch handling per view.

Constraints: watch app memory limits (check per device in simulator), no
floating-point-heavy loops in onUpdate, timer tick at 1 Hz for UI and sensor
callback at batch rate.

## 7. Rep counter development method

1. Data capture build: logs raw accel (x, y, z, timestamp) via System.println
   to the on-device log file (sideload + APPS/LOGS/<app>.TXT), plus manual rep
   markers on button press.
2. Record sessions filmed on phone; use WODvision to produce ground-truth rep
   timestamps from the video.
3. Python: align accel and video labels, tune filter and peak detection per
   movement, measure precision/recall.
4. Port the tuned algorithm to Monkey C with fixed parameters per movement.
5. Target: 95 %+ count accuracy on supported movements.

## 8. Milestones

- M0: SDK + VS Code extension set up, hello world in simulator and on the watch.
- M1: TimerEngine for 4 WOD types with hardcoded WODs, vibration, pause.
- M2: Recording with laps per round, HR, custom FIT fields, verified in Garmin Connect.
- M3: WOD import (settings text parser, then URL fetch + cache).
- M4: Data capture build + Python tuning pipeline with WODvision labels.
- M5: On-watch rep counting for the 5 v1 movements + manual correction.
- M6: Coach mode + web WOD editor on GitHub Pages.
- M7: Polish across devices, Connect IQ store submission.

## 9. Repo layout

```
/watch-app        Connect IQ project (manifest.xml, monkey.jungle, source/, resources/)
/web-editor       static WOD editor (HTML/JS), deployed to GitHub Pages
/rep-lab          Python: data alignment, tuning, WODvision bridge
/docs             this spec, WOD schema, movement catalog
```

## 10. Naming and legal

- Do not use "CrossFit" in the app name or store listing (trademark). "WOD",
  "functional fitness" are fine.
- Check name availability on the Connect IQ store before submission.
