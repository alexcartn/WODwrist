import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// After the workout: "how hard was it?" 1-10 (session RPE, Foster).
// UP / DOWN (or swipe) to change, START / tap to confirm, BACK to skip.
// Heart rate recovery is measured in the background meanwhile.
class RpeView extends WatchUi.View {

    var value as Number = 7;
    private var _s as WorkoutSession;

    function initialize(session as WorkoutSession) {
        View.initialize();
        _s = session;
    }

    static function label(v as Number) as String {
        var l = ["Very easy", "Easy", "Moderate", "Somewhat hard", "Hard",
                 "Hard +", "Very hard", "Very hard +", "Near max", "Max effort"];
        return Tr.s(l[v - 1] as String);
    }

    static function color(v as Number) as Number {
        if (v <= 3) { return Graphics.COLOR_GREEN; }
        if (v <= 6) { return Graphics.COLOR_YELLOW; }
        if (v <= 8) { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_RED;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 14 / 100, Graphics.FONT_XTINY, Tr.s("HOW HARD WAS IT?"), center);
        dc.setColor(color(value), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 40 / 100, Graphics.FONT_NUMBER_HOT, value.format("%d"), center);
        dc.drawText(cx, h * 60 / 100, Graphics.FONT_SMALL, label(value), center);

        // 10 small steps
        var x0 = w * 20 / 100;
        var step = w * 60 / 100 / 10;
        for (var i = 1; i <= 10; i++) {
            dc.setColor(i <= value ? color(i) : Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0 + (i - 1) * step + 1, h * 69 / 100, step - 2, h * 2 / 100);
        }

        if (_s.hrEnd > 0 && _s.hrr == null) {
            dc.setColor(Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 84 / 100, Graphics.FONT_XTINY,
                Tr.s("HR recovery") + " " + (60 - _s.hrrElapsedSec).format("%d") + " s", center);
        }
        Ui.buttonHint(dc, true, Theme.WORK, ICON_CHECK);
    }
}

class RpeDelegate extends WatchUi.BehaviorDelegate {

    private var _s as WorkoutSession;
    private var _v as RpeView;

    function initialize(session as WorkoutSession, view as RpeView) {
        BehaviorDelegate.initialize();
        _s = session;
        _v = view;
    }

    function onNextPage() as Boolean {
        if (_v.value > 1) { _v.value--; }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_v.value < 10) { _v.value++; }
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        _s.setRpe(_v.value);
        afterRpe(_s);
        return true;
    }

    function onBack() as Boolean {
        _s.setRpe(null);
        afterRpe(_s);
        return true;
    }
}

// RX or scaled (only for WODs with a load written in them), then the summary.
function afterRpe(s as WorkoutSession) as Void {
    if (!s.hasLoad()) {
        s.showSummary();
        return;
    }
    var menu = Ui.menu(Tr.s("Done as"));
    menu.addItem(new WatchUi.MenuItem(Tr.s("RX"), Tr.s("Load as written"), :rx, {}));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Scaled"), Tr.s("Lighter or modified"), :scaled, {}));
    WatchUi.switchToView(menu, new ScaledDelegate(s), WatchUi.SLIDE_LEFT);
}

class ScaledDelegate extends WatchUi.Menu2InputDelegate {

    private var _s as WorkoutSession;

    function initialize(session as WorkoutSession) {
        Menu2InputDelegate.initialize();
        _s = session;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _s.setScaled(item.getId() == :scaled);
        _s.showSummary();
    }

    function onBack() as Void {
        _s.setScaled(false);
        _s.showSummary();
    }
}
