// Quick timer: a WOD without movements, set up on the watch in a few taps.
// Reference for watch-app/source/model/QuickTimer.mc (keep in sync).
//
// One pseudo block stands for "a round": BACK (+1) closes the round (AMRAP,
// For time) or marks the interval done (EMOM). Tabata counts reps.

export const QT_TYPES = ["AMRAP", "FOR_TIME", "EMOM", "TABATA"];

// Tap on a menu row = next value (wraps). Lists stay short on purpose.
export const QT_CHOICES = {
  amrapMin: [5, 7, 8, 10, 12, 14, 15, 16, 18, 20, 25, 30, 35, 40, 45, 60],
  ftRounds: [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20], // 0 = stopwatch
  ftCapMin: [0, 5, 8, 10, 12, 15, 20, 25, 30, 40, 60],    // 0 = no cap
  emomEverySec: [60, 90, 120, 150, 180, 240, 300],
  emomRounds: [5, 6, 8, 10, 12, 14, 15, 16, 18, 20, 24, 30],
  tabataWorkRest: [[20, 10], [30, 15], [40, 20], [45, 15], [30, 30], [60, 30]],
  tabataRounds: [4, 6, 8, 10, 12, 16, 20],
};

// Indexes into QT_CHOICES (that is what the watch stores).
export const QT_DEFAULTS = {
  type: 0,
  amrapMin: 9,      // 20 min
  ftRounds: 0,      // stopwatch
  ftCapMin: 0,
  emomEverySec: 0,  // 1:00
  emomRounds: 3,    // 10
  tabataWorkRest: 0,
  tabataRounds: 2,  // 8
};

// Rows of the menu for a type (the type row is always first).
export function qtRows(type) {
  switch (QT_TYPES[type]) {
    case "AMRAP": return ["amrapMin"];
    case "FOR_TIME": return ["ftRounds", "ftCapMin"];
    case "EMOM": return ["emomEverySec", "emomRounds"];
    default: return ["tabataWorkRest", "tabataRounds"];
  }
}

export function qtCycle(cfg, key) {
  const n = key === "type" ? QT_TYPES.length : QT_CHOICES[key].length;
  return { ...cfg, [key]: ((cfg[key] ?? 0) + 1) % n };
}

function pick(cfg, key) {
  const list = QT_CHOICES[key];
  const i = cfg[key] ?? QT_DEFAULTS[key];
  return list[i >= 0 && i < list.length ? i : QT_DEFAULTS[key]];
}

function clock(sec) {
  return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`;
}

// Sub-label of a row: "20 min", "Chrono", "No cap", "1:30", "8 x 20/10"...
export function qtLabel(cfg, key) {
  const v = pick(cfg, key);
  switch (key) {
    case "amrapMin": case "ftCapMin":
      return v === 0 ? "No cap" : `${v} min`;
    case "ftRounds": return v === 0 ? "Chrono" : `${v} rounds`;
    case "emomEverySec": return clock(v);
    case "emomRounds": return `x ${v}`;
    case "tabataWorkRest": return `${v[0]}/${v[1]}`;
    default: return `${v} rounds`;
  }
}

// Same WOD structure as the parser output, plus quick: true.
export function quickWod(cfg) {
  const type = QT_TYPES[cfg.type ?? 0] || "AMRAP";
  const round = { movement: "custom", name: "Round", reps: 1, unit: "reps", slot: null, load: null };
  const wod = {
    version: 1, name: "", type, quick: true,
    timeCapSec: null, intervalSec: null, workSec: null, restSec: null, rounds: null,
    repScheme: null, repStep: null, blocks: [round],
  };
  if (type === "AMRAP") {
    const m = pick(cfg, "amrapMin");
    wod.name = `AMRAP ${m}`;
    wod.timeCapSec = m * 60;
  } else if (type === "FOR_TIME") {
    const r = pick(cfg, "ftRounds");
    const cap = pick(cfg, "ftCapMin");
    wod.rounds = r;
    wod.name = r === 0 ? "Chrono" : `${r} RFT`;
    if (cap > 0) {
      wod.timeCapSec = cap * 60;
      wod.name += ` cap ${cap}`;
    }
  } else if (type === "EMOM") {
    const every = pick(cfg, "emomEverySec");
    const r = pick(cfg, "emomRounds");
    wod.intervalSec = every;
    wod.rounds = r;
    wod.timeCapSec = every * r;
    round.slot = 0;
    if (every === 60) wod.name = `EMOM ${r}`;
    else if (every % 60 === 0) wod.name = `E${every / 60}MOM ${every / 60 * r}`;
    else wod.name = `EVERY ${clock(every)} x ${r}`;
  } else {
    const [work, rest] = pick(cfg, "tabataWorkRest");
    const r = pick(cfg, "tabataRounds");
    wod.workSec = work;
    wod.restSec = rest;
    wod.intervalSec = work + rest;
    wod.rounds = r;
    wod.timeCapSec = r * (work + rest) - rest;
    round.slot = 0;
    round.name = "Reps";
    round.reps = 0;
    wod.name = `TABATA ${r}x${work}/${rest}`;
  }
  return wod;
}
