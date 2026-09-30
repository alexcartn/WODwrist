import Toybox.Lang;

// WOD state machine. Pure logic: time is passed in (ms, System.getTimer()).
// Port of web-editor/js/timer-engine.js (the tested reference). Keep in sync.
//
// start/tick/addRep/next/finish return events as [[code, arg], ...].

// Engine states
const ST_IDLE = 0;
const ST_COUNTDOWN = 1;
const ST_WORK = 2;
const ST_REST = 3;
const ST_PAUSED = 4;
const ST_DONE = 5;

// Events
const EV_WARN = 1;        // arg = seconds left (3, 2, 1) in the current timed segment
const EV_START = 2;       // countdown over
const EV_LAP = 3;         // round/interval closed, arg = reps in that lap
const EV_REST = 4;        // tabata work -> rest
const EV_BLOCK = 5;       // next movement, arg = block index
const EV_ROUND = 6;       // round completed (AMRAP / FOR_TIME), arg = rounds completed
const EV_TARGET_DONE = 7; // EMOM / TABATA interval work done early
const EV_DONE = 8;        // workout over, arg = reps of the last (open) lap

// WOD types
const WT_AMRAP = 0;
const WT_EMOM = 1;
const WT_FOR_TIME = 2;
const WT_TABATA = 3;

class TimerEngine {

    var wod as Dictionary;
    var wodType as Number;
    var state as Number = ST_IDLE;
    var round as Number = 0;          // 0-based round (AMRAP/FT) or interval (EMOM/TABATA)
    var blockIdx as Number = 0;
    var blockReps as Number = 0;
    var lapReps as Number = 0;
    var totalReps as Number = 0;
    var roundsCompleted as Number = 0;
    var intervalDone as Boolean = false;
    var capped as Boolean = false;

    private var _countdownMs as Number;
    private var _pausedFrom as Number = ST_IDLE;
    private var _startMs as Number = 0;
    private var _pauseStartMs as Number = 0;
    private var _pausedTotalMs as Number = 0;
    private var _doneActiveMs as Number = -1;
    private var _lastWarnKey as Number = -1;

    private var _blocks as Array<Dictionary>;
    private var _slots as Array<Number>;
    private var _capMs as Number;
    private var _intervalMs as Number;
    private var _workMs as Number;
    private var _rounds as Number;
    private var _repScheme as Array<Number>?;

    function initialize(w as Dictionary, countdownSec as Number) {
        wod = w;
        _countdownMs = countdownSec * 1000;
        var t = w["type"] as String;
        if (t.equals("AMRAP")) {
            wodType = WT_AMRAP;
        } else if (t.equals("EMOM")) {
            wodType = WT_EMOM;
        } else if (t.equals("FOR_TIME")) {
            wodType = WT_FOR_TIME;
        } else {
            wodType = WT_TABATA;
        }
        _blocks = w["blocks"] as Array<Dictionary>;
        _capMs = w["timeCapSec"] == null ? 0 : (w["timeCapSec"] as Number) * 1000;
        _intervalMs = w["intervalSec"] == null ? 0 : (w["intervalSec"] as Number) * 1000;
        _workMs = w["workSec"] == null ? 0 : (w["workSec"] as Number) * 1000;
        _rounds = w["rounds"] == null ? 0 : w["rounds"] as Number;
        _repScheme = w["repScheme"] as Array<Number>?;

        _slots = [] as Array<Number>;
        for (var i = 0; i < _blocks.size(); i++) {
            var s = _blocks[i]["slot"];
            if (s != null && _slots.indexOf(s as Number) < 0) { _slots.add(s as Number); }
        }
        // insertion sort, slot lists are tiny
        for (var i = 1; i < _slots.size(); i++) {
            var v = _slots[i];
            var j = i - 1;
            while (j >= 0 && _slots[j] > v) {
                _slots[j + 1] = _slots[j];
                j--;
            }
            _slots[j + 1] = v;
        }
    }

    function isInterval() as Boolean {
        return wodType == WT_EMOM || wodType == WT_TABATA;
    }

    // ---------- time ----------

    function activeMs(now as Number) as Number {
        if (state == ST_IDLE) { return -_countdownMs; }
        if (state == ST_DONE && _doneActiveMs >= 0) { return _doneActiveMs; }
        var t = state == ST_PAUSED ? _pauseStartMs : now;
        return t - _startMs - _pausedTotalMs - _countdownMs;
    }

