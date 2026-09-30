import { test } from "node:test";
import assert from "node:assert/strict";
import { alertsDue, secondsToNextSlot, splitParts, ALERT_HALF, ALERT_ONE_MIN } from "../js/coach.js";

test("halfway and one minute alerts fire once when crossed", () => {
  const o = { halfway: true, oneMin: true };
  assert.deepEqual(alertsDue(359000, 360000, 720000, o), [ALERT_HALF]);
  assert.deepEqual(alertsDue(360000, 361000, 720000, o), []);
  assert.deepEqual(alertsDue(659500, 660250, 720000, o), [ALERT_ONE_MIN]);
  assert.deepEqual(alertsDue(0, 720000, 720000, o), [ALERT_HALF, ALERT_ONE_MIN]);
});

test("alerts respect options and short or open WODs", () => {
  assert.deepEqual(alertsDue(359000, 360000, 720000, { halfway: false, oneMin: true }), []);
  assert.deepEqual(alertsDue(59000, 61000, 120000, { halfway: false, oneMin: true }), []);
  assert.deepEqual(alertsDue(1000, 999999, 0, { halfway: true, oneMin: true }), []);
});

test("next wall clock slot", () => {
  assert.equal(secondsToNextSlot(18, 22, 10, 15), 7 * 60 + 50);   // -> 18:30
  assert.equal(secondsToNextSlot(18, 29, 50, 15), 15 * 60 + 10);  // too close -> 18:45
  assert.equal(secondsToNextSlot(18, 29, 50, 1), 70);             // -> 18:31
  assert.equal(secondsToNextSlot(23, 50, 0, 15), 600);            // -> midnight
});

test("plan parts split on ---", () => {
  assert.deepEqual(splitParts("A\n---\nB\nC\n---\n\n"), ["A", "B\nC"]);
  assert.deepEqual(splitParts("AMRAP 12\n10 burpees"), ["AMRAP 12\n10 burpees"]);
  assert.deepEqual(splitParts(""), []);
});
