import Toybox.Activity;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Glue for one workout: TimerEngine (logic) + RepCounter (sensor) +
// RecordingManager (FIT) + Feedback (vibration). Views only read from here.
class WorkoutSession {

    var engine as TimerEngine;
    var coach as Boolean;
    var hr as Number = 0;
    var hrMax as Number = 0;
    // one entry per lap: [durationMs, reps, avgHr]
    var laps as Array<Array<Number> > = [] as Array<Array<Number> >;
    var finished as Boolean = false;
    // score memory: previous entry for this WOD (last / best), this run's result
    var history as Dictionary? = null;
    var result as Dictionary? = null;
    var isNewBest as Boolean = false;
    // cumulative active ms at the end of each completed round (AMRAP / FOR_TIME)
    var roundTimes as Array<Number> = [] as Array<Number>;
    // time spent per movement (only "reps" blocks): id -> [reps, ms]
    var movementStats as Dictionary = {};
    private var _mvId as String? = null;
    private var _mvStartMs as Number = 0;
    private var _mvStartReps as Number = 0;

    private var _counter as RepCounter? = null;
    private var _recorder as RecordingManager? = null;
    private var _capture as Boolean = false;
    private var _timer as Timer.Timer? = null;
    private var _lastShownSec as Number = -1;
    private var _lastHrSec as Number = -1;
    private var _hrSum as Number = 0;
    private var _hrCount as Number = 0;
    private var _lapHrSum as Number = 0;
    private var _lapHrCount as Number = 0;
    private var _lapStartMs as Number = 0;
    private var _summaryFromMenu as Boolean = false;
    // class plan: this session is part partIndex (0-based) of partCount
    var partIndex as Number = 0;
    var partCount as Number = 1;
    // short message over the run screen ("HALFWAY", "1 MIN LEFT")
    var flashText as String? = null;
    private var _flashUntil as Number = 0;
    private var _lastActive as Number = 0;
    private var _alertHalf as Boolean = false;
    private var _alertOneMin as Boolean = true;

    // countdownSec null = the "Countdown" setting.
    function initialize(wod as Dictionary, coachMode as Boolean, countdownSec as Number?) {
        coach = coachMode;
        Feedback.strong = coachMode;
        engine = new TimerEngine(wod, countdownSec != null ? countdownSec : propNumber("countdownSec", 10));
        _alertHalf = propBool("alertHalf", false);
        _alertOneMin = propBool("alertOneMin", true);
        _capture = !coachMode && propBool("captureMode", false);
        if (!coachMode && (_capture || propBool("autoCount", true))) {
            _counter = new RepCounter(method(:onCounterRep), _capture);
        }
        if (!coachMode || propBool("coachRecord", false)) {
            _recorder = new RecordingManager();
        }
        if (!coachMode) {
            history = ScoreHistory.load(wod);
        }
    }

    // ---------- settings ----------

    static function propBool(key as String, def as Boolean) as Boolean {
        var v = Application.Properties.getValue(key);
        return v instanceof Boolean ? v as Boolean : def;
    }

    static function propNumber(key as String, def as Number) as Number {
        var v = Application.Properties.getValue(key);
        return v instanceof Number ? v as Number : def;
    }

    // ---------- lifecycle ----------

    function now() as Number {
        return System.getTimer();
    }

