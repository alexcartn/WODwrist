import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

const ONBOARD_PAGES = 3;

// First launch: 3 short pages on how to get a WOD on the watch.
class OnboardView extends WatchUi.View {

    var page as Number = 0;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var titles = ["WODwrist", "1. " + Tr.s("Phone"), "2. " + Tr.s("Coach")];
        var bodies = [
            Tr.s("Your WOD on the wrist: timer, reps, rounds, heart rate."),
            Tr.s("Garmin Connect > WODwrist > Settings > WOD text. Example: AMRAP 12; 10 burpees"),
            Tr.s("Coach page? Paste its URL in the settings, then Sync WOD. Or try a sample.")
        ];
        dc.setColor(page == 0 ? Theme.WORK : Theme.SCORE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 22 / 100, Graphics.FONT_MEDIUM, titles[page] as String, Ui.CENTER);
        var body = bodies[page] as String;
        if (Graphics has :fitTextToArea) {
            var f = Graphics.fitTextToArea(body, Graphics.FONT_SMALL, w * 76 / 100, h * 40 / 100, true);
            if (f != null) { body = f; }
        }
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 52 / 100, Graphics.FONT_SMALL, body, Ui.CENTER);
        Ui.pageDots(dc, page, ONBOARD_PAGES);
        Ui.buttonHint(dc, true, Theme.WORK, page < ONBOARD_PAGES - 1 ? ICON_PLAY : ICON_CHECK);
    }
}

class OnboardDelegate extends WatchUi.BehaviorDelegate {

    private var _v as OnboardView;
    private var _first as Boolean;  // shown at first launch instead of the menu

    function initialize(view as OnboardView, first as Boolean) {
        BehaviorDelegate.initialize();
        _v = view;
        _first = first;
    }

    function onSelect() as Boolean {
        if (_v.page < ONBOARD_PAGES - 1) {
            _v.page++;
            WatchUi.requestUpdate();
            return true;
        }
        return done();
    }

    function onNextPage() as Boolean {
        return onSelect();
    }

    function onPreviousPage() as Boolean {
        if (_v.page > 0) {
            _v.page--;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onBack() as Boolean {
        return done();
    }

    private function done() as Boolean {
        Application.Storage.setValue("onboarded", true);
        if (_first) {
            getApp().menuOnTop = true;
            WatchUi.switchToView(buildMainMenu(), new MainMenuDelegate(), WatchUi.SLIDE_LEFT);
        } else {
            getApp().backToMenu(1);
        }
        return true;
    }
}
