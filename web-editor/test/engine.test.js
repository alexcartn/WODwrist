import { test } from "node:test";
import assert from "node:assert/strict";
import { parseWod } from "../js/wod-parser.js";
import { TimerEngine, S, E } from "../js/timer-engine.js";

const wod = (txt) => {
  const r = parseWod(txt);
  assert.ok(r.wod, r.error);
  return r.wod;
};
const codes = (ev, code) => ev.filter((e) => e[0] === code);

// Tick every 250 ms from t0 to t1, collect events.
function run(eng, t0, t1) {
  const ev = [];
  for (let t = t0; t <= t1; t += 250) ev.push(...eng.tick(t));
  return ev;
}

test("countdown warns 3-2-1 then starts", () => {
  const e = new TimerEngine(wod("AMRAP 1\n5 burpees"), 10);
  let ev = e.start(0);
  assert.equal(e.state, S.COUNTDOWN);
  ev = ev.concat(run(e, 0, 10000));
  assert.deepEqual(codes(ev, E.WARN).map((x) => x[1]), [3, 2, 1]);
  assert.equal(codes(ev, E.START).length, 1);
  assert.equal(e.state, S.WORK);
});

test("AMRAP rounds, laps and score", () => {
  const e = new TimerEngine(wod("AMRAP 2\n3 burpees\n2 wall balls"), 0);
  e.start(0);
  let ev = [];
  for (let r = 0; r < 2; r++) {
    for (let i = 0; i < 3; i++) ev.push(...e.addRep(1, 1000));
    for (let i = 0; i < 2; i++) ev.push(...e.addRep(1, 1000));
  }
  ev.push(...e.addRep(1, 1000)); // 1 extra rep into round 3
  assert.equal(codes(ev, E.ROUND).length, 2);
  assert.deepEqual(codes(ev, E.LAP).map((x) => x[1]), [5, 5]);
  ev = run(e, 1000, 120000);
  assert.equal(e.state, S.DONE);
  assert.deepEqual(codes(ev, E.DONE)[0], [E.DONE, 1]);
  assert.deepEqual(e.score(), { kind: "rounds", rounds: 2, reps: 1 });
  assert.equal(e.clockMs(200000), 0);
});

test("AMRAP manual next for distance blocks", () => {
  const e = new TimerEngine(wod("AMRAP 5\n200m run\n5 burpees"), 0);
  e.start(0);
  assert.equal(e.currentBlock().movement, "run");
  assert.deepEqual(e.addRep(1, 10), []); // reps ignored on a distance block
  const ev = e.next(10);
  assert.deepEqual(ev, [[E.BLOCK, 1]]);
  assert.equal(e.currentBlock().movement, "burpee");
});

test("-1 never goes below zero", () => {
  const e = new TimerEngine(wod("AMRAP 5\n5 burpees"), 0);
  e.start(0);
  e.addRep(1, 0);
  e.addRep(-1, 0);
  e.addRep(-1, 0);
  assert.equal(e.blockReps, 0);
  assert.equal(e.totalReps, 0);
});

test("FOR TIME 21-15-9 finishes with time score", () => {
  const e = new TimerEngine(wod("FOR TIME cap 15\n21-15-9\nthrusters\npull-ups"), 0);
  e.start(0);
  const laps = [];
  let now = 0;
  for (const n of [21, 15, 9]) {
    assert.equal(e.target(e.currentBlock()), n);
    for (let b = 0; b < 2; b++) {
      for (let i = 0; i < n; i++) {
        now += 1000;
        e.tick(now);
        laps.push(...codes(e.addRep(1, now), E.LAP));
      }
    }
  }
  assert.equal(e.state, S.DONE);
  assert.deepEqual(laps.map((x) => x[1]), [42, 30]);
  assert.deepEqual(e.score(), { kind: "time", ms: 90000 });
  assert.equal(e.clockMs(999999), 90000);
});

