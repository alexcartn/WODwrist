import Toybox.Application;
import Toybox.Lang;

// Quick timer: a WOD without movements, set up on the watch in a few taps.
// Port of web-editor/js/quick-timer.js (the tested reference). Keep in sync.
//
// One pseudo block stands for "a round": BACK (+1) closes the round (AMRAP,
// For time) or marks the interval done (EMOM). Tabata counts reps.
// The choices (indexes) are kept in Storage "quick" for the next time.
module QuickTimer {

    const TYPES = ["AMRAP", "FOR_TIME", "EMOM", "TABATA"];
    const TYPE_LABELS = ["AMRAP", "For time", "EMOM", "Tabata"];

    // Tap on a menu row = next value (wraps).
    function choices(key as String) as Array {
        if (key.equals("amrapMin")) { return [5, 7, 8, 10, 12, 14, 15, 16, 18, 20, 25, 30, 35, 40, 45, 60]; }
        if (key.equals("ftRounds")) { return [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20]; }  // 0 = stopwatch
        if (key.equals("ftCapMin")) { return [0, 5, 8, 10, 12, 15, 20, 25, 30, 40, 60]; }    // 0 = no cap
        if (key.equals("emomEverySec")) { return [60, 90, 120, 150, 180, 240, 300]; }
        if (key.equals("emomRounds")) { return [5, 6, 8, 10, 12, 14, 15, 16, 18, 20, 24, 30]; }
        if (key.equals("tabataWorkRest")) { return [[20, 10], [30, 15], [40, 20], [45, 15], [30, 30], [60, 30]]; }
        if (key.equals("tabataRounds")) { return [4, 6, 8, 10, 12, 16, 20]; }
        return TYPES;
    }

    function defaults() as Dictionary<String, Number> {
        return {
            "type" => 0,
            "amrapMin" => 9,       // 20 min
            "ftRounds" => 0,       // stopwatch
            "ftCapMin" => 0,
            "emomEverySec" => 0,   // 1:00
            "emomRounds" => 3,     // 10
            "tabataWorkRest" => 0,
            "tabataRounds" => 2    // 8
        };
    }

    function load() as Dictionary<String, Number> {
        var cfg = defaults();
        var v = Application.Storage.getValue("quick");
        if (v instanceof Dictionary) {
            var keys = cfg.keys();
            for (var i = 0; i < keys.size(); i++) {
                var x = (v as Dictionary)[keys[i]];
                // ignore a stored index that no longer fits its list
                if (x instanceof Number && (x as Number) >= 0 && (x as Number) < choices(keys[i] as String).size()) {
                    cfg[keys[i]] = x as Number;
                }
            }
        }
        return cfg;
    }

