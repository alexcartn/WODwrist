// TimerEngine: reference implementation of the WOD state machine.
// Pure logic, time is injected (ms). Ported 1:1 to
// watch-app/source/engine/TimerEngine.mc. Keep both in sync.

export const S = { IDLE: 0, COUNTDOWN: 1, WORK: 2, REST: 3, PAUSED: 4, DONE: 5 };

// Events are [code, arg] pairs returned by start/tick/addRep/next.
export const E = {
  WARN: 1,          // arg = seconds left (3, 2, 1) in the current timed segment
  START: 2,         // countdown over, work begins
  LAP: 3,           // a round/interval closed, arg = reps in that lap
  REST: 4,          // tabata work -> rest
  BLOCK: 5,         // moved to next movement, arg = new block index
  ROUND: 6,         // round completed (AMRAP / FOR_TIME), arg = rounds completed
  TARGET_DONE: 7,   // EMOM / TABATA interval work finished early
  DONE: 8,          // workout over
};

export class TimerEngine {
  constructor(wod, countdownSec = 10) {
    this.wod = wod;
    this.countdownMs = countdownSec * 1000;
    this.state = S.IDLE;
    this.pausedFrom = S.IDLE;
    this.startMs = 0;
    this.pauseStartMs = 0;
    this.pausedTotalMs = 0;
    this.doneActiveMs = -1;
    this.capped = false;

    this.round = 0;          // 0-based round (AMRAP/FT) or interval (EMOM/TABATA)
    this.blockIdx = 0;       // index into currentBlocks()
    this.blockReps = 0;
    this.lapReps = 0;
    this.totalReps = 0;
    this.roundsCompleted = 0;
    this.intervalDone = false;
    this.lastWarnKey = -1;

    const slots = [];
    for (const b of wod.blocks) if (b.slot != null && !slots.includes(b.slot)) slots.push(b.slot);
    slots.sort((a, b) => a - b);
    this.slots = slots;
  }

  isInterval() { return this.wod.type === "EMOM" || this.wod.type === "TABATA"; }

  // Death by: EMOM whose target grows every minute, ends at the first miss.
  isDeathBy() { return this.wod.type === "EMOM" && this.wod.repStep > 0; }

  // ---------- time ----------

  activeMs(now) {
    if (this.state === S.IDLE) return -this.countdownMs;
    if (this.state === S.DONE && this.doneActiveMs >= 0) return this.doneActiveMs;
    const t = this.state === S.PAUSED ? this.pauseStartMs : now;
    return t - this.startMs - this.pausedTotalMs - this.countdownMs;
  }

  // Big number on screen: countdown, time left, or elapsed (FOR_TIME).
  clockMs(now) {
    const a = this.activeMs(now);
    if (a < 0) return -a;
    const w = this.wod;
    switch (w.type) {
      case "AMRAP": return Math.max(0, w.timeCapSec * 1000 - a);
      case "FOR_TIME": return w.timeCapSec ? Math.min(a, w.timeCapSec * 1000) : a;
      case "EMOM": {
        if (this.state === S.DONE) return 0;
        const iv = w.intervalSec * 1000;
        return iv - (a % iv);
      }
      case "TABATA": {
        if (this.state === S.DONE) return 0;
        const p = w.intervalSec * 1000, work = w.workSec * 1000;
        const within = a % p;
        return within < work ? work - within : p - within;
      }
    }
    return 0;
  }

  // [elapsedMs, totalMs] of the current timed segment (countdown, cap,
  // interval, tabata phase) for the progress ring, or null without a fixed length.
  segment(now) {
    const a = this.activeMs(now);
    if (a < 0) return [this.countdownMs + a, this.countdownMs];
    const w = this.wod;
    const done = this.state === S.DONE;
    switch (w.type) {
      case "AMRAP": {
        const cap = w.timeCapSec * 1000;
        return [Math.min(a, cap), cap];
      }
      case "FOR_TIME": {
        if (!w.timeCapSec) return null;
        const cap = w.timeCapSec * 1000;
        return [Math.min(a, cap), cap];
      }
      case "EMOM": {
        const iv = w.intervalSec * 1000;
        return done ? [iv, iv] : [a % iv, iv];
      }
      case "TABATA": {
        const p = w.intervalSec * 1000, work = w.workSec * 1000;
        if (done) return [work, work];
        const within = a % p;
        return within < work ? [within, work] : [within - work, p - work];
      }
    }
    return null;
  }

