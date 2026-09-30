import Toybox.Application;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Demo data for the simulator, debug builds only (monkeyc without -r):
// "Load demo data" at the top of the main menu wipes Storage and fills it
// with 4 WODs, a 2-part coach plan, 6 weeks of scores and training load, heart
// rate recovery and movement totals, so every screen has something to show.
// Release builds get the empty stubs at the end of this file.

const MENU_DEMO = 1009;

(:debug)
var demoLoader as DemoLoader? = null;

(:debug)
function addDemoMenuItem(menu as WatchUi.Menu2) as Void {
    menu.addItem(new WatchUi.MenuItem("Load demo data", "Debug build only", MENU_DEMO, {}));
}

(:debug)
function loadDemoData() as Void {
    demoLoader = new DemoLoader();
    (demoLoader as DemoLoader).start();
}

(:debug)
class DemoLoader {

    private var _timer as Timer.Timer = new Timer.Timer();
    private var _i as Number = 0;
    private var _wods as Array<Dictionary> = [] as Array<Dictionary>;
    private var _today as Number = 0;

    function initialize() {
    }

    // Samples used: wall ball AMRAP, Fran-ish, swing EMOM, clean ladder.
    function samples() as Array<Number> {
        return [0, 2, 1, 6] as Array<Number>;
    }

    function start() as Void {
        Application.Storage.clearValues();
        _today = Perf.today();
        // one parse per tick: parsing several WODs in one event trips the watchdog
        _timer.start(method(:step), 100, true);
    }

    function step() as Void {
        var s = samples();
        if (_i < s.size()) {
            var w = SampleWods.get(s[_i]);
            if (w != null) { _wods.add(w); }
            _i++;
            return;
        }
        _timer.stop();
        finish();
        demoLoader = null;
    }

    private function finish() as Void {
        var sync = getApp().syncSvc();
        for (var i = _wods.size() - 1; i >= 0; i--) { sync.addWod(_wods[i]); }
        if (_wods.size() >= 2) {
            Application.Storage.setValue("plan", [_wods[1], _wods[0]] as Array<Application.PropertyValueType>);
        }
        saveScores();
        saveLoad();
        saveTotals();
        Application.Storage.setValue("onboarded", true);
        Glance.update(_wods[0]["name"] as String, Tr.s("Last") + " 6 + 30");
        if (WatchUi has :showToast) { WatchUi.showToast("Demo data loaded", null); }
        getApp().refreshMenu();
    }

    // ---------- scores ----------

