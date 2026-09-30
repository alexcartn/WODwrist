import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { parseWod, validateWod, wodToText, parseDuration, lookupMovement, parseMovement } from "../js/wod-parser.js";
import { MOVEMENTS } from "../js/movements.js";

const FIX = new URL("../../docs/fixtures/", import.meta.url).pathname;
const fixtures = fs.readdirSync(FIX).filter((f) => f.endsWith(".txt"));

for (const f of fixtures) {
  test(`fixture ${f}`, () => {
    const got = parseWod(fs.readFileSync(path.join(FIX, f), "utf8"));
    const want = JSON.parse(fs.readFileSync(path.join(FIX, f.replace(/\.txt$/, ".json")), "utf8"));
    assert.ok(got.wod, got.error);
    assert.deepEqual(got.wod, want);
  });

  test(`round trip ${f}`, () => {
    const a = parseWod(fs.readFileSync(path.join(FIX, f), "utf8")).wod;
    for (const sep of ["\n", "; "]) {
      const b = parseWod(wodToText(a, sep)).wod;
      assert.ok(b, `re-parse failed for ${sep}`);
      assert.deepEqual(b, a);
    }
  });

  test(`validate ${f}`, () => {
    const a = parseWod(fs.readFileSync(path.join(FIX, f), "utf8")).wod;
    const v = validateWod(JSON.parse(JSON.stringify(a)));
    assert.ok(v.wod, v.error);
    assert.deepEqual(v.wod, a);
  });
}

test("every catalog name resolves to its own id", () => {
  for (const [id, m] of Object.entries(MOVEMENTS)) {
    assert.equal(lookupMovement(m.name), id, m.name);
  }
});

test("durations", () => {
  assert.equal(parseDuration("12"), 720);
  assert.equal(parseDuration("12min"), 720);
  assert.equal(parseDuration("12'"), 720);
  assert.equal(parseDuration("90s"), 90);
  assert.equal(parseDuration("12:30"), 750);
  assert.equal(parseDuration("abc"), -1);
  assert.equal(parseDuration("12x"), -1);
});

test("movement lines", () => {
  assert.deepEqual(parseMovement("wall balls x 10"), { movement: "wall_ball", name: "Wall balls", reps: 10, unit: "reps", slot: null, load: null });
  assert.deepEqual(parseMovement("run 1.5km"), { movement: "run", name: "Run", reps: 1500, unit: "m", slot: null, load: null });
  assert.deepEqual(parseMovement("10x Burpees"), { movement: "burpee", name: "Burpees", reps: 10, unit: "reps", slot: null, load: null });
  assert.deepEqual(parseMovement("Thrusters @ 43/30kg"), { movement: "thruster", name: "Thrusters", reps: 0, unit: "reps", slot: null, load: [43, 30] });
  assert.deepEqual(parseMovement("15 deadlifts 100 kg"), { movement: "deadlift", name: "Deadlifts", reps: 15, unit: "reps", slot: null, load: [100] });
  assert.deepEqual(parseMovement("1 min plank"), { movement: "plank", name: "Plank", reps: 60, unit: "sec", slot: null, load: null });
  assert.deepEqual(parseMovement("20 push presses"), { movement: "push_press", name: "Push press", reps: 20, unit: "reps", slot: null, load: null });
  assert.deepEqual(parseMovement("21 thrusters (43/30kg)").load, [43, 30]);
  assert.deepEqual(parseMovement("10 kbs (1.5 pood)").load, [25]);
  assert.deepEqual(parseMovement("5 cleans (135/95 lb)").load, [61, 43]);
  assert.deepEqual(parseMovement("wall balls 20/14").load, [20, 14]);
  assert.deepEqual(parseMovement("21 thrusters (43/30)").load, [43, 30]);
  assert.deepEqual(parseMovement("12 kb swings (24)").load, [24]);
  assert.deepEqual(parseMovement("10 deadlifts @ 100").load, [100]);
  assert.deepEqual(parseMovement("10 deadlifts @100").load, [100]);
  assert.equal(parseMovement("10 deadlifts @100").reps, 10);
  assert.equal(parseMovement("10 burpees").load, null);
  assert.equal(parseMovement("12 sandbag cleans").movement, "custom");
  assert.equal(parseMovement("12 sandbag cleans").name, "Sandbag cleans");
});

test("header variants", () => {
  assert.equal(parseWod("amrap 15:00\n5 burpees").wod.timeCapSec, 900);
  assert.equal(parseWod("E3MOM x 5\n3 cleans").wod.timeCapSec, 900);
  assert.equal(parseWod("RFT\n10 burpees").wod.rounds, 1);
  assert.equal(parseWod("5 RFT\n10 burpees").wod.rounds, 5);
  assert.equal(parseWod("For time, cap 12\n10 burpees").wod.timeCapSec, 720);
  const t = parseWod("Tabata 10x30/15\nburpees").wod;
  assert.deepEqual([t.rounds, t.workSec, t.restSec, t.timeCapSec], [10, 30, 15, 435]);
});

test("errors", () => {
  assert.match(parseWod("").error, /Empty/);
  assert.match(parseWod("10 burpees").error, /Unknown WOD type/);
  assert.match(parseWod("AMRAP\n10 burpees").error, /duration/);
  assert.match(parseWod("AMRAP 10").error, /No movements/);
  assert.match(parseWod("TABATA 8x20\nsquats").error, /Tabata format/);
  assert.match(parseWod("EMOM 0\nsquats").error, /EMOM/);
});

test("watch SampleWods.mc texts parse", () => {
  const mc = fs.readFileSync(new URL("../../watch-app/source/model/SampleWods.mc", import.meta.url), "utf8");
  const texts = [...mc.matchAll(/^\s*"(#[^"]*)"/gm)].map((m) => m[1].replace(/\\n/g, "\n"));
  assert.ok(texts.length >= 4);
  for (const t of texts) assert.ok(parseWod(t).wod, t);
});

test("published sample today.json is valid", () => {
  const raw = JSON.parse(fs.readFileSync(new URL("../wod/today.json", import.meta.url), "utf8"));
  const v = validateWod(raw);
  assert.ok(v.wod, v.error);
});

test("validateWod rejects bad input and fills defaults", () => {
  assert.ok(validateWod({ version: 2 }).error);
  assert.ok(validateWod({ version: 1, type: "X", blocks: [] }).error);
  assert.ok(validateWod({ version: 1, type: "AMRAP", blocks: [{ movement: "burpee" }] }).error);
  const v = validateWod({ version: 1, type: "EMOM", intervalSec: 60, timeCapSec: 600, blocks: [{ movement: "burpee", reps: 10 }] });
  assert.equal(v.wod.rounds, 10);
  assert.equal(v.wod.blocks[0].slot, 0);
  assert.equal(v.wod.blocks[0].name, "Burpees");
  assert.equal(v.wod.blocks[0].unit, "reps");
});
