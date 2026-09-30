// Screenshot import: turns the OCR text of a training app page (HWPO, gym
// apps...) into WOD text for the editor. Pure functions, tested in
// test/shot.test.js. The OCR itself (tesseract.js) runs in the browser.

import { parseHeader, parseCapLine, parseRestLine } from "./wod-parser.js";

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
    .replace(/\s+(MODIFIER|EDIT|SWAP|REMPLACER)\s*>?\s*$/i, "")
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

// A line cut in two by the app layout: "..., complete 8/6" + "Cal Ski".
function continues(prev, next) {
  if (isHeader(prev) || isScheme(prev) || /^\d/.test(next) || isHeader(next)) return false;
  if (parseCapLine(next) > 0 || parseRestLine(next)) return false;
  return /(\d+\/\d+|\d|,|\bof|\band|\+|complete|\()$/i.test(prev) || /^[a-z(]/.test(next);
}

// OCR text -> { text, wods }: WOD text with parts separated by "---".
export function cleanOcr(raw) {
  const lines = [];
  for (let line of raw.replace(/\r/g, "").split("\n")) {
    line = line.replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[–—]/g, "-").replace(/\s+/g, " ").trim();
    if (line.length === 0) continue;
    if (line.includes("|")) {
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

  // one WOD per heading, or per new header line
  const wods = [];
  let cur = null;
  const open = (name) => {
    cur = { name, lines: [], hasHeader: false };
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
  const kept = wods.filter((w) => w.hasHeader);
  const text = kept
    .map((w) => (w.name ? [`# ${w.name}`, ...w.lines] : w.lines).join("\n"))
    .join("\n---\n");
  return { text, wods: kept.length };
}
