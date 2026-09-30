// Editor helpers: syntax highlighting of the WOD text and movement
// autocomplete. Pure functions (tested in test/assist.test.js).

import { parseHeader, parseMovement, normalizeName, parseCapLine, parseRestLine, parseTaskLine, cutNotes } from "./wod-parser.js";
import { MOVEMENTS, ALIASES } from "./movements.js";

const LOAD_RE = /(@\s*)?\d+(?:\.\d+)?(?:\/\d+(?:\.\d+)?)*\s*(?:kgs?|lbs?|#|pood|pd)\b|\([^)]*\)|\[[^\]]*\]|@\s*\d+(?:\/\d+)*|\b\d+(?:\/\d+)+\b/gi;
const NUM_RE = /^\s*(\d+(?:\.\d+)?\s*(?:m|km|cal|cals|calories|s|sec|secs|min|mins|x)?)(?=\s|$)/i;
const SCHEME_RE = /^\s*\d+(\s*-\s*\d+)*\s*(-\s*)?(\.\.\.|…|\+)?\s*$/;
const SLOT_RE = /^\s*(odd|even|min(?:ute)?\s+\d+)\s*:/i;

// One line -> [[text, class], ...] covering the whole line.
// Classes: name, hdr, bad, scheme, sep, slot, num, load, mv, custom, txt
export function classifyLine(line, isFirstContent) {
  if (line.trim() === "") return [[line, "txt"]];
  if (line.trim() === "---") return [[line, "sep"]];
  if (line.trimStart().startsWith("#") || /^\s*name\s*:/i.test(line)) return [[line, "name"]];
  if (isFirstContent) {
    const h = parseHeader(line);
    if (h && !h.error) return [[line, "hdr"]];
    if (h && h.error) return [[line, "bad"]];
  }
  if (line.includes("-") && SCHEME_RE.test(line)) return [[line, "scheme"]];
  if (isFirstContent) return [[line, "bad"]];
  // intensity note ("RPE 8"): ignored by the parser
  if (cutNotes(line).trim() === "") return [[line, "name"]];
  // option lines: time cap, rest between sets, every-minute task
  if (parseCapLine(line) > 0 || parseRestLine(line)) return [[line, "hdr"]];
  const task = parseTaskLine(line);
  if (task) {
    // "Every minute (including 0:00)," in the option color, then the movements
    const start = line.lastIndexOf(task.body);
    if (start > 0) return [[line.substring(0, start), "slot"], ...movementTokens(line.substring(start))];
    return [[line, "slot"]];
  }

  const out = [];
  let rest = line;
  const slot = rest.match(SLOT_RE);
  if (slot) {
    out.push([slot[0], "slot"]);
    rest = rest.substring(slot[0].length);
  }
  for (const part of splitKeep(rest, "+")) {
    if (part === "+") {
      out.push([part, "sep"]);
      continue;
    }
    out.push(...movementTokens(part));
  }
  return out;
}

function splitKeep(s, ch) {
  const out = [];
  let cur = "";
  for (const c of s) {
    if (c === ch) {
      out.push(cur, ch);
      cur = "";
    } else cur += c;
  }
  out.push(cur);
  return out.filter((x) => x.length > 0);
}

function movementTokens(part) {
  const known = parseMovement(part).movement !== "custom";
  const pieces = [];
  let last = 0;
  // loads first, then the leading number, the rest is the movement name
  const spans = [];
  // "15/12 cal row": a leading pair is men / women reps, not a load
  const pair = part.match(/^\s*(\d+\/\d+)(?=\s+(?!(?:kgs?|lbs?|#|pood|pd)\b)\S)/i);
  if (pair) spans.push([part.indexOf(pair[1]), part.indexOf(pair[1]) + pair[1].length, "num"]);
  for (const m of part.matchAll(LOAD_RE)) {
    if (pair && m.index < part.indexOf(pair[1]) + pair[1].length) continue;
    spans.push([m.index, m.index + m[0].length, "load"]);
  }
  const num = part.match(NUM_RE);
  if (num) {
    const at = part.indexOf(num[1]);
    if (!spans.some(([a, b]) => at < b && at + num[1].length > a)) spans.push([at, at + num[1].length, "num"]);
  }
  spans.sort((a, b) => a[0] - b[0]);
  for (const [a, b, cls] of spans) {
    if (a < last) continue;
    if (a > last) pieces.push([part.substring(last, a), known ? "mv" : "custom"]);
    pieces.push([part.substring(a, b), cls]);
    last = b;
  }
  if (last < part.length) pieces.push([part.substring(last), known ? "mv" : "custom"]);
  // whitespace-only runs stay plain text
  return pieces.map(([t, c]) => [t, t.trim() === "" ? "txt" : c]);
}

function esc(s) {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);
}

// Whole text -> HTML for the highlight layer. errorLine: 0-based line to underline.
export function highlight(text, errorLine = -1) {
  const lines = text.split("\n");
  let expectHeader = true;
  return lines
    .map((line, i) => {
      if (line.trim() === "---") expectHeader = true;
      const isHeader = expectHeader && line.trim() !== "" && line.trim() !== "---" && !line.trimStart().startsWith("#") && !/^\s*name\s*:/i.test(line);
      const toks = classifyLine(line, isHeader);
      if (isHeader) expectHeader = false;
      const html = toks.map(([t, c]) => (c === "txt" ? esc(t) : `<span class="hl-${c}">${esc(t)}</span>`)).join("");
      return i === errorLine ? `<span class="hl-err">${html || " "}</span>` : html;
    })
    .join("\n");
}

// ---------- autocomplete ----------

const NAMES = Object.entries(MOVEMENTS).map(([id, m]) => ({ id, name: m.name }));

// The movement words being typed at the end of `before` (text of the line
// before the cursor), without the leading number / unit.
export function partialMovement(before) {
  let s = before.replace(SLOT_RE, "");
  const plus = s.lastIndexOf("+");
  if (plus >= 0) s = s.substring(plus + 1);
  s = s.replace(LOAD_RE, " ").replace(NUM_RE, "");
  return s.replace(/^\s+/, "");
}

// Up to `max` suggestions [{ id, name, insert }] for the partial text.
export function suggest(before, max = 4) {
  const p = normalizeName(partialMovement(before));
  if (p.length < 2 || /^\d/.test(p)) return [];
  const seen = new Set();
  const out = [];
  const push = (id, insert) => {
    if (seen.has(id) || out.length >= max) return;
    seen.add(id);
    out.push({ id, name: MOVEMENTS[id].name, insert });
  };
  // catalog names first, then aliases
  for (const { id, name } of NAMES) if (normalizeName(name).startsWith(p) && normalizeName(name) !== p) push(id, name.toLowerCase());
  for (const [alias, id] of Object.entries(ALIASES)) if (alias.startsWith(p) && alias !== p && alias.length > 3) push(id, alias);
  return out;
}

// Replace the partial movement at the end of `before` by `insert`.
export function applySuggestion(before, insert) {
  const partial = partialMovement(before);
  return before.substring(0, before.length - partial.length) + insert;
}
