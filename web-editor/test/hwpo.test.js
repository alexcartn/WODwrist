import { test } from "node:test";
import assert from "node:assert/strict";
import { parseWod, parseCapLine, parseRestLine, parseTaskLine, wodToText, validateWod } from "../js/wod-parser.js";
import { TimerEngine, S, E } from "../js/timer-engine.js";

const wod = (txt) => {
  const r = parseWod(txt);
  assert.ok(r.wod, r.error);
  return r.wod;
};
const codes = (ev, code) => ev.filter((e) => e[0] === code);
function run(eng, t0, t1) {
  const ev = [];
  for (let t = t0; t <= t1; t += 250) ev.push(...eng.tick(t));
  return ev;
}

// ---------- parser ----------

test("option lines", () => {
  assert.equal(parseCapLine("Cap : 10:00"), 600);
  assert.equal(parseCapLine("Cap: 10:00"), 600);
  assert.equal(parseCapLine("Time cap 12 min"), 720);
  assert.equal(parseCapLine("(TC 15)"), 900);
  assert.equal(parseCapLine("Capture 10"), -1);
  assert.deepEqual(parseRestLine("Rest 3:00 Between Sets"), { sec: 180, betweenSets: true });
  assert.deepEqual(parseRestLine("Rest 90 sec"), { sec: 90, betweenSets: false });
  assert.equal(parseRestLine("Rest and breathe"), null);
  assert.deepEqual(parseTaskLine("Every minute on the minute (including 0:00), complete 8/6 Cal Ski"),
    { everySec: 60, at0: true, body: "8/6 Cal Ski" });
  assert.deepEqual(parseTaskLine("EMOM: 5 burpees"), { everySec: 60, at0: false, body: "5 burpees" });
  assert.deepEqual(parseTaskLine("Every 2:00, 10 wall balls"), { everySec: 120, at0: false, body: "10 wall balls" });
  assert.deepEqual(parseTaskLine("Every other minute, 3 burpees"), { everySec: 120, at0: false, body: "3 burpees" });
  assert.equal(parseTaskLine("10 burpees"), null);
});

test("sets of AMRAP", () => {
  const w = wod("3 x AMRAP 1:15\nTough set of strict handstand push up\nRest 3:00 between sets");
  assert.equal(w.sets, 3);
  assert.equal(w.setRestSec, 180);
  assert.equal(w.timeCapSec, 75);
  assert.equal(w.blocks.length, 1);
  assert.equal(wod("3 sets of AMRAP 4\n10 burpees").sets, 3);
  assert.equal(wod("AMRAP 12\n10 burpees").sets, undefined);
});

test("max qualifiers, variants, holds", () => {
  const w = wod("AMRAP 5\nTough Set Of Strict Ring Dip\nMax strict pull-ups\nIn Remaining Time, Max Dual Dumbbell Overhead Hold");
  assert.deepEqual(w.blocks.map((b) => [b.movement, b.name, b.reps, b.unit]), [
    ["ring_dip", "Strict ring dip", 0, "reps"],
    ["pull_up", "Pull-ups", 0, "reps"],
    ["custom", "Dual dumbbell overhead hold", 0, "sec"],
  ]);
});

test("men / women reps", () => {
  const b = wod("AMRAP 10\n15/12 cal row\n21 thrusters 43/30").blocks;
  assert.deepEqual([b[0].reps, b[0].repsAlt, b[0].unit, b[0].load], [15, 12, "cal", null]);
  assert.deepEqual([b[1].reps, b[1].repsAlt, b[1].load], [21, undefined, [43, 30]]);
  // a pair followed by a weight unit is still a load
  assert.deepEqual(wod("AMRAP 10\n20/14 kg wall balls").blocks[0].load, [20, 14]);
});

test("every-minute task is not a movement of the WOD", () => {
  const w = wod("For Time\n50 Ring Push-Up\nEvery minute on the minute (including 0:00), complete 8/6 Cal Ski\nCap : 10:00");
  assert.equal(w.blocks.length, 1);
  assert.equal(w.timeCapSec, 600);
  assert.deepEqual(w.task, {
    everySec: 60, at0: true,
    blocks: [{ movement: "ski", name: "Ski erg", reps: 8, unit: "cal", slot: null, load: null, repsAlt: 6 }],
  });
});