    // 6 results per WOD, oldest first, as ScoreHistory.value() numbers.
    private function saveScores() as Void {
        var series = [
            [5010, 5020, 6005, 5025, 6015, 6030],
            [540000, 505000, 512000, 478000, 461000, 455000],
            [96, 102, 104, 110, 108, 110],
            [4005, 4012, 5003, 4020, 5010, 5014]
        ];
        var keys = [] as Array<String>;
        for (var k = 0; k < _wods.size() && k < series.size(); k++) {
            var w = _wods[k];
            var kind = kindOf(w);
            var vals = series[k] as Array<Number>;
            var hist = [] as Array;
            var best = null as Dictionary?;
            var last = null as Dictionary?;
            for (var j = 0; j < vals.size(); j++) {
                var day = _today - 38 + j * 7 + k;
                var r = record(w, kind, vals[j], day);
                var v = kind.equals("time") ? 2000000000 - vals[j] : vals[j];
                hist.add([day, v]);
                if (ScoreHistory.isBetter(r, best)) { best = r; }
                last = r;
            }
            var sig = ScoreHistory.signature(w, false);
            var key = ScoreHistory.key(sig);
            Application.Storage.setValue(key, {
                "sig" => sig, "name" => w["name"], "last" => last, "best" => best,
                "n" => vals.size(), "hist" => hist
            } as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
            keys.add(key);
        }
        Application.Storage.setValue("hkeys", keys as Array<Application.PropertyValueType>);
    }

    private function kindOf(w as Dictionary) as String {
        var t = w["type"] as String;
        if (t.equals("AMRAP")) { return "rounds"; }
        if (t.equals("FOR_TIME")) { return "time"; }
        return "reps";
    }

    // A result record as WorkoutSession.buildResult() makes it.
    private function record(w as Dictionary, kind as String, v as Number, day as Number) as Dictionary {
        var cap = w["timeCapSec"] instanceof Number ? (w["timeCapSec"] as Number) * 1000 : 600000;
        var rounds = kind.equals("rounds") ? v / 1000 : 3;
        var ms = kind.equals("time") ? v : cap;
        var laps = [] as Array<Number>;
        // each round a bit slower than the one before (fade)
        var lap = ms / (rounds + 1);
        var t = 0;
        for (var i = 0; i < rounds; i++) {
            t += lap + i * lap / 20;
            laps.add(t < ms ? t : ms);
        }
        var zones = [0, 60, 120, 240, (ms / 1000) / 2, 90] as Array<Number>;
        return {
            "kind" => kind,
            "rounds" => rounds,
            "reps" => kind.equals("rounds") ? v % 1000 : (kind.equals("reps") ? v : 0),
            "ms" => ms,
            "t" => day * 86400 + 18 * 3600,
            "laps" => laps,
            "hr" => 150 + v % 12,
            "hrMax" => 176 + v % 9,
            "trimp" => Perf.trimp(zones),
            "zones" => zones,
            "srpe" => Perf.srpeLoad(7, ms),
            "tonnage" => 0
        };
    }

    // ---------- training load ----------

    // 6 weeks, 4 sessions a week, the last week harder (load ratio above 1).
    private function saveLoad() as Void {
        var rows = [] as Array<Array<Number> >;
        var hrr = [] as Array<Array<Number> >;
        for (var d = _today - LOAD_KEEP_DAYS + 1; d <= _today; d++) {
            var wd = d % 7;
            if (wd != 0 && wd != 1 && wd != 3 && wd != 5) { continue; }
            var hard = d > _today - 7 ? 30 : 0;
            var min = 18 + (d * 7) % 14 + hard / 3;
            var gym = (min * 60000) * (40 + d % 3 * 10) / 100;
            var wl = (min * 60000) * (d % 2 == 0 ? 35 : 15) / 100;
            var mono = min * 60000 - gym - wl;
            var prs = d % 11 == 0 ? 1 : 0;
            // seconds per HR zone: mostly Z3-Z4, more Z5 in the hard week
            var sec = min * 60;
            var z5 = sec * (6 + hard / 3 + d % 4) / 100;
            var z4 = sec * (28 + d % 9) / 100;
            var z3 = sec * (30 - d % 7) / 100;
            var z2 = sec * 18 / 100;
            var z1 = sec - z2 - z3 - z4 - z5;
            // [day, trimp, srpe, gym ms, weights ms, mono ms, sessions, tonnage kg, PRs, Z1..Z5 s]
            rows.add([d, 55 + (d * 13) % 50 + hard, (6 + d % 3) * min, gym, wl, mono, 1,
                d % 2 == 0 ? 1800 + (d * 37) % 1500 : 0, prs, z1, z2, z3, z4, z5] as Array<Number>);
            hrr.add([d, 26 + (d * 5) % 12] as Array<Number>);
        }
        Application.Storage.setValue("load", rows as Array<Application.PropertyValueType>);
        if (hrr.size() > 30) { hrr = hrr.slice(hrr.size() - 30, null); }
        Application.Storage.setValue("hrr", hrr as Array<Application.PropertyValueType>);
    }

    // Lifetime totals and per-movement reps / time (pace per rep, strong / weak).
    private function saveTotals() as Void {
        var mv = {} as Dictionary;
        var reps = 0;
        var ms = 0;
        for (var k = 0; k < _wods.size(); k++) {
            var blocks = _wods[k]["blocks"] as Array<Dictionary>;
            for (var b = 0; b < blocks.size(); b++) {
                var id = blocks[b]["movement"] as String;
                var n = 240 + (id.hashCode() & 0xff);
                var t = n * (1800 + (id.hashCode() & 0x7ff));
                var cur = mv[id];
                if (cur instanceof Array) {
                    mv[id] = [(cur as Array<Number>)[0] + n, (cur as Array<Number>)[1] + t];
                } else {
                    mv[id] = [n, t];
                }
                reps += n;
                ms += t;
            }
        }
        Application.Storage.setValue("mv", mv as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
        Application.Storage.setValue("tot", { "n" => 24, "reps" => reps, "ms" => ms });
    }
}

(:release)
function addDemoMenuItem(menu as WatchUi.Menu2) as Void {
}

(:release)
function loadDemoData() as Void {
}
