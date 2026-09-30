// Coach helpers: reference implementation, ported to
// watch-app/source/session/Coach.mc. Keep in sync.

export const ALERT_HALF = 1;
export const ALERT_ONE_MIN = 2;

// Alerts crossed between two ticks. totalMs = 0 when the WOD has no fixed
// length (For time without cap): no alert then.
export function alertsDue(prevMs, nowMs, totalMs, opts) {
  const out = [];
  if (totalMs <= 0 || nowMs <= prevMs) return out;
  const half = Math.floor(totalMs / 2);
  if (opts.halfway && prevMs < half && nowMs >= half) out.push(ALERT_HALF);
  // "1 min left" only makes sense on WODs longer than 2 min
  const oneMin = totalMs - 60000;
  if (opts.oneMin && totalMs > 120000 && prevMs < oneMin && nowMs >= oneMin) out.push(ALERT_ONE_MIN);
  return out;
}

// Seconds until the next multiple of stepMin minutes on the wall clock.
// Less than minLeadSec away -> the one after (time to get ready).
export function secondsToNextSlot(hour, min, sec, stepMin, minLeadSec = 30) {
  const now = hour * 3600 + min * 60 + sec;
  const step = stepMin * 60;
  let next = (Math.floor(now / step) + 1) * step;
  if (next - now < minLeadSec) next += step;
  return next - now; // may roll past midnight, still the right delay
}

// Plan text: parts separated by a line "---".
export function splitParts(text) {
  const parts = [];
  let cur = [];
  for (const line of (text || "").split(/\r?\n/)) {
    if (line.trim() === "---") {
      parts.push(cur.join("\n"));
      cur = [];
    } else {
      cur.push(line);
    }
  }
  parts.push(cur.join("\n"));
  return parts.filter((p) => p.trim().length > 0);
}
