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
    // performance: seconds per HR zone (0..5), EMOM work time per interval
    var zoneSec as Array<Number> = [0, 0, 0, 0, 0, 0] as Array<Number>;
    var intervalWorkMs as Array<Number> = [] as Array<Number>;
    private var _zoneBounds as Array<Number>;
    // time spent per movement (only "reps" blocks): id -> [reps, ms]
    var movementStats as Dictionary = {};
    // each time a movement was done: id -> [[reps, ms], ...] (fatigue)
    var occurrences as Dictionary = {};
    // active ms per domain: gymnastics, weightlifting, monostructural
    var domainMs as Array<Number> = [0, 0, 0] as Array<Number>;
    // sets done / sets without a break / breaks, time lost between movements, kg moved
    var sets as Number = 0;
    var unbrokenSets as Number = 0;
    var breaks as Number = 0;
    var transitionMs as Number = 0;
    var tonnage as Number = 0;
    private var _mvId as String? = null;
    private var _mvReps as Boolean = false;
    private var _mvLoadKg as Number = 0;
    private var _mvStartMs as Number = 0;
    private var _mvStartReps as Number = 0;
    private var _setRepTimes as Array<Number> = [] as Array<Number>;

    // after the workout: effort 1-10 (null = skipped), RX or scaled,
    // heart rate recovery (drop in bpm 60 s after the end)
    var rpe as Number? = null;
    var scaled as Boolean = false;
    var hrEnd as Number = 0;
    var hrNow as Number = 0;
    var hrr as Number? = null;
    var hrrElapsedSec as Number = 0;
    private var _hrrTimer as Timer.Timer? = null;
    private var _doneAt as Number = 0;

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
    // banner over the run screen ("HALFWAY", "BURPEES" when the movement changes)
    var flashText as String? = null;
    var flashColor as Number = Theme.WARN;
    private var _flashUntil as Number = 0;
    // "+1" / "-1" next to the rep count, confirms a tap or a button press
    var popText as String? = null;
    private var _popUntil as Number = 0;
    private var _lastActive as Number = 0;
    private var _alertHalf as Boolean = false;
    private var _alertOneMin as Boolean = true;

    // countdownSec null = the "Countdown" setting.
    function initialize(wod as Dictionary, coachMode as Boolean, countdownSec as Number?) {
        coach = coachMode;
        Feedback.strong = coachMode;
        engine = new TimerEngine(wod, countdownSec != null ? countdownSec : propNumber("countdownSec", 10));
        _zoneBounds = Perf.bounds();
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
            history = ScoreHistory.load(wod, false);
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
        if (popText != null && t >= _popUntil) {
            popText = null;
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
            showFlash(Tr.s(due[i] == ALERT_HALF ? "HALFWAY" : "1 MIN LEFT"), Theme.WARN, 2000);
            Feedback.alert();
        }
    }

    function showFlash(text as String, color as Number, ms as Number) as Void {
        flashText = text;
        flashColor = color;
        _flashUntil = now() + ms;
        WatchUi.requestUpdate();
    }

    // The new movement in big letters for 1.5 s (easier than reading mid-rep).
    private function announceBlock() as Void {
        var b = engine.currentBlock();
        if (b == null || engine.state != ST_WORK) { return; }
        showFlash((b["name"] as String).toUpper(), Theme.WORK, 1500);
    }

    private function pop(delta as Number) as Void {
        popText = delta > 0 ? "+1" : "-1";
        _popUntil = now() + 700;
    }

    private function sampleHr() as Void {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentHeartRate == null) { return; }
        hr = info.currentHeartRate as Number;
        if (engine.state != ST_WORK && engine.state != ST_REST) { return; }
        if (hr > hrMax) { hrMax = hr; }
        zoneSec[Perf.zoneOf(hr, _zoneBounds)] += 1;
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
                    announceBlock();
                    mvClose();
                    mvOpen();
                }
            } else if (code == EV_REST) {
                Feedback.rest();
                mvClose();
            } else if (code == EV_BLOCK) {
                Feedback.block();
                updateCounter();
                announceBlock();
                mvClose();
                mvOpen();
            } else if (code == EV_ROUND) {
                roundTimes.add(engine.activeMs(now()));
                Feedback.round();
            } else if (code == EV_TARGET_DONE) {
                Feedback.block();
                if (engine.wodType == WT_EMOM && engine.intervalMs() > 0) {
                    intervalWorkMs.add(engine.activeMs(now()) % engine.intervalMs());
                }
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

    // ---------- per-movement tracking (one "set" = one block occurrence) ----------

    // Rep times of the current set, recorded before the engine sees the rep
    // (a rep that completes the set closes it inside handle()).
    private function noteRep(delta as Number) as Void {
        var b = engine.currentBlock();
        if (engine.state != ST_WORK || engine.intervalDone || b == null || !(b["unit"] as String).equals("reps")) { return; }
        if (delta > 0) {
            _setRepTimes.add(engine.activeMs(now()));
        } else if (_setRepTimes.size() > 0) {
            _setRepTimes = _setRepTimes.slice(0, _setRepTimes.size() - 1);
        }
    }

    private function mvOpen() as Void {
        _setRepTimes = [] as Array<Number>;
        var b = engine.currentBlock();
        if (b == null || (b["movement"] as String).equals("custom")) {
            _mvId = null;
            return;
        }
        _mvId = b["movement"] as String;
        _mvReps = (b["unit"] as String).equals("reps");
        _mvLoadKg = 0;
        var load = b["load"];
        if (load instanceof Array && (load as Array).size() > 0) {
            var side = propNumber("loadSide", 0);
            var l = load as Array<Number>;
            _mvLoadKg = side < l.size() ? l[side] : l[0];
        }
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
        if (ms <= 0) { return; }
        var d = Movements.domain(id);
        if (d >= 0) { domainMs[d] += ms; }
        if (!_mvReps || reps <= 0) { return; }

        var cur = movementStats[id];
        if (cur instanceof Array) {
            var c = cur as Array<Number>;
            movementStats[id] = [c[0] + reps, c[1] + ms];
        } else {
            movementStats[id] = [reps, ms];
        }
        var occ = occurrences[id];
        if (occ instanceof Array) {
            (occ as Array).add([reps, ms]);
        } else {
            occurrences[id] = [[reps, ms]];
        }
        tonnage += reps * _mvLoadKg;

        // breaks inside the set, time lost before the first rep
        var t = _setRepTimes;
        if (t.size() >= 2) {
            var n = Perf.countBreaks(t);
            breaks += n;
            sets++;
            if (n == 0) { unbrokenSets++; }
            var gaps = [] as Array<Number>;
            for (var i = 1; i < t.size(); i++) { gaps.add(t[i] - t[i - 1]); }
            var med = Perf.median(gaps);
            var lost = t[0] - _mvStartMs - med;
            if (lost > 0 && _mvStartMs > 0) { transitionMs += lost; }
        }
        _setRepTimes = [] as Array<Number>;
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
        pop(1);
        noteRep(1);
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
        if (engine.state == ST_WORK) { pop(delta); }
        noteRep(delta);
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
        if (!coach) { startHrr(); }
        if (!_summaryFromMenu) { getApp().onSessionDone(self); }
    }

    private function buildResult(active as Number) as Dictionary {
        var kind = "reps";
        if (engine.wodType == WT_AMRAP || engine.isDeathBy()) {
            kind = "rounds";
        } else if (engine.hasTimeScore()) {
            kind = "time";
        }
        return {
            "kind" => kind,
            "rounds" => engine.roundsCompleted,
            "reps" => engine.wodType == WT_AMRAP || engine.isDeathBy() ? engine.lapReps : engine.totalReps,
            "ms" => active,
            "t" => Time.now().value(),
            "laps" => roundTimes,
            "hr" => avgHr(),
            "hrMax" => hrMax,
            "trimp" => Perf.trimp(zoneSec),
            "zones" => zoneSec
        };
    }

    // ---------- after the workout ----------

    // Heart rate recovery: HR drop 60 s after the end, measured while the
    // athlete answers the RPE question and looks at the summary.
    private function startHrr() as Void {
        hrEnd = hr;
        hrNow = hr;
        _doneAt = now();
        if (hrEnd <= 0) { return; }
        _hrrTimer = new Timer.Timer();
        (_hrrTimer as Timer.Timer).start(method(:onHrrTick), 1000, true);
    }

    function onHrrTick() as Void {
        var info = Sensor.getInfo();
        if (info != null && info.heartRate != null) { hrNow = info.heartRate as Number; }
        hrrElapsedSec = (now() - _doneAt) / 1000;
        if (hrrElapsedSec >= 60) {
            hrr = hrEnd - hrNow;
            if (result != null) { (result as Dictionary)["hrr"] = hrr; }
            (_hrrTimer as Timer.Timer).stop();
            _hrrTimer = null;
        }
        WatchUi.requestUpdate();
    }

    function setRpe(v as Number?) as Void {
        rpe = v;
        if (result != null) { (result as Dictionary)["rpe"] = v; }
    }

    // Scaled results are compared with scaled results only.
    function setScaled(v as Boolean) as Void {
        scaled = v;
        if (result == null) { return; }
        (result as Dictionary)["scaled"] = v;
        history = ScoreHistory.load(engine.wod, v);
        isNewBest = history != null && ScoreHistory.isBetter(result as Dictionary, (history as Dictionary)["best"] as Dictionary);
    }

    // WOD with a load written in it (tonnage, RX / scaled question)
    function hasLoad() as Boolean {
        var blocks = engine.wod["blocks"] as Array<Dictionary>;
        for (var i = 0; i < blocks.size(); i++) {
            if (blocks[i]["load"] != null) { return true; }
        }
        return false;
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
            var r = result as Dictionary;
            var active = engine.finalActiveMs();
            var srpe = rpe != null ? Perf.srpeLoad(rpe as Number, active) : 0;
            var kg = scaled ? 0 : tonnage;
            r["srpe"] = srpe;
            r["tonnage"] = kg;
            ScoreHistory.save(engine.wod, r, scaled);
            ScoreHistory.addTotals(engine.totalReps, active, movementStats);
            Perf.addDay(Perf.today(), [Perf.trimp(zoneSec), srpe, domainMs[0], domainMs[1], domainMs[2], 1, kg,
                isNewBest ? 1 : 0]);
            if (hrr != null) { Perf.addHrr(Perf.today(), hrr as Number); }
        }
    }

    function discard() as Void {
        stopTimers();
        if (_hrrTimer != null) {
            (_hrrTimer as Timer.Timer).stop();
            _hrrTimer = null;
        }
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
