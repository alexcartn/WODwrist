// WOD text parser: reference implementation.
// The Monkey C port (watch-app/source/model/WodParser.mc) follows this file
// step by step. Keep both in sync; shared fixtures live in docs/fixtures.

import { MOVEMENTS, ALIASES } from "./movements.js";

export const TYPES = ["AMRAP", "EMOM", "FOR_TIME", "TABATA"];
export const UNITS = ["reps", "m", "cal", "sec"];

const UNIT_MAP = {
  m: ["m", 1], meter: ["m", 1], meters: ["m", 1], metre: ["m", 1], metres: ["m", 1],
  km: ["m", 1000],
  cal: ["cal", 1], cals: ["cal", 1], calorie: ["cal", 1], calories: ["cal", 1],
  s: ["sec", 1], sec: ["sec", 1], secs: ["sec", 1], second: ["sec", 1], seconds: ["sec", 1],
  min: ["sec", 60], mins: ["sec", 60], minute: ["sec", 60], minutes: ["sec", 60],
  rep: ["reps", 1], reps: ["reps", 1],
};
const WEIGHT_UNITS = ["kg", "kgs", "lb", "lbs", "#", "pood", "pd"];

// ---------- small string helpers (mirrored by Str.mc) ----------

function isDigit(c) { return c >= "0" && c <= "9"; }

export function isNumeric(s) {
  if (s.length === 0) return false;
  let dots = 0;
  for (const c of s) {
    if (c === ".") { dots++; if (dots > 1) return false; }
    else if (!isDigit(c)) return false;
  }
  return s !== ".";
}

function isInt(s) {
  if (s.length === 0) return false;
  for (const c of s) if (!isDigit(c)) return false;
  return true;
}

// Only digits, dots and slashes, with at least one digit: "43/30", "9.5".
function isWeightNumber(s) {
  let digit = false;
  for (const c of s) {
    if (isDigit(c)) digit = true;
    else if (c !== "." && c !== "/") return false;
  }
  return digit;
}

function tokens(s) {
  return s.split(" ").filter((t) => t.length > 0);
}

function replaceChars(s, chars, by) {
  let out = "";
  for (const c of s) out += chars.includes(c) ? by : c;
  return out;
}

export function normalizeName(s) {
  return tokens(replaceChars(s.toLowerCase(), "-_.", " ")).join(" ");
}

// ---------- durations ----------

// "12" (minutes by default), "12min", "12'", "90s", "12:30". Returns seconds or -1.
export function parseDuration(tok) {
  if (tok == null || tok.length === 0) return -1;
  const colon = tok.indexOf(":");
  if (colon >= 0) {
    const m = tok.substring(0, colon);
    const s = tok.substring(colon + 1);
    if (!isInt(m) || !isInt(s)) return -1;
    return parseInt(m, 10) * 60 + parseInt(s, 10);
  }
  let i = 0;
  while (i < tok.length && isDigit(tok[i])) i++;
  if (i === 0) return -1;
  const n = parseInt(tok.substring(0, i), 10);
  const suffix = tok.substring(i);
  if (suffix === "" || suffix === "m" || suffix === "min" || suffix === "mins" || suffix === "minutes" || suffix === "'") return n * 60;
  if (suffix === "s" || suffix === "sec" || suffix === "secs" || suffix === "\"") return n;
  return -1;
}

// ---------- header ----------

function emptyHeader(type) {
  return { type, timeCapSec: null, intervalSec: null, workSec: null, restSec: null, rounds: null, inline: null };
}

const SEC_WORDS = ["s", "sec", "secs", "second", "seconds"];
const MIN_WORDS = ["min", "mins", "minute", "minutes"];
const ROUND_WORDS = ["rounds", "round", "sets", "set", "intervals"];

// Duration at t[k], possibly followed by a unit word ("90 sec", "3 min").
// Returns [seconds, next index] or null.
function durationAt(t, k) {
  if (k >= t.length) return null;
  if (k + 1 < t.length && isInt(t[k])) {
    if (SEC_WORDS.includes(t[k + 1])) return [parseInt(t[k], 10), k + 2];
    if (MIN_WORDS.includes(t[k + 1])) return [parseInt(t[k], 10) * 60, k + 2];
  }
  const d = parseDuration(t[k]);
  return d > 0 ? [d, k + 1] : null;
}

