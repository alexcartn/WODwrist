import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// End screen. Page 0: score and totals. Next pages: splits per lap.
// START saves, BACK asks to discard (athlete mode).
class SummaryView extends WatchUi.View {

    private var _s as WorkoutSession;
    var page as Number = 0;
    const SPLITS_PER_PAGE = 5;

    function initialize(session as WorkoutSession) {
        View.initialize();
        _s = session;
    }

    // page 0: score, 1: analysis, 2: details, 3: charts, 4+: splits
    function pageCount() as Number {
        var n = _s.laps.size();
        return 4 + (n + SPLITS_PER_PAGE - 1) / SPLITS_PER_PAGE;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (page == 0) {
            drawOverview(dc, w, h, cx, center);
        } else if (page == 1) {
            drawAnalysis(dc, w, h, cx, center);
        } else if (page == 2) {
            drawDetails(dc, h, cx, center);
        } else if (page == 3) {
            drawCharts(dc, w, h, cx, center);
        } else {
            drawSplits(dc, w, h, cx, center);
        }
        // Garmin-style hints next to the physical buttons, page dots on the right
        if (_s.hasRecording()) {
            Ui.buttonHint(dc, true, Theme.WORK, ICON_CHECK);
            Ui.buttonHint(dc, false, Theme.MUTED, ICON_CROSS);
        } else {
            Ui.buttonHint(dc, false, Theme.MUTED, ICON_CROSS);
        }
        Ui.pageDots(dc, page, pageCount());
    }

    private function drawOverview(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var e = _s.engine;
        dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_XTINY, Ui.fit(dc, e.wod["name"] as String, Graphics.FONT_XTINY, Ui.widthAt(dc, h * 13 / 100)), center);
        dc.setColor(Theme.SCORE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 28 / 100, Graphics.FONT_LARGE, e.scoreText(), center);
        // vs previous attempts at the same WOD
        if (_s.history != null) {
            if (_s.isNewBest) {
                dc.setColor(Theme.WORK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 38 / 100, Graphics.FONT_XTINY, Tr.s("NEW BEST"), center);
            } else {
                dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
                var best = (_s.history as Dictionary)["best"] as Dictionary;
                dc.drawText(cx, h * 38 / 100, Graphics.FONT_XTINY, Tr.s("Best") + " " + ScoreHistory.scoreText(best), center);
            }
        }