  // ---------- blocks ----------

  currentBlocks() {
    if (!this.isInterval()) return this.wod.blocks;
    const slot = this.slots[this.round % this.slots.length];
    return this.wod.blocks.filter((b) => b.slot === slot);
  }

  currentBlock() {
    const bl = this.currentBlocks();
    return this.blockIdx < bl.length ? bl[this.blockIdx] : null;
  }

  // Interval WODs: blocks of the next interval, [] after the last one.
  // Shown while waiting (EMOM work done early, Tabata rest).
  nextBlocks() {
    if (!this.isInterval() || this.round + 1 >= this.wod.rounds) return [];
    const slot = this.slots[(this.round + 1) % this.slots.length];
    return this.wod.blocks.filter((b) => b.slot === slot);
  }

  target(block) {
    if (block == null) return 0;
    const step = this.wod.repStep || 0;
    if (this.isDeathBy()) return block.reps + this.round * step;
    if (block.reps > 0) return block.reps;
    const rs = this.wod.repScheme;
    if (rs && this.round < rs.length) return rs[this.round];
    // open ladder (3-6-9-...): keep adding the step
    if (rs && step > 0) return rs[rs.length - 1] + (this.round - rs.length + 1) * step;
    return 0;
  }

  // Rounds shown as "3/10"; null when open-ended (AMRAP, Death by).
  totalRounds() {
    return this.wod.type === "AMRAP" || this.isDeathBy() ? null : this.wod.rounds;
  }

  // ---------- controls ----------

  start(now) {
    if (this.state !== S.IDLE) return [];
    this.startMs = now;
    this.state = this.countdownMs > 0 ? S.COUNTDOWN : S.WORK;
    return this.state === S.WORK ? [[E.START, 0]] : this.tick(now);
  }

  pause(now) {
    if (this.state === S.IDLE || this.state === S.PAUSED || this.state === S.DONE) return;
    this.pausedFrom = this.state;
    this.pauseStartMs = now;
    this.state = S.PAUSED;
  }

  resume(now) {
    if (this.state !== S.PAUSED) return;
    this.pausedTotalMs += now - this.pauseStartMs;
    this.state = this.pausedFrom;
  }

  // Athlete stops early. Score keeps what was done.
  finish(now) {
    if (this.state === S.DONE) return [];
    if (this.state === S.PAUSED) this.resume(now);
    return this.done(Math.max(0, this.activeMs(now)), true);
  }

  done(activeMs, capped) {
    this.doneActiveMs = activeMs;
    this.capped = capped;
    this.state = S.DONE;
    return [[E.DONE, this.lapReps]];
  }

  warn(key, remMs, ev) {
    const sec = Math.ceil(remMs / 1000);
    if (sec >= 1 && sec <= 3 && key * 10 + sec !== this.lastWarnKey) {
      this.lastWarnKey = key * 10 + sec;
      ev.push([E.WARN, sec]);
    }
  }

  closeLap(ev) {
    ev.push([E.LAP, this.lapReps]);
    this.lapReps = 0;
  }

