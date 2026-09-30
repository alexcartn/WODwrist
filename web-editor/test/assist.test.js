import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyLine, highlight, suggest, applySuggestion, partialMovement } from "../js/editor-assist.js";
import { BENCHMARKS } from "../js/benchmarks.js";
import { parseWod } from "../js/wod-parser.js";

const cls = (line, first = false) => classifyLine(line, first).filter(([t, c]) => c !== "txt").map(([t, c]) => `${c}:${t.trim()}`);

test("line classes", () => {
  assert.deepEqual(cls("AMRAP 12", true), ["hdr:AMRAP 12"]);
  assert.deepEqual(cls("AMRAP", true), ["bad:AMRAP"]);
  assert.deepEqual(cls("# Fran"), ["name:# Fran"]);
  assert.deepEqual(cls("21-15-9"), ["scheme:21-15-9"]);
  assert.deepEqual(cls("3-6-9-..."), ["scheme:3-6-9-..."]);
  assert.deepEqual(cls("---"), ["sep:---"]);
  assert.deepEqual(cls("10 wall balls (9/6)"), ["num:10", "mv:wall balls", "load:(9/6)"]);
  assert.deepEqual(cls("200m run"), ["num:200m", "mv:run"]);
  assert.deepEqual(cls("12 sandbag cleans"), ["num:12", "custom:sandbag cleans"]);
  assert.deepEqual(cls("odd: 12 kb swings @24kg"), ["slot:odd:", "num:12", "mv:kb swings", "load:@24kg"]);
  assert.deepEqual(cls("5 cleans + 10 box jumps"), ["num:5", "mv:cleans", "sep:+", "num:10", "mv:box jumps"]);
});

test("highlight keeps the text and marks the error line", () => {
  const text = "# X\nAMRAP 12\n10 burpees\n---\nEMOM 5\n5 cleans";
  const html = highlight(text, 2);
  assert.equal(html.replace(/<[^>]+>/g, ""), text);
  assert.match(html, /hl-hdr">EMOM 5/);
  assert.match(html, /hl-err/);
});

test("autocomplete", () => {
  assert.equal(partialMovement("10 wall b"), "wall b");
  assert.equal(partialMovement("odd: 12 kb"), "kb");
  assert.equal(partialMovement("5 cleans + 10 bo"), "bo");
  assert.equal(partialMovement("21 thrusters (43/30) + 12 pu"), "pu");
  const s = suggest("10 wall b");
  assert.equal(s[0].id, "wall_ball");
  assert.equal(applySuggestion("10 wall b", s[0].insert), "10 wall balls");
  assert.ok(suggest("12 pul").some((x) => x.id === "pull_up"));
  assert.deepEqual(suggest("10 b"), []);          // too short
  assert.deepEqual(suggest("10 wall balls"), []);  // already complete
});

test("benchmarks parse, with known movements only", () => {
  for (const [name, text] of BENCHMARKS) {
    const r = parseWod(text);
    assert.ok(r.wod, `${name}: ${r.error}`);
    assert.ok(r.wod.blocks.every((b) => b.movement !== "custom"), `${name}: custom movement`);
  }
});
