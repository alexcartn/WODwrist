// Score memory and AMRAP / For time pacing: reference implementation.
// Ported to watch-app/source/session/ScoreHistory.mc. Keep in sync.
//
// A record is { kind: "rounds" | "time" | "reps", rounds, reps, ms, t, laps }
//   laps = cumulative active ms at the end of each completed round
//   t    = epoch seconds when saved

// Same WOD = same structure, whatever its name ("WOD" vs "WOD 2026-09-30").
// Scaled results only compete with scaled results.
export function wodSignature(wod, scaled = false) {
  const head = [wod.type, wod.timeCapSec, wod.intervalSec, wod.workSec, wod.restSec, wod.rounds,
    wod.repScheme ? wod.repScheme.join("-") : "", wod.repStep].map((v) => (v == null ? "" : String(v)));
  const blocks = wod.blocks.map((b) => `${b.movement}:${b.reps}${b.unit}:${b.slot == null ? "" : b.slot}`);
  return head.join("|") + "|" + blocks.join(",") + (scaled ? "|scaled" : "");
}

// Higher is better. A finished For time always beats a capped one.
export function scoreValue(rec) {
  if (rec.kind === "time") return 2000000000 - rec.ms;
  if (rec.kind === "rounds") return rec.rounds * 1000 + rec.reps;
  return rec.reps;
}

export function isBetter(a, b) {
  return b == null || scoreValue(a) > scoreValue(b);
}

// ms ahead (<0) or behind (>0) the reference at the last completed round,
// or null when there is nothing to compare yet.
export function paceDelta(myLaps, refLaps) {
  const k = myLaps.length;
  if (k === 0 || refLaps == null || refLaps.length < k) return null;
  return myLaps[k - 1] - refLaps[k - 1];
}

// -8400 -> "-0:08", 14000 -> "+0:14", 0 -> "+0:00" (rounded to the second)
export function formatDelta(ms) {
  const sign = ms < 0 ? "-" : "+";
  const sec = Math.round(Math.abs(ms) / 1000);
  return `${sign}${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`;
}

export function scoreText(rec) {
  if (rec.kind === "rounds") return `${rec.rounds} + ${rec.reps}`;
  if (rec.kind === "time") {
    const s = Math.floor(rec.ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }
  return `${rec.reps} reps`;
}

// History entry for one WOD: { last, best, n }
export function addResult(entry, rec) {
  if (entry == null) return { last: rec, best: rec, n: 1 };
  return { last: rec, best: isBetter(rec, entry.best) ? rec : entry.best, n: entry.n + 1 };
}

// ---------- on-watch stats ----------

// Round durations from cumulative round end times.
export function roundDurations(laps) {
  return laps.map((t, i) => (i === 0 ? t : t - laps[i - 1]));
}

// Fade: how much slower the last round was than the first, in %.
// null with fewer than 2 rounds.
export function fadePct(laps) {
  if (laps == null || laps.length < 2) return null;
  const d = roundDurations(laps);
  if (d[0] <= 0) return null;
  return Math.round(((d[d.length - 1] - d[0]) * 100) / d[0]);
}

// Seconds per rep with one decimal, as tenths: 2400 ms / 1 rep -> 24 (2.4 s)
export function tenthsPerRep(reps, ms) {
  if (reps <= 0) return null;
  return Math.round(ms / reps / 100);
}

// Movement stats: { id: [reps, ms] }, merged session into totals.
export function mergeMovementStats(total, session) {
  const out = { ...total };
  for (const [id, [r, ms]] of Object.entries(session)) {
    const cur = out[id] || [0, 0];
    out[id] = [cur[0] + r, cur[1] + ms];
  }
  return out;
}
