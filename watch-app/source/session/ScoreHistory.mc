import Toybox.Application;
import Toybox.Lang;

const HISTORY_MAX = 30;
const HIST_MAX = 12;

// Score memory per WOD (last + best, with round split times for pacing).
// Port of web-editor/js/score-history.js. Keep in sync.
//
// Record: { "kind" => "rounds"|"time"|"reps", "rounds", "reps", "ms", "t", "laps" }
//   laps = cumulative active ms at the end of each completed round
// Entry in Storage under "h<hash>": { "sig", "last", "best", "n" }
module ScoreHistory {

    // Same WOD = same structure, whatever its name.
    function signature(wod as Dictionary, scaled as Boolean) as String {
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
        var step = wod["repStep"];
        parts.add(step == null ? "" : step.toString());
        var blocks = wod["blocks"] as Array<Dictionary>;
        var bs = [] as Array<String>;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            var slot = b["slot"];
            bs.add((b["movement"] as String) + ":" + (b["reps"] as Number).format("%d") + (b["unit"] as String)
                + ":" + (slot == null ? "" : (slot as Number).format("%d")));
        }
        // sets and every-minute task only when used, so older signatures stay the same
        var extra = "";
        var sets = wod["sets"];
        if (sets instanceof Number && (sets as Number) > 1) {
            var sr = wod["setRestSec"];
            extra += "|sets" + (sets as Number).format("%d") + "/" + (sr instanceof Number ? (sr as Number) : 0).format("%d");
        }
        var tk = wod["task"];
        if (tk instanceof Dictionary) {
            var t = tk as Dictionary;
            var tb = t["blocks"] as Array<Dictionary>;
            var ts = [] as Array<String>;
            for (var i = 0; i < tb.size(); i++) {
                ts.add((tb[i]["movement"] as String) + ":" + (tb[i]["reps"] as Number).format("%d") + (tb[i]["unit"] as String));
            }
            extra += "|task" + (t["everySec"] as Number).format("%d") + (t["at0"] == true ? "a" : "") + ":" + Str.join(ts, ",");
        }
        return Str.join(parts, "|") + "|" + Str.join(bs, ",") + extra + (scaled ? "|scaled" : "");
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

    // Back from value() to the score text.
    function valueText(kind as String, v as Number) as String {
        if (kind.equals("rounds")) { return (v / 1000).format("%d") + " + " + (v % 1000).format("%d"); }
        if (kind.equals("time")) { return Str.clock(2000000000 - v, false); }
        return v.format("%d") + " reps";
    }

    function scoreText(rec as Dictionary) as String {
        var kind = rec["kind"] as String;
        if (kind.equals("rounds")) {
            return (rec["rounds"] as Number).format("%d") + " + " + (rec["reps"] as Number).format("%d");
        }
        if (kind.equals("time")) { return Str.clock(rec["ms"] as Number, false); }
        return (rec["reps"] as Number).format("%d") + " reps";
    }

    // ---------- stats (pure) ----------

    // Fade: how much slower the last round was than the first, in %. null under 2 rounds.
    function fadePct(laps as Array?) as Number? {
        if (laps == null || laps.size() < 2) { return null; }
        var n = laps.size();
        var first = laps[0] as Number;
        if (first <= 0) { return null; }
        var last = (laps[n - 1] as Number) - (laps[n - 2] as Number);
        var x = (last - first) * 100;
        return (x >= 0 ? x + first / 2 : x - first / 2) / first;
    }

    // Tenths of a second per rep: 10 reps in 24 s -> 24 (shown "2.4 s"). null without reps.
    function tenthsPerRep(reps as Number, ms as Number) as Number? {
        if (reps <= 0) { return null; }
        return (ms + reps * 50) / (reps * 100);
    }

    function formatTenths(t as Number) as String {
        return (t / 10).format("%d") + "." + (t % 10).format("%d") + " s";
    }

    // ---------- storage ----------

    function key(sig as String) as String {
        return "h" + sig.hashCode().format("%d");
    }

    function load(wod as Dictionary, scaled as Boolean) as Dictionary? {
        var sig = signature(wod, scaled);
        var e = Application.Storage.getValue(key(sig));
        if (!(e instanceof Dictionary)) { return null; }
        var d = e as Dictionary;
        // hash collision guard
        if (!(d["sig"] instanceof String) || !(d["sig"] as String).equals(sig)) { return null; }
        return d;
    }

    // Returns the updated entry.
    function save(wod as Dictionary, rec as Dictionary, scaled as Boolean) as Dictionary {
        var sig = signature(wod, scaled);
        var k = key(sig);
        var prev = load(wod, scaled);
        var entry;
        var point = [Perf.today(), value(rec)];
        if (prev == null) {
            entry = { "sig" => sig, "name" => wod["name"], "last" => rec, "best" => rec, "n" => 1, "hist" => [point] };
        } else {
            var best = prev["best"] as Dictionary;
            // last HIST_MAX results for the progress chart
            var hist = prev["hist"] instanceof Array ? (prev["hist"] as Array).slice(0, null) : [] as Array;
            hist.add(point);
            if (hist.size() > HIST_MAX) { hist = hist.slice(hist.size() - HIST_MAX, null); }
            entry = {
                "sig" => sig,
                "name" => wod["name"],
                "last" => rec,
                "best" => isBetter(rec, best) ? rec : best,
                "n" => (prev["n"] as Number) + 1,
                "hist" => hist
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

    // WOD entries, most recently done first.
    function entries() as Array<Dictionary> {
        var idx = Application.Storage.getValue("hkeys");
        var out = [] as Array<Dictionary>;
        if (!(idx instanceof Array)) { return out; }
        var keys = idx as Array<String>;
        for (var i = 0; i < keys.size(); i++) {
            var e = Application.Storage.getValue(keys[i]);
            if (e instanceof Dictionary) { out.add(e as Dictionary); }
        }
        return out;
    }

    // ---------- lifetime totals ----------

    // { "n" => workouts, "reps" => reps, "ms" => active ms }
    function totals() as Dictionary {
        var t = Application.Storage.getValue("tot");
        return t instanceof Dictionary ? t as Dictionary : { "n" => 0, "reps" => 0, "ms" => 0 };
    }

    // movement id -> [reps, ms]
    function movementStats() as Dictionary {
        var m = Application.Storage.getValue("mv");
        return m instanceof Dictionary ? m as Dictionary : {};
    }

    function addTotals(reps as Number, ms as Number, session as Dictionary) as Void {
        var t = totals();
        Application.Storage.setValue("tot", {
            "n" => (t["n"] as Number) + 1,
            "reps" => (t["reps"] as Number) + reps,
            "ms" => (t["ms"] as Number) + ms
        });
        var m = movementStats();
        var ids = session.keys();
        for (var i = 0; i < ids.size(); i++) {
            var add = session[ids[i]] as Array<Number>;
            var cur = m[ids[i]];
            if (cur instanceof Array) {
                var c = cur as Array<Number>;
                m[ids[i]] = [c[0] + add[0], c[1] + add[1]];
            } else {
                m[ids[i]] = [add[0], add[1]];
            }
        }
        Application.Storage.setValue("mv", m as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
    }
}
