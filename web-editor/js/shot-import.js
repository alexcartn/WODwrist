// Screenshot import: turns the OCR text of a training app page (HWPO, gym
// apps...) into WOD text for the editor. Pure functions, tested in
// test/shot.test.js. The OCR itself (tesseract.js) runs in the browser.

import { parseHeader, parseCapLine, parseRestLine, parseMovement } from "./wod-parser.js";

// Words of app menus and buttons, French and English (accents removed).
const UI_WORDS = new Set([
  "masquer", "afficher", "les", "des", "de", "du", "details", "detail", "notes", "note", "coachs", "coach",
  "demonstrations", "demonstration", "mouvements", "mouvement", "score", "scores", "modifier", "accueil",
  "communaute", "boutique", "profil", "profi", "classement", "resultats", "enregistrer", "partager",
  "hide", "show", "coaches", "movement", "movements", "demos", "demo", "edit", "home", "community", "shop",
  "profile", "leaderboard", "results", "log", "share", "more", "v", ">", "<", "o",
]);

function plain(s) {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Menu line ("NOTES DES COACHS >", "v MASQUER LES DETAILS", bottom tab bar).
function isChrome(line) {
  const toks = plain(line).split(/\s+/).filter((t) => t.length > 0);
  if (toks.length === 0) return true;
  const ui = toks.filter((t) => UI_WORDS.has(t.replace(/[^a-z<>]/g, ""))).length;
  return ui * 2 >= toks.length && ui > 0 && !/\d/.test(line);
}

// OCR noise: no word of 3+ letters / digits holding a letter ("O [0]", "A & BA J)").
function isJunk(line) {
  if (!/[a-z]/i.test(line)) return !/\d/.test(line);
  return !line.split(/\s+/).some((t) => {
    const w = t.replace(/[^a-z0-9]/gi, "");
    return w.length >= 3 && /[a-z]/i.test(w);
  });
}

// Buttons glued at the end of a line: "Tough Set Of HSPU   MODIFIER >".
function stripTail(line) {
  return line
    .replace(/\s+(MODIFIER|MODIFY|EDIT|SWAP|REMPLACER)\s*>?\s*$/i, "")
    .replace(/\s*[>›]\s*$/, "")
    .trim();
}

// "Skill | Ring Push-Up @)" -> "Skill: Ring Push-Up"
function heading(line) {
  const parts = line.split("|").map((p) => p.trim()).filter((p) => p.length > 0);
  const clean = (p) => p.replace(/[^A-Za-z0-9)]+$/, "").replace(/\s+\S{1,2}$/, (m) => (/[a-z]{2}/i.test(m) ? m : "")).trim();
  const out = parts.map(clean).filter((p) => p.length > 0);
  if (out.length === 0) return null;
  const first = out[0];
  return out.length > 1 ? `${first[0].toUpperCase()}${first.substring(1)}: ${out.slice(1).join(" ")}` : first;
}

const isScheme = (l) => /^\d+(\s*-\s*\d+)+(\s*-?\s*(\.\.\.|…|\+))?$/.test(l);
const isHeader = (l) => {
  const h = parseHeader(l);
  return h != null && !h.error;
};

const unclosed = (s) => (s.match(/[([]/g) || []).length > (s.match(/[)\]]/g) || []).length;