test("text and JSON round trip keep sets, task and pairs", () => {
  for (const t of [
    "3 x AMRAP 1:15\nTough set of strict HSPU\nRest 3:00 between sets",
    "For Time\n50 ring push-ups\nEvery minute (including 0:00), 8/6 cal ski\nCap: 10",
    "AMRAP 14\n15/12 cal row\nEvery 3:00, 5 thrusters 40/30",
  ]) {
    const w = wod(t);
    const again = wod(wodToText(w));
    assert.deepEqual({ ...again, name: w.name }, w, t);
    assert.deepEqual(validateWod(JSON.parse(JSON.stringify(w))).wod, w, t);
  }
});

// ---------- engine: sets ----------

test("3 x AMRAP 1:00 rest 0:30: work, rest, work...", () => {
  const e = new TimerEngine(wod("3 x AMRAP 1\n5 burpees\nRest 0:30 between sets"), 0);
  e.start(0);
  for (let i = 0; i < 7; i++) e.addRep(1, 10000 + i * 1000); // 1 round + 2 reps
  assert.equal(e.clockMs(30000), 30000);
  let ev = run(e, 0, 60000);
  assert.equal(e.state, S.REST);
  assert.equal(codes(ev, E.REST).length, 1);
  assert.equal(e.clockMs(70000), 20000);
  assert.deepEqual(e.segment(70000), [10000, 30000]);
  assert.equal(e.addRep(1, 70000).length, 0);
  ev = run(e, 60250, 90000);
  assert.deepEqual(codes(ev, E.SET), [[E.SET, 1]]);
  assert.equal(e.state, S.WORK);
  assert.equal(e.clockMs(100000), 50000);
  for (let i = 0; i < 3; i++) e.addRep(1, 100000 + i * 1000);
  ev = run(e, 90250, 240000);
  assert.equal(e.state, S.DONE);
  assert.equal(e.set, 2);
  // 1 round, and 2 + 3 + 0 reps of unfinished rounds
  assert.deepEqual(e.score(), { kind: "rounds", rounds: 1, reps: 5 });
  assert.equal(e.activeMs(250000), 240000);
});

test("single AMRAP unchanged", () => {
  const e = new TimerEngine(wod("AMRAP 1\n5 burpees"), 0);
  e.start(0);
  const ev = run(e, 0, 60000);
  assert.equal(codes(ev, E.REST).length + codes(ev, E.SET).length, 0);
  assert.equal(e.state, S.DONE);
});

// ---------- engine: every-minute task ----------

test("For time with a task every minute from 0:00", () => {
  const e = new TimerEngine(wod("For Time\n50 ring push-ups\nEvery minute (including 0:00), 3 burpees\nCap: 10"), 0);
  let ev = e.start(0);
  ev = ev.concat(e.tick(0));
  assert.equal(codes(ev, E.TASK).length, 1);
  assert.equal(e.currentBlock().movement, "burpee");
  assert.equal(e.target(e.currentBlock()), 3);
  e.addRep(1, 1000);
  e.addRep(1, 2000);
  ev = e.addRep(1, 3000);
  assert.equal(codes(ev, E.TASK_DONE).length, 1);
  assert.equal(e.currentBlock().movement, "ring_push_up");
  assert.equal(e.lapReps, 0);
  assert.equal(e.totalReps, 3);
  for (let i = 0; i < 20; i++) e.addRep(1, 4000 + i * 1000);
  assert.equal(e.blockReps, 20);
  // minute 1: the task interrupts, the push-ups count is kept
  ev = run(e, 30000, 60000);
  assert.equal(codes(ev, E.TASK).length, 1);
  assert.equal(e.blockReps, 0);
  ev = e.next(62000);
  assert.equal(codes(ev, E.TASK_DONE).length, 1);
  assert.equal(e.blockReps, 20);
  assert.equal(e.totalReps, 26);
  for (let i = 0; i < 30; i++) ev = e.addRep(1, 63000 + i * 1000);
  assert.equal(codes(ev, E.DONE).length, 1);
  assert.deepEqual(e.score(), { kind: "time", ms: 92000 });
});