  tick(now) {
    const ev = [];
    if (this.state === S.IDLE || this.state === S.PAUSED || this.state === S.DONE) return ev;
    const a = this.activeMs(now);
    const w = this.wod;
    if (a < 0) {
      this.warn(9999, -a, ev);
      return ev;
    }
    if (this.state === S.COUNTDOWN) {
      this.state = S.WORK;
      ev.push([E.START, 0]);
    }
    switch (w.type) {
      case "AMRAP": {
        const cap = w.timeCapSec * 1000;
        if (a >= cap) return ev.concat(this.done(cap, true));
        this.warn(0, cap - a, ev);
        break;
      }
      case "FOR_TIME": {
        if (w.timeCapSec) {
          const cap = w.timeCapSec * 1000;
          if (a >= cap) return ev.concat(this.done(cap, true));
          this.warn(0, cap - a, ev);
        }
        break;
      }
      case "EMOM": {
        const iv = w.intervalSec * 1000;
        const idx = Math.floor(a / iv);
        while (this.round < idx && this.round < w.rounds - 1) {
          // Death by: the minute ended before the target, it is over
          if (this.isDeathBy() && !this.intervalDone) return ev.concat(this.done((this.round + 1) * iv, false));
          this.closeLap(ev);
          this.nextInterval();
        }
        if (idx >= w.rounds) return ev.concat(this.done(w.rounds * iv, false));
        this.warn(idx, iv - (a % iv), ev);
        break;
      }
      case "TABATA": {
        const p = w.intervalSec * 1000, work = w.workSec * 1000;
        const end = w.timeCapSec * 1000;
        if (a >= end) return ev.concat(this.done(end, false));
        const idx = Math.floor(a / p);
        while (this.round < idx) {
          this.closeLap(ev);
          this.nextInterval();
          this.state = S.WORK;
        }
        const within = a % p;
        if (within >= work && this.state === S.WORK) {
          this.state = S.REST;
          ev.push([E.REST, 0]);
        }
        this.warn(idx * 2 + (within < work ? 0 : 1), within < work ? work - within : p - within, ev);
        break;
      }
    }
    return ev;
  }

  nextInterval() {
    this.round++;
    this.blockIdx = 0;
    this.blockReps = 0;
    this.intervalDone = false;
  }

  // +1 / -1 from the rep counter or the athlete.
  addRep(delta, now) {
    const ev = [];
    if (this.state !== S.WORK || this.intervalDone) return ev;
    const b = this.currentBlock();
    if (b == null || b.unit !== "reps") return ev;
    if (delta < 0 && this.blockReps + delta < 0) delta = -this.blockReps;
    if (delta === 0) return ev;
    this.blockReps += delta;
    this.lapReps += delta;
    this.totalReps += delta;
    const t = this.target(b);
    if (t > 0 && this.blockReps >= t) this.advance(ev, now);
    return ev;
  }

  // Athlete says "this movement is done". Credits the missing target reps.
  next(now) {
    const ev = [];
    if (this.state !== S.WORK || this.intervalDone) return ev;
    const b = this.currentBlock();
    if (b == null) return ev;
    if (b.unit === "reps") {
      const missing = this.target(b) - this.blockReps;
      if (missing > 0) {
        this.lapReps += missing;
        this.totalReps += missing;
      }
    }
    this.advance(ev, now);
    return ev;
  }

  advance(ev, now) {
    this.blockIdx++;
    this.blockReps = 0;
    const n = this.currentBlocks().length;
    if (this.blockIdx < n) {
      ev.push([E.BLOCK, this.blockIdx]);
      return;
    }
    if (this.isInterval()) {
      this.intervalDone = true;
      if (this.isDeathBy()) this.roundsCompleted++;
      ev.push([E.TARGET_DONE, 0]);
      return;
    }
    this.roundsCompleted++;
    ev.push([E.ROUND, this.roundsCompleted]);
    if (this.wod.type === "FOR_TIME" && this.roundsCompleted >= this.wod.rounds) {
      ev.push(...this.done(this.activeMs(now), false));
      return;
    }
    this.closeLap(ev);
    this.round++;
    this.blockIdx = 0;
    ev.push([E.BLOCK, 0]);
  }

  // ---------- score ----------

  // { kind: "rounds", rounds, reps } | { kind: "time", ms } | { kind: "reps", reps }
  score() {
    switch (this.wod.type) {
      case "AMRAP": return { kind: "rounds", rounds: this.roundsCompleted, reps: this.lapReps };
      case "EMOM":
        if (this.isDeathBy()) return { kind: "rounds", rounds: this.roundsCompleted, reps: this.lapReps };
        return { kind: "reps", reps: this.totalReps };
      case "FOR_TIME":
        if (this.state === S.DONE && !this.capped) return { kind: "time", ms: this.doneActiveMs };
        return { kind: "reps", reps: this.totalReps };
      default: return { kind: "reps", reps: this.totalReps };
    }
  }
}
