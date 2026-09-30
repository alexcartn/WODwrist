import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { cleanOcr, mergeParts } from "../js/shot-import.js";
import { parseWod } from "../js/wod-parser.js";

const OCR = new URL("./ocr/", import.meta.url).pathname;

test("HWPO page (real OCR output): two WODs, app menus dropped, cut line joined", () => {
  const r = cleanOcr(fs.readFileSync(OCR + "hwpo-skill.txt", "utf8"));
  assert.equal(r.wods, 2);
  const [a, b] = r.text.split("\n---\n");
  assert.ok(!/MASQUER|NOTES|SCORE|Accueil|MODIFIER/i.test(r.text), r.text);
  const wa = parseWod(a).wod;
  assert.equal(wa.sets, 3);
  assert.equal(wa.setRestSec, 180);
  assert.equal(wa.blocks.length, 5);
  const wb = parseWod(b).wod;
  assert.equal(wb.name, "Skill: Ring Push-Up");
  assert.equal(wb.timeCapSec, 600);
  assert.equal(wb.blocks.length, 1);
  assert.deepEqual([wb.task.everySec, wb.task.at0, wb.task.blocks[0].reps, wb.task.blocks[0].repsAlt], [60, true, 8, 6]);
});

test("headers split WODs, schemes and headers are never joined", () => {
  const r = cleanOcr("Metcon\nFor Time\n21-15-9\nThrusters\nPull-ups\nEMOM 10\nBurpees\n");
  assert.equal(r.wods, 2);
  assert.equal(r.text, "# Metcon\nFor Time\n21-15-9\nThrusters\nPull-ups\n---\nEMOM 10\nBurpees");
});

test("junk and tab bar", () => {
  const r = cleanOcr("AMRAP 12\n10 T2B\nO [0]\nA & BA J)\nHome Community Shop Profile\n");
  assert.equal(r.text, "AMRAP 12\n10 T2B");
});

test("HWPO metcon page: kg loads, titles without |, part cut at the bottom", () => {
  const r = cleanOcr(fs.readFileSync(OCR + "hwpo-metcon.txt", "utf8"));
  assert.equal(r.wods, 2);
  assert.equal(r.cut, 1);
  const [a, b] = r.text.split("\n---\n").map((p) => parseWod(p).wod);
  assert.equal(a.name, "Metcon");
  assert.equal(a.rounds, 3);
  assert.deepEqual(a.blocks.map((x) => [x.movement, x.reps, x.unit, x.load]), [
    ["double_under", 100, "reps", null],
    ["custom", 30, "m", [70, 45]],
    ["kb_swing", 30, "reps", [24, 16]],
    ["toes_to_bar", 30, "reps", null],
  ]);
  assert.equal(b.name, "Bonus: Part 1 (then rest 2:00)");
  assert.deepEqual(b.blocks.map((x) => [x.movement, x.reps, x.repsAlt]), [["bike", 30, 24], ["bike", 30, 24]]);
});

test("HWPO strength page: 1RM box dropped, RPE notes ignored, rests timed", () => {
  const r = cleanOcr(fs.readFileSync(OCR + "hwpo-strength.txt", "utf8"));
  assert.equal(r.wods, 2);
  assert.ok(!/1RM|IRM/.test(r.text));
  const [a, b] = r.text.split("\n---\n").map((p) => parseWod(p).wod);
  assert.deepEqual([a.type, a.intervalSec, a.rounds, a.blocks.length, a.blocks[0].load], ["EMOM", 90, 8, 1, [145]]);
  assert.deepEqual([b.type, b.rounds], ["FOR_TIME", 4]);
  assert.deepEqual(b.blocks.map((x) => [x.movement, x.reps, x.unit]), [
    ["goblet_squat", 20, "reps"], ["rest", 60, "sec"], ["custom", 12, "reps"], ["rest", 120, "sec"],
  ]);
});

test("three screenshots of one day: parts in order, overlaps kept once", () => {
  const read = (f) => cleanOcr(fs.readFileSync(OCR + f, "utf8")).text;
  let text = "";
  for (const f of ["hwpo-strength.txt", "hwpo-skill.txt", "hwpo-metcon.txt"]) text = mergeParts(text, read(f));
  const parts = text.split("\n---\n");
  assert.equal(parts.length, 6);
  assert.ok(parts.every((p) => parseWod(p).wod), text);
  // the same page imported twice adds nothing
  assert.equal(mergeParts(text, read("hwpo-metcon.txt")), text);
  // overlap: the end of a part at the top of the next screenshot, without its title
  const a = "# Bonus: Part 1\n3:00 AMRAP\n30/24 cal Fan Bike";
  const b = "3:00 AMRAP\n30/24 cal Fan Bike\n30/24 cal C2 Bike";
  assert.equal(mergeParts(a, b), "# Bonus: Part 1\n3:00 AMRAP\n30/24 cal Fan Bike\n30/24 cal C2 Bike");
});
