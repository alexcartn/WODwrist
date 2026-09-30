import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WodWristApp extends Application.AppBase {

    var sync as SyncService;
    var session as WorkoutSession? = null;
    // true while the main menu is the visible view (so a background sync can refresh it)
    var menuOnTop as Boolean = true;

    function initialize() {
        AppBase.initialize();
        sync = new SyncService();
    }

    function onStart(state as Dictionary?) as Void {
        sync.importSettingsText();
        if (sync.hasUrl()) {
            sync.fetch(method(:onStartupSync));
        }
    }

    function onStop(state as Dictionary?) as Void {
        if (session != null) {
            (session as WorkoutSession).abort();
            session = null;
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [buildMainMenu(), new MainMenuDelegate()];
    }

    function onSettingsChanged() as Void {
        sync.importSettingsText();
        refreshMenu();
    }

    function onStartupSync(ok as Boolean, msg as String) as Void {
        if (ok) { refreshMenu(); }
    }

    // Rebuild the menu in place when it is visible (new WODs, new settings).
    function refreshMenu() as Void {
        if (menuOnTop && session == null) {
            WatchUi.switchToView(buildMainMenu(), new MainMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
        }
    }

    // Pop `pops` views and show a fresh main menu.
    function backToMenu(pops as Number) as Void {
        for (var i = 0; i < pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        session = null;
        menuOnTop = true;
        WatchUi.switchToView(buildMainMenu(), new MainMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }
}

function getApp() as WodWristApp {
    return Application.getApp() as WodWristApp;
}