    // Big number on screen: countdown, time left, or elapsed (FOR_TIME).
    function clockMs(now as Number) as Number {
        var a = activeMs(now);
        if (a < 0) { return -a; }
        if (wodType == WT_AMRAP) {
            return _capMs - a > 0 ? _capMs - a : 0;
        }
        if (wodType == WT_FOR_TIME) {
            return (_capMs > 0 && a > _capMs) ? _capMs : a;
        }
        if (state == ST_DONE) { return 0; }
        if (wodType == WT_EMOM) {
            return _intervalMs - (a % _intervalMs);
        }
        var within = a % _intervalMs;
        return within < _workMs ? _workMs - within : _intervalMs - within;
    }

    // true when the clock counts down (round the displayed seconds up)
    function clockCountsDown(now as Number) as Boolean {
        return activeMs(now) < 0 || wodType != WT_FOR_TIME;
    }

    // ---------- blocks ----------

    function currentBlocks() as Array<Dictionary> {
        if (!isInterval()) { return _blocks; }
        var slot = _slots[round % _slots.size()];
        var out = [] as Array<Dictionary>;
        for (var i = 0; i < _blocks.size(); i++) {
            if (_blocks[i]["slot"] == slot) { out.add(_blocks[i]); }
        }
        return out;
    }

    function currentBlock() as Dictionary? {
        var bl = currentBlocks();
        return blockIdx < bl.size() ? bl[blockIdx] : null;
    }

    // Interval WODs: blocks of the next interval, [] after the last one.
    // Shown while waiting (EMOM work done early, Tabata rest).
    function nextBlocks() as Array<Dictionary> {
        var out = [] as Array<Dictionary>;
        if (!isInterval() || round + 1 >= _rounds) { return out; }
        var slot = _slots[(round + 1) % _slots.size()];
        for (var i = 0; i < _blocks.size(); i++) {
            if (_blocks[i]["slot"] == slot) { out.add(_blocks[i]); }
        }
        return out;
    }

    function target(b as Dictionary?) as Number {
        if (b == null) { return 0; }
        var reps = b["reps"] as Number;
        if (reps > 0) { return reps; }
        if (_repScheme != null && round < (_repScheme as Array<Number>).size()) {
            return (_repScheme as Array<Number>)[round];
        }
        return 0;
    }

    // Planned length in ms (0 for For time without cap): used for coach alerts.
    function totalMs() as Number {
        return _capMs;
    }

    // 0 for AMRAP (open-ended)
    function totalRounds() as Number {
        return wodType == WT_AMRAP ? 0 : _rounds;
    }

    // ---------- controls ----------

    function start(now as Number) as Array<Array<Number> > {
        if (state != ST_IDLE) { return [] as Array<Array<Number> >; }
        _startMs = now;
        state = _countdownMs > 0 ? ST_COUNTDOWN : ST_WORK;
        if (state == ST_WORK) { return [[EV_START, 0]] as Array<Array<Number> >; }
        return tick(now);
    }

    function pause(now as Number) as Void {
        if (state == ST_IDLE || state == ST_PAUSED || state == ST_DONE) { return; }
        _pausedFrom = state;
        _pauseStartMs = now;
        state = ST_PAUSED;
    }

    function resume(now as Number) as Void {
        if (state != ST_PAUSED) { return; }
        _pausedTotalMs += now - _pauseStartMs;
        state = _pausedFrom;
    }

    // Athlete stops early. Score keeps what was done.
    function finish(now as Number) as Array<Array<Number> > {
        if (state == ST_DONE) { return [] as Array<Array<Number> >; }
        if (state == ST_PAUSED) { resume(now); }
        var a = activeMs(now);
        return done(a > 0 ? a : 0, true);
    }

    private function done(a as Number, isCapped as Boolean) as Array<Array<Number> > {
        _doneActiveMs = a;
        capped = isCapped;
        state = ST_DONE;
        return [[EV_DONE, lapReps]] as Array<Array<Number> >;
    }

    private function warn(key as Number, remMs as Number, ev as Array<Array<Number> >) as Void {
        var sec = (remMs + 999) / 1000;
        if (sec >= 1 && sec <= 3 && key * 10 + sec != _lastWarnKey) {
            _lastWarnKey = key * 10 + sec;
            ev.add([EV_WARN, sec]);
        }
    }

    private function closeLap(ev as Array<Array<Number> >) as Void {
        ev.add([EV_LAP, lapReps]);
        lapReps = 0;
    }

    private function appendAll(ev as Array<Array<Number> >, more as Array<Array<Number> >) as Array<Array<Number> > {
        for (var i = 0; i < more.size(); i++) { ev.add(more[i]); }
        return ev;
    }

