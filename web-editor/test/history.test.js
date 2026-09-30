import { test } from "node:test";
import assert from "node:assert/strict";
import { parseWod } from "../js/wod-parser.js";
import { wodSignature, isBetter, paceDelta, formatDelta, scoreText, addResult } from "../js/score-history.js";

const w = (t) => parseWod(t).wod;

test("signature ignores the name, not the content", () => {
  const a = w("# Monday\nAMRAP 12\n10 wall balls\n10 burpees");
  const b = w("# Friday\nAMRAP 12\n10 wall balls\n10 burpees");
  const c = w("AMRAP 12\n10 wall balls\n12 burpees");
  const d = w("AMRAP 15\n10 wall balls\n10 burpees");
  assert.equal(wodSignature(a), wodSignature(b));
  assert.notEqual(wodSignature(a), wodSignature(c));
  assert.notEqual(wodSignature(a), wodSignature(d));
  assert.notEqual(wodSignature(a), wodSignature(a, true));
});

test("score comparison per kind", () => {
  const r = (rounds, reps) => ({ kind: "rounds", rounds, reps });
  assert.ok(isBetter(r(7, 12), r(7, 3)));
  assert.ok(isBetter(r(8, 0), r(7, 99)));
  assert.ok(!isBetter(r(7, 3), r(7, 3)));
  assert.ok(isBetter({ kind: "time", ms: 250000 }, { kind: "time", ms: 260000 }));
  assert.ok(isBetter({ kind: "time", ms: 900000 }, { kind: "reps", reps: 400 }));
  assert.ok(isBetter({ kind: "reps", reps: 90 }, null));
});

test("pace delta at the last completed round", () => {
  const ref = [90000, 185000, 283000];
  assert.equal(paceDelta([], ref), null);
  assert.equal(paceDelta([85000], ref), -5000);
  assert.equal(paceDelta([85000, 199000], ref), 14000);
  assert.equal(paceDelta([1, 2, 3, 4], ref), null);
  assert.equal(paceDelta([1], null), null);
});

test("formatting", () => {
  assert.equal(formatDelta(-8400), "-0:08");
  assert.equal(formatDelta(14000), "+0:14");
  assert.equal(formatDelta(75000), "+1:15");
  assert.equal(scoreText({ kind: "rounds", rounds: 7, reps: 12 }), "7 + 12");
  assert.equal(scoreText({ kind: "time", ms: 277900 }), "4:37");
  assert.equal(scoreText({ kind: "reps", reps: 88 }), "88 reps");
});

test("history keeps last and best", () => {
  let e = addResult(null, { kind: "rounds", rounds: 6, reps: 0 });
  e = addResult(e, { kind: "rounds", rounds: 7, reps: 5 });
  e = addResult(e, { kind: "rounds", rounds: 6, reps: 20 });
  assert.equal(e.n, 3);
  assert.deepEqual(e.best, { kind: "rounds", rounds: 7, reps: 5 });
  assert.deepEqual(e.last, { kind: "rounds", rounds: 6, reps: 20 });
});

import { roundDurations, fadePct, tenthsPerRep, mergeMovementStats } from "../js/score-history.js";

test("stats: round durations and fade", () => {
  assert.deepEqual(roundDurations([90000, 185000, 290000]), [90000, 95000, 105000]);
  assert.equal(fadePct([90000, 185000, 290000]), 17);
  assert.equal(fadePct([100000, 190000]), -10);
  assert.equal(fadePct([90000]), null);
  assert.equal(fadePct(null), null);
});

test("stats: pace per rep and movement merge", () => {
  assert.equal(tenthsPerRep(10, 24000), 24);
  assert.equal(tenthsPerRep(0, 1000), null);
  assert.deepEqual(
    mergeMovementStats({ burpee: [100, 300000] }, { burpee: [20, 50000], wall_ball: [30, 70000] }),
    { burpee: [120, 350000], wall_ball: [30, 70000] },
  );
});