        var lines = [] as Array<String>;
        lines.add(Tr.s("Time") + " " + Str.clock(e.finalActiveMs(), false));
        if (e.wodType == WT_AMRAP || e.wodType == WT_FOR_TIME || e.isDeathBy()) {
            lines.add(Tr.s("Rounds") + " " + e.roundsCompleted.format("%d") + "  " + Tr.s("Reps") + " " + e.totalReps.format("%d"));
        } else {
            lines.add(Tr.s("Reps") + " " + e.totalReps.format("%d"));
        }
        if (_s.hrMax > 0) {
            lines.add(Tr.s("HR") + " " + _s.avgHr().format("%d") + " / " + _s.hrMax.format("%d"));
        }
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        var y = h * 50 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y, Graphics.FONT_TINY, lines[i], center);
            y += lh;
        }
    }

    // HR zone bar + load, pacing, EMOM density, fitness trend vs last time.
    private function drawAnalysis(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var e = _s.engine;
        dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_XTINY, Tr.s("ANALYSIS"), center);

        // time in zones 1..5 as one stacked bar
        var z = _s.zoneSec;
        var total = z[1] + z[2] + z[3] + z[4] + z[5];
        var x0 = w * 15 / 100;
        var bw = w * 70 / 100;
        var by = h * 21 / 100;
        var bh = h * 5 / 100;
        var lines = [] as Array<String>;
        var colors = [] as Array<Number>;
        if (total > 0) {
            var zc = [Theme.MUTED, Graphics.COLOR_BLUE, Graphics.COLOR_GREEN, Theme.WARN, Graphics.COLOR_RED];
            var x = x0;
            var top = 1;
            for (var i = 1; i <= 5; i++) {
                var seg = i == 5 ? x0 + bw - x : bw * z[i] / total;
                dc.setColor(zc[i - 1] as Number, Graphics.COLOR_TRANSPARENT);
                if (seg > 0) { dc.fillRectangle(x, by, seg, bh); }
                x += seg;
                if (z[i] > z[top]) { top = i; }
            }
            dc.setColor(Theme.SCORE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 33 / 100, Graphics.FONT_TINY, Tr.s("Load") + " " + Perf.trimp(z).format("%d"), center);
            lines.add(Tr.s("Mostly") + " Z" + top.format("%d") + " (" + ((z[top] + 30) / 60).format("%d") + " min)");
            colors.add(Theme.TEXT);
        } else {
            dc.drawText(cx, h * 30 / 100, Graphics.FONT_TINY, Tr.s("No heart rate"), center);
        }

        // pacing: round-to-round consistency and fade
        var rt = _s.roundTimes;
        if (rt.size() >= 2) {
            var d = [] as Array<Number>;
            for (var i = 0; i < rt.size(); i++) { d.add(rt[i] - (i > 0 ? rt[i - 1] : 0)); }
            var cv = Perf.cvPct(d);
            var fade = ScoreHistory.fadePct(rt);
            // variation of round times (low = even pacing)
            lines.add(Tr.s("Round var") + " " + (cv == null ? 0 : cv as Number).format("%d") + "%");
            colors.add(Theme.TEXT);
            if (fade != null) {
                // > 10 % slower on the last round: probably went out too fast
                var f = fade as Number;
                lines.add(Tr.s("Fade") + " " + (f >= 0 ? "+" : "") + f.format("%d") + "%");
                colors.add(f > 10 ? Theme.WARN : Theme.TEXT);
            }
        }

        // EMOM: how much of each interval was work (high = little rest)
        var dens = Perf.densityPct(_s.intervalWorkMs, e.intervalMs());
        if (e.wodType == WT_EMOM && dens != null) {
            lines.add(Tr.s("Work") + " " + (dens as Number).format("%d") + "% " + Tr.s("per interval"));
            colors.add((dens as Number) > 85 ? Theme.WARN : Theme.TEXT);
        }

        // same WOD, same or better score, lower HR = fitter
        if (_s.history != null && _s.result != null) {
            var trend = Perf.cardiacTrend((_s.history as Dictionary)["last"] as Dictionary, _s.result as Dictionary);
            if (trend != null) {
                var t = trend as Number;
                lines.add((t <= 0 ? Tr.s("Fitter") + ": " + t.format("%d") : Tr.s("HR") + " +" + t.format("%d")) + " bpm " + Tr.s("vs last"));
                colors.add(t <= 0 ? Theme.WORK : Theme.WARN);
            }
        }

        var y = h * 44 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < lines.size() && i < 4; i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_TINY, lines[i], center);
            y += lh;
        }
    }

    // Effort, recovery, sets, transitions, fatigue, cardiac drift, tonnage.
    private function drawDetails(dc as Graphics.Dc, h as Number, cx as Number, center as Number) as Void {
        var e = _s.engine;
        dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_XTINY, Tr.s("DETAILS"), center);
        var lines = [] as Array<String>;
        var colors = [] as Array<Number>;

        if (_s.rpe != null) {
            var r = _s.rpe as Number;
            lines.add("RPE " + r.format("%d") + "  " + Tr.s("Load").toLower() + " " + Perf.srpeLoad(r, e.finalActiveMs()).format("%d"));
            colors.add(RpeView.color(r));
        }
        if (_s.hrr != null) {
            // > 30 bpm in 1 min: good recovery, < 20: poor
            var v = _s.hrr as Number;
            lines.add(Tr.s("HR recovery") + " -" + v.format("%d") + " bpm");
            colors.add(v >= 30 ? Theme.WORK : (v < 20 ? Theme.WARN : Theme.TEXT));
        } else if (_s.hrEnd > 0) {
            lines.add(Tr.s("HR recovery in") + " " + (60 - _s.hrrElapsedSec).format("%d") + " s");
            colors.add(Theme.MUTED);
        }
        if (_s.sets > 0) {
            lines.add(Tr.s("Unbroken") + " " + _s.unbrokenSets.format("%d") + "/" + _s.sets.format("%d") + ", " + _s.breaks.format("%d") + " " + Tr.s("breaks"));
            colors.add(Theme.TEXT);
        }
        if (_s.transitionMs >= 1000) {
            lines.add(Tr.s("Transitions") + " " + Str.clock(_s.transitionMs, false));
            colors.add(Theme.TEXT);
        }
        var worst = worstFatigue();
        if (worst != null) {
            var wf = worst as Array;
            var f = wf[1] as Number;
            lines.add((wf[0] as String) + " " + (f >= 0 ? "+" : "") + f.format("%d") + "%");
            colors.add(f > 15 ? Theme.WARN : Theme.TEXT);
        }
        var drift = Perf.beatsDriftPct(completedLaps());
        if (drift != null) {
            var d = drift as Number;
            lines.add(Tr.s("Beats/round") + " " + (d >= 0 ? "+" : "") + d.format("%d") + "%");
            colors.add(d > 15 ? Theme.WARN : Theme.TEXT);
        }
        if (_s.tonnage > 0 && !_s.scaled) {
            lines.add(Tr.s("Moved") + " " + _s.tonnage.format("%d") + " kg");
            colors.add(Theme.TEXT);
        }
        if (lines.size() == 0) {
            lines.add(Tr.s("No details for this WOD"));
            colors.add(Theme.MUTED);
        }
        var y = h * 25 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < lines.size() && i < 6; i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_TINY, lines[i], center);
            y += lh;
        }
    }

    // Round times as bars (fastest green, slowest orange) and the HR curve.
    private function drawCharts(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var laps = completedLaps();
        // narrower than the screen: the button hints sit on the right edge
        var x0 = w * 20 / 100;
        var cw = w * 56 / 100;
        if (laps.size() >= 2) {
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 14 / 100, Graphics.FONT_XTINY, Tr.s("Rounds times"), center);
            var v = [] as Array<Number>;
            var lo = laps[0][0];
            var hi = laps[0][0];
            for (var i = 0; i < laps.size(); i++) {
                v.add(laps[i][0] / 1000);
                if (laps[i][0] < lo) { lo = laps[i][0]; }
                if (laps[i][0] > hi) { hi = laps[i][0]; }
            }
            var colors = [] as Array<Number>;
            for (var i = 0; i < laps.size(); i++) {
                colors.add(laps[i][0] == lo ? Theme.WORK : (laps[i][0] == hi ? Theme.WARN : Theme.MUTED));
            }
            Ui.bars(dc, v, colors, x0, h * 19 / 100, cw, h * 25 / 100, lo / 1000 * 8 / 10);
            dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 49 / 100, Graphics.FONT_XTINY,
                Str.clock(lo, false) + " - " + Str.clock(hi, false), center);
        }
        if (_s.hrTrace.size() >= 2) {
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 58 / 100, Graphics.FONT_XTINY, Tr.s("HR during the WOD"), center);
            Ui.line(dc, _s.hrTrace, Theme.DANGER, x0, h * 63 / 100, cw, h * 16 / 100);
            dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 85 / 100, Graphics.FONT_XTINY, _s.avgHr().format("%d") + " / " + _s.hrMax.format("%d") + " bpm", center);
        }
        if (laps.size() < 2 && _s.hrTrace.size() < 2) {
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Graphics.FONT_TINY, Tr.s("No data yet"), center);
        }
    }

    // Movement that slowed down the most: [name, % slower], or null.
    private function worstFatigue() as Array? {
        var ids = _s.occurrences.keys();
        var best = null;
        for (var i = 0; i < ids.size(); i++) {
            var f = Perf.fatiguePct(_s.occurrences[ids[i]] as Array<Array<Number> >);
            if (f != null && (best == null || (f as Number) > ((best as Array)[1] as Number))) {
                var name = Movements.name(ids[i] as String);
                best = [name == null ? ids[i] : name, f];
            }
        }
        return best;
    }

    // Laps that are full rounds: an AMRAP / Death by ends on a partial one.
    private function completedLaps() as Array<Array<Number> > {
        var l = _s.laps;
        var e = _s.engine;
        if ((e.wodType == WT_AMRAP || e.isDeathBy()) && l.size() > 0) { return l.slice(0, l.size() - 1); }
        return l;
    }

    // "R3  1:02  12r  151" : lap, duration, reps, avg HR
    private function drawSplits(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var first = (page - 4) * SPLITS_PER_PAGE;
        var laps = _s.laps;
        dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 14 / 100, Graphics.FONT_XTINY, Tr.s("Splits") + " " + (page - 3).format("%d") + "/" + (pageCount() - 4).format("%d"), center);
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        var y = h * 28 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = first; i < laps.size() && i < first + SPLITS_PER_PAGE; i++) {
            var l = laps[i];
            var s = "R" + (i + 1).format("%d") + "  " + Str.clock(l[0], false) + "  " + l[1].format("%d") + "r";
            if (l[2] > 0) { s += "  " + l[2].format("%d"); }
            dc.drawText(cx, y, Graphics.FONT_TINY, s, center);
            y += lh;
        }
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    private var _s as WorkoutSession;
    private var _view as SummaryView?;

    function initialize(session as WorkoutSession) {
        BehaviorDelegate.initialize();
        _s = session;
    }

    function setView(v as SummaryView) as Void {
        _view = v;
    }

    function onSelect() as Boolean {
        if (_s.hasRecording()) {
            _s.save();
            if (WatchUi has :showToast) {
                WatchUi.showToast(Tr.s("Save"), null);
            }
        }
        getApp().backToMenu(1);
        return true;
    }

    function onBack() as Boolean {
        if (!_s.hasRecording()) {
            getApp().backToMenu(1);
            return true;
        }
        WatchUi.pushView(new WatchUi.Confirmation("Discard workout?"), new DiscardConfirmDelegate(_s), WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function onNextPage() as Boolean {
        if (_view != null) {
            var v = _view as SummaryView;
            if (v.page < v.pageCount() - 1) {
                v.page++;
                WatchUi.requestUpdate();
            }
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view != null) {
            var v = _view as SummaryView;
            if (v.page > 0) {
                v.page--;
                WatchUi.requestUpdate();
            }
        }
        return true;
    }
}

class DiscardConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _s as WorkoutSession;

    function initialize(session as WorkoutSession) {
        ConfirmationDelegate.initialize();
        _s = session;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _s.discard();
            // the confirmation closes itself; this pops the summary
            getApp().backToMenu(1);
        }
        return true;
    }
}
