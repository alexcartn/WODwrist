import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

const MENU_SAMPLE_BASE = 100;
const MENU_SYNC = 1000;
const MENU_COACH = 1001;
const MENU_ERROR = 1002;
const MENU_STATS = 1003;

// Stored WODs first (newest on top), then sync, coach toggle, samples.
function buildMainMenu() as WatchUi.Menu2 {
    var app = getApp();
    var menu = new WatchUi.Menu2({ :title => "WODwrist" });
    var list = app.sync.wods();
    for (var i = 0; i < list.size(); i++) {
        menu.addItem(new WatchUi.MenuItem(list[i]["name"] as String, WodFormat.headline(list[i]), i, {}));
    }
    if (app.sync.settingsError != null) {
        menu.addItem(new WatchUi.MenuItem("Settings WOD error", app.sync.settingsError as String, MENU_ERROR, {}));
    }
    menu.addItem(new WatchUi.MenuItem("Sync WOD", app.sync.hasUrl() ? "From coach page" : "Set URL in settings", MENU_SYNC, {}));
    var tot = ScoreHistory.totals();
    menu.addItem(new WatchUi.MenuItem("My stats", weekReportIsNew() ? "New weekly report" : (tot["n"] as Number).format("%d") + " workouts", MENU_STATS, {}));
    menu.addItem(new WatchUi.MenuItem("Coach", WorkoutSession.propBool("coachMode", false) ? "Class timer ON" : "Class timer, plan, alerts",
        MENU_COACH, {}));
    for (var i = 0; i < SampleWods.count(); i++) {
        var w = SampleWods.get(i);
        if (w != null) {
            menu.addItem(new WatchUi.MenuItem("Sample: " + (w["name"] as String), WodFormat.headline(w), MENU_SAMPLE_BASE + i, {}));
        }
    }
    return menu;
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var app = getApp();
        var id = item.getId() as Number;
        if (id == MENU_COACH) {
            app.menuOnTop = false;
            WatchUi.pushView(buildCoachMenu(), new CoachMenuDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == MENU_ERROR) {
            return;
        }
        if (id == MENU_STATS) {
            app.menuOnTop = false;
            WatchUi.pushView(buildStatsMenu(), new StatsMenuDelegate(), WatchUi.SLIDE_LEFT);
            return;
        }
        if (id == MENU_SYNC) {
            app.menuOnTop = false;
            var view = new SyncView();
            WatchUi.pushView(view, new SyncDelegate(), WatchUi.SLIDE_LEFT);
            app.sync.fetch(view.method(:onResult));
            return;
        }
        var wod = null;
        if (id >= MENU_SAMPLE_BASE) {
            wod = SampleWods.get(id - MENU_SAMPLE_BASE);
        } else {
            var list = app.sync.wods();
            if (id < list.size()) { wod = list[id]; }
        }
        if (wod == null) { return; }
        app.menuOnTop = false;
        WatchUi.pushView(new WodPreviewView(wod), new WodPreviewDelegate(wod), WatchUi.SLIDE_LEFT);
    }
}
