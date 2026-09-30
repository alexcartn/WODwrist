import { test } from "node:test";
import assert from "node:assert/strict";
import { zoneOf, defaultBounds, trimp, cvPct, densityPct, addLoad, acwr, loadStatus, cardiacTrend } from "../js/perf.js";
import { scoreValue } from "../js/score-history.js";

test("zones", () => {
  const b = defaultBounds(190);
  assert.deepEqual(b, [95, 114, 133, 152, 171, 190]);
  assert.equal(zoneOf(80, b), 0);
  assert.equal(zoneOf(114, b), 1);
  assert.equal(zoneOf(150, b), 4 - 1);
  assert.equal(zoneOf(160, b), 4);
  assert.equal(zoneOf(185, b), 5);
});

test("trimp", () => {
  // 10 min z3 + 5 min z4 + 2 min z5 = 30 + 20 + 10
  assert.equal(trimp([0, 0, 0, 600, 300, 120]), 60);
});

test("cv and density", () => {
  assert.equal(cvPct([90000, 90000, 90000]), 0);
  assert.equal(cvPct([90000, 100000, 110000]), 8);
  assert.equal(cvPct([1]), null);
  assert.equal(densityPct([40000, 45000, 50000], 60000), 75);
  assert.equal(densityPct([], 60000), null);
});

test("load history and ACWR", () => {
  let e = [];
  for (let d = 100; d < 128; d += 2) e = addLoad(e, d, 60);   // every other day, 4 weeks
  e = addLoad(e, 126, 40);                                     // same day merges
  assert.deepEqual(e.find(([d]) => d === 126), [126, 100]);
  const a = acwr(e, 127);
  assert.equal(a.acute, 60 * 2 + 100);          // days 121..127: 122, 124, 126
  assert.equal(a.chronic, Math.round((60 * 13 + 100) / 4));
  assert.equal(loadStatus(e, 127, a.ratio), "optimal");
  assert.equal(loadStatus(e, 110, 200), "building");
  assert.equal(loadStatus(e, 127, 160), "risk");
  assert.equal(loadStatus(e, 127, 70), "low");
  e = addLoad(e, 200, 10);                      // old entries dropped (42 days)
  assert.deepEqual(e, [[200, 10]]);
});

test("cardiac trend", () => {
  const prev = { kind: "rounds", rounds: 7, reps: 5, hr: 168 };
  assert.equal(cardiacTrend(prev, { kind: "rounds", rounds: 7, reps: 10, hr: 162 }, scoreValue), -6);
  assert.equal(cardiacTrend(prev, { kind: "rounds", rounds: 6, reps: 10, hr: 150 }, scoreValue), null);
  assert.equal(cardiacTrend(prev, { kind: "rounds", rounds: 8, reps: 0, hr: 0 }, scoreValue), null);
});
