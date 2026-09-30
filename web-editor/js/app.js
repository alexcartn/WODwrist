import { parseWod, wodToText } from "./wod-parser.js";
import { TimerEngine, S, E } from "./timer-engine.js";
import { splitParts } from "./coach.js";
import { drawWatch } from "./watch-preview.js";
import { highlight, suggest, applySuggestion } from "./editor-assist.js";
import { BENCHMARKS } from "./benchmarks.js";
import { cleanOcr } from "./shot-import.js";

const $ = (id) => document.getElementById(id);

const EXAMPLES = {
  amrap: "# WOD of the day\nAMRAP 12\n10 wall balls\n10 burpees\n200m run",
  emom: "EMOM 10\nodd: 12 kb swings\neven: 10 burpees",
  fortime: "FOR TIME cap 15\n21-15-9\nthrusters\npull-ups",
  tabata: "TABATA 8x20/10\nair squats",
  deathby: "DEATH BY burpees",
  ladder: "AMRAP 10\n3-6-9-...\nthrusters\nchest to bar",
  class: "# Warm-up\nEMOM 6\nodd: 10 air squats\neven: 10 push-ups\n---\n# Strength\nE2MOM 10\n3 power cleans\n---\n# Metcon\nAMRAP 12\n10 wall balls\n10 burpees\n200m run",
};

const store = {
  get(k, d = "") {
    try { return localStorage.getItem("wodwrist." + k) ?? d; } catch { return d; }
  },
  set(k, v) {
    try { localStorage.setItem("wodwrist." + k, v); } catch { /* private mode */ }
  },
};

let parts = [];      // valid WODs, one per part of the class plan
let current = null;  // first part (settings text, default timer)

// What gets published: one WOD, or { wods: [...] } for a class plan.
function payload() {
  return parts.length > 1 ? { version: 1, wods: parts } : parts[0];
}

// ---------- editor ----------