    function save(cfg as Dictionary<String, Number>) as Void {
        Application.Storage.setValue("quick", cfg as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
    }

    // Rows of the menu for a type (the type row is always first).
    function rows(type as Number) as Array<String> {
        if (type == 0) { return ["amrapMin"] as Array<String>; }
        if (type == 1) { return ["ftRounds", "ftCapMin"] as Array<String>; }
        if (type == 2) { return ["emomEverySec", "emomRounds"] as Array<String>; }
        return ["tabataWorkRest", "tabataRounds"] as Array<String>;
    }

    function rowTitle(key as String) as String {
        if (key.equals("amrapMin")) { return Tr.s("Duration"); }
        if (key.equals("ftRounds")) { return Tr.s("Rounds"); }
        if (key.equals("ftCapMin")) { return Tr.s("Time cap"); }
        if (key.equals("emomEverySec")) { return Tr.s("Every"); }
        if (key.equals("emomRounds")) { return Tr.s("Intervals"); }
        if (key.equals("tabataWorkRest")) { return Tr.s("Work / rest"); }
        if (key.equals("tabataRounds")) { return Tr.s("Rounds"); }
        return Tr.s("Type");
    }

    function cycle(cfg as Dictionary<String, Number>, key as String) as Void {
        cfg[key] = ((cfg[key] as Number) + 1) % choices(key).size();
    }

    function pick(cfg as Dictionary<String, Number>, key as String) {
        var list = choices(key);
        var i = cfg[key];
        if (!(i instanceof Number) || (i as Number) < 0 || (i as Number) >= list.size()) {
            i = defaults()[key];
        }
        return list[i as Number];
    }

    function clock(sec as Number) as String {
        return (sec / 60).format("%d") + ":" + (sec % 60).format("%02d");
    }

    // Sub-label of a row: "20 min", "Chrono", "No cap", "1:30", "20/10"...
    function label(cfg as Dictionary<String, Number>, key as String) as String {
        if (key.equals("type")) { return Tr.s(TYPE_LABELS[cfg["type"] as Number] as String); }
        var v = pick(cfg, key);
        if (key.equals("amrapMin") || key.equals("ftCapMin")) {
            return (v as Number) == 0 ? Tr.s("No cap") : (v as Number).format("%d") + " min";
        }
        if (key.equals("ftRounds")) {
            return (v as Number) == 0 ? "Chrono" : (v as Number).format("%d") + " " + Tr.s("rounds");
        }
        if (key.equals("emomEverySec")) { return clock(v as Number); }
        if (key.equals("emomRounds")) { return "x " + (v as Number).format("%d"); }
        if (key.equals("tabataWorkRest")) {
            var wr = v as Array<Number>;
            return wr[0].format("%d") + "/" + wr[1].format("%d");
        }
        return (v as Number).format("%d") + " " + Tr.s("rounds");
    }

    // Same WOD structure as the parser output, plus "quick" => true.
    function wod(cfg as Dictionary<String, Number>) as Dictionary {
        var t = cfg["type"] as Number;
        if (t < 0 || t >= TYPES.size()) { t = 0; }
        var type = TYPES[t] as String;
        var round = {
            "movement" => "custom", "name" => "Round", "reps" => 1, "unit" => "reps", "slot" => null, "load" => null
        } as Dictionary;
        var w = {
            "version" => 1, "name" => "", "type" => type, "quick" => true,
            "timeCapSec" => null, "intervalSec" => null, "workSec" => null, "restSec" => null, "rounds" => null,
            "repScheme" => null, "repStep" => null, "blocks" => [round]
        } as Dictionary;
        if (t == 0) {
            var m = pick(cfg, "amrapMin") as Number;
            w["name"] = "AMRAP " + m.format("%d");
            w["timeCapSec"] = m * 60;
        } else if (t == 1) {
            var r = pick(cfg, "ftRounds") as Number;
            var cap = pick(cfg, "ftCapMin") as Number;
            w["rounds"] = r;
            var name = r == 0 ? "Chrono" : r.format("%d") + " RFT";
            if (cap > 0) {
                w["timeCapSec"] = cap * 60;
                name += " cap " + cap.format("%d");
            }
            w["name"] = name;
        } else if (t == 2) {
            var every = pick(cfg, "emomEverySec") as Number;
            var r = pick(cfg, "emomRounds") as Number;
            w["intervalSec"] = every;
            w["rounds"] = r;
            w["timeCapSec"] = every * r;
            round["slot"] = 0;
            if (every == 60) {
                w["name"] = "EMOM " + r.format("%d");
            } else if (every % 60 == 0) {
                w["name"] = "E" + (every / 60).format("%d") + "MOM " + (every / 60 * r).format("%d");
            } else {
                w["name"] = "EVERY " + clock(every) + " x " + r.format("%d");
            }
        } else {
            var wr = pick(cfg, "tabataWorkRest") as Array<Number>;
            var r = pick(cfg, "tabataRounds") as Number;
            w["workSec"] = wr[0];
            w["restSec"] = wr[1];
            w["intervalSec"] = wr[0] + wr[1];
            w["rounds"] = r;
            w["timeCapSec"] = r * (wr[0] + wr[1]) - wr[1];
            round["slot"] = 0;
            round["name"] = "Reps";
            round["reps"] = 0;
            w["name"] = "TABATA " + r.format("%d") + "x" + wr[0].format("%d") + "/" + wr[1].format("%d");
        }
        return w;
    }

    function isQuick(w as Dictionary) as Boolean {
        return w["quick"] == true;
    }
}
