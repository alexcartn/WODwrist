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

    function pageCount() as Number {
        var n = _s.laps.size();
        return 1 + (n + SPLITS_PER_PAGE - 1) / SPLITS_PER_PAGE;
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
        } else {
            drawSplits(dc, w, h, cx, center);
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var hint = _s.hasRecording() ? "START save  BACK discard" : "BACK exit";
        dc.drawText(cx, h * 91 / 100, Graphics.FONT_XTINY, hint, center);
    }

    private function drawOverview(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var e = _s.engine;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_XTINY, e.wod["name"] as String, center);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 30 / 100, Graphics.FONT_LARGE, e.scoreText(), center);

        var lines = [] as Array<String>;
        lines.add("Time " + Str.clock(e.finalActiveMs(), false));
        if (e.wodType == WT_AMRAP || e.wodType == WT_FOR_TIME) {
            lines.add("Rounds " + e.roundsCompleted.format("%d") + "  Reps " + e.totalReps.format("%d"));
        } else {
            lines.add("Reps " + e.totalReps.format("%d"));
        }
        if (_s.hrMax > 0) {
            lines.add("HR avg " + _s.avgHr().format("%d") + "  max " + _s.hrMax.format("%d"));
        }
        if (_s.laps.size() > 1) {
            lines.add(_s.laps.size().format("%d") + " splits, scroll down");
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var y = h * 48 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(cx, y, Graphics.FONT_TINY, lines[i], center);
            y += lh;
        }
    }

    // "R3  1:02  12r  151" : lap, duration, reps, avg HR
    private function drawSplits(dc as Graphics.Dc, w as Number, h as Number, cx as Number, center as Number) as Void {
        var first = (page - 1) * SPLITS_PER_PAGE;
        var laps = _s.laps;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 14 / 100, Graphics.FONT_XTINY, "Splits " + page.format("%d") + "/" + (pageCount() - 1).format("%d"), center);
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
