// Performance engineering helpers: reference implementation, ported to
// watch-app/source/session/Perf.mc. Keep in sync. Integer math only.

// Garmin heart rate zones: bounds = [z1 min, z1 max, z2 max, z3 max, z4 max, z5 max]
// (UserProfile.getHeartRateZones). Below z1 min = zone 0.
export function zoneOf(hr, bounds) {
  if (hr < bounds[0]) return 0;
  for (let z = 1; z <= 4; z++) if (hr <= bounds[z]) return z;
  return 5;
}

// Fallback zones from a max HR, Garmin's default split: 50/60/70/80/90 %.
export function defaultBounds(maxHr) {
  return [50, 60, 70, 80, 90, 100].map((p) => Math.floor((maxHr * p) / 100));
}

// Edwards TRIMP: minutes in zone x zone number. zoneSec[0..5].
export function trimp(zoneSec) {
  let s = 0;
  for (let z = 1; z <= 5; z++) s += z * zoneSec[z];
  return Math.round(s / 60);
}

// Coefficient of variation in %, null under 2 values.
export function cvPct(values) {
  const n = values.length;
  if (n < 2) return null;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  if (mean <= 0) return null;
  const variance = values.reduce((a, v) => a + (v - mean) * (v - mean), 0) / n;
  return Math.round((Math.sqrt(variance) * 100) / mean);
}

// Share of each interval spent working, in %.
export function densityPct(workMs, intervalMs) {
  if (workMs.length === 0 || intervalMs <= 0) return null;
  const mean = workMs.reduce((a, b) => a + b, 0) / workMs.length;
  return Math.round((mean * 100) / intervalMs);
}

// ---------- daily history ----------
// entries: [[day, v1, v2, ...], ...], day = days since epoch (local).
// Watch layout (Perf.mc): [day, trimp, sRPE, gymMs, wlMs, monoMs, sessions, tonnageKg, prs]
export const D_TRIMP = 1, D_SRPE = 2, D_GYM = 3, D_WL = 4, D_MONO = 5, D_SESSIONS = 6, D_TONNAGE = 7, D_PRS = 8;
export const DAY_FIELDS = 8;

// Add values (index 1..) to a day, dropping days older than keepDays.
export function addDay(entries, day, values, keepDays = 42) {
  const out = entries.filter(([d]) => d > day - keepDays).map((e) => e.slice());
  let cur = out.find(([d]) => d === day);
  if (!cur) {
    cur = [day];
    out.push(cur);
  }
  values.forEach((v, i) => {
    while (cur.length < i + 2) cur.push(0);
    cur[i + 1] += v;
  });
  return out.sort((a, b) => a[0] - b[0]);
}

export function addLoad(entries, day, load, keepDays = 42) {
  return addDay(entries, day, [load], keepDays);
}

export function sumDays(entries, today, days, idx = 1) {
  return entries.filter(([d]) => d > today - days && d <= today).reduce((a, e) => a + (e[idx] || 0), 0);
}

// Acute = last 7 days, chronic = weekly average over the last 28 days.
// ratio in hundredths (130 = 1.30), null without a chronic load.
export function acwr(entries, today, idx = 1) {
  const acute = sumDays(entries, today, 7, idx);
  const chronic = Math.round(sumDays(entries, today, 28, idx) / 4);
  return { acute, chronic, ratio: chronic > 0 ? Math.round((acute * 100) / chronic) : null };
}

// Foster monotony (mean / sd of the last 7 daily loads, rest days = 0) and
// strain (weekly load x monotony). monotony in hundredths, capped at 1000.
export function monotony(entries, today, idx = 1) {
  const days = [];
  for (let i = 6; i >= 0; i--) days.push(sumDays(entries, today - i, 1, idx));
  const week = days.reduce((a, b) => a + b, 0);
  if (week <= 0) return null;
  const mean = week / 7;
  const sd = Math.sqrt(days.reduce((a, v) => a + (v - mean) * (v - mean), 0) / 7);
  const mono = sd > 0 ? Math.min(1000, Math.round((mean * 100) / sd)) : 1000;
  return { monotony: mono, strain: Math.round((week * mono) / 100) };
}

