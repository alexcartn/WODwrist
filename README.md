# WODwrist

Garmin Connect IQ watch app that runs any WOD without typing on the watch:
the WOD comes from the phone or the coach's page, the watch runs the right
timer (AMRAP, EMOM, For time, Tabata), counts reps from the accelerometer
where it can, and saves a training activity to Garmin Connect with one lap per
round and custom rep fields.

Spec: [docs/SPEC.md](docs/SPEC.md). Sibling project: WODvision (video rep labels).

```
watch-app/    Connect IQ project (Monkey C)
web-editor/   coach page: WOD text -> JSON, publish to GitHub Pages, browser class timer
rep-lab/      Python: capture log parsing, WODvision labels, rep counter tuning
docs/         spec, text format, JSON schema, movement catalog, controls, fixtures
tools/        generators (movement catalog, Monkey C parser tests, icon)
```

## How the pieces fit

```
coach text ──► web-editor (JS parser) ──► today.json on GitHub Pages ──┐
athlete text ─► Garmin Connect settings ─► watch parser ──────────────┤
                                                                      ▼
                                              watch cache (Storage) ─► TimerEngine
                                                                      ├► RepCounter (accel)
                                                                      └► RecordingManager ─► Garmin Connect
```

Logic that must behave the same everywhere has one tested reference and one port:

| Logic | Reference (tested here) | Watch port |
| --- | --- | --- |
| WOD text parser | `web-editor/js/wod-parser.js` | `watch-app/source/model/WodParser.mc` |
| Timer state machine | `web-editor/js/timer-engine.js` | `watch-app/source/engine/TimerEngine.mc` |
| Rep counter | `rep-lab/replab/counter.py` | `watch-app/source/rep/RepCounter.mc` |
| Movement catalog | `docs/movements.json` | generated `MovementCatalog.mc` + `movements.js` |

Change the reference first, run its tests, then port. `docs/fixtures/` drive
both parser test suites (`tools/gen_mc_tests.mjs` writes the Monkey C one).

## Status

| Milestone | Code | Still to do on a real SDK / watch |
| --- | --- | --- |
| M0 setup | project, manifest, resources, icon | install SDK, confirm product ids, first build |
| M1 timers | TimerEngine (4 types, countdown, pause, 3-2-1 warnings), run screen, vibration/tones | tune layouts per device in the simulator |
| M2 recording | session training/cardio, lap per round/interval, FIT fields | verify laps + fields in Garmin Connect |
| M3 import | settings text parser, URL fetch, cache of 8 WODs | test through Garmin Connect Mobile |
| M4 capture | capture mode log, rep-lab parsing / alignment / tuning | film + label real sets with WODvision |
| M5 rep counting | on-watch counter, per-movement profiles, +1/-1, confidence dot | replace untuned parameters with rep-lab output |
| M6 coach | class timer mode on watch, web editor + Pages publish + browser timer | |
| M7 polish | | multi-device pass, store listing |

The Monkey C code has not been compiled yet (no SDK in the environment where it
was written): expect a round of small compiler fixes at M0. The JS and Python
references are tested (`npm test`, `pytest`).

## Watch app: build and run

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
   with the SDK Manager, download the devices you target, and the VS Code
   "Monkey C" extension.
2. Create a developer key once:
   ```bash
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```
3. Build and run in the simulator:
   ```bash
   cd watch-app
   monkeyc -f monkey.jungle -d venu2 -o bin/WODWRIST.prg -y ../developer_key.der
   connectiq &                       # simulator
   monkeydo bin/WODWRIST.prg venu2
   ```
   Settings can be edited in the simulator (File > Edit Persistent Storage /
   App Settings). Accelerometer data can be played back from a FIT file.
4. Unit tests (parser fixtures, engine, rep counter):
   ```bash
   monkeyc -f monkey.jungle -d venu2 -o bin/test.prg -y ../developer_key.der --unit-test
   monkeydo bin/test.prg venu2 -t
   ```
5. Sideload: copy `bin/WODWRIST.prg` (built for your exact device) to
   `GARMIN/APPS/` on the watch over USB.

No WOD at hand: main menu > Quick timer (AMRAP, For time / chrono, EMOM,
Tabata set up on the watch, BACK = +1 round).

Controls: [docs/controls.md](docs/controls.md). The app follows the watch
language: English, or French (`resources-fre/` for the settings, `Tr.mc` for
the screens). Mockups of every screen: [docs/mockups](docs/mockups).

### Settings (Garmin Connect app > WODwrist)

| Setting | Use |
| --- | --- |
| WOD text | e.g. `AMRAP 12; 10 wall balls; 10 burpees; 200m run` ([format](docs/wod-format.md)) |
| Coach WOD URL | e.g. `https://alexcartn.github.io/WODwrist/web-editor/wod/today.json` |
| Countdown | seconds before start, default 10 |
| Automatic rep counting | on by default |
| Class timer | coach mode (also a toggle in the watch menu) |
| Record activity in coach mode | off by default |
| Data capture mode | logs accelerometer for rep-lab |

## Web editor

Syntax highlighting (header, reps, movements, loads, unknown movements in
purple, errors underlined), movement autocomplete (Tab), benchmark library,
live watch preview, QR code of the WOD URL for athletes, class timer in gym
mode, dark theme by default. `vendor/qrcode.js` is qrcode-generator (MIT).

From a screenshot: the button (or pasting an image in the text box) reads the
text of a training app page (HWPO...) with tesseract.js, in the browser: the
image is not uploaded. App menus are dropped, cut lines joined, one WOD per
section (`---`), titles kept (`Strength: Deadlift`, `Bonus: Part 1`), the
1RM box and RPE notes dropped, a part cut at the bottom of the screenshot
reported. Several screenshots at once (the day's pages) are read in the
order they were taken and merged: a part seen on two overlapping screenshots
is kept once. While the imported text is untouched, the next screenshot is
added to it. Check the result: OCR can misread small italic text.

Installable app (PWA): on the phone, open the editor and "Add to Home
Screen" (iPhone: Share > Add to Home Screen; Android: menu > Install app). It
opens full screen, works offline after the first visit (text reader
included), and on Android appears in the share sheet: select the day's
screenshots in the gallery > Share > WODwrist. `sw.js` is the service worker,
`tools/make_web_icons.py` draws the icons.

```bash
cd web-editor
npm test                      # parser + engine reference tests
python3 -m http.server 8000   # then open http://localhost:8000
```

Served by GitHub Pages through `.github/workflows/pages.yml` (Settings > Pages >
Source: GitHub Actions), deployed on every push to `master` that touches
`web-editor/`: https://alexcartn.github.io/WODwrist/web-editor/
The Publish button commits `web-editor/wod/today.json` with a fine-grained
token (contents: write on this repo) kept in the browser.

## rep-lab

See [rep-lab/README.md](rep-lab/README.md).

```bash
cd rep-lab && pip install -r requirements.txt && python -m pytest -q
```

## Movement catalog

Edit [docs/movements.json](docs/movements.json), then:

```bash
python3 tools/gen_movements.py
```

CI fails if generated files are stale.

## Naming

No "CrossFit" in the app name or store listing (trademark). "WOD" and
"functional fitness" are fine.