test("FOR TIME cap reached scores reps", () => {
  const e = new TimerEngine(wod("FOR TIME cap 1\n21-15-9\nthrusters\npull-ups"), 0);
  e.start(0);
  for (let i = 0; i < 25; i++) e.addRep(1, 0);
  const ev = run(e, 0, 61000);
  assert.equal(codes(ev, E.DONE).length, 1);
  assert.deepEqual(e.score(), { kind: "reps", reps: 25 });
});

test("next() credits missing target reps", () => {
  const e = new TimerEngine(wod("FOR TIME\n10 burpees\n5 wall balls"), 0);
  e.start(0);
  e.addRep(1, 0);
  e.next(0);
  assert.equal(e.totalReps, 10);
  e.next(0);
  assert.equal(e.state, S.DONE);
  assert.equal(e.totalReps, 15);
});

test("EMOM alternates slots and laps every interval", () => {
  const e = new TimerEngine(wod("EMOM 4\nodd: 12 kb swings\neven: 10 burpees"), 0);
  e.start(0);
  const seen = [];
  const laps = [];
  let done = 0;
  for (let t = 0; t <= 240000; t += 250) {
    for (const x of e.tick(t)) {
      if (x[0] === E.LAP) laps.push(x);
      if (x[0] === E.DONE) done++;
    }
    if (e.state === S.WORK && t % 60000 === 1000) {
      seen.push(e.currentBlock().movement);
      e.addRep(3, t);
    }
  }
  assert.deepEqual(seen, ["kb_swing", "burpee", "kb_swing", "burpee"]);
  assert.deepEqual(laps.map((x) => x[1]), [3, 3, 3]); // 4th lap closed by DONE
  assert.equal(done, 1);
  assert.equal(e.totalReps, 12);
});

test("EMOM target done flags interval, warns each minute", () => {
  const e = new TimerEngine(wod("EMOM 2\n2 burpees"), 0);
  e.start(0);
  const ev = e.addRep(2, 100);
  assert.deepEqual(ev, [[E.TARGET_DONE, 0]]);
  assert.deepEqual(e.addRep(1, 200), []);
  const all = run(e, 0, 120000);
  assert.deepEqual(codes(all, E.WARN).map((x) => x[1]), [3, 2, 1, 3, 2, 1]);
  assert.equal(e.clockMs(30000), 0);
});

test("TABATA work/rest phases, rotation, 8 laps worth", () => {
  const e = new TimerEngine(wod("TABATA 8x20/10\nair squats\npush-ups"), 0);
  e.start(0);
  const ev = [];
  const moves = [];
  for (let t = 0; t <= 240000; t += 250) {
    ev.push(...e.tick(t));
    if (t % 30000 === 5000) moves.push(e.currentBlock().movement);
    if (t === 25000) assert.equal(e.state, S.REST);
    if (t === 31000) assert.equal(e.state, S.WORK);
  }
  assert.equal(codes(ev, E.REST).length, 7);
  assert.equal(codes(ev, E.LAP).length, 7);
  assert.equal(codes(ev, E.DONE).length, 1);
  assert.deepEqual(moves.slice(0, 4), ["air_squat", "push_up", "air_squat", "push_up"]);
  assert.equal(e.activeMs(999999), 230000);
});

test("pause freezes the clock", () => {
  const e = new TimerEngine(wod("AMRAP 10\n5 burpees"), 0);
  e.start(0);
  e.tick(5000);
  e.pause(5000);
  assert.equal(e.clockMs(60000), 595000);
  assert.deepEqual(e.tick(60000), []);
  e.addRep(1, 60000);
  assert.equal(e.totalReps, 0);
  e.resume(60000);
  assert.equal(e.clockMs(61000), 594000);
  assert.equal(e.state, S.WORK);
});

test("finish early", () => {
  const e = new TimerEngine(wod("FOR TIME\n100 burpees"), 0);
  e.start(0);
  e.addRep(40, 0);
  const ev = e.finish(30000);
  assert.deepEqual(ev, [[E.DONE, 40]]);
  assert.deepEqual(e.score(), { kind: "reps", reps: 40 });
  assert.equal(e.activeMs(99999), 30000);
});
