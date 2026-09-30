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

// ---------- load over time ----------
// entries: [[day, load], ...], day = days since epoch (local)

export function addLoad(entries, day, load, keepDays = 42) {
  const out = entries.filter(([d]) => d > day - keepDays);
  const same = out.find(([d]) => d === day);
  if (same) same[1] += load;
  else out.push([day, load]);
  return out.sort((a, b) => a[0] - b[0]);
}

export function sumDays(entries, today, days) {
  return entries.filter(([d]) => d > today - days && d <= today).reduce((a, [, l]) => a + l, 0);
}

// Acute = last 7 days, chronic = weekly average over the last 28 days.
// ratio in hundredths (130 = 1.30), null without a chronic load.
export function acwr(entries, today) {
  const acute = sumDays(entries, today, 7);
  const chronic = Math.round(sumDays(entries, today, 28) / 4);
  return { acute, chronic, ratio: chronic > 0 ? Math.round((acute * 100) / chronic) : null };
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
