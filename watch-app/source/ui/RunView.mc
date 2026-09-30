import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Workout screen. All positions are fractions of the screen so the same
// layout works on round (Venu, Forerunner) and square (Venu Sq) devices.
class RunView extends WatchUi.View {

    private var _s as WorkoutSession;

    function initialize(session as WorkoutSession) {
        View.initialize();
        _s = session;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var e = _s.engine;
        var now = System.getTimer();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // ---- status line ----
        var label = "WORK";
        var color = Graphics.COLOR_GREEN;
        if (e.state == ST_COUNTDOWN) {
            label = "GET READY";
            color = Graphics.COLOR_YELLOW;
        } else if (e.state == ST_REST) {
            label = "REST";
            color = Graphics.COLOR_BLUE;
        } else if (e.state == ST_PAUSED) {
            label = "PAUSED";
            color = Graphics.COLOR_ORANGE;
        } else if (e.state == ST_DONE) {
            label = "DONE";
            color = Graphics.COLOR_WHITE;
        } else if (e.intervalDone) {
            label = "DONE, WAIT";
            color = Graphics.COLOR_BLUE;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 11 / 100, Graphics.FONT_TINY, label, center);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 21 / 100, Graphics.FONT_TINY, roundText(e), center);

        // ---- clock ----
        var ms = e.clockMs(now);
        var clock;
        if (e.state == ST_COUNTDOWN) {
            clock = ((ms + 999) / 1000).format("%d");
        } else {
            clock = Str.clock(ms, e.clockCountsDown(now));
        }
        dc.setColor(e.state == ST_PAUSED ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (_s.coach) {
            dc.drawText(cx, h * 47 / 100, Graphics.FONT_NUMBER_THAI_HOT, clock, center);
        } else {
            dc.drawText(cx, h * 40 / 100, Graphics.FONT_NUMBER_HOT, clock, center);
        }

        // ---- movement ----
        var b = e.currentBlock();
        if (e.state == ST_COUNTDOWN || e.state == ST_IDLE) {
            var bl = e.currentBlocks();
            b = bl.size() > 0 ? bl[0] : null;
        }
        if (b != null && e.state != ST_DONE && !e.intervalDone) {
            var name = b["name"] as String;
            var unit = b["unit"] as String;
            var target = e.target(b);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (_s.coach) {
                dc.drawText(cx, h * 76 / 100, Graphics.FONT_SMALL, WodFormat.target(unit, target) + " " + name, center);
            } else {
                dc.drawText(cx, h * 62 / 100, Graphics.FONT_SMALL, name, center);
                var reps;
                if (unit.equals("reps")) {
                    reps = target > 0 ? e.blockReps.format("%d") + "/" + target.format("%d") : e.blockReps.format("%d");
                } else {
                    reps = WodFormat.target(unit, target);
                }
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 75 / 100, Graphics.FONT_MEDIUM, reps, center);
                drawConfidence(dc, cx + w * 22 / 100, h * 75 / 100, w);
            }
        }

        // ---- footer ----
        if (!_s.coach) {
            var foot = "Reps " + e.totalReps.format("%d");
            if (_s.hr > 0) { foot += "  HR " + _s.hr.format("%d"); }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 88 / 100, Graphics.FONT_XTINY, foot, center);
        }
    }

    private function roundText(e as TimerEngine) as String {
        var total = e.totalRounds();
        if (total == 0) {
            return "Rounds " + e.roundsCompleted.format("%d");
        }
        var r = e.round + 1 > total ? total : e.round + 1;
        return (e.isInterval() ? "Int " : "Round ") + r.format("%d") + "/" + total.format("%d");
    }

    // Small dot: green = regular rhythm, yellow = unsure, red = irregular.
    private function drawConfidence(dc as Graphics.Dc, x as Number, y as Number, w as Number) as Void {
        if (!_s.isAutoCounting()) { return; }
        var c = _s.confidence();
        if (c < 0) { return; }
        var color = c >= 80 ? Graphics.COLOR_GREEN : (c >= 50 ? Graphics.COLOR_YELLOW : Graphics.COLOR_RED);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var r = w / 60;
        dc.fillCircle(x, y, r < 3 ? 3 : r);
    }
}

// Controls during the workout (see docs/controls.md):
//   START / ENTER .......... pause menu
//   BACK short ............. +1 rep (or "done" on run / row / hold blocks)
//   BACK long .............. -1 rep
//   DOWN / UP (5 buttons) .. +1 / -1 rep
//   tap / hold ............. +1 / -1 rep
//   swipe left ............. next movement (credits the target reps)
class RunDelegate extends WatchUi.InputDelegate {

    private var _s as WorkoutSession;
    private var _backDownAt as Number = -1;
    const LONG_PRESS_MS = 700;

    function initialize(session as WorkoutSession) {
        InputDelegate.initialize();
        _s = session;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER) {
            openPauseMenu();
            return true;
        }
        if (key == WatchUi.KEY_DOWN) {
            _s.manualRep(1);
            return true;
        }
        if (key == WatchUi.KEY_UP) {
            _s.manualRep(-1);
            return true;
        }
        // BACK is handled on press/release to tell short from long presses.
        return key == WatchUi.KEY_ESC;
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ESC) {
            _backDownAt = System.getTimer();
            return true;
        }
        return false;
    }

    function onKeyReleased(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() != WatchUi.KEY_ESC || _backDownAt < 0) { return false; }
        var held = System.getTimer() - _backDownAt;
        _backDownAt = -1;
        _s.manualRep(held >= LONG_PRESS_MS ? -1 : 1);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _s.manualRep(1);
        return true;
    }

    function onHold(evt as WatchUi.ClickEvent) as Boolean {
        _s.manualRep(-1);
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        if (evt.getDirection() == WatchUi.SWIPE_LEFT) {
            _s.nextBlock();
        }
        // swallow the others: a stray swipe right must not leave the workout
        return true;
    }

    private function openPauseMenu() as Void {
        if (_s.finished) { return; }
        _s.pause();
        WatchUi.pushView(buildPauseMenu(), new PauseMenuDelegate(_s), WatchUi.SLIDE_UP);
    }
}
