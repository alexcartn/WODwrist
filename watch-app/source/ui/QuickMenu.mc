import Toybox.Lang;
import Toybox.WatchUi;

// Quick timer menu: Start on top, then the type and its settings.
// Tap a row = next value (wraps). Changing the type rebuilds the rows.
function buildQuickMenu(cfg as Dictionary<String, Number>) as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => Tr.s("Quick timer") });
    menu.addItem(Icons.menuItem(Tr.s("Start timer"), (QuickTimer.wod(cfg)["name"] as String), "go", "m_play"));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Type"), QuickTimer.label(cfg, "type"), "type", {}));
    var rows = QuickTimer.rows(cfg["type"] as Number);
    for (var i = 0; i < rows.size(); i++) {
        menu.addItem(new WatchUi.MenuItem(QuickTimer.rowTitle(rows[i]), QuickTimer.label(cfg, rows[i]), rows[i], {}));
    }
    return menu;
}

function openQuickMenu(replace as Boolean) as Void {
    var cfg = QuickTimer.load();
    var menu = buildQuickMenu(cfg);
    var d = new QuickMenuDelegate(menu, cfg);
    if (replace) {
        menu.setFocus(1);   // stay on the type row
        WatchUi.switchToView(menu, d, WatchUi.SLIDE_IMMEDIATE);
    } else {
        WatchUi.pushView(menu, d, WatchUi.SLIDE_LEFT);
    }
}

class QuickMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as WatchUi.Menu2;
    private var _cfg as Dictionary<String, Number>;

    function initialize(menu as WatchUi.Menu2, cfg as Dictionary<String, Number>) {
        Menu2InputDelegate.initialize();
        _menu = menu;
        _cfg = cfg;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        if (id.equals("go")) {
            QuickTimer.save(_cfg);
            var coach = WorkoutSession.propBool("coachMode", false);
            // the run view replaces this menu: stack [main menu, run]
            getApp().startWorkout(QuickTimer.wod(_cfg), coach, coach ? Coach.startDelaySec() : null, true);
            return;
        }
        QuickTimer.cycle(_cfg, id);
        QuickTimer.save(_cfg);
        if (id.equals("type")) {
            // other rows for the new type
            openQuickMenu(true);
            return;
        }
        item.setSubLabel(QuickTimer.label(_cfg, id));
        var go = _menu.getItem(0);
        if (go != null) { (go as WatchUi.MenuItem).setSubLabel(QuickTimer.wod(_cfg)["name"] as String); }
        WatchUi.requestUpdate();
    }

    function onBack() as Void {
        getApp().backToMenu(1);
    }
}