// Returns a header object, or null when the line is not a WOD header.
// On a recognised type with bad parameters returns { error }.
export function parseHeader(line) {
  const t = tokens(replaceChars(line.toLowerCase(), "(),", " "));
  if (t.length === 0) return null;

  // AMRAP 12 | 12 min AMRAP | AMRAP 12:30
  let i = t.indexOf("amrap");
  if (i >= 0 && t.includes("death")) i = -1;
  if (i >= 0) {
    let d = i + 1 < t.length ? parseDuration(t[i + 1]) : -1;
    if (d < 0 && i > 0) {
      let j = i - 1;
      if ((t[j] === "min" || t[j] === "mins" || t[j] === "minutes") && j > 0) j--;
      d = parseDuration(t[j]);
    }
    if (d <= 0) return { error: "AMRAP needs a duration, e.g. AMRAP 12" };
    const h = emptyHeader("AMRAP");
    h.timeCapSec = d;
    return h;
  }

  // DEATH BY burpees: 1 rep the first minute, 2 the second... until failure
  for (let k = 0; k + 1 < t.length; k++) {
    if (t[k] === "death" && (t[k + 1] === "by" || t[k + 1] === "by:")) {
      const h = emptyHeader("EMOM");
      h.intervalSec = 60;
      h.rounds = 60;
      h.timeCapSec = 3600;
      h.deathBy = true;
      const low = line.toLowerCase();
      const at = low.indexOf("by", low.indexOf("death") + 5);
      const rest = line.substring(at + 2).replace(/^[\s:]+/, "").trim();
      h.inline = rest.length > 0 ? rest : null;
      return h;
    }
  }

  // EVERY 2:30 x 6 | every 90 sec for 12 min | every 3 min for 5 rounds
  i = t.indexOf("every");
  if (i >= 0) {
    const d = durationAt(t, i + 1);
    if (!d) return { error: "EVERY needs an interval, e.g. EVERY 2:30 x 6" };
    const h = emptyHeader("EMOM");
    h.intervalSec = d[0];
    let j = d[1];
    if (j + 1 < t.length && t[j] === "x" && isInt(t[j + 1])) {
      h.rounds = parseInt(t[j + 1], 10);
    } else if (j < t.length && t[j][0] === "x" && isInt(t[j].substring(1))) {
      h.rounds = parseInt(t[j].substring(1), 10);
    } else if (j < t.length && t[j] === "for") {
      if (j + 2 < t.length && isInt(t[j + 1]) && ROUND_WORDS.includes(t[j + 2])) {
        h.rounds = parseInt(t[j + 1], 10);
      } else {
        const total = durationAt(t, j + 1);
        if (total) h.rounds = Math.floor(total[0] / h.intervalSec);
      }
    } else if (j + 1 < t.length && isInt(t[j]) && ROUND_WORDS.includes(t[j + 1])) {
      h.rounds = parseInt(t[j], 10);
    }
    if (!(h.rounds > 0)) return { error: "EVERY needs a number of rounds, e.g. EVERY 2:30 x 6" };
    h.timeCapSec = h.rounds * h.intervalSec;
    return h;
  }

  // EMOM 10 | E2MOM 20 | E3MOM x 5
  for (let k = 0; k < t.length; k++) {
    const tok = t[k];
    if (tok.length >= 4 && tok[0] === "e" && tok.endsWith("mom")) {
      const mid = tok.substring(1, tok.length - 3);
      if (mid !== "" && !isInt(mid)) continue;
      const every = mid === "" ? 1 : parseInt(mid, 10);
      if (every <= 0) return { error: "Invalid EMOM interval" };
      const h = emptyHeader("EMOM");
      h.intervalSec = every * 60;
      if (k + 2 < t.length && t[k + 1] === "x" && isInt(t[k + 2])) {
        h.rounds = parseInt(t[k + 2], 10);
      } else {
        const d = k + 1 < t.length ? parseDuration(t[k + 1]) : -1;
        if (d <= 0) return { error: "EMOM needs a duration, e.g. EMOM 10" };
        h.rounds = Math.floor(d / h.intervalSec);
      }
      if (h.rounds <= 0) return { error: "EMOM duration shorter than one interval" };
      h.timeCapSec = h.rounds * h.intervalSec;
      return h;
    }
  }

  // FOR TIME | 3 ROUNDS FOR TIME | RFT | FOR TIME cap 15 | FOR TIME (time cap 15:00)
  let forTime = false;
  for (let k = 0; k < t.length; k++) {
    if (t[k] === "fortime" || t[k] === "rft") forTime = true;
    if (t[k] === "for" && k + 1 < t.length && t[k + 1] === "time") forTime = true;
  }
  if (forTime) {
    const h = emptyHeader("FOR_TIME");
    for (let k = 0; k < t.length; k++) {
      if ((t[k] === "rounds" || t[k] === "round" || t[k] === "rft") && k > 0 && isInt(t[k - 1])) {
        h.rounds = parseInt(t[k - 1], 10);
      }
      if ((t[k] === "cap" || t[k] === "tc" || t[k] === "timecap") && k + 1 < t.length) {
        const d = parseDuration(t[k + 1]);
        if (d <= 0) return { error: "Invalid time cap" };
        h.timeCapSec = d;
      }
    }
    return h;
  }

  // TABATA | TABATA 8x20/10
  i = t.indexOf("tabata");
  if (i >= 0) {
    const h = emptyHeader("TABATA");
    h.rounds = 8; h.workSec = 20; h.restSec = 10;
    const spec = t.slice(i + 1).join("");
    if (spec.length > 0) {
      const x = spec.indexOf("x");
      const sl = spec.indexOf("/");
      if (x <= 0 || sl <= x + 1) return { error: "Tabata format is ROUNDSxWORK/REST, e.g. 8x20/10" };
      const r = spec.substring(0, x), w = spec.substring(x + 1, sl), z = spec.substring(sl + 1);
      if (!isInt(r) || !isInt(w) || !isInt(z)) return { error: "Tabata format is ROUNDSxWORK/REST, e.g. 8x20/10" };
      h.rounds = parseInt(r, 10); h.workSec = parseInt(w, 10); h.restSec = parseInt(z, 10);
      if (h.rounds <= 0 || h.workSec <= 0) return { error: "Tabata rounds and work must be > 0" };
    }
    h.intervalSec = h.workSec + h.restSec;
    h.timeCapSec = h.rounds * h.intervalSec - h.restSec;
    return h;
  }
  return null;
}

