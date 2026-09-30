import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

const MENU_SAMPLE_BASE = 100;
const MENU_SYNC = 1000;
const MENU_COACH = 1001;
const MENU_ERROR = 1002;
const MENU_STATS = 1003;
const MENU_MY_WODS = 1004;
const MENU_SAMPLES = 1005;
const MENU_ONBOARD = 1006;
const MENU_QUICK = 1007;
const MENU_PLAN = 1008;

// Today's WOD on top, quick timer, then my WODs, stats, coach, sync, samples.
function buildMainMenu() as WatchUi.Menu2 {
    var app = getApp();
    var menu = new WatchUi.Menu2({ :title => "WODwrist" });
    var list = app.syncSvc().wods();
    if (list.size() > 0) {
        menu.addItem(Icons.menuItem(list[0]["name"] as String,
            Tr.s("Today") + " - " + WodFormat.headline(list[0]), 0, "m_play"));
    } else {
        menu.addItem(Icons.menuItem(Tr.s("Get started"), Tr.s("No WOD yet"), MENU_ONBOARD, "m_play"));
    }
    // the day's parts from the coach URL (strength, metcon, bonus), back to back
    var plan = Coach.plan();
    if (plan.size() > 1) {
        menu.addItem(Icons.menuItem(Tr.s("Today's plan"), plan.size().format("%d") + " " + Tr.s("parts"), MENU_PLAN, "m_list"));
    }
    menu.addItem(Icons.menuItem(Tr.s("Quick timer"), Tr.s("No WOD needed"), MENU_QUICK, "m_quick"));
    if (app.syncSvc().settingsError != null) {
        menu.addItem(new WatchUi.MenuItem(Tr.s("Settings WOD error"), app.syncSvc().settingsError as String, MENU_ERROR, {}));
    }
    if (list.size() > 1) {
        menu.addItem(Icons.menuItem(Tr.s("My WODs"), list.size().format("%d") + " WODs", MENU_MY_WODS, "m_list"));
    }
    var tot = ScoreHistory.totals();
    menu.addItem(Icons.menuItem(Tr.s("My stats"),
        weekReportIsNew() ? Tr.s("New weekly report") : (tot["n"] as Number).format("%d") + " " + Tr.s("workouts"), MENU_STATS, "m_stats"));
    menu.addItem(Icons.menuItem(Tr.s("Coach"),
        WorkoutSession.propBool("coachMode", false) ? Tr.s("Class timer") + " ON" : null, MENU_COACH, "m_coach"));
    menu.addItem(Icons.menuItem(Tr.s("Sync WOD"), syncLabel(), MENU_SYNC, "m_sync"));
    menu.addItem(Icons.menuItem(Tr.s("Samples"), Tr.s("Try a built-in WOD"), MENU_SAMPLES, "m_star"));
    return menu;
}

// "Synced 7:02" today, "Synced 3d ago", or what to do.
function syncLabel() as String {
    if (!getApp().syncSvc().hasUrl()) { return Tr.s("Set URL in settings"); }
    var last = Application.Storage.getValue("lastSync");
    if (!(last instanceof Number)) { return Tr.s("Never synced"); }
    var t = last as Number;
    var midnight = Time.today().value();
    if (t >= midnight) {
        var i = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT);
        return Tr.s("Synced") + " " + (i.hour as Number).format("%d") + ":" + (i.min as Number).format("%02d");
    }
    var days = (midnight - t) / 86400 + 1;
    return Tr.s("Synced") + " -" + days.format("%d") + "d";
}

function buildWodListMenu(title as String, wods as Array<Dictionary?>, idBase as Number) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => title });
    for (var i = 0; i < wods.size(); i++) {
        var w = wods[i];
        if (w != null) {
            menu.addItem(new WatchUi.MenuItem(w["name"] as String, WodFormat.headline(w), idBase + i, {}));
        }
    }
    return menu;
}

function openPreview(wod as Dictionary, replace as Boolean) as Void {
    getApp().menuOnTop = false;
    if (replace) {
        WatchUi.switchToView(new WodPreviewView(wod), new WodPreviewDelegate(wod), WatchUi.SLIDE_LEFT);
    } else {
        WatchUi.pushView(new WodPreviewView(wod), new WodPreviewDelegate(wod), WatchUi.SLIDE_LEFT);
    }
}

// id < 100: stored WOD index, id >= 100: sample.
function wodForId(id as Number) as Dictionary? {
    if (id >= MENU_SAMPLE_BASE) { return SampleWods.get(id - MENU_SAMPLE_BASE); }
    var list = getApp().syncSvc().wods();
    return id < list.size() ? list[id] : null;
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var app = getApp();
        var id = item.getId() as Number;
        if (id == MENU_ERROR) {
            return;
        }
        app.menuOnTop = false;
        if (id == MENU_PLAN) {
            app.startPlan(false);
        } else if (id == MENU_QUICK) {
            openQuickMenu(false);
        } else if (id == MENU_COACH) {
            WatchUi.pushView(buildCoachMenu(), new CoachMenuDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == MENU_STATS) {
            WatchUi.pushView(buildStatsMenu(), new StatsMenuDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == MENU_SYNC) {
            var view = new SyncView();
            WatchUi.pushView(view, new SyncDelegate(), WatchUi.SLIDE_LEFT);
            app.syncSvc().fetch(view.method(:onResult));
        } else if (id == MENU_ONBOARD) {
            var v = new OnboardView();
            WatchUi.pushView(v, new OnboardDelegate(v, false), WatchUi.SLIDE_LEFT);
        } else if (id == MENU_MY_WODS) {
            WatchUi.pushView(buildWodListMenu(Tr.s("My WODs"), app.syncSvc().wods() as Array<Dictionary?>, 0),
                new WodListDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == MENU_SAMPLES) {
            var samples = [] as Array<Dictionary?>;
            for (var i = 0; i < SampleWods.count(); i++) { samples.add(SampleWods.get(i)); }
            WatchUi.pushView(buildWodListMenu(Tr.s("Samples"), samples, MENU_SAMPLE_BASE),
                new WodListDelegate(), WatchUi.SLIDE_LEFT);
        } else {
            var wod = wodForId(id);
            if (wod != null) { openPreview(wod, false); }
        }
    }
}

// Sub-list (my WODs, samples): the preview replaces the list so that the
// stack stays [main menu, preview / run / summary].
class WodListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var wod = wodForId(item.getId() as Number);
        if (wod != null) { openPreview(wod, true); }
    }

    function onBack() as Void {
        getApp().backToMenu(1);
    }
}
