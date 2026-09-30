// Live watch preview in the editor: draws the run screen of the watch app
// (same layout fractions and colors as watch-app/source/ui/RunView.mc).

const C = { work: "#00d23c", rest: "#1e8cff", score: "#ffd400", warn: "#ff8a00", text: "#fff", muted: "#aaa", dim: "#444" };

function fmt(sec) {
  return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`;
}

function text(d, x, y, size, color, s, bold = false, num = false) {
  d.fillStyle = color;
  d.font = `${bold || num ? 700 : 500} ${size}px ${num ? '"Roboto Condensed", "Arial Narrow", Arial' : "Roboto, Arial"}, sans-serif`;
  d.textAlign = "center";
  d.textBaseline = "middle";
  d.fillText(s, x, y);
}

function fitText(d, s, maxW) {
  if (d.measureText(s).width <= maxW) return s;
  while (s.length > 1 && d.measureText(s + "…").width > maxW) s = s.slice(0, -1);
  return s.trimEnd() + "…";
}

// Draws `wod` at the start of the work phase, with the ring a quarter done.
export function drawWatch(canvas, wod) {
  const d = canvas.getContext("2d");
  const w = canvas.width, h = canvas.height, cx = w / 2, k = w / 416;
  d.clearRect(0, 0, w, h);
  d.fillStyle = "#000";
  d.beginPath();
  d.arc(cx, h / 2, w / 2, 0, Math.PI * 2);
  d.fill();
  if (!wod) {
    text(d, cx, h / 2, 30 * k, C.muted, "No valid WOD");
    return;
  }
  const b = wod.blocks[0];
  let clock = "0:00", round = "Rounds 0", total = null, done = 0.25;
  switch (wod.type) {
    case "AMRAP": clock = fmt(Math.round(wod.timeCapSec * 0.75)); total = wod.timeCapSec; break;
    case "FOR_TIME":
      clock = wod.timeCapSec ? fmt(Math.round(wod.timeCapSec * 0.25)) : "1:05";
      round = `Round 1/${wod.rounds}`;
      total = wod.timeCapSec;
      break;
    case "EMOM":
      clock = fmt(Math.round(wod.intervalSec * 0.75));
      round = wod.repStep ? "Rounds 0" : `Int 1/${wod.rounds}`;
      total = wod.intervalSec;
      break;
    case "TABATA": clock = fmt(Math.round(wod.workSec * 0.75)); round = `Int 1/${wod.rounds}`; total = wod.workSec; break;
  }
  // ring
  const rw = 10 * k, r = w / 2 - rw / 2 - 1;
  d.lineWidth = rw;
  d.strokeStyle = C.dim;
  d.beginPath();
  d.arc(cx, h / 2, r, 0, Math.PI * 2);
  d.stroke();
  if (total) {
    d.strokeStyle = C.work;
    d.beginPath();
    d.arc(cx, h / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * done);
    d.stroke();
  }
  text(d, cx, h * 0.12, 30 * k, C.work, "WORK");
  text(d, cx, h * 0.22, 30 * k, C.muted, round);
  text(d, cx, h * 0.41, 120 * k, C.text, clock, false, true);
  let target = b.reps;
  if (!target && wod.repScheme) target = wod.repScheme[0];
  d.font = `500 ${34 * k}px Roboto, Arial, sans-serif`;
  text(d, cx, h * 0.62, 34 * k, C.text, fitText(d, b.name, w * 0.7));
  const unit = { m: " m", cal: " cal", sec: " s", reps: "" }[b.unit];
  const reps = b.unit === "reps" ? (target ? `0/${target}` : "0") : `${b.reps}${unit}`;
  text(d, cx, h * 0.75, 40 * k, C.score, reps, true);
  text(d, cx, h * 0.87, 26 * k, C.muted, "Reps 0  HR 142");
}
