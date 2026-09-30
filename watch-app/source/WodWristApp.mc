import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// (:glance): the app class is also loaded for the glance (widget list), where
// only glance code is available. Everything else is created lazily in the
// full app (getInitialView), never in the glance.
(:glance)
class WodWristApp extends Application.AppBase {

    private var _sync as SyncService? = null;
    private var _started as Boolean = false;
    var session as WorkoutSession? = null;
    // true while the main menu is the visible view (so a background sync can refresh it)
    var menuOnTop as Boolean = true;
    // class plan being run (coach), null otherwise
    var plan as Array<Dictionary>? = null;
    var planIndex as Number = 0;

    function initialize() {
        AppBase.initialize();
    }

    function syncSvc() as SyncService {
        if (_sync == null) { _sync = new SyncService(); }
        return _sync as SyncService;
    }

    // Settings text import and background URL sync, once, in the full app.
    private function startFullApp() as Void {
        if (_started) { return; }
        _started = true;
        syncSvc().importSettingsText();
        if (syncSvc().hasUrl()) {
            syncSvc().fetch(method(:onStartupSync));
        }
    }

    (:glance)
    function getGlanceView() as [WatchUi.GlanceView] or [WatchUi.GlanceView, WatchUi.GlanceViewDelegate] or Null {
        return [new WodGlanceView()];
    }

    function onStop(state as Dictionary?) as Void {
        if (session != null) {
            (session as WorkoutSession).abort();
            session = null;
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        startFullApp();
        // first launch without any WOD: a short how-to first
        if (Application.Storage.getValue("onboarded") != true && syncSvc().wods().size() == 0) {
            menuOnTop = false;
            var v = new OnboardView();
            return [v, new OnboardDelegate(v, true)];
        }
        return [buildMainMenu(), new MainMenuDelegate()];
    }

    function onSettingsChanged() as Void {
        if (!_started) { return; }  // glance: nothing to do
        syncSvc().importSettingsText();
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
        var v = new RunView(s);
        var d = new RunDelegate(s);
        d.setView(v);
        if (replace) {
            WatchUi.switchToView(v, d, WatchUi.SLIDE_UP);
        } else {
            WatchUi.pushView(v, d, WatchUi.SLIDE_UP);
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