// [this 7 days, previous 7 days]
export function weekCompare(entries, today, idx) {
  return [sumDays(entries, today, 7, idx), sumDays(entries, today - 7, 7, idx)];
}

// Share of time per domain [gym, weightlifting, mono] in %, over `days`.
export function domainShare(entries, today, days = 28) {
  const v = [D_GYM, D_WL, D_MONO].map((i) => sumDays(entries, today, days, i));
  const tot = v[0] + v[1] + v[2];
  if (tot <= 0) return null;
  const p = v.map((x) => Math.round((x * 100) / tot));
  return p;
}

// ---------- movements ----------

// Your pace vs the reference pace, per movement with enough reps:
// [[id, ratio in %], ...] strongest first (100 = reference, 80 = 20 % faster).
export function rankMovements(mvStats, refTenths, minReps = 30) {
  const out = [];
  for (const [id, [reps, ms]] of Object.entries(mvStats)) {
    const ref = refTenths[id];
    if (!ref || reps < minReps) continue;
    const t = Math.round(ms / reps / 100);
    out.push([id, Math.round((t * 100) / ref)]);
  }
  return out.sort((a, b) => a[1] - b[1] || (a[0] < b[0] ? -1 : 1));
}

// Pace change from the first to the last time a movement was done in the
// workout, in % (+25 = 25 % slower). occ = [[reps, ms], ...] in order.
export function fatiguePct(occ) {
  const v = occ.filter(([r, ms]) => r > 0 && ms > 0);
  if (v.length < 2) return null;
  const first = v[0][1] / v[0][0];
  const last = v[v.length - 1][1] / v[v.length - 1][0];
  return Math.round(((last - first) * 100) / first);
}

// Breaks inside a set: rep-to-rep gaps longer than max(3 s, 2.5 x median gap).
export function countBreaks(repTimes) {
  if (repTimes.length < 3) return 0;
  const gaps = [];
  for (let i = 1; i < repTimes.length; i++) gaps.push(repTimes[i] - repTimes[i - 1]);
  const s = gaps.slice().sort((a, b) => a - b);
  const med = s[Math.floor(s.length / 2)];
  const limit = Math.max(3000, Math.floor((med * 5) / 2));
  return gaps.filter((g) => g > limit).length;
}

// Heartbeats per round, last vs first completed round, in %.
// laps = [[durationMs, reps, avgHr], ...]
export function beatsDriftPct(laps) {
  const v = laps.filter(([ms, , hr]) => ms > 0 && hr > 0);
  if (v.length < 2) return null;
  const beats = ([ms, , hr]) => (ms * hr) / 60000;
  const a = beats(v[0]);
  const b = beats(v[v.length - 1]);
  return Math.round(((b - a) * 100) / a);
}

// Session RPE load (Foster): RPE x minutes.
export function srpeLoad(rpe, activeMs) {
  return rpe * Math.round(activeMs / 60000);
}

// "building" until there are 3 weeks of history.
export function loadStatus(entries, today, ratio) {
  if (entries.length === 0 || entries[0][0] > today - 21 || ratio == null) return "building";
  if (ratio < 80) return "low";
  if (ratio <= 130) return "optimal";
  if (ratio <= 150) return "high";
  return "risk";
}

// Same WOD, score at least as good: heart rate difference (bpm), else null.
// Negative = same work for less heart: fitter.
export function cardiacTrend(prevRec, lastRec, scoreValue) {
  if (!prevRec || !lastRec || !(prevRec.hr > 0) || !(lastRec.hr > 0)) return null;
  if (scoreValue(lastRec) < scoreValue(prevRec)) return null;
  return lastRec.hr - prevRec.hr;
}
