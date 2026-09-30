import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Workout screen. All positions are fractions of the screen so the same
// layout works on round (Venu, Forerunner) and square (Venu Sq) devices.
class RunView extends WatchUi.View {

    private var _s as WorkoutSession;
    // data page (athlete): 0 clock, 1 reps, 2 heart rate. Swipe up / down.
    var page as Number = 0;
    const PAGES = 3;

    function initialize(session as WorkoutSession) {
        View.initialize();
        _s = session;
    }

    function nextPage(delta as Number) as Void {
        if (_s.coach) { return; }
        page = (page + delta + PAGES) % PAGES;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var e = _s.engine;
        var now = System.getTimer();
        var center = Ui.CENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // ---- state: word + color, reused by the ring ----
        var label = "WORK";
        var color = Theme.WORK;
        if (e.state == ST_COUNTDOWN) {
            label = "GET READY";
            color = Theme.SCORE;
        } else if (e.state == ST_REST) {
            label = "REST";
            color = Theme.REST;
        } else if (e.state == ST_PAUSED) {
            label = "PAUSED";
            color = Theme.WARN;
        } else if (e.state == ST_DONE) {
            label = "DONE";
            color = Theme.TEXT;
        } else if (e.intervalDone) {
            label = "DONE, WAIT";
            color = Theme.REST;
        } else if (e.taskActive) {
            // every-minute task on top of the main work
            label = "TASK";
            color = Theme.WARN;
        } else if (e.restLeftMs(now) >= 0) {
            // "Rest 1:00" block of a strength superset
            label = "REST";
            color = Theme.REST;
        }

        // ---- progress ring: countdown, cap, interval or tabata phase ----
        var seg = e.segment(now);
        if (seg != null) {
            Ui.ring(dc, (seg as Array<Number>)[0], (seg as Array<Number>)[1], color, _s.coach ? w / 28 : w / 40);
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 12 / 100, Graphics.FONT_TINY, Tr.s(label), center);

        if (e.state == ST_COUNTDOWN) {
            // what is about to start (and which part of the class plan)
            var title = e.wod["name"] as String;
            if (_s.partCount > 1) {
                title = (_s.partIndex + 1).format("%d") + "/" + _s.partCount.format("%d") + " " + title;
            }
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 22 / 100, Graphics.FONT_TINY, Ui.fit(dc, title, Graphics.FONT_TINY, Ui.widthAt(dc, h * 22 / 100)), center);
        } else {
            drawRoundLine(dc, e, cx, h * 22 / 100);
        }

        // ---- clock ----
        var ms = e.clockMs(now);
        var clock;
        if (e.state == ST_COUNTDOWN && ms < 60000) {
            clock = ((ms + 999) / 1000).format("%d");
        } else {
            clock = Str.clock(ms, e.clockCountsDown(now));
        }
        var clockColor = e.state == ST_PAUSED ? Theme.WARN : Theme.TEXT;
        if (!_s.coach && page != 0 && e.state != ST_COUNTDOWN) {
            drawDataPage(dc, e, w, h, cx, clock, clockColor);
            drawOverlays(dc, w, h, cx);
            return;
        }
        if (_s.coach) {
            Ui.drawClock(dc, clock, cx, h * 47 / 100, h * 30 / 100, clockColor);
        } else {
            Ui.drawClock(dc, clock, cx, h * 41 / 100, h * 22 / 100, clockColor);
        }

