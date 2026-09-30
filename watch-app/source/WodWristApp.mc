import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class WodWristApp extends Application.AppBase {

    var sync as SyncService;
    var session as WorkoutSession? = null;
    // true while the main menu is the visible view (so a background sync can refresh it)
    var menuOnTop as Boolean = true;
    // class plan being run (coach), null otherwise
    var plan as Array<Dictionary>? = null;
    var planIndex as Number = 0;

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
        // first launch without any WOD: a short how-to first
        if (Application.Storage.getValue("onboarded") != true && sync.wods().size() == 0) {
            menuOnTop = false;
            var v = new OnboardView();
            return [v, new OnboardDelegate(v, true)];
        }
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

    // Show the run screen for a new workout. replace = switch the current
    // view (preview, previous part), otherwise push over the main menu.
    function startWorkout(wod as Dictionary, coachMode as Boolean, countdownSec as Number?, replace as Boolean) as Void {
        var s = new WorkoutSession(wod, coachMode, countdownSec);
        if (plan != null) {
            s.partIndex = planIndex;
            s.partCount = (plan as Array<Dictionary>).size();
        }
        session = s;
        menuOnTop = false;
        if (replace) {
            WatchUi.switchToView(new RunView(s), new RunDelegate(s), WatchUi.SLIDE_UP);
        } else {
            WatchUi.pushView(new RunView(s), new RunDelegate(s), WatchUi.SLIDE_UP);
        }
        s.begin();
    }

    // Coach: run every part of the stored plan back to back.
    function startPlan() as Void {
        var p = Coach.plan();
        if (p.size() == 0) { return; }
        plan = p;
        planIndex = 0;
        startWorkout(p[0], true, Coach.startDelaySec(), false);
    }

    // A workout ended (time up, target reached, or Finish in the pause menu).
    function onSessionDone(s as WorkoutSession) as Void {
        if (plan != null && planIndex + 1 < (plan as Array<Dictionary>).size()) {
            // keep the finished part if the coach records, then chain the next one
            if (s.hasRecording()) { s.save(); }
            planIndex++;
            startWorkout((plan as Array<Dictionary>)[planIndex], true, Coach.restSec(), true);
            return;
        }
        plan = null;
        if (s.coach) {
            s.showSummary();
            return;
        }
        // athlete: effort 1-10 first (and RX / scaled), then the summary
        var v = new RpeView(s);
        WatchUi.switchToView(v, new RpeDelegate(s, v), WatchUi.SLIDE_UP);
    }

    // Pop `pops` views and show a fresh main menu.
    function backToMenu(pops as Number) as Void {
        for (var i = 0; i < pops; i++) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
        session = null;
        plan = null;
        menuOnTop = true;
        WatchUi.switchToView(buildMainMenu(), new MainMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }
}

function getApp() as WodWristApp {
    return Application.getApp() as WodWristApp;
}
