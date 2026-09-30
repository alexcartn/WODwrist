import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Coach menu: class timer mode, class plan, start time, rest, alerts.
function buildCoachMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => Tr.s("Coach") });
    menu.addItem(new WatchUi.ToggleMenuItem(Tr.s("Class timer"), Tr.s("Big clock, no recording"), :coachMode,
        WorkoutSession.propBool("coachMode", false), {}));
    var plan = Coach.plan();
    if (plan.size() > 1) {
        menu.addItem(new WatchUi.MenuItem(Tr.s("Run class plan"), plan.size().format("%d") + " parts", :plan, {}));
    } else {
        menu.addItem(new WatchUi.MenuItem(Tr.s("Run class plan"), "Publish parts with --- then sync", :noPlan, {}));
    }
    menu.addItem(new WatchUi.MenuItem(Tr.s("Start"), Coach.startLabel(Coach.startOption()), :start, {}));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Rest between parts"), restLabel(Coach.restSec()), :rest, {}));
    menu.addItem(new WatchUi.ToggleMenuItem(Tr.s("Halfway alert"), null, :alertHalf,
        WorkoutSession.propBool("alertHalf", false), {}));
    menu.addItem(new WatchUi.ToggleMenuItem(Tr.s("1 min left alert"), null, :alertOneMin,
        WorkoutSession.propBool("alertOneMin", true), {}));
    return menu;
}

function restLabel(sec as Number) as String {
    return sec == 0 ? "None" : Str.clock(sec * 1000, false);
}

const REST_CHOICES = [30, 60, 90, 120, 180, 0];

class CoachMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :coachMode || id == :alertHalf || id == :alertOneMin) {
            var key = id == :coachMode ? "coachMode" : (id == :alertHalf ? "alertHalf" : "alertOneMin");
            Application.Properties.setValue(key, (item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id == :start) {
            // tap cycles through the options
            var next = (Coach.startOption() + 1) % 5;
            Application.Properties.setValue("coachStart", next);
            item.setSubLabel(Coach.startLabel(next));
        } else if (id == :rest) {
            var cur = Coach.restSec();
            var idx = 0;
            for (var i = 0; i < REST_CHOICES.size(); i++) {
                if (REST_CHOICES[i] == cur) { idx = (i + 1) % REST_CHOICES.size(); }
            }
            var v = REST_CHOICES[idx] as Number;
            Application.Properties.setValue("planRestSec", v);
            item.setSubLabel(restLabel(v));
        } else if (id == :plan) {
            // leave only the main menu under the workout
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            getApp().startPlan();
        }
    }

    function onBack() as Void {
        getApp().backToMenu(1);
    }
}
