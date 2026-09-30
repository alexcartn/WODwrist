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

    // page 0: score, 1: analysis, 2: details, 3+: splits
    function pageCount() as Number {
        var n = _s.laps.size();
        return 3 + (n + SPLITS_PER_PAGE - 1) / SPLITS_PER_PAGE;
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
        } else {
            drawSplits(dc, w, h, cx, center);
        }
        drawHints(dc, h, cx, center);
    }

    // Two short lines: one long line gets clipped by the bezel on round screens.
    private function drawHints(dc as Graphics.Dc, h as Number, cx as Number, center as Number) as Void {
        if (!_s.hasRecording()) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 87 / 100, Graphics.FONT_XTINY, "BACK exit", center);
            return;
        }
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 83 / 100, Graphics.FONT_XTINY, "START save", center);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 90 / 100, Graphics.FONT_XTINY, "BACK discard", center);
    }

    private function drawOverview(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var e = _s.engine;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_XTINY, e.wod["name"] as String, center);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 28 / 100, Graphics.FONT_LARGE, e.scoreText(), center);
        // vs previous attempts at the same WOD
        if (_s.history != null) {
            if (_s.isNewBest) {
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, h * 38 / 100, Graphics.FONT_XTINY, "NEW BEST", center);
            } else {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                var best = (_s.history as Dictionary)["best"] as Dictionary;
                dc.drawText(cx, h * 38 / 100, Graphics.FONT_XTINY, "Best " + ScoreHistory.scoreText(best), center);
            }
        }

        var lines = [] as Array<String>;
        lines.add("Time " + Str.clock(e.finalActiveMs(), false));
        if (e.wodType == WT_AMRAP || e.wodType == WT_FOR_TIME || e.isDeathBy()) {
            lines.add("Rounds " + e.roundsCompleted.format("%d") + "  Reps " + e.totalReps.format("%d"));
        } else {
            lines.add("Reps " + e.totalReps.format("%d"));
        }
        if (_s.hrMax > 0) {
            lines.add("HR avg " + _s.avgHr().format("%d") + "  max " + _s.hrMax.format("%d"));
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var y = h * 46 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y, Graphics.FONT_TINY, lines[i], center);
            y += lh;
        }
        // "Analysis" + a small down arrow: scroll for analysis and splits
        var ay = y - lh / 4;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w * 3 / 100, ay, Graphics.FONT_XTINY, "Analysis", center);
        var ax = cx + w * 14 / 100;
        var s = w / 40;
        dc.fillPolygon([[ax - s, ay - s / 2], [ax + s, ay - s / 2], [ax, ay + s]]);
    }

    // HR zone bar + load, pacing, EMOM density, fitness trend vs last time.
    private function drawAnalysis(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var e = _s.engine;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_XTINY, "ANALYSIS", center);

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
            var zc = [Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLUE, Graphics.COLOR_GREEN, Graphics.COLOR_ORANGE, Graphics.COLOR_RED];
            var x = x0;
            var top = 1;
            for (var i = 1; i <= 5; i++) {
                var seg = i == 5 ? x0 + bw - x : bw * z[i] / total;
                dc.setColor(zc[i - 1] as Number, Graphics.COLOR_TRANSPARENT);
                if (seg > 0) { dc.fillRectangle(x, by, seg, bh); }
                x += seg;
                if (z[i] > z[top]) { top = i; }
            }
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 33 / 100, Graphics.FONT_TINY, "Load " + Perf.trimp(z).format("%d"), center);
            lines.add("Mostly Z" + top.format("%d") + " (" + ((z[top] + 30) / 60).format("%d") + " min)");
            colors.add(Graphics.COLOR_WHITE);
        } else {
            dc.drawText(cx, h * 30 / 100, Graphics.FONT_TINY, "No heart rate", center);
        }

        // pacing: round-to-round consistency and fade
        var rt = _s.roundTimes;
        if (rt.size() >= 2) {
            var d = [] as Array<Number>;
            for (var i = 0; i < rt.size(); i++) { d.add(rt[i] - (i > 0 ? rt[i - 1] : 0)); }
            var cv = Perf.cvPct(d);
            var fade = ScoreHistory.fadePct(rt);
            // variation of round times (low = even pacing)
            lines.add("Round var " + (cv == null ? 0 : cv as Number).format("%d") + "%");
            colors.add(Graphics.COLOR_WHITE);
            if (fade != null) {
                // > 10 % slower on the last round: probably went out too fast
                var f = fade as Number;
                lines.add("Fade " + (f >= 0 ? "+" : "") + f.format("%d") + "%");
                colors.add(f > 10 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE);
            }
        }

        // EMOM: how much of each interval was work (high = little rest)
        var dens = Perf.densityPct(_s.intervalWorkMs, e.intervalMs());
        if (e.wodType == WT_EMOM && dens != null) {
            lines.add("Work " + (dens as Number).format("%d") + "% / interval");
            colors.add((dens as Number) > 85 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE);
        }

        // same WOD, same or better score, lower HR = fitter
        if (_s.history != null && _s.result != null) {
            var trend = Perf.cardiacTrend((_s.history as Dictionary)["last"] as Dictionary, _s.result as Dictionary);
            if (trend != null) {
                var t = trend as Number;
                lines.add(t <= 0 ? "Fitter: " + t.format("%d") + " bpm vs last" : "HR +" + t.format("%d") + " bpm vs last");
                colors.add(t <= 0 ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE);
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
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_XTINY, "DETAILS", center);
        var lines = [] as Array<String>;
        var colors = [] as Array<Number>;

        if (_s.rpe != null) {
            var r = _s.rpe as Number;
            lines.add("RPE " + r.format("%d") + "  load " + Perf.srpeLoad(r, e.finalActiveMs()).format("%d"));
            colors.add(RpeView.color(r));
        }
        if (_s.hrr != null) {
            // > 30 bpm in 1 min: good recovery, < 20: poor
            var v = _s.hrr as Number;
            lines.add("HR recovery -" + v.format("%d") + " bpm");
            colors.add(v >= 30 ? Graphics.COLOR_GREEN : (v < 20 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE));
        } else if (_s.hrEnd > 0) {
            lines.add("HR recovery in " + (60 - _s.hrrElapsedSec).format("%d") + " s");
            colors.add(Graphics.COLOR_LT_GRAY);
        }
        if (_s.sets > 0) {
            lines.add("Unbroken " + _s.unbrokenSets.format("%d") + "/" + _s.sets.format("%d") + ", " + _s.breaks.format("%d") + " breaks");
            colors.add(Graphics.COLOR_WHITE);
        }
        if (_s.transitionMs >= 1000) {
            lines.add("Transitions " + Str.clock(_s.transitionMs, false));
            colors.add(Graphics.COLOR_WHITE);
        }
        var worst = worstFatigue();
        if (worst != null) {
            var wf = worst as Array;
            var f = wf[1] as Number;
            lines.add((wf[0] as String) + " " + (f >= 0 ? "+" : "") + f.format("%d") + "%");
            colors.add(f > 15 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE);
        }
        var drift = Perf.beatsDriftPct(completedLaps());
        if (drift != null) {
            var d = drift as Number;
            lines.add("Beats/round " + (d >= 0 ? "+" : "") + d.format("%d") + "%");
            colors.add(d > 15 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE);
        }
        if (_s.tonnage > 0 && !_s.scaled) {
            lines.add("Moved " + _s.tonnage.format("%d") + " kg");
            colors.add(Graphics.COLOR_WHITE);
        }
        if (lines.size() == 0) {
            lines.add("No details for this WOD");
            colors.add(Graphics.COLOR_LT_GRAY);
        }
        var y = h * 25 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < lines.size() && i < 6; i++) {
            dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, Graphics.FONT_TINY, lines[i], center);
            y += lh;
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
        var first = (page - 3) * SPLITS_PER_PAGE;
        var laps = _s.laps;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 14 / 100, Graphics.FONT_XTINY, "Splits " + (page - 2).format("%d") + "/" + (pageCount() - 3).format("%d"), center);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
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
                WatchUi.showToast("Saved", null);
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
