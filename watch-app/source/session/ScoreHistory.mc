import Toybox.Application;
import Toybox.Lang;

const HISTORY_MAX = 30;

// Score memory per WOD (last + best, with round split times for pacing).
// Port of web-editor/js/score-history.js. Keep in sync.
//
// Record: { "kind" => "rounds"|"time"|"reps", "rounds", "reps", "ms", "t", "laps" }
//   laps = cumulative active ms at the end of each completed round
// Entry in Storage under "h<hash>": { "sig", "last", "best", "n" }
module ScoreHistory {

    // Same WOD = same structure, whatever its name.
    function signature(wod as Dictionary) as String {
        var keys = ["type", "timeCapSec", "intervalSec", "workSec", "restSec", "rounds"];
        var parts = [] as Array<String>;
        for (var i = 0; i < keys.size(); i++) {
            var v = wod[keys[i]];
            parts.add(v == null ? "" : v.toString());
        }
        var rs = wod["repScheme"];
        var scheme = [] as Array<String>;
        if (rs != null) {
            for (var i = 0; i < (rs as Array).size(); i++) { scheme.add(((rs as Array)[i] as Number).format("%d")); }
        }
        parts.add(Str.join(scheme, "-"));
        var blocks = wod["blocks"] as Array<Dictionary>;
        var bs = [] as Array<String>;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            var slot = b["slot"];
            bs.add((b["movement"] as String) + ":" + (b["reps"] as Number).format("%d") + (b["unit"] as String)
                + ":" + (slot == null ? "" : (slot as Number).format("%d")));
        }
        return Str.join(parts, "|") + "|" + Str.join(bs, ",");
    }

    // Higher is better. A finished For time always beats a capped one.
    function value(rec as Dictionary) as Number {
        var kind = rec["kind"] as String;
        if (kind.equals("time")) { return 2000000000 - (rec["ms"] as Number); }
        if (kind.equals("rounds")) { return (rec["rounds"] as Number) * 1000 + (rec["reps"] as Number); }
        return rec["reps"] as Number;
    }

    function isBetter(a as Dictionary, b as Dictionary?) as Boolean {
        return b == null || value(a) > value(b);
    }

    // ms ahead (<0) or behind (>0) the reference at the last completed round, or null.
    function paceDelta(myLaps as Array<Number>, refLaps as Array?) as Number? {
        var k = myLaps.size();
        if (k == 0 || refLaps == null || refLaps.size() < k) { return null; }
        return myLaps[k - 1] - (refLaps[k - 1] as Number);
    }

    // -8400 -> "-0:08", 14000 -> "+0:14"
    function formatDelta(ms as Number) as String {
        var sign = ms < 0 ? "-" : "+";
        var a = ms < 0 ? -ms : ms;
        var sec = (a + 500) / 1000;
        return sign + (sec / 60).format("%d") + ":" + (sec % 60).format("%02d");
    }

    function scoreText(rec as Dictionary) as String {
        var kind = rec["kind"] as String;
        if (kind.equals("rounds")) {
            return (rec["rounds"] as Number).format("%d") + " + " + (rec["reps"] as Number).format("%d");
        }
        if (kind.equals("time")) { return Str.clock(rec["ms"] as Number, false); }
        return (rec["reps"] as Number).format("%d") + " reps";
    }

    // ---------- storage ----------

    function key(sig as String) as String {
        return "h" + sig.hashCode().format("%d");
    }

    function load(wod as Dictionary) as Dictionary? {
        var sig = signature(wod);
        var e = Application.Storage.getValue(key(sig));
        if (!(e instanceof Dictionary)) { return null; }
        var d = e as Dictionary;
        // hash collision guard
        if (!(d["sig"] instanceof String) || !(d["sig"] as String).equals(sig)) { return null; }
        return d;
    }

    // Returns the updated entry.
    function save(wod as Dictionary, rec as Dictionary) as Dictionary {
        var sig = signature(wod);
        var k = key(sig);
        var prev = load(wod);
        var entry;
        if (prev == null) {
            entry = { "sig" => sig, "last" => rec, "best" => rec, "n" => 1 };
        } else {
            var best = prev["best"] as Dictionary;
            entry = {
                "sig" => sig,
                "last" => rec,
                "best" => isBetter(rec, best) ? rec : best,
                "n" => (prev["n"] as Number) + 1
            };
        }
        Application.Storage.setValue(k, entry as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);

        // keep the index bounded: forget the WOD not done for the longest time
        var idx = Application.Storage.getValue("hkeys");
        var keys = idx instanceof Array ? idx as Array<String> : [] as Array<String>;
        var out = [k] as Array<String>;
        for (var i = 0; i < keys.size(); i++) {
            if (keys[i].equals(k)) { continue; }
            if (out.size() < HISTORY_MAX) {
                out.add(keys[i]);
            } else {
                Application.Storage.deleteValue(keys[i]);
            }
        }
        Application.Storage.setValue("hkeys", out as Array<Application.PropertyValueType>);
        return entry;
    }
}
