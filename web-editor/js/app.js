import { parseWod, wodToText } from "./wod-parser.js";
import { TimerEngine, S, E } from "./timer-engine.js";

const $ = (id) => document.getElementById(id);

const EXAMPLES = {
  amrap: "# WOD of the day\nAMRAP 12\n10 wall balls\n10 burpees\n200m run",
  emom: "EMOM 10\nodd: 12 kb swings\neven: 10 burpees",
  fortime: "FOR TIME cap 15\n21-15-9\nthrusters\npull-ups",
  tabata: "TABATA 8x20/10\nair squats",
};

const store = {
  get(k, d = "") {
    try { return localStorage.getItem("wodwrist." + k) ?? d; } catch { return d; }
  },
  set(k, v) {
    try { localStorage.setItem("wodwrist." + k, v); } catch { /* private mode */ }
  },
};

let current = null; // last valid WOD

// ---------- editor ----------

function fmt(sec) {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

function headline(w) {
  switch (w.type) {
    case "AMRAP": return `AMRAP ${fmt(w.timeCapSec)}`;
    case "EMOM": return `${w.intervalSec === 60 ? "EMOM" : `E${w.intervalSec / 60}MOM`}: ${w.rounds} intervals of ${fmt(w.intervalSec)} (${fmt(w.timeCapSec)})`;
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
  return b.reps > 0 ? `${b.reps}${unit} ${b.name}` : `${b.name} (max)`;
}

function plan(w) {
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

function render() {
  const text = $("wodText").value;
  store.set("text", text);
  const r = parseWod(text);
  const status = $("status");
  if (r.error) {
    current = null;
    status.className = "status err";
    status.textContent = r.line ? `Line ${r.line}: ${r.error}` : r.error;
    $("preview").innerHTML = "";
    $("json").textContent = "";
    return;
  }
  current = r.wod;
  const w = r.wod;
  const custom = w.blocks.filter((b) => b.movement === "custom").length;
  status.className = "status ok";
  status.textContent = custom
    ? `OK, ${custom} movement(s) not in the catalog: counted by hand on the watch`
    : "OK";
  const items = w.blocks
    .map((b) => {
      const tag = b.movement === "custom" ? '<span class="tag">custom</span>' : "";
      return `<li>${escapeHtml(blockText(b))}${tag}</li>`;
    })
    .join("");
  $("preview").innerHTML = `
    <h2>${escapeHtml(w.name)}</h2>
    <div class="headline">${escapeHtml(headline(w))}</div>
    <ol>${items}</ol>
    <div class="plan">${plan(w)}</div>`;
  $("json").textContent = JSON.stringify(w, null, 2);
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
  const blob = new Blob([JSON.stringify(current, null, 2) + "\n"], { type: "application/json" });
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
    branch: $("ghBranch").value.trim() || "main",
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
  // The Pages workflow publishes the web-editor/ folder at the site root.
  const rel = path.startsWith("web-editor/") ? path.substring("web-editor/".length) : path;
  $("watchUrl").textContent = `https://${owner.toLowerCase()}.github.io/${name}/${rel}`;
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
        message: `WOD: ${current.name}`,
        content: b64(JSON.stringify(current, null, 2) + "\n"),
        branch,
        sha,
      }),
    });
    if (!res.ok) throw new Error(`GitHub ${res.status}: ${(await res.json()).message ?? ""}`);
    btn.textContent = "Published";
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
  }
}

function resetTimer() {
  cancelAnimationFrame(raf);
  engine = current ? new TimerEngine(current, 10) : null;
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
  st.textContent = labels[engine.state];
  st.className = "t-state " + (cls[engine.state] ?? "");
  const ms = engine.clockMs(now);
  const down = engine.state === S.COUNTDOWN || engine.state === S.IDLE || engine.wod.type !== "FOR_TIME";
  const sec = down ? Math.ceil(ms / 1000) : Math.floor(ms / 1000);
  $("tClock").textContent = engine.state === S.COUNTDOWN ? String(sec) : fmt(sec);
  const total = engine.totalRounds();
  $("tRound").textContent = total
    ? `${engine.isInterval() ? "Interval" : "Round"} ${Math.min(engine.round + 1, total)} / ${total}`
    : `Rounds done: ${engine.roundsCompleted}`;
  const b = engine.currentBlock() ?? engine.currentBlocks()[0];
  $("tMove").textContent =
    engine.state === S.DONE ? engine.wod.name
      : engine.intervalDone ? "Rest until next interval"
      : b ? blockText({ ...b, reps: engine.target(b) }) : "";
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

function init() {
  $("wodText").value = store.get("text", EXAMPLES.amrap);
  $("wodText").addEventListener("input", render);
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
  $("copyJson").addEventListener("click", (e) => current && copy(JSON.stringify(current, null, 2), e.target));
  $("downloadJson").addEventListener("click", download);

  for (const [id, key, def] of [["ghRepo", "repo", "alexcartn/WODwrist"], ["ghBranch", "branch", "main"], ["ghPath", "path", "web-editor/wod/today.json"], ["ghToken", "token", ""]]) {
    $(id).value = store.get(key, def);
    $(id).addEventListener("input", () => {
      store.set(key, $(id).value.trim());
      updateWatchUrl();
    });
  }
  $("publish").addEventListener("click", publish);
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