// ---------- movement lines ----------

function stripBrackets(s) {
  let out = "";
  let depth = 0;
  for (const c of s) {
    if (c === "(" || c === "[") depth++;
    else if (c === ")" || c === "]") { if (depth > 0) depth--; }
    else if (depth === 0) out += c;
  }
  return out;
}

export function lookupMovement(text) {
  const n = normalizeName(text);
  if (ALIASES[n]) return ALIASES[n];
  if (n.endsWith("es") && ALIASES[n.substring(0, n.length - 2)]) return ALIASES[n.substring(0, n.length - 2)];
  if (n.endsWith("s") && ALIASES[n.substring(0, n.length - 1)]) return ALIASES[n.substring(0, n.length - 1)];
  return null;
}

function capitalize(s) {
  return s.length === 0 ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------- loads: "43/30kg", "24 kg", "@60kg", "(53/35 lb)", "1.5 pood" ----------

const KG_PER = { kg: 1, kgs: 1, lb: 0.4536, lbs: 0.4536, "#": 0.4536, pood: 16.38, pd: 16.38 };

function weightValues(num, unit) {
  const out = [];
  for (const v of num.split("/")) {
    if (v.length === 0 || !isNumeric(v)) return null;
    out.push(Math.round(parseFloat(v) * KG_PER[unit]));
  }
  return out.length > 0 && out.every((x) => x > 0) ? out : null;
}

// First load written in these tokens, in kg: [rx] or [rx, alternative].
// Without a unit, loads are kg: "20/14", "@60". In brackets any number is a
// load: "(24)", "(43/30)".
function findLoad(t, inBrackets = false) {
  for (let k = 0; k < t.length; k++) {
    const tok = t[k][0] === "@" ? t[k].substring(1) : t[k];
    for (const u of WEIGHT_UNITS) {
      if (tok.endsWith(u) && tok.length > u.length && isWeightNumber(tok.substring(0, tok.length - u.length))) {
        const v = weightValues(tok.substring(0, tok.length - u.length), u);
        if (v) return v;
      }
    }
    if (WEIGHT_UNITS.includes(tok) && k > 0) {
      const prev = t[k - 1][0] === "@" ? t[k - 1].substring(1) : t[k - 1];
      if (isWeightNumber(prev)) {
        const v = weightValues(prev, tok);
        if (v) return v;
      }
    }
  }
  // no unit written: kg
  for (let k = 0; k < t.length; k++) {
    const at = t[k][0] === "@";
    const tok = at ? t[k].substring(1) : t[k];
    const next = k + 1 < t.length ? t[k + 1] : "";
    if (WEIGHT_UNITS.includes(next)) continue;
    if (isWeightNumber(tok) && (at || inBrackets || tok.includes("/"))) {
      const v = weightValues(tok, "kg");
      if (v) return v;
    }
    if (t[k] === "@" && k + 1 < t.length && isWeightNumber(t[k + 1])) {
      const v = weightValues(t[k + 1], "kg");
      if (v) return v;
    }
  }
  return null;
}

function bracketText(s) {
  let out = "";
  let depth = 0;
  for (const c of s) {
    if (c === "(" || c === "[") { depth++; out += " "; }
    else if (c === ")" || c === "]") { if (depth > 0) depth--; out += " "; }
    else if (depth > 0) out += c;
  }
  return out;
}

export function parseMovement(raw) {
  const t0 = tokens(stripBrackets(raw).toLowerCase());
  const load = findLoad(t0) ?? findLoad(tokens(bracketText(raw).toLowerCase()), true);

  // drop loads: "43/30kg", "20/14", "24 kg", "@", "@60kg"
  const t1 = [];
  for (let k = 0; k < t0.length; k++) {
    const tok = t0[k];
    if (tok[0] === "@") continue;
    if (tok.includes("/") && isWeightNumber(tok)) continue;
    let unitAt = -1;
    for (const u of WEIGHT_UNITS) {
      if (tok.endsWith(u) && tok.length > u.length && isWeightNumber(tok.substring(0, tok.length - u.length))) unitAt = 1;
    }
    if (unitAt > 0) continue;
    if (WEIGHT_UNITS.includes(tok) && t1.length > 0 && isWeightNumber(t1[t1.length - 1])) { t1.pop(); continue; }
    t1.push(tok);
  }

  // split "200m" -> "200" "m", "10x" -> "10" "x"
  const t = [];
  for (const tok of t1) {
    let i = 0;
    while (i < tok.length && (isDigit(tok[i]) || tok[i] === ".")) i++;
    if (i > 0 && i < tok.length && isNumeric(tok.substring(0, i))) {
      t.push(tok.substring(0, i));
      t.push(tok.substring(i));
    } else {
      t.push(tok);
    }
  }

  let reps = 0;
  let unit = "reps";
  const used = new Array(t.length).fill(false);
  for (let k = 0; k < t.length; k++) {
    if (!isNumeric(t[k])) continue;
    let value = parseFloat(t[k]);
    let mult = 1;
    used[k] = true;
    if (k + 1 < t.length && UNIT_MAP[t[k + 1]]) {
      [unit, mult] = UNIT_MAP[t[k + 1]];
      used[k + 1] = true;
    }
    if (k + 1 < t.length && t[k + 1] === "x") used[k + 1] = true;
    if (k > 0 && t[k - 1] === "x") used[k - 1] = true;
    reps = Math.round(value * mult);
    break;
  }

  const rest = [];
  for (let k = 0; k < t.length; k++) if (!used[k]) rest.push(t[k]);
  const text = rest.join(" ");
  const id = lookupMovement(text);
  let name;
  if (id) name = MOVEMENTS[id].name;
  else name = text.length > 0 ? capitalize(text) : raw.trim();
  return { movement: id || "custom", name, reps, unit, slot: null, load };
}

// ---------- rep scheme ----------

// "21-15-9" -> { scheme: [21, 15, 9], step: null }
// "3-6-9-..." or "3-6-9..." (open ladder) -> { scheme: [3, 6, 9], step: 3 }
function parseRepScheme(line) {
  let s = replaceChars(line, " ", "");
  let open = false;
  for (const tail of ["...", "\u2026", "+"]) {
    if (s.endsWith(tail)) {
      open = true;
      s = s.substring(0, s.length - tail.length);
      if (s.endsWith("-")) s = s.substring(0, s.length - 1);
      break;
    }
  }
  if (!s.includes("-") && !(open && isInt(s))) return null;
  const out = [];
  for (const p of s.split("-")) {
    if (!isInt(p)) return null;
    out.push(parseInt(p, 10));
  }
  let step = null;
  if (open) step = out.length >= 2 ? out[out.length - 1] - out[out.length - 2] : out[0];
  if (open && !(step > 0)) return null;
  return { scheme: out, step };
}

// ---------- slot prefixes ----------

// "odd: x" -> [0, "x"], "even: x" -> [1, "x"], "min 3: x" -> [2, "x"]
function parseSlot(line) {
  const c = line.indexOf(":");
  if (c <= 0) return null;
  const head = tokens(line.substring(0, c).toLowerCase());
  const body = line.substring(c + 1).trim();
  if (head.length === 1 && head[0] === "odd") return [0, body];
  if (head.length === 1 && head[0] === "even") return [1, body];
  if (head.length === 2 && (head[0] === "min" || head[0] === "minute") && isInt(head[1]) && parseInt(head[1], 10) > 0) {
    return [parseInt(head[1], 10) - 1, body];
  }
  return null;
}

// ---------- main entry ----------

export function splitLines(text) {
  const out = [];
  let cur = "";
  for (const c of text) {
    if (c === "\n" || c === "\r" || c === ";" || c === "|") {
      if (cur.trim().length > 0) out.push(cur.trim());
      cur = "";
    } else {
      cur += c;
    }
  }
  if (cur.trim().length > 0) out.push(cur.trim());
  return out;
}

// Returns { wod } or { error, line } (line is 1-based within the split lines).
export function parseWod(text) {
  const lines = splitLines(text || "");
  let name = null;
  let header = null;
  let headerLine = null;
  let repScheme = null;
  let repStep = null;
  const blocks = [];
  let nextSlot = 0;

  for (let n = 0; n < lines.length; n++) {
    const line = lines[n];
    if (line[0] === "#") { name = line.substring(1).trim(); continue; }
    if (line.toLowerCase().startsWith("name:")) { name = line.substring(5).trim(); continue; }

    if (header == null) {
      const h = parseHeader(line);
      if (h == null) return { error: `Unknown WOD type: "${line}". Start with AMRAP, EMOM, FOR TIME or TABATA.`, line: n + 1 };
      if (h.error) return { error: h.error, line: n + 1 };
      header = h;
      headerLine = line;
      if (h.inline) {
        for (const part of h.inline.split("+")) {
          if (part.trim().length === 0) continue;
          const b = parseMovement(part);
          b.slot = 0;
          blocks.push(b);
        }
        nextSlot = 1;
      }
      continue;
    }

    const scheme = parseRepScheme(line);
    if (scheme) { repScheme = scheme.scheme; repStep = scheme.step; continue; }

    let slot = null;
    let body = line;
    const sp = parseSlot(line);
    if (sp) { slot = sp[0]; body = sp[1]; }
    const interval = header.type === "EMOM" || header.type === "TABATA";
    if (header.deathBy) slot = 0;
    if (interval && slot == null) slot = nextSlot;

    for (const part of body.split("+")) {
      if (part.trim().length === 0) continue;
      const b = parseMovement(part);
      b.slot = interval ? slot : null;
      blocks.push(b);
    }
    if (interval && slot + 1 > nextSlot) nextSlot = slot + 1;
  }

  if (header == null) return { error: "Empty WOD", line: 0 };
  if (blocks.length === 0) return { error: "No movements found", line: lines.length };

  const wod = {
    version: 1,
    name: name || headerLine,
    type: header.type,
    timeCapSec: header.timeCapSec,
    intervalSec: header.intervalSec,
    workSec: header.workSec,
    restSec: header.restSec,
    rounds: header.rounds,
    repScheme: null,
    repStep: null,
    blocks,
  };
  if (header.type === "FOR_TIME") {
    if (repStep) return { error: "An open ladder (3-6-9-...) needs an AMRAP", line: lines.length };
    if (repScheme) { wod.repScheme = repScheme; wod.rounds = repScheme.length; }
    else if (wod.rounds == null) wod.rounds = 1;
  }
  if (header.type === "AMRAP" && repScheme) {
    wod.repScheme = repScheme;
    wod.repStep = repStep;
  }
  if (header.deathBy) {
    // start at the written reps (1 by default) and add that much every minute
    for (const b of blocks) if (b.reps === 0) b.reps = 1;
    wod.repStep = blocks[0].reps;
  }
  return { wod };
}

// ---------- JSON validation (for WODs coming from a URL) ----------

function isIntValue(v) { return typeof v === "number" && Number.isInteger(v); }
function optInt(v) { return v === undefined || v === null || isIntValue(v); }

export function validateWod(obj) {
  if (obj == null || typeof obj !== "object") return { error: "WOD must be an object" };
  if (obj.version !== 1) return { error: "Unsupported WOD version" };
  if (!TYPES.includes(obj.type)) return { error: "Unknown WOD type" };
  for (const k of ["timeCapSec", "intervalSec", "workSec", "restSec", "rounds", "repStep"]) {
    if (!optInt(obj[k])) return { error: `${k} must be an integer or null` };
  }
  if (!Array.isArray(obj.blocks) || obj.blocks.length === 0) return { error: "WOD needs at least one block" };
  const wod = {
    version: 1,
    name: typeof obj.name === "string" && obj.name.length > 0 ? obj.name : "WOD",
    type: obj.type,
    timeCapSec: obj.timeCapSec ?? null,
    intervalSec: obj.intervalSec ?? null,
    workSec: obj.workSec ?? null,
    restSec: obj.restSec ?? null,
    rounds: obj.rounds ?? null,
    repScheme: null,
    repStep: obj.repStep ?? null,
    blocks: [],
  };
  if (wod.repStep != null && wod.repStep <= 0) wod.repStep = null;
  if (obj.repScheme != null) {
    if (!Array.isArray(obj.repScheme) || obj.repScheme.length === 0 || !obj.repScheme.every((r) => isIntValue(r) && r > 0)) {
      return { error: "repScheme must be a list of positive integers" };
    }
    wod.repScheme = obj.repScheme.slice();
  }
  for (const b of obj.blocks) {
    if (b == null || typeof b.movement !== "string") return { error: "Each block needs a movement" };
    const reps = b.reps ?? 0;
    if (!isIntValue(reps) || reps < 0) return { error: "Block reps must be an integer >= 0" };
    const unit = b.unit ?? "reps";
    if (!UNITS.includes(unit)) return { error: `Unknown unit ${unit}` };
    if (!optInt(b.slot)) return { error: "Block slot must be an integer or null" };
    const load = b.load ?? null;
    if (load != null && !(Array.isArray(load) && load.length >= 1 && load.length <= 2 && load.every((x) => isIntValue(x) && x > 0))) {
      return { error: "Block load must be a list of 1 or 2 positive integers (kg)" };
    }
    const known = MOVEMENTS[b.movement];
    wod.blocks.push({
      movement: b.movement,
      name: typeof b.name === "string" && b.name.length > 0 ? b.name : known ? known.name : b.movement,
      reps,
      unit,
      slot: b.slot ?? null,
      load,
    });
  }

  switch (wod.type) {
    case "AMRAP":
      if (!(wod.timeCapSec > 0)) return { error: "AMRAP needs timeCapSec" };
      if (!wod.repScheme) wod.repStep = null;
      break;
    case "EMOM":
      if (!(wod.intervalSec > 0)) return { error: "EMOM needs intervalSec" };
      if (!(wod.rounds > 0)) {
        if (!(wod.timeCapSec > 0)) return { error: "EMOM needs rounds or timeCapSec" };
        wod.rounds = Math.floor(wod.timeCapSec / wod.intervalSec);
      }
      wod.timeCapSec = wod.rounds * wod.intervalSec;
      break;
    case "FOR_TIME":
      wod.repStep = null;
      if (wod.repScheme) wod.rounds = wod.repScheme.length;
      if (!(wod.rounds > 0)) wod.rounds = 1;
      break;
    case "TABATA":
      wod.repStep = null;
      if (!(wod.workSec > 0)) wod.workSec = 20;
      if (wod.restSec == null || wod.restSec < 0) wod.restSec = 10;
      if (!(wod.rounds > 0)) wod.rounds = 8;
      wod.intervalSec = wod.workSec + wod.restSec;
      wod.timeCapSec = wod.rounds * wod.intervalSec - wod.restSec;
      break;
  }
  // Interval WODs: blocks without slot get their own slot in order.
  if (wod.type === "EMOM" || wod.type === "TABATA") {
    let next = 0;
    for (const b of wod.blocks) {
      if (b.slot == null) b.slot = next;
      if (b.slot + 1 > next) next = b.slot + 1;
    }
  } else {
    for (const b of wod.blocks) b.slot = null;
  }
  return { wod };
}

// ---------- back to text (for the Garmin Connect settings field) ----------

function fmtMin(sec) {
  if (sec % 60 === 0) return String(sec / 60);
  const s = sec % 60;
  return `${Math.floor(sec / 60)}:${s < 10 ? "0" : ""}${s}`;
}

function fmtBlock(b) {
  const load = b.load ? ` (${b.load.join("/")}kg)` : "";
  if (b.reps === 0) return b.name + load;
  if (b.unit === "m") return `${b.reps}m ${b.name}${load}`;
  if (b.unit === "cal") return `${b.reps} cal ${b.name}${load}`;
  if (b.unit === "sec") return `${b.reps}s ${b.name}${load}`;
  return `${b.reps} ${b.name}${load}`;
}

export function wodToText(wod, sep = "\n") {
  const lines = [];
  lines.push(`# ${wod.name}`);
  switch (wod.type) {
    case "AMRAP":
      lines.push(`AMRAP ${fmtMin(wod.timeCapSec)}`);
      if (wod.repScheme) lines.push(wod.repScheme.join("-") + (wod.repStep ? "-..." : ""));
      break;
    case "EMOM": {
      if (wod.repStep) {
        lines.push("DEATH BY");
        lines.push(wod.blocks.map(fmtBlock).join(" + "));
        return lines.join(sep);
      }
      if (wod.intervalSec % 60 !== 0) {
        lines.push(`EVERY ${fmtMin(wod.intervalSec)} x ${wod.rounds}`);
        break;
      }
      const every = wod.intervalSec / 60;
      lines.push(`${every === 1 ? "EMOM" : `E${every}MOM`} x ${wod.rounds}`);
      break;
    }
    case "FOR_TIME": {
      let h = wod.rounds > 1 && !wod.repScheme ? `${wod.rounds} ROUNDS FOR TIME` : "FOR TIME";
      if (wod.timeCapSec) h += ` cap ${fmtMin(wod.timeCapSec)}`;
      lines.push(h);
      if (wod.repScheme) lines.push(wod.repScheme.join("-"));
      break;
    }
    case "TABATA": lines.push(`TABATA ${wod.rounds}x${wod.workSec}/${wod.restSec}`); break;
  }
  if (wod.type === "EMOM" || wod.type === "TABATA") {
    const slots = [...new Set(wod.blocks.map((b) => b.slot))].sort((a, b) => a - b);
    slots.forEach((s, idx) => {
      const parts = wod.blocks.filter((b) => b.slot === s).map(fmtBlock).join(" + ");
      lines.push(s === idx ? parts : `min ${s + 1}: ${parts}`);
    });
  } else {
    for (const b of wod.blocks) lines.push(fmtBlock(b));
  }
  return lines.join(sep);
}
