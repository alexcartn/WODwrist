import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { cleanOcr } from "../js/shot-import.js";
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
  assert.equal(r.text, "For Time\n21-15-9\nThrusters\nPull-ups\n---\nEMOM 10\nBurpees");
});

test("junk and tab bar", () => {
  const r = cleanOcr("AMRAP 12\n10 T2B\nO [0]\nA & BA J)\nHome Community Shop Profile\n");
  assert.equal(r.text, "AMRAP 12\n10 T2B");
});
