import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// WOD details before starting. START (or tap) starts, BACK returns.
class WodPreviewView extends WatchUi.View {

    private var _wod as Dictionary;

    function initialize(wod as Dictionary) {
        View.initialize();
        _wod = wod;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 14 / 100, Graphics.FONT_SMALL, _wod["name"] as String, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 26 / 100, Graphics.FONT_TINY, WodFormat.headline(_wod), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var blocks = _wod["blocks"] as Array<Dictionary>;
        var lineH = dc.getFontHeight(Graphics.FONT_XTINY);
        var maxLines = (h * 44 / 100) / lineH;
        var y = h * 36 / 100;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var shown = blocks.size() > maxLines ? maxLines - 1 : blocks.size();
        for (var i = 0; i < shown; i++) {
            var line = WodFormat.block(blocks[i]);
            var slot = blocks[i]["slot"];
            if (slot != null && isNewSlot(blocks, i)) {
                line = "M" + ((slot as Number) + 1).format("%d") + " " + line;
            }
            dc.drawText(cx, y, Graphics.FONT_XTINY, line, Graphics.TEXT_JUSTIFY_CENTER);
            y += lineH;
        }
        if (shown < blocks.size()) {
            dc.drawText(cx, y, Graphics.FONT_XTINY, "+" + (blocks.size() - shown).format("%d") + " more", Graphics.TEXT_JUSTIFY_CENTER);
        }

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        var mode = WorkoutSession.propBool("coachMode", false) ? "START: class timer" : "START: go";
        dc.drawText(cx, h * 88 / 100, Graphics.FONT_XTINY, mode, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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
        var app = getApp();
        var session = new WorkoutSession(_wod, WorkoutSession.propBool("coachMode", false));
        app.session = session;
        WatchUi.switchToView(new RunView(session), new RunDelegate(session), WatchUi.SLIDE_UP);
        session.begin();
        return true;
    }

    function onBack() as Boolean {
        getApp().backToMenu(1);
        return true;
    }
}
