import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// "Syncing..." then the result of the URL fetch.
class SyncView extends WatchUi.View {

    private var _msg as String = "Syncing...";
    private var _ok as Boolean = true;

    function initialize() {
        View.initialize();
    }

    function onResult(ok as Boolean, msg as String) as Void {
        _ok = ok;
        _msg = msg;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(_ok ? Graphics.COLOR_WHITE : Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        // fitTextToArea wraps long error messages on small screens
        var text = _msg;
        if (Graphics has :fitTextToArea) {
            var fitted = Graphics.fitTextToArea(_msg, Graphics.FONT_SMALL, w * 80 / 100, h * 60 / 100, true);
            if (fitted != null) { text = fitted; }
        }
        dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class SyncDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        getApp().backToMenu(1);
        return true;
    }

    function onSelect() as Boolean {
        return onBack();
    }
}
