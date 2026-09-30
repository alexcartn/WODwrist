import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// WOD details before starting. START (or tap) starts, BACK returns.
class WodPreviewView extends WatchUi.View {

    private var _wod as Dictionary;
    private var _hist as Dictionary?;
    private var _ready as Array<Number> = [-1, -1] as Array<Number>;

    function initialize(wod as Dictionary) {
        View.initialize();
        _wod = wod;
        _hist = ScoreHistory.load(wod, false);
        _ready = Perf.readiness();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 13 / 100, Graphics.FONT_SMALL, Ui.fit(dc, _wod["name"] as String, Graphics.FONT_SMALL, Ui.widthAt(dc, h * 13 / 100)), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Theme.SCORE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 23 / 100, Graphics.FONT_TINY, WodFormat.headline(_wod), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // readiness: Garmin Body Battery and stress right now
        if (_ready[0] >= 0 || _ready[1] >= 0) {
            var r = "";
            if (_ready[0] >= 0) { r += Tr.s("Battery") + " " + _ready[0].format("%d"); }
            if (_ready[1] >= 0) { r += (r.length() > 0 ? "  " : "") + Tr.s("Stress") + " " + _ready[1].format("%d"); }
            var low = (_ready[0] >= 0 && _ready[0] < 25) || _ready[1] > 60;
            dc.setColor(low ? Theme.WARN : Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 33 / 100, Graphics.FONT_XTINY, r, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var blocks = _wod["blocks"] as Array<Dictionary>;
        var lineH = dc.getFontHeight(Graphics.FONT_XTINY);
        var maxLines = (h * 36 / 100) / lineH;
        var y = h * 39 / 100;
        dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
        var shown = blocks.size() > maxLines ? maxLines - 1 : blocks.size();
        for (var i = 0; i < shown; i++) {
            var line = WodFormat.block(blocks[i]);
            var ld = blocks[i]["load"];
            if (ld instanceof Array && (ld as Array).size() > 0) {
                var l = ld as Array<Number>;
                line += " @" + l[0].format("%d") + (l.size() > 1 ? "/" + l[1].format("%d") : "") + "kg";
            }
            var slot = blocks[i]["slot"];
            if (slot != null && isNewSlot(blocks, i)) {
                line = "M" + ((slot as Number) + 1).format("%d") + " " + line;
            }
            dc.drawText(cx, y, Graphics.FONT_XTINY, Ui.fit(dc, line, Graphics.FONT_XTINY, Ui.widthAt(dc, y + lineH / 2)), Graphics.TEXT_JUSTIFY_CENTER);
            y += lineH;
        }
        if (shown < blocks.size()) {
            dc.drawText(cx, y, Graphics.FONT_XTINY, "+" + (blocks.size() - shown).format("%d") + " " + Tr.s("more"), Graphics.TEXT_JUSTIFY_CENTER);
        }

        // score memory: "Best 8 + 3  Last 7 + 12"
        if (_hist != null) {
            var hist = _hist as Dictionary;
            var histLine = Tr.s("Best") + " " + ScoreHistory.scoreText(hist["best"] as Dictionary);
            if ((hist["n"] as Number) > 1) {
                histLine += "  " + Tr.s("Last") + " " + ScoreHistory.scoreText(hist["last"] as Dictionary);
            }
            dc.setColor(Theme.SCORE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 79 / 100, Graphics.FONT_XTINY, histLine, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        Ui.buttonHint(dc, true, WorkoutSession.propBool("coachMode", false) ? Theme.SCORE : Theme.WORK, ICON_PLAY);
    }

    private function isNewSlot(blocks as Array<Dictionary>, i as Number) as Boolean {
        return i == 0 || blocks[i - 1]["slot"] != blocks[i]["slot"];
    }
}

class WodPreviewDelegate extends WatchUi.BehaviorDelegate {

    private var _wod as Dictionary;

    function initialize(wod as Dictionary) {
        BehaviorDelegate.initialize();
        _wod = wod;
    }

    function onSelect() as Boolean {
        var coach = WorkoutSession.propBool("coachMode", false);
        // coach: start at the chosen time (next quarter, in 2 min...)
        getApp().startWorkout(_wod, coach, coach ? Coach.startDelaySec() : null, true);
        return true;
    }

    function onBack() as Boolean {
        // back to the main menu (sub-lists are replaced by the preview)
        getApp().backToMenu(1);
        return true;
    }
}