function fmt(sec) {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function headline(w) {
  switch (w.type) {
    case "AMRAP":
      return (w.sets > 1 ? `${w.sets} x ` : "") + `AMRAP ${fmt(w.timeCapSec)}`
        + (w.sets > 1 ? `, rest ${fmt(w.setRestSec)} between sets` : "")
        + (w.repScheme ? `, ladder ${w.repScheme.join("-")}${w.repStep ? "-..." : ""}` : "");
    case "EMOM":
      if (w.repStep) return `Death by: +${w.repStep} rep(s) every minute until you miss`;
      if (w.intervalSec % 60) return `Every ${fmt(w.intervalSec)} x ${w.rounds} (${fmt(w.timeCapSec)})`;
      return `${w.intervalSec === 60 ? "EMOM" : `E${w.intervalSec / 60}MOM`}: ${w.rounds} intervals of ${fmt(w.intervalSec)} (${fmt(w.timeCapSec)})`;
    case "FOR_TIME": {
      let h = "For time";
      if (w.repScheme) h += " " + w.repScheme.join("-");
      else if (w.rounds > 1) h = `${w.rounds} rounds for time`;
      if (w.timeCapSec) h += `, cap ${fmt(w.timeCapSec)}`;
      return h;
    }
    case "TABATA": return `Tabata ${w.rounds} x ${w.workSec}s/${w.restSec}s (${fmt(w.timeCapSec)})`;
  }
  return w.type;
}

function blockText(b) {
  const unit = { m: " m", cal: " cal", sec: " s", reps: "" }[b.unit];
  const load = b.load ? ` @ ${b.load.join("/")} kg` : "";
  const n = b.repsAlt != null ? `${b.reps}/${b.repsAlt}` : `${b.reps}`;
  return (b.reps > 0 ? `${n}${unit} ${b.name}` : `${b.name} (max)`) + load;
}

function plan(w) {
  if (w.type === "EMOM" && w.repStep) {
    return [0, 1, 2].map((i) => `${fmt(i * 60)}: ${w.blocks.map((b) => `${b.reps + i * w.repStep} ${b.name}`).join(" + ")}`).join("<br>") + "<br>…";
  }
  if (w.type !== "EMOM" && w.type !== "TABATA") return "";
  const slots = [...new Set(w.blocks.map((b) => b.slot))].sort((a, b) => a - b);
  const label = w.type === "EMOM" ? "" : "Round ";
  const lines = [];
  for (let i = 0; i < Math.min(w.rounds, slots.length * 2); i++) {
    const s = slots[i % slots.length];
    const t = w.type === "EMOM" ? `${fmt(i * w.intervalSec)}` : `${i + 1}`;
    lines.push(`${label}${t}: ${w.blocks.filter((b) => b.slot === s).map(blockText).join(" + ")}`);
  }
  if (w.rounds > lines.length) lines.push("…");
  return lines.join("<br>");
}

function escapeHtml(s) {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

function partHtml(w) {
  const items = w.blocks
    .map((b) => {
      const tag = b.movement === "custom" ? '<span class="tag">custom</span>' : "";
      return `<li>${escapeHtml(blockText(b))}${tag}</li>`;
    })
    .join("");
  return `
    <h2>${escapeHtml(w.name)}</h2>
    <div class="headline">${escapeHtml(headline(w))}</div>
    <ol>${items}</ol>
    ${w.task ? `<div class="task">Every ${w.task.everySec === 60 ? "minute" : fmt(w.task.everySec)}${w.task.at0 ? " from 0:00" : ""}: ${escapeHtml(w.task.blocks.map(blockText).join(" + "))}</div>` : ""}
    <div class="plan">${plan(w)}</div>`;
}

// Textarea line (0-based) of the n-th non-empty WOD line (1-based) of part p.
function errorLineIndex(text, p, n) {
  const lines = text.split("\n");
  let part = 0;
  let count = 0;
  let seenContent = false;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() === "---") {
      if (seenContent) part++;
      continue;
    }
    if (part !== p) {
      if (lines[i].trim()) seenContent = true;
      continue;
    }
    seenContent = true;
    const segs = lines[i].split(/[;|]/).filter((x) => x.trim()).length;
    if (segs === 0) continue;
    count += segs;
    if (count >= n) return i;
  }
  return -1;
}

function paintEditor(errLine = -1) {
  const ta = $("wodText");
  $("hl").innerHTML = highlight(ta.value, errLine) + "\n";
  ta.style.height = "auto";
  ta.style.height = Math.max(260, ta.scrollHeight + 2) + "px";
}

function render() {
  const text = $("wodText").value;
  store.set("text", text);
  paintEditor();
  const status = $("status");
  const texts = splitParts(text);
  const parsed = [];
  for (let i = 0; i < texts.length; i++) {
    const r = parseWod(texts[i]);
    if (r.error) {
      parts = [];
      current = null;
      status.className = "status err";
      const where = texts.length > 1 ? `Part ${i + 1}, ` : "";
      status.textContent = r.line ? `${where}line ${r.line}: ${r.error}` : `${where}${r.error}`;
      paintEditor(r.line ? errorLineIndex(text, i, r.line) : -1);
      $("preview").innerHTML = "";
      $("json").textContent = "";
      drawWatch($("watch"), null);
      return;
    }
    parsed.push(r.wod);
  }
  if (parsed.length === 0) {
    parts = [];
    current = null;
    status.className = "status err";
    status.textContent = "Empty WOD";
    $("preview").innerHTML = "";
    $("json").textContent = "";
    return;
  }
  parts = parsed;
  current = parts[0];
  const custom = parts.flatMap((w) => w.blocks).filter((b) => b.movement === "custom").length;
  status.className = "status ok";
  let msg = parts.length > 1 ? `OK, class plan with ${parts.length} parts` : "OK";
  if (custom) msg += `, ${custom} movement(s) not in the catalog: counted by hand on the watch`;
  status.textContent = msg;
  $("preview").innerHTML = parts.map(partHtml).join('<hr class="part">');
  drawWatch($("watch"), current);
  $("json").textContent = JSON.stringify(payload(), null, 2);
  $("copySettings").disabled = parts.length > 1;
  $("copySettings").title = parts.length > 1
    ? "The watch settings field takes one WOD: publish the plan to the coach URL instead"
    : "Paste this into Garmin Connect > WODwrist > Settings > WOD text";
  const sel = $("tPart");
  sel.innerHTML = parts.map((w, i) => `<option value="${i}">${i + 1}. ${escapeHtml(w.name)}</option>`).join("");
  sel.hidden = parts.length < 2;
  resetTimer();
}

