import Toybox.Lang;
import Toybox.WatchUi;

function buildPauseMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => "Paused" });
    menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, {}));
    menu.addItem(new WatchUi.MenuItem("Finish", "Save the score", :finish, {}));
    menu.addItem(new WatchUi.MenuItem("Discard", "Throw away", :discard, {}));
    return menu;
}

class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _s as WorkoutSession;

    function initialize(session as WorkoutSession) {
        Menu2InputDelegate.initialize();
        _s = session;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            _s.resume();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :finish) {
            _s.finishEarly();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            _s.showSummary();
        } else if (id == :discard) {
            _s.discard();
            // stack: menu, run view, this menu
            getApp().backToMenu(2);
        }
    }

    function onBack() as Void {
        _s.resume();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