        // ---- movement ----
        var b = e.currentBlock();
        if (e.state == ST_COUNTDOWN || e.state == ST_IDLE) {
            var bl = e.currentBlocks();
            b = bl.size() > 0 ? bl[0] : null;
        }
        var waiting = e.state != ST_DONE && (e.intervalDone || e.state == ST_REST);
        // quick timer: no movement, BACK closes the round / the interval
        var quickRounds = QuickTimer.isQuick(e.wod) && e.wodType != WT_TABATA;
        if (quickRounds) {
            if (e.state == ST_WORK && !e.intervalDone) {
                var hint = Tr.s("BACK") + " = " + Tr.s(e.wodType == WT_EMOM ? "done" : "+1 round");
                dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * (_s.coach ? 76 : 68) / 100, Graphics.FONT_SMALL, Ui.fit(dc, hint, Graphics.FONT_SMALL, Ui.widthAt(dc, h * 68 / 100)), center);
            }
        } else if (waiting) {
            drawNext(dc, e, cx, h, center);
        } else if (b != null && e.state != ST_DONE && e.restLeftMs(now) >= 0) {
            // timed rest: the time left instead of a target, then the next movement by itself
            var left = Str.clock(e.restLeftMs(now), true);
            dc.setColor(Theme.REST, Graphics.COLOR_TRANSPARENT);
            if (_s.coach) {
                dc.drawText(cx, h * 76 / 100, Graphics.FONT_SMALL, Tr.s("Rest") + " " + left, center);
            } else {
                dc.drawText(cx, h * 62 / 100, Graphics.FONT_SMALL, Tr.s("Rest"), center);
                dc.drawText(cx, h * 75 / 100, Graphics.FONT_MEDIUM, left, center);
            }
        } else if (b != null && e.state != ST_DONE) {
            var name = b["name"] as String;
            var unit = b["unit"] as String;
            var target = e.target(b);
            dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
            if (_s.coach) {
                var line = WodFormat.target(unit, target) + " " + name;
                dc.drawText(cx, h * 76 / 100, Graphics.FONT_SMALL, Ui.fit(dc, line, Graphics.FONT_SMALL, Ui.widthAt(dc, h * 76 / 100)), center);
            } else {
                drawNameWithIcon(dc, b, cx, h * 62 / 100);
                var reps;
                if (unit.equals("reps")) {
                    reps = target > 0 ? e.blockReps.format("%d") + "/" + target.format("%d") : e.blockReps.format("%d");
                } else {
                    reps = WodFormat.target(unit, target);
                }
                dc.setColor(Theme.SCORE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 75 / 100, Graphics.FONT_MEDIUM, reps, center);
                // reps of this set as a short arc at the bottom of the ring
                if (unit.equals("reps") && target > 0) {
                    Ui.innerArc(dc, e.blockReps, target, Theme.SCORE, w / 40 + 8);
                }
                drawConfidence(dc, cx + w * 22 / 100, h * 75 / 100, w);
                // "+1" confirms a tap or a button press
                if (_s.popText != null) {
                    var p = _s.popText as String;
                    dc.setColor(Str.startsWith(p, "+") ? Theme.WORK : Theme.WARN, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(cx - w * 23 / 100, h * 75 / 100, Graphics.FONT_SMALL, p, center);
                }
            }
        }

        // ---- footer ----
        if (!_s.coach) {
            var foot = quickRounds ? "" : Tr.s("Reps") + " " + e.totalReps.format("%d");
            if (_s.hr > 0) { foot += (foot.length() > 0 ? "  " : "") + Tr.s("HR") + " " + _s.hr.format("%d"); }
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 87 / 100, Graphics.FONT_XTINY, foot, center);
        }
        drawOverlays(dc, w, h, cx);
    }

    // Banner (alerts, new movement), round celebration, page dots.
    private function drawOverlays(dc as Graphics.Dc, w as Number, h as Number, cx as Number) as Void {
        var center = Ui.CENTER;
        if (!_s.coach) { Ui.pageDots(dc, page, PAGES); }
        if (_s.flashText != null) {
            var fh = dc.getFontHeight(Graphics.FONT_MEDIUM);
            var fy = _s.coach ? h * 79 / 100 : h * 62 / 100;
            var bw = Ui.widthAt(dc, fy);
            dc.setColor(_s.flashColor, _s.flashColor);
            dc.fillRoundedRectangle(cx - bw / 2, fy - fh * 3 / 4, bw, fh * 3 / 2, fh / 3);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, fy, Graphics.FONT_MEDIUM, Ui.fit(dc, _s.flashText as String, Graphics.FONT_MEDIUM, bw - 8), center);
        }
        // ---- round completed: full screen for 1.5 s ----
        if (_s.celebrate != null) {
            var c = _s.celebrate as Array<String>;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillCircle(cx, h / 2, w / 2 - w / 30);
            if (!Ui.isRound()) { dc.fillRectangle(0, h / 20, w, h - h / 10); }
            dc.setColor(Theme.WORK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 27 / 100, Graphics.FONT_MEDIUM, c[0], center);
            Ui.drawClock(dc, c[1], cx, h * 50 / 100, h * 22 / 100, Theme.TEXT);
            if (c[2].length() > 0) {
                dc.setColor(_s.celebrateBest ? Theme.WORK : Theme.DANGER, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 72 / 100, Graphics.FONT_MEDIUM, c[2], center);
            }
        }
    }

    // Name with the movement pictogram on its left.
    private function drawNameWithIcon(dc as Graphics.Dc, b as Dictionary, cx as Number, y as Number) as Void {
        var font = Graphics.FONT_SMALL;
        var icon = Icons.forMovement(b["movement"] as String);
        var iw = icon == null ? 0 : (icon as WatchUi.BitmapResource).getWidth() + 6;
        var name = Ui.fit(dc, b["name"] as String, font, Ui.widthAt(dc, y) - iw);
        var tw = dc.getTextWidthInPixels(name, font);
        var x0 = cx - (tw + iw) / 2;
        if (icon != null) { Icons.draw(dc, icon, x0 + iw / 2 - 3, y); }
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + iw, y, font, name, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Page 1: the rep count in giant digits. Page 2: heart rate and zone.
    private function drawDataPage(dc as Graphics.Dc, e as TimerEngine, w as Number, h as Number, cx as Number,
            clock as String, clockColor as Number) as Void {
        var center = Ui.CENTER;
        if (page == 1 && QuickTimer.isQuick(e.wod) && e.wodType != WT_TABATA) {
            // quick timer: rounds (or interval) in giant digits, labelled by the line above
            var n = e.isInterval() ? e.round + 1 : e.roundsCompleted;
            Ui.drawClock(dc, n.format("%d"), cx, h * 52 / 100, h * 34 / 100, Theme.SCORE);
        } else if (page == 1) {
            var b = e.currentBlock();
            if (b != null && !e.intervalDone && e.state == ST_WORK) {
                drawNameWithIcon(dc, b, cx, h * 32 / 100);
                var target = e.target(b);
                var reps = e.blockReps.format("%d");
                var bigH = h * 30 / 100;
                var tail = target > 0 ? "/" + target.format("%d") : "";
                var rw = Ui.clockWidth(reps, bigH);
                var tw = dc.getTextWidthInPixels(tail, Graphics.FONT_MEDIUM);
                var x0 = cx - (rw + tw + 6) / 2;
                Ui.drawClock(dc, reps, x0 + rw / 2, h * 55 / 100, bigH, Theme.SCORE);
                dc.setColor(Theme.SCORE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x0 + rw + 6, h * 55 / 100 + bigH / 3, Graphics.FONT_MEDIUM, tail, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                if (_s.popText != null) {
                    dc.setColor(Theme.WORK, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(cx - w * 30 / 100, h * 55 / 100, Graphics.FONT_SMALL, _s.popText as String, center);
                }
            } else {
                dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 50 / 100, Graphics.FONT_SMALL, Tr.s(e.state == ST_REST || e.intervalDone ? "REST" : "DONE"), center);
            }
        } else {
            var z = _s.hrZone();
            var zc = [Theme.MUTED, Theme.MUTED, Theme.REST, Theme.WORK, Theme.WARN, Theme.DANGER];
            Ui.drawClock(dc, _s.hr > 0 ? _s.hr.format("%d") : "0", cx, h * 50 / 100, h * 26 / 100, zc[z] as Number);
            dc.setColor(zc[z] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 70 / 100, Graphics.FONT_SMALL,
                z > 0 ? Tr.s("Zone") + " " + z.format("%d") + "  bpm" : "bpm", center);
        }
        // small clock at the bottom of the data pages
        dc.setColor(clockColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 83 / 100, Graphics.FONT_MEDIUM, clock, center);
    }

    // While waiting (EMOM work done, Tabata rest): what comes next.
    private function drawNext(dc as Graphics.Dc, e as TimerEngine, cx as Number, h as Number, center as Number) as Void {
        if (!e.isInterval()) {
            // rest between the sets of a "3 x AMRAP"
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * (_s.coach ? 76 : 61) / 100, _s.coach ? Graphics.FONT_SMALL : Graphics.FONT_XTINY,
                Tr.s("NEXT") + ": " + Tr.s("Set") + " " + (e.set + 2).format("%d") + "/" + e.sets.format("%d"), center);
            return;
        }
        var next = e.nextBlocks();
        if (QuickTimer.isQuick(e.wod) && next.size() > 0) { return; }   // nothing to announce
        var parts = [] as Array<String>;
        for (var i = 0; i < next.size(); i++) { parts.add(WodFormat.block(next[i])); }
        var text = Str.join(parts, " + ");
        if (_s.coach) {
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            var c = next.size() > 0 ? Tr.s("Next") + ": " + text : Tr.s("Last interval");
            dc.drawText(cx, h * 76 / 100, Graphics.FONT_SMALL, Ui.fit(dc, c, Graphics.FONT_SMALL, Ui.widthAt(dc, h * 76 / 100)), center);
            return;
        }
        dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
        if (next.size() == 0) {
            dc.drawText(cx, h * 66 / 100, Graphics.FONT_SMALL, Tr.s("Last interval"), center);
            return;
        }
        dc.drawText(cx, h * 61 / 100, Graphics.FONT_XTINY, Tr.s("NEXT"), center);
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 72 / 100, Graphics.FONT_SMALL, Ui.fit(dc, text, Graphics.FONT_SMALL, Ui.widthAt(dc, h * 72 / 100)), center);
    }

    // "Rounds 3" + your pace vs your best at the same round: "-0:08" green, "+0:14" red.
    private function drawRoundLine(dc as Graphics.Dc, e as TimerEngine, cx as Number, y as Number) as Void {
        var text = roundText(e);
        var delta = e.state == ST_WORK || e.state == ST_PAUSED ? _s.paceDelta() : null;
        dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
        if (delta == null) {
            dc.drawText(cx, y, Graphics.FONT_TINY, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        text += "  ";
        var d = ScoreHistory.formatDelta(delta);
        var w1 = dc.getTextWidthInPixels(text, Graphics.FONT_TINY);
        var w2 = dc.getTextWidthInPixels(d, Graphics.FONT_TINY);
        var x = cx - (w1 + w2) / 2;
        dc.drawText(x, y, Graphics.FONT_TINY, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor((delta as Number) <= 0 ? Theme.WORK : Theme.DANGER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w1, y, Graphics.FONT_TINY, d, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function roundText(e as TimerEngine) as String {
        var total = e.totalRounds();
        if (e.sets > 1) {
            return Tr.s("Set") + " " + (e.set + 1).format("%d") + "/" + e.sets.format("%d") + "  "
                + Tr.s("Rounds") + " " + e.roundsCompleted.format("%d");
        }
        if (total == 0) {
            return Tr.s("Rounds") + " " + e.roundsCompleted.format("%d");
        }
        var r = e.round + 1 > total ? total : e.round + 1;
        return Tr.s(e.isInterval() ? "Int" : "Round") + " " + r.format("%d") + "/" + total.format("%d");
    }

    // Small dot: green = regular rhythm, yellow = unsure, red = irregular.
    private function drawConfidence(dc as Graphics.Dc, x as Number, y as Number, w as Number) as Void {
        if (!_s.isAutoCounting()) { return; }
        var c = _s.confidence();
        if (c < 0) { return; }
        var color = c >= 80 ? Theme.WORK : (c >= 50 ? Theme.SCORE : Theme.DANGER);
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
    private var _view as RunView? = null;
    // "Touch counts reps" setting: off = only the buttons count (sweat, stray taps)
    private var _touch as Boolean;
    const LONG_PRESS_MS = 700;

    function initialize(session as WorkoutSession) {
        InputDelegate.initialize();
        _s = session;
        _touch = WorkoutSession.propBool("touchReps", true);
    }

    function setView(v as RunView) as Void {
        _view = v;
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
        if (_touch) { _s.manualRep(1); }
        return true;
    }

    function onHold(evt as WatchUi.ClickEvent) as Boolean {
        if (_touch) { _s.manualRep(-1); }
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_LEFT) {
            _s.nextBlock();
        } else if (d == WatchUi.SWIPE_UP && _view != null) {
            (_view as RunView).nextPage(1);
        } else if (d == WatchUi.SWIPE_DOWN && _view != null) {
            (_view as RunView).nextPage(-1);
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