async function copy(text, btn) {
  try {
    await navigator.clipboard.writeText(text);
    const old = btn.textContent;
    btn.textContent = "Copied";
    setTimeout(() => (btn.textContent = old), 1200);
  } catch {
    prompt("Copy:", text);
  }
}

function download() {
  if (!current) return;
  const blob = new Blob([JSON.stringify(payload(), null, 2) + "\n"], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "today.json";
  a.click();
  URL.revokeObjectURL(a.href);
}

// ---------- GitHub publish ----------

function ghSettings() {
  return {
    repo: $("ghRepo").value.trim(),
    branch: $("ghBranch").value.trim() || "master",
    path: $("ghPath").value.trim() || "web-editor/wod/today.json",
    token: $("ghToken").value.trim(),
  };
}

function updateWatchUrl() {
  const { repo, path } = ghSettings();
  const [owner, name] = repo.split("/");
  if (!owner || !name) {
    $("watchUrl").textContent = "(set the repo)";
    return;
  }
  // Pages serves the master branch as is: the file keeps its repo path.
  $("watchUrl").textContent = `https://${owner.toLowerCase()}.github.io/${name}/${path}`;
}

function showPublished() {
  const t = store.get("published", "");
  $("published").textContent = t ? `Last published ${new Date(t).toLocaleString()}` : "Not published from this browser yet";
}

function b64(str) {
  return btoa(String.fromCharCode(...new TextEncoder().encode(str)));
}

async function publish() {
  const btn = $("publish");
  if (!current) return alert("Fix the WOD first.");
  const { repo, branch, path, token } = ghSettings();
  if (!repo || !token) return alert("Repo and token are needed.");
  btn.disabled = true;
  btn.textContent = "Publishing…";
  const api = `https://api.github.com/repos/${repo}/contents/${path}`;
  const headers = { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json" };
  try {
    let sha;
    const head = await fetch(`${api}?ref=${encodeURIComponent(branch)}`, { headers });
    if (head.ok) sha = (await head.json()).sha;
    else if (head.status !== 404) throw new Error(`GitHub ${head.status}`);
    const res = await fetch(api, {
      method: "PUT",
      headers,
      body: JSON.stringify({
        message: `WOD: ${parts.map((w) => w.name).join(" / ")}`,
        content: b64(JSON.stringify(payload(), null, 2) + "\n"),
        branch,
        sha,
      }),
    });
    if (!res.ok) throw new Error(`GitHub ${res.status}: ${(await res.json()).message ?? ""}`);
    btn.textContent = "Published";
    store.set("published", new Date().toISOString());
    showPublished();
  } catch (e) {
    alert(`Publish failed: ${e.message}`);
    btn.textContent = "Publish WOD";
  } finally {
    btn.disabled = false;
    setTimeout(() => (btn.textContent = "Publish WOD"), 2500);
  }
}

// ---------- class timer ----------

let engine = null;
let raf = 0;
let audio = null;

function beep(freq = 880, ms = 120) {
  try {
    audio ??= new AudioContext();
    const o = audio.createOscillator();
    const g = audio.createGain();
    o.frequency.value = freq;
    g.gain.value = 0.2;
    o.connect(g).connect(audio.destination);
    o.start();
    o.stop(audio.currentTime + ms / 1000);
  } catch { /* no audio */ }
}

function onEvents(ev) {
  for (const [code, arg] of ev) {
    if (code === E.WARN) beep(660, 120);
    else if (code === E.START || code === E.LAP) beep(1000, 400);
    else if (code === E.REST) beep(440, 300);
    else if (code === E.DONE) beep(1200, 900);
    else if (code === E.ROUND) beep(880, 200);
    else if (code === E.SET) beep(1000, 400);
    else if (code === E.TASK) { beep(880, 250); setTimeout(() => beep(880, 250), 350); }
  }
}

function resetTimer() {
  cancelAnimationFrame(raf);
  const w = parts[Number($("tPart").value) || 0] ?? current;
  engine = w ? new TimerEngine(w, 10) : null;
  $("tStart").textContent = "Start";
  drawTimer();
}

function drawTimer() {
  const st = $("tState");
  if (!engine) {
    st.textContent = "No valid WOD";
    st.className = "t-state";
    $("tClock").textContent = "0:00";
    $("tRound").textContent = "";
    $("tMove").textContent = "";
    return;
  }
  const now = performance.now();
  onEvents(engine.tick(now));
  const labels = { [S.IDLE]: "READY", [S.COUNTDOWN]: "GET READY", [S.WORK]: "WORK", [S.REST]: "REST", [S.PAUSED]: "PAUSED", [S.DONE]: "DONE" };
  const cls = { [S.COUNTDOWN]: "countdown", [S.WORK]: "work", [S.REST]: "rest" };
  st.textContent = engine.taskActive && engine.state === S.WORK ? "EVERY-MINUTE TASK" : labels[engine.state];
  st.className = "t-state " + (cls[engine.state] ?? "");
  $("timer").dataset.state = engine.intervalDone ? "rest" : (cls[engine.state] ?? "idle");
  const ms = engine.clockMs(now);
  const down = engine.state === S.COUNTDOWN || engine.state === S.IDLE || engine.wod.type !== "FOR_TIME";
  const sec = down ? Math.ceil(ms / 1000) : Math.floor(ms / 1000);
  $("tClock").textContent = engine.state === S.COUNTDOWN ? String(sec) : fmt(sec);
  const total = engine.totalRounds();
  $("tRound").textContent = (engine.sets > 1 ? `Set ${engine.set + 1} / ${engine.sets}  ` : "") + (total
    ? `${engine.isInterval() ? "Interval" : "Round"} ${Math.min(engine.round + 1, total)} / ${total}`
    : `Rounds done: ${engine.roundsCompleted}`);
  const b = engine.currentBlock() ?? engine.currentBlocks()[0];
  $("tMove").textContent =
    engine.state === S.DONE ? engine.wod.name
      : engine.intervalDone ? "Rest until next interval"
      : engine.state === S.REST && !engine.isInterval() ? `Next: set ${engine.set + 2} / ${engine.sets}`
      : b ? blockText({ ...b, reps: engine.target(b) }) : "";
  // what comes next, readable from across the room
  let next = "";
  if (engine.state !== S.DONE) {
    if (engine.isInterval()) {
      const nb = engine.nextBlocks();
      if (nb.length) next = "Next: " + nb.map((x) => blockText({ ...x, reps: x.reps })).join(" + ");
    } else {
      const bl = engine.currentBlocks();
      const nx = bl[engine.blockIdx + 1] ?? (engine.wod.type === "AMRAP" ? bl[0] : null);
      if (nx && bl.length > 1) next = "Next: " + nx.name;
    }
  }
  $("tNextMove").textContent = next;
  if (engine.state !== S.DONE && engine.state !== S.IDLE) raf = requestAnimationFrame(drawTimer);
}

function toggleTimer() {
  if (!engine) return;
  const now = performance.now();
  if (engine.state === S.IDLE) {
    onEvents(engine.start(now));
    $("tStart").textContent = "Pause";
  } else if (engine.state === S.PAUSED) {
    engine.resume(now);
    $("tStart").textContent = "Pause";
  } else if (engine.state !== S.DONE) {
    engine.pause(now);
    $("tStart").textContent = "Resume";
  }
  cancelAnimationFrame(raf);
  drawTimer();
}

// ---------- wiring ----------

// ---------- movement suggestions ----------

let currentSuggestions = [];

function lineBeforeCursor() {
  const ta = $("wodText");
  const pos = ta.selectionStart;
  const start = ta.value.lastIndexOf("\n", pos - 1) + 1;
  const end = ta.value.indexOf("\n", pos);
  const lineEnd = end < 0 ? ta.value.length : end;
  // only at the end of the line (typing a new movement)
  if (ta.value.substring(pos, lineEnd).trim() !== "") return null;
  return { start, pos, before: ta.value.substring(start, pos) };
}

function updateSuggestions() {
  const box = $("suggest");
  const at = lineBeforeCursor();
  currentSuggestions = at ? suggest(at.before) : [];
  box.hidden = currentSuggestions.length === 0;
  box.innerHTML = currentSuggestions.length
    ? currentSuggestions.map((s, i) => `<button data-i="${i}">${escapeHtml(s.name)}</button>`).join("") + " <kbd>Tab</kbd>"
    : "";
  box.querySelectorAll("button").forEach((b) => b.addEventListener("click", () => acceptSuggestion(currentSuggestions[+b.dataset.i])));
}

function acceptSuggestion(sug) {
  const ta = $("wodText");
  const at = lineBeforeCursor();
  if (!at || !sug) return;
  const replaced = applySuggestion(at.before, sug.insert);
  ta.value = ta.value.substring(0, at.start) + replaced + ta.value.substring(at.pos);
  const cur = at.start + replaced.length;
  ta.setSelectionRange(cur, cur);
  ta.focus();
  render();
  updateSuggestions();
}

// ---------- theme, QR ----------

function applyTheme(t) {
  document.documentElement.dataset.theme = t;
  store.set("theme", t);
}

function toggleQr() {
  const box = $("qrBox");
  if (!box.hidden) {
    box.hidden = true;
    return;
  }
  const url = $("watchUrl").textContent;
  if (typeof window.qrcode !== "function") {
    box.textContent = "QR library not loaded (offline?)";
  } else {
    const q = window.qrcode(0, "M");
    q.addData(url);
    q.make();
    box.innerHTML = `<img alt="QR code of the WOD URL" src="${q.createDataURL(6, 2)}"><p class="small">Athletes scan it to get the URL for the watch settings.</p>`;
  }
  box.hidden = false;
}

// ---------- screenshot import (OCR in the browser, image never uploaded) ----------

const TESSERACT = "https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js";
let tesseractLoading = null;

function loadTesseract() {
  if (window.Tesseract) return Promise.resolve(window.Tesseract);
  tesseractLoading ??= new Promise((ok, ko) => {
    const s = document.createElement("script");
    s.src = TESSERACT;
    s.onload = () => ok(window.Tesseract);
    s.onerror = () => {
      tesseractLoading = null;
      ko(new Error("Could not load the text reader (offline?)"));
    };
    document.head.appendChild(s);
  });
  return tesseractLoading;
}

async function importShot(file) {
  const st = $("shotStatus");
  const undo = $("shotUndo");
  undo.hidden = true;
  $("shotBtn").disabled = true;
  try {
    st.textContent = "Loading the text reader…";
    const T = await loadTesseract();
    const r = await T.recognize(file, "eng", {
      logger: (m) => {
        if (m.status === "recognizing text") st.textContent = `Reading the screenshot… ${Math.round(m.progress * 100)}%`;
      },
    });
    const out = cleanOcr(r.data.text);
    if (!out.wods) {
      st.textContent = "No WOD found in this image. Try a sharper screenshot, or copy the text with Live Text / Google Lens.";
      return;
    }
    const before = $("wodText").value;
    $("wodText").value = out.text;
    render();
    st.textContent = out.wods === 1 ? "1 WOD imported: check it below." : `${out.wods} WODs imported as a class plan: check them below.`;
    undo.hidden = false;
    undo.onclick = () => {
      $("wodText").value = before;
      render();
      undo.hidden = true;
      st.textContent = "";
    };
  } catch (e) {
    st.textContent = e.message;
  } finally {
    $("shotBtn").disabled = false;
  }
}

function init() {
  $("wodText").value = store.get("text", EXAMPLES.amrap);
  $("wodText").addEventListener("input", () => {
    render();
    updateSuggestions();
  });
  $("wodText").addEventListener("scroll", () => ($("hl").scrollTop = $("wodText").scrollTop));
  $("wodText").addEventListener("keydown", (e) => {
    if (e.key === "Tab" && currentSuggestions.length) {
      e.preventDefault();
      acceptSuggestion(currentSuggestions[0]);
    }
  });
  $("wodText").addEventListener("click", updateSuggestions);
  for (const [name, text] of BENCHMARKS) {
    const o = document.createElement("option");
    o.value = name;
    o.textContent = name;
    $("benchmarks").appendChild(o);
  }
  $("benchmarks").addEventListener("change", (e) => {
    const b = BENCHMARKS.find(([n]) => n === e.target.value);
    if (b) {
      $("wodText").value = b[1];
      render();
    }
    e.target.value = "";
  });
  applyTheme(store.get("theme", "dark"));
  $("themeBtn").addEventListener("click", () => applyTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark"));
  $("qrBtn").addEventListener("click", toggleQr);
  $("shotBtn").addEventListener("click", () => $("shotFile").click());
  $("shotFile").addEventListener("change", (e) => {
    if (e.target.files[0]) importShot(e.target.files[0]);
    e.target.value = "";
  });
  $("wodText").addEventListener("paste", (e) => {
    const item = [...(e.clipboardData?.items ?? [])].find((i) => i.type.startsWith("image/"));
    if (!item) return;
    e.preventDefault();
    importShot(item.getAsFile());
  });
  document.querySelectorAll("[data-example]").forEach((b) =>
    b.addEventListener("click", () => {
      $("wodText").value = EXAMPLES[b.dataset.example];
      render();
    }),
  );
  document.querySelectorAll(".tab").forEach((t) =>
    t.addEventListener("click", () => {
      document.querySelectorAll(".tab").forEach((x) => x.classList.toggle("active", x === t));
      document.querySelectorAll(".panel").forEach((p) => p.classList.toggle("active", p.id === t.dataset.tab));
    }),
  );
  $("copySettings").addEventListener("click", (e) => current && copy(wodToText(current, "; "), e.target));
  $("copyJson").addEventListener("click", (e) => current && copy(JSON.stringify(payload(), null, 2), e.target));
  $("tPart").addEventListener("change", resetTimer);
  $("downloadJson").addEventListener("click", download);

  for (const [id, key, def] of [["ghRepo", "repo", "alexcartn/WODwrist"], ["ghBranch", "branch", "master"], ["ghPath", "path", "web-editor/wod/today.json"], ["ghToken", "token", ""]]) {
    $(id).value = store.get(key, def);
    $(id).addEventListener("input", () => {
      store.set(key, $(id).value.trim());
      updateWatchUrl();
    });
  }
  $("publish").addEventListener("click", publish);
  $("copyUrl").addEventListener("click", (e) => copy($("watchUrl").textContent, e.target));
  showPublished();
  updateWatchUrl();

  $("tStart").addEventListener("click", toggleTimer);
  $("tReset").addEventListener("click", resetTimer);
  $("tNext").addEventListener("click", () => engine && (onEvents(engine.next(performance.now())), drawTimer()));
  $("tFull").addEventListener("click", () => $("timer").requestFullscreen?.());
  document.addEventListener("keydown", (e) => {
    if (e.code === "Space" && $("timer").classList.contains("active")) {
      e.preventDefault();
      toggleTimer();
    }
  });
  render();
}

init();