// A line cut in two by the app layout: "..., complete 8/6" + "Cal Ski",
// "Carry (150/100lbs ||" + "70/45kg)".
function continues(prev, next) {
  if (unclosed(prev) && /^[^([]*[)\]]/.test(next)) return true;
  if (isHeader(prev) || isScheme(prev) || /^\d/.test(next) || isHeader(next)) return false;
  if (parseCapLine(prev) > 0 || parseRestLine(prev)) return false;
  if (parseCapLine(next) > 0 || parseRestLine(next)) return false;
  return /(\d+\/\d+|\d|,|\bof|\band|\+|complete|\()$/i.test(prev) || /^[a-z(]/.test(next);
}

// A section title without "|": "Metcon", "Bonus", "Part 1".
function titleLike(line) {
  if (line == null || isHeader(line) || /^\d/.test(line) || /[@([:]/.test(line)) return false;
  if (parseCapLine(line) > 0 || parseRestLine(line)) return false;
  if (line.split(" ").length > 4) return false;
  if (/^(part|partie|block|bloc|section)\s+\w{1,2}$/i.test(line)) return true;
  const b = parseMovement(line);
  return b.movement === "custom" && b.reps === 0;
}

// OCR text -> { text, wods, cut }: WOD text with parts separated by "---",
// cut = parts dropped because the screenshot ends before their movements.
export function cleanOcr(raw) {
  const lines = [];
  for (let line of raw.replace(/\r/g, "").split("\n")) {
    line = line.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[–—]/g, "-").replace(/\s+/g, " ").trim();
    // checkbox circle read as a letter: "Metcon O"
    line = line.replace(/\s+[O0o]$/, "").replace(/(\d)\s?Ibs\b/g, "$1lbs");
    if (line.length === 0) continue;
    // the athlete's max shown by the app: "Deadlift 1RM 200 kg"
    if (/\b[1I]RM\b/.test(line)) continue;
    if (line.includes("|") && !line.includes("||") && !unclosed(line)) {
      const h = heading(line);
      if (h) lines.push({ heading: h });
      continue;
    }
    line = stripTail(line);
    if (line.length === 0 || isChrome(line) || isJunk(line)) continue;
    const last = lines[lines.length - 1];
    if (last && !last.heading && continues(last.text, line)) {
      last.text += " " + line;
      continue;
    }
    lines.push({ text: line });
  }

  // titles without "|": a short unknown line right before a header
  for (let i = 0; i < lines.length; i++) {
    const t = (k) => (k < lines.length && !lines[k].heading ? lines[k].text : null);
    if (titleLike(t(i)) && (isHeader(t(i + 1) ?? "") || (titleLike(t(i + 1)) && isHeader(t(i + 2) ?? "")))) {
      lines[i] = { heading: t(i) };
    }
  }
  // "Bonus" + "Part 1" -> "Bonus: Part 1"
  for (let i = lines.length - 1; i > 0; i--) {
    if (lines[i].heading && lines[i - 1].heading) {
      lines[i - 1] = { heading: `${lines[i - 1].heading}: ${lines[i].heading}` };
      lines.splice(i, 1);
    }
  }

  // one WOD per heading, or per new header line
  const wods = [];
  let cur = null;
  const open = (name) => {
    // "Rest 2:00" closing a part is the rest before the next one
    if (cur && cur.lines.length > 1) {
      const r = parseRestLine(cur.lines[cur.lines.length - 1]);
      if (r && !r.betweenSets) {
        cur.lines.pop();
        cur.restAfter = cur.lines.length > 0 ? r.sec : 0;
      }
    }
    cur = { name, lines: [], hasHeader: false, restAfter: 0 };
    wods.push(cur);
  };
  for (const l of lines) {
    if (l.heading) {
      open(l.heading);
      continue;
    }
    if (isHeader(l.text)) {
      if (!cur || cur.hasHeader) open(null);
      cur.hasHeader = true;
    } else if (!cur) {
      continue; // text before the first WOD (page title, date)
    }
    cur.lines.push(l.text);
  }
  const withHeader = wods.filter((w) => w.hasHeader);
  const kept = withHeader.filter((w) => w.lines.length > 1);
  const clock = (sec) => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`;
  const text = kept
    .map((w) => {
      let name = w.name;
      if (w.restAfter > 0) name = `${name ?? w.lines[0]} (then rest ${clock(w.restAfter)})`;
      return (name ? [`# ${name}`, ...w.lines] : w.lines).join("\n");
    })
    .join("\n---\n");
  return { text, wods: kept.length, cut: withHeader.length - kept.length };
}

// ---------- several screenshots of the same day ----------

function splitPart(p) {
  const lines = p.split("\n").filter((l) => l.trim().length > 0);
  const name = lines.length > 0 && lines[0].startsWith("#") ? lines.shift() : null;
  return { name, lines };
}

// Same part seen twice (screenshots overlap): same header and first movement,
// with or without its title.
function partKey(lines) {
  return lines.slice(0, 2).join("|").toLowerCase().replace(/\s+/g, " ");
}

// Adds the parts of `text` after the parts of `base` (both "---" separated).
// A part already there is kept once: the longer version, with its title.
export function mergeParts(base, text) {
  const out = (base.trim().length > 0 ? base.split("\n---\n") : []).map(splitPart);
  for (const p of text.split("\n---\n").map(splitPart)) {
    if (p.lines.length === 0) continue;
    const same = out.find((o) => partKey(o.lines) === partKey(p.lines));
    if (!same) {
      out.push(p);
      continue;
    }
    if (p.lines.length > same.lines.length) same.lines = p.lines;
    same.name = same.name ?? p.name;
  }
  return out.map((p) => (p.name ? [p.name, ...p.lines] : p.lines).join("\n")).join("\n---\n");
}
