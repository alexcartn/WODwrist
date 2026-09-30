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

import { addDay, monotony, weekCompare, domainShare, rankMovements, fatiguePct, countBreaks, beatsDriftPct, srpeLoad, sumDays } from "../js/perf.js";

test("daily vectors, monotony, week compare, domains", () => {
  let e = [[10, 50]];                            // old 2-field entry
  e = addDay(e, 10, [10, 200, 60000, 0, 0, 1]);  // padded then summed
  assert.deepEqual(e, [[10, 60, 200, 60000, 0, 0, 1]]);
  e = [];
  for (let d = 1; d <= 14; d++) e = addDay(e, d, [0, d % 2 ? 300 : 0, 600000, 300000, 100000]);
  assert.deepEqual(weekCompare(e, 14, 2), [900, 1200]);
  const m = monotony(e, 14, 2);
  assert.equal(m.monotony, Math.round((900 / 7) * 100 / Math.sqrt(((300 - 900 / 7) ** 2 * 3 + (900 / 7) ** 2 * 4) / 7)));
  assert.equal(m.strain, Math.round(900 * m.monotony / 100));
  assert.equal(monotony(e, 100, 2), null);
  assert.deepEqual(domainShare(e, 14, 28), [60, 30, 10]);
  assert.equal(sumDays(e, 14, 1, 7), 0);
});

test("movement ranking, fatigue, breaks, drift, sRPE", () => {
  const r = rankMovements({ burpee: [100, 280000], wall_ball: [200, 600000], pull_up: [10, 30000] }, { burpee: 35, wall_ball: 25, pull_up: 20 });
  assert.deepEqual(r, [["burpee", 80], ["wall_ball", 120]]);
  assert.equal(fatiguePct([[10, 30000], [10, 33000], [10, 37500]]), 25);
  assert.equal(fatiguePct([[10, 30000]]), null);
  assert.equal(countBreaks([0, 2000, 4000, 6000, 12000, 14000, 16000]), 1);
  assert.equal(countBreaks([0, 2000]), 0);
  assert.equal(beatsDriftPct([[90000, 30, 150], [95000, 30, 160], [100000, 30, 170]]), 26);
  assert.equal(srpeLoad(8, 12 * 60000 + 20000), 96);
});
