import { test } from "node:test";
import assert from "node:assert/strict";
import { parseWod } from "../js/wod-parser.js";
import { TimerEngine, S, E } from "../js/timer-engine.js";
import { quickWod, qtCycle, qtLabel, qtRows, QT_DEFAULTS } from "../js/quick-timer.js";

const codes = (ev, code) => ev.filter((e) => e[0] === code);
const strip = (w) => { const { name, quick, blocks, ...rest } = w; return rest; };

test("defaults: AMRAP 20", () => {
  const w = quickWod(QT_DEFAULTS);
  assert.equal(w.name, "AMRAP 20");
  assert.equal(w.timeCapSec, 1200);
  assert.equal(w.quick, true);
});

test("timings match the parser for the same header", () => {
  const cases = [
    [{ type: 0, amrapMin: 6 }, "AMRAP 15"],
    [{ type: 1, ftRounds: 5, ftCapMin: 6 }, "5 ROUNDS FOR TIME cap 20"],
    [{ type: 2, emomEverySec: 0, emomRounds: 3 }, "EMOM 10"],
    [{ type: 2, emomEverySec: 2, emomRounds: 3 }, "E2MOM 20"],
    [{ type: 2, emomEverySec: 3, emomRounds: 1 }, "EVERY 2:30 x 6"],
    [{ type: 3, tabataWorkRest: 0, tabataRounds: 2 }, "TABATA 8x20/10"],
  ];
  for (const [cfg, text] of cases) {
    const q = quickWod(cfg);
    const p = parseWod(text + "\n10 burpees").wod;
    assert.deepEqual(strip(q), strip(p), text);
  }
  assert.equal(quickWod({ type: 2, emomEverySec: 2, emomRounds: 3 }).name, "E2MOM 20");
  assert.equal(quickWod({ type: 2, emomEverySec: 1, emomRounds: 3 }).name, "EVERY 1:30 x 10");
});

test("cycling wraps and labels read well", () => {
  let c = { ...QT_DEFAULTS };
  for (let i = 0; i < 4; i++) c = qtCycle(c, "type");
  assert.equal(c.type, 0);
  assert.deepEqual(qtRows(1), ["ftRounds", "ftCapMin"]);
  assert.equal(qtLabel(QT_DEFAULTS, "ftRounds"), "Chrono");
  assert.equal(qtLabel(QT_DEFAULTS, "ftCapMin"), "No cap");
  assert.equal(qtLabel(QT_DEFAULTS, "emomEverySec"), "1:00");
  assert.equal(qtLabel(QT_DEFAULTS, "tabataWorkRest"), "20/10");
  c = { ...QT_DEFAULTS, amrapMin: 15 };
  assert.equal(qtCycle(c, "amrapMin").amrapMin, 0);
});

test("quick AMRAP: each +1 closes a round", () => {
  const e = new TimerEngine(quickWod({ type: 0, amrapMin: 0 }), 0);
  e.start(0);
  const ev = [...e.addRep(1, 60000), ...e.addRep(1, 120000), ...e.addRep(1, 190000)];
  assert.deepEqual(codes(ev, E.ROUND).map((x) => x[1]), [1, 2, 3]);
  assert.equal(codes(ev, E.LAP).length, 3);
  e.tick(300000);
  assert.equal(e.state, S.DONE);
  assert.deepEqual(e.score(), { kind: "rounds", rounds: 3, reps: 0 });
});

test("chrono: laps until finish, score is the time", () => {
  const e = new TimerEngine(quickWod({ type: 1, ftRounds: 0, ftCapMin: 0 }), 0);
  assert.equal(e.totalRounds(), null);
  e.start(0);
  let ev = [];
  for (let i = 1; i <= 25; i++) ev.push(...e.addRep(1, i * 1000));
  assert.equal(e.state, S.WORK);
  assert.equal(codes(ev, E.LAP).length, 25);
  ev = e.finish(90000);
  assert.equal(codes(ev, E.DONE).length, 1);
  assert.deepEqual(e.score(), { kind: "time", ms: 90000 });
});

test("rounds for time ends on the last round", () => {
  const e = new TimerEngine(quickWod({ type: 1, ftRounds: 3, ftCapMin: 0 }), 0);
  e.start(0);
  e.addRep(1, 1000);
  e.addRep(1, 2000);
  const ev = e.addRep(1, 3000);
  assert.equal(codes(ev, E.DONE).length, 1);
  assert.deepEqual(e.score(), { kind: "time", ms: 3000 });
});

test("finishing a normal For time early is still capped", () => {
  const e = new TimerEngine(parseWod("3 ROUNDS FOR TIME\n10 burpees").wod, 0);
  e.start(0);
  e.finish(5000);
  assert.deepEqual(e.score(), { kind: "reps", reps: 0 });
});

test("quick EMOM: +1 marks the interval done", () => {
  const e = new TimerEngine(quickWod({ type: 2, emomEverySec: 0, emomRounds: 0 }), 0);
  e.start(0);
  const ev = e.addRep(1, 20000);
  assert.equal(codes(ev, E.TARGET_DONE).length, 1);
  assert.equal(e.intervalDone, true);
  e.tick(61000);
  assert.equal(e.intervalDone, false);
});

test("quick Tabata counts reps without advancing", () => {
  const e = new TimerEngine(quickWod({ type: 3 }), 0);
  e.start(0);
  for (let i = 0; i < 12; i++) e.addRep(1, 1000 + i * 1000);
  assert.equal(e.blockReps, 12);
  assert.equal(e.intervalDone, false);
});