    function begin() as Void {
        if (Sensor has :setEnabledSensors) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        }
        log("S", engine.wod["name"] as String);
        if (_counter != null) { (_counter as RepCounter).start(); }
        handle(engine.start(now()));
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:onTick), 250, true);
    }

    function onTick() as Void {
        var t = now();
        handle(engine.tick(t));
        if (finished) { return; }
        checkAlerts(t);
        var sec = t / 1000;
        if (sec != _lastHrSec) {
            _lastHrSec = sec;
            sampleHr();
        }
        var shown = engine.clockMs(t) / 1000;
        if (flashText != null && t >= _flashUntil) {
            flashText = null;
            WatchUi.requestUpdate();
        }
        if (shown != _lastShownSec) {
            _lastShownSec = shown;
            WatchUi.requestUpdate();
        }
    }

    // Halfway / 1 min left: long vibration + a word on screen for 2 s.
    private function checkAlerts(t as Number) as Void {
        var a = engine.activeMs(t);
        if (engine.state != ST_WORK && engine.state != ST_REST) {
            _lastActive = a;
            return;
        }
        var due = Coach.alertsDue(_lastActive, a, engine.totalMs(), _alertHalf, _alertOneMin);
        _lastActive = a;
        for (var i = 0; i < due.size(); i++) {
            flashText = due[i] == ALERT_HALF ? "HALFWAY" : "1 MIN LEFT";
            _flashUntil = t + 2000;
            Feedback.alert();
            WatchUi.requestUpdate();
        }
    }

    private function sampleHr() as Void {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentHeartRate == null) { return; }
        hr = info.currentHeartRate as Number;
        if (engine.state != ST_WORK && engine.state != ST_REST) { return; }
        if (hr > hrMax) { hrMax = hr; }
        _hrSum += hr;
        _hrCount++;
        _lapHrSum += hr;
        _lapHrCount++;
    }

    function avgHr() as Number {
        return _hrCount > 0 ? _hrSum / _hrCount : 0;
    }

    // ---------- events ----------

    private function handle(ev as Array<Array<Number> >) as Void {
        for (var i = 0; i < ev.size(); i++) {
            var code = ev[i][0];
            var arg = ev[i][1];
            if (code == EV_WARN) {
                Feedback.warn(arg);
            } else if (code == EV_START) {
                Feedback.go();
                _lapStartMs = 0;
                if (_recorder != null) { (_recorder as RecordingManager).start(engine.wod["name"] as String); }
                updateCounter();
                mvOpen();
            } else if (code == EV_LAP) {
                closeLap(arg, engine.activeMs(now()));
                if (_recorder != null) { (_recorder as RecordingManager).lap(arg); }
                log("L", arg.format("%d"));
                if (engine.isInterval()) {
                    Feedback.interval();
                    updateCounter();
                    mvClose();
                    mvOpen();
                }
            } else if (code == EV_REST) {
                Feedback.rest();
                mvClose();
            } else if (code == EV_BLOCK) {
                Feedback.block();
                updateCounter();
                mvClose();
                mvOpen();
            } else if (code == EV_ROUND) {
                roundTimes.add(engine.activeMs(now()));
                Feedback.round();
            } else if (code == EV_TARGET_DONE) {
                Feedback.block();
                mvClose();
                if (_counter != null) { (_counter as RepCounter).setProfile(null); }
            } else if (code == EV_DONE) {
                mvClose();
                onDone(arg);
            }
        }
        if (ev.size() > 0) { WatchUi.requestUpdate(); }
    }

    private function closeLap(reps as Number, activeMs as Number) as Void {
        var avg = _lapHrCount > 0 ? _lapHrSum / _lapHrCount : 0;
        laps.add([activeMs - _lapStartMs, reps, avg]);
        _lapStartMs = activeMs;
        _lapHrSum = 0;
        _lapHrCount = 0;
    }

    // ---------- per-movement time ----------

    private function mvOpen() as Void {
        var b = engine.currentBlock();
        if (b == null || !(b["unit"] as String).equals("reps") || (b["movement"] as String).equals("custom")) {
            _mvId = null;
            return;
        }
        _mvId = b["movement"] as String;
        _mvStartMs = engine.activeMs(now());
        _mvStartReps = engine.totalReps;
    }

    // BLOCK / ROUND events arrive after the engine moved on: totalReps already
    // includes the reps of the block being closed.
    private function mvClose() as Void {
        if (_mvId == null) { return; }
        var id = _mvId as String;
        _mvId = null;
        var reps = engine.totalReps - _mvStartReps;
        var ms = engine.activeMs(now()) - _mvStartMs;
        if (reps <= 0 || ms <= 0) { return; }
        var cur = movementStats[id];
        if (cur instanceof Array) {
            var c = cur as Array<Number>;
            movementStats[id] = [c[0] + reps, c[1] + ms];
        } else {
            movementStats[id] = [reps, ms];
        }
    }

    // Point the rep counter at the current movement (or disable it).
    private function updateCounter() as Void {
        var b = engine.currentBlock();
        var mv = b == null ? "none" : b["movement"] as String;
        log("B", mv);
        if (_counter == null) { return; }
        var profile = null;
        if (b != null && (b["unit"] as String).equals("reps")) {
            profile = Movements.profile(mv);
        }
        (_counter as RepCounter).setProfile(profile);
    }

    // ---------- inputs ----------

    function onCounterRep(t as Number) as Void {
        if (_capture) { System.println("R," + t.format("%d") + ",1"); }
        // In capture mode the athlete's presses are the ground truth: the
        // detected reps are only logged, not counted.
        if (_capture || engine.state != ST_WORK) { return; }
        handle(engine.addRep(1, now()));
    }

    // Tap / button. On distance, calorie and time blocks a +1 means "done, next".
    function manualRep(delta as Number) as Void {
        var b = engine.currentBlock();
        if (delta > 0 && b != null && !(b["unit"] as String).equals("reps")) {
            nextBlock();
            return;
        }
        log("M", delta.format("%d"));
        handle(engine.addRep(delta, now()));
    }

    function nextBlock() as Void {
        log("M", "next");
        handle(engine.next(now()));
    }

    function pause() as Void {
        engine.pause(now());
        if (_recorder != null) { (_recorder as RecordingManager).pause(); }
        WatchUi.requestUpdate();
    }

    function resume() as Void {
        engine.resume(now());
        if (_recorder != null) { (_recorder as RecordingManager).resume(); }
        WatchUi.requestUpdate();
    }

    function isPaused() as Boolean {
        return engine.state == ST_PAUSED;
    }

    // From the pause menu: the menu delegate shows the summary itself.
    function finishEarly() as Void {
        _summaryFromMenu = true;
        handle(engine.finish(now()));
    }

    function confidence() as Number {
        if (_counter == null || !(_counter as RepCounter).isEnabled()) { return -1; }
        return (_counter as RepCounter).confidence();
    }

    function isAutoCounting() as Boolean {
        return _counter != null && (_counter as RepCounter).isEnabled() && !_capture;
    }

    // ---------- end ----------

    private function onDone(lastLapReps as Number) as Void {
        if (finished) { return; }
        finished = true;
        stopTimers();
        var active = engine.finalActiveMs();
        closeLap(lastLapReps, active);
        var timeSec = engine.hasTimeScore() ? active / 1000 : 0;
        var extra = engine.wodType == WT_AMRAP ? engine.lapReps : 0;
        if (_recorder != null) {
            (_recorder as RecordingManager).finish(lastLapReps, engine.totalReps, engine.roundsCompleted, extra, timeSec);
        }
        result = buildResult(active);
        if (history != null) {
            isNewBest = ScoreHistory.isBetter(result as Dictionary, history["best"] as Dictionary);
        }
        log("E", engine.scoreText());
        Feedback.done();
        if (!_summaryFromMenu) { getApp().onSessionDone(self); }
    }

    private function buildResult(active as Number) as Dictionary {
        var kind = "reps";
        if (engine.wodType == WT_AMRAP) {
            kind = "rounds";
        } else if (engine.hasTimeScore()) {
            kind = "time";
        }
        return {
            "kind" => kind,
            "rounds" => engine.roundsCompleted,
            "reps" => engine.wodType == WT_AMRAP ? engine.lapReps : engine.totalReps,
            "ms" => active,
            "t" => Time.now().value(),
            "laps" => roundTimes,
            "hr" => avgHr(),
            "hrMax" => hrMax
        };
    }

    // Ahead (<0) / behind (>0) your best at the last completed round, or null.
    function paceDelta() as Number? {
        if (history == null || (engine.wodType != WT_AMRAP && engine.wodType != WT_FOR_TIME)) { return null; }
        var best = (history as Dictionary)["best"] as Dictionary;
        return ScoreHistory.paceDelta(roundTimes, best["laps"] as Array?);
    }

    function showSummary() as Void {
        var view = new SummaryView(self);
        var delegate = new SummaryDelegate(self);
        delegate.setView(view);
        WatchUi.switchToView(view, delegate, WatchUi.SLIDE_UP);
    }

    private function stopTimers() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
        if (_counter != null) { (_counter as RepCounter).stop(); }
    }

    function hasRecording() as Boolean {
        return _recorder != null && (_recorder as RecordingManager).hasSession();
    }

    function save() as Void {
        if (_recorder != null) { (_recorder as RecordingManager).save(); }
        if (!coach && result != null) {
            ScoreHistory.save(engine.wod, result as Dictionary);
            ScoreHistory.addTotals(engine.totalReps, engine.finalActiveMs(), movementStats);
        }
    }

    function discard() as Void {
        stopTimers();
        if (_recorder != null) { (_recorder as RecordingManager).discard(); }
    }

    // App closed mid-workout: keep what was done rather than lose it.
    function abort() as Void {
        if (!finished) {
            _summaryFromMenu = true;
            handle(engine.finish(now()));
        }
        if (hasRecording()) {
            if (engine.finalActiveMs() >= 60000) {
                save();
            } else {
                discard();
            }
        }
    }

    // ---------- capture log (rep-lab) ----------

    private function log(kind as String, value as String) as Void {
        if (_capture) {
            System.println(kind + "," + System.getTimer().format("%d") + "," + value);
        }
    }
}