test("task without 0:00 starts at the first minute", () => {
  const e = new TimerEngine(wod("AMRAP 5\n10 burpees\nEvery 2:00, 5 thrusters"), 0);
  e.start(0);
  let ev = run(e, 0, 119000);
  assert.equal(codes(ev, E.TASK).length, 0);
  ev = run(e, 119250, 120000);
  assert.equal(codes(ev, E.TASK).length, 1);
  assert.equal(e.currentBlock().movement, "thruster");
});

// ---------- strength pages ----------

test("sets headers, notes, ranges, feet, kg before lb", () => {
  assert.deepEqual([wod("3-4 Sets\n5 deadlifts").type, wod("3-4 Sets\n5 deadlifts").rounds], ["FOR_TIME", 4]);
  assert.equal(wod("4 rounds\n10 burpees").rounds, 4);
  const b = wod("AMRAP 10\n3 Deadlift @ 145-155 kg (72.5-77.5%)\nRPE 8\n20 goblet squats @ RPE 7-8").blocks;
  assert.deepEqual(b.map((x) => [x.movement, x.reps, x.load]), [["deadlift", 3, [145]], ["goblet_squat", 20, null]]);
  assert.deepEqual(wod("AMRAP 10\n100ft sled push").blocks[0].reps, 30);
  assert.deepEqual(wod("AMRAP 10\n30 KB swings (53/35lbs || 24/16kg)").blocks[0].load, [24, 16]);
  assert.deepEqual(parseRestLine("1:00 Rest"), { sec: 60, betweenSets: false });
});

test("timed rest block moves on by itself, with 3-2-1", () => {
  const e = new TimerEngine(wod("2 Sets\n2 deadlifts\n1:00 Rest"), 0);
  e.start(0);
  e.addRep(1, 1000);
  e.addRep(1, 5000);
  assert.equal(e.currentBlock().movement, "rest");
  assert.equal(e.restLeftMs(35000), 30000);
  assert.equal(e.addRep(1, 6000).length, 0);
  let ev = run(e, 5250, 64000);
  assert.deepEqual(codes(ev, E.WARN).map((x) => x[1]), [3, 2, 1]);
  assert.equal(codes(ev, E.ROUND).length, 0);
  ev = run(e, 64250, 66000);
  assert.deepEqual(codes(ev, E.ROUND), [[E.ROUND, 1]]);
  assert.equal(e.currentBlock().movement, "deadlift");
  assert.equal(e.restLeftMs(66000), -1);
});

test("rest between rounds: header, brackets, none after the last round", () => {
  const w = wod("2 Rounds For Time (Rest 1:00 between rounds)\n5 burpees");
  assert.deepEqual(w.blocks.map((x) => [x.movement, x.reps]), [["burpee", 5], ["rest", 60]]);
  const b = wod("AMRAP 10\n400m run (rest 1:00)\n10 burpees").blocks;
  assert.deepEqual(b.map((x) => x.movement), ["run", "rest", "burpee"]);
  assert.equal(wod("AMRAP 3\n10 burpees\nThen rest 2:00").restAfterSec, 120);
  assert.deepEqual(parseRestLine("Then rest 2:00"), { sec: 120, betweenSets: false, after: true });
  const e = new TimerEngine(w, 0);
  e.start(0);
  for (let i = 0; i < 5; i++) e.addRep(1, 1000 + i * 1000);
  assert.equal(e.currentBlock().movement, "rest");
  run(e, 5250, 66000);
  assert.equal(e.currentBlock().movement, "burpee");
  let ev = [];
  for (let i = 0; i < 5; i++) ev = ev.concat(e.addRep(1, 70000 + i * 1000));
  // the last round ends on the last burpee, not after a rest
  assert.equal(e.state, S.DONE);
  assert.deepEqual(e.score(), { kind: "time", ms: 74000 });
});