    function tick(now as Number) as Array<Array<Number> > {
        var ev = [] as Array<Array<Number> >;
        if (state == ST_IDLE || state == ST_PAUSED || state == ST_DONE) { return ev; }
        var a = activeMs(now);
        if (a < 0) {
            warn(9999, -a, ev);
            return ev;
        }
        if (state == ST_COUNTDOWN) {
            state = ST_WORK;
            ev.add([EV_START, 0]);
        }
        if (wodType == WT_AMRAP) {
            if (a >= _capMs) { return appendAll(ev, done(_capMs, true)); }
            warn(0, _capMs - a, ev);
        } else if (wodType == WT_FOR_TIME) {
            if (_capMs > 0) {
                if (a >= _capMs) { return appendAll(ev, done(_capMs, true)); }
                warn(0, _capMs - a, ev);
            }
        } else if (wodType == WT_EMOM) {
            var idx = a / _intervalMs;
            while (round < idx && round < _rounds - 1) {
                closeLap(ev);
                nextInterval();
            }
            if (idx >= _rounds) { return appendAll(ev, done(_rounds * _intervalMs, false)); }
            warn(idx, _intervalMs - (a % _intervalMs), ev);
        } else {
            if (a >= _capMs) { return appendAll(ev, done(_capMs, false)); }
            var idx = a / _intervalMs;
            while (round < idx) {
                closeLap(ev);
                nextInterval();
                state = ST_WORK;
            }
            var within = a % _intervalMs;
            if (within >= _workMs && state == ST_WORK) {
                state = ST_REST;
                ev.add([EV_REST, 0]);
            }
            if (within < _workMs) {
                warn(idx * 2, _workMs - within, ev);
            } else {
                warn(idx * 2 + 1, _intervalMs - within, ev);
            }
        }
        return ev;
    }

    private function nextInterval() as Void {
        round++;
        blockIdx = 0;
        blockReps = 0;
        intervalDone = false;
    }

    // +1 / -1 from the rep counter or the athlete.
    function addRep(delta as Number, now as Number) as Array<Array<Number> > {
        var ev = [] as Array<Array<Number> >;
        if (state != ST_WORK || intervalDone) { return ev; }
        var b = currentBlock();
        if (b == null || !(b["unit"] as String).equals("reps")) { return ev; }
        if (delta < 0 && blockReps + delta < 0) { delta = -blockReps; }
        if (delta == 0) { return ev; }
        blockReps += delta;
        lapReps += delta;
        totalReps += delta;
        var t = target(b);
        if (t > 0 && blockReps >= t) { advance(ev, now); }
        return ev;
    }

    // Athlete says "this movement is done". Credits the missing target reps.
    function next(now as Number) as Array<Array<Number> > {
        var ev = [] as Array<Array<Number> >;
        if (state != ST_WORK || intervalDone) { return ev; }
        var b = currentBlock();
        if (b == null) { return ev; }
        if ((b["unit"] as String).equals("reps")) {
            var missing = target(b) - blockReps;
            if (missing > 0) {
                lapReps += missing;
                totalReps += missing;
            }
        }
        advance(ev, now);
        return ev;
    }

    private function advance(ev as Array<Array<Number> >, now as Number) as Void {
        blockIdx++;
        blockReps = 0;
        if (blockIdx < currentBlocks().size()) {
            ev.add([EV_BLOCK, blockIdx]);
            return;
        }
        if (isInterval()) {
            intervalDone = true;
            ev.add([EV_TARGET_DONE, 0]);
            return;
        }
        roundsCompleted++;
        ev.add([EV_ROUND, roundsCompleted]);
        if (wodType == WT_FOR_TIME && roundsCompleted >= _rounds) {
            appendAll(ev, done(activeMs(now), false));
            return;
        }
        closeLap(ev);
        round++;
        blockIdx = 0;
        ev.add([EV_BLOCK, 0]);
    }

    // ---------- score ----------

    // FOR_TIME finished under the cap: score is a time.
    function hasTimeScore() as Boolean {
        return wodType == WT_FOR_TIME && state == ST_DONE && !capped;
    }

    function finalActiveMs() as Number {
        return _doneActiveMs;
    }

    // "5 + 12" (AMRAP), "4:37" (FOR_TIME), "123 reps"
    function scoreText() as String {
        if (wodType == WT_AMRAP) {
            return roundsCompleted.format("%d") + " + " + lapReps.format("%d");
        }
        if (hasTimeScore()) {
            return Str.clock(_doneActiveMs, false);
        }
        if (wodType == WT_FOR_TIME) {
            return "CAP + " + totalReps.format("%d");
        }
        return totalReps.format("%d") + " reps";
    }
}
