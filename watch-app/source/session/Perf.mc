import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

const LOAD_KEEP_DAYS = 42;

// Performance engineering on the watch: HR zones, training load (TRIMP),
// acute:chronic load ratio, pacing consistency, EMOM density, cardiac trend.
// Port of web-editor/js/perf.js (tested there). Integer math where possible.
module Perf {

    // bounds = [z1 min, z1 max, z2 max, z3 max, z4 max, z5 max]
    function zoneOf(hr as Number, b as Array<Number>) as Number {
        if (hr < b[0]) { return 0; }
        for (var z = 1; z <= 4; z++) {
            if (hr <= b[z]) { return z; }
        }
        return 5;
    }

    function defaultBounds(maxHr as Number) as Array<Number> {
        return [maxHr * 50 / 100, maxHr * 60 / 100, maxHr * 70 / 100, maxHr * 80 / 100, maxHr * 90 / 100, maxHr];
    }

    // The athlete's Garmin zones, else 220 - age, else 190 bpm max.
    function bounds() as Array<Number> {
        if (Toybox has :UserProfile) {
            if (UserProfile has :getHeartRateZones) {
                var z = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
                if (z != null && z.size() >= 6) { return z as Array<Number>; }
            }
            var p = UserProfile.getProfile();
            if (p != null && p.birthYear != null) {
                var age = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT).year - (p.birthYear as Number);
                if (age > 10 && age < 100) { return defaultBounds(220 - age); }
            }
        }
        return defaultBounds(190);
    }

    // Edwards TRIMP: minutes in zone x zone number.
    function trimp(zoneSec as Array<Number>) as Number {
        var s = 0;
        for (var z = 1; z <= 5; z++) { s += z * zoneSec[z]; }
        return (s + 30) / 60;
    }

    // Coefficient of variation in %, null under 2 values.
    function cvPct(v as Array<Number>) as Number? {
        var n = v.size();
        if (n < 2) { return null; }
        var sum = 0.0;
        for (var i = 0; i < n; i++) { sum += v[i]; }
        var mean = sum / n;
        if (mean <= 0) { return null; }
        var acc = 0.0;
        for (var i = 0; i < n; i++) { acc += (v[i] - mean) * (v[i] - mean); }
        return Math.round(Math.sqrt(acc / n) * 100 / mean).toNumber();
    }

    // Share of each interval spent working, in %.
    function densityPct(workMs as Array<Number>, intervalMs as Number) as Number? {
        var n = workMs.size();
        if (n == 0 || intervalMs <= 0) { return null; }
        var sum = 0;
        for (var i = 0; i < n; i++) { sum += workMs[i]; }
        return (sum * 100 + n * intervalMs / 2) / (n * intervalMs);
    }

    // Same WOD, score at least as good: bpm difference (negative = fitter), else null.
    function cardiacTrend(prev as Dictionary?, last as Dictionary?) as Number? {
        if (prev == null || last == null) { return null; }
        var ph = prev["hr"];
        var lh = last["hr"];
        if (!(ph instanceof Number) || !(lh instanceof Number) || (ph as Number) <= 0 || (lh as Number) <= 0) { return null; }
        if (ScoreHistory.value(last) < ScoreHistory.value(prev)) { return null; }
        return (lh as Number) - (ph as Number);
    }

    // ---------- load over time: Storage "load" = [[day, load], ...] ----------

    function today() as Number {
        return Time.today().value() / 86400;
    }

    function loads() as Array<Array<Number> > {
        var v = Application.Storage.getValue("load");
        return v instanceof Array ? v as Array<Array<Number> > : [] as Array<Array<Number> >;
    }

    function addLoad(day as Number, load as Number) as Void {
        var e = loads();
        var out = [] as Array<Array<Number> >;
        var merged = false;
        for (var i = 0; i < e.size(); i++) {
            if (e[i][0] <= day - LOAD_KEEP_DAYS) { continue; }
            if (e[i][0] == day) {
                out.add([day, e[i][1] + load]);
                merged = true;
            } else {
                out.add(e[i]);
            }
        }
        if (!merged) { out.add([day, load]); }
        Application.Storage.setValue("load", out as Array<Application.PropertyValueType>);
    }

    function sumDays(e as Array<Array<Number> >, today as Number, days as Number) as Number {
        var s = 0;
        for (var i = 0; i < e.size(); i++) {
            if (e[i][0] > today - days && e[i][0] <= today) { s += e[i][1]; }
        }
        return s;
    }

    // [acute (7 days), chronic (weekly avg over 28 days), ratio in hundredths or -1]
    function acwr(e as Array<Array<Number> >, today as Number) as Array<Number> {
        var acute = sumDays(e, today, 7);
        var chronic = (sumDays(e, today, 28) + 2) / 4;
        var ratio = chronic > 0 ? (acute * 100 + chronic / 2) / chronic : -1;
        return [acute, chronic, ratio];
    }

    // "building" until 3 weeks of history, then low / optimal / high / risk.
    function status(e as Array<Array<Number> >, today as Number, ratio as Number) as String {
        var first = today + 1;
        for (var i = 0; i < e.size(); i++) {
            if (e[i][0] < first) { first = e[i][0]; }
        }
        if (e.size() == 0 || first > today - 21 || ratio < 0) { return "building"; }
        if (ratio < 80) { return "low"; }
        if (ratio <= 130) { return "optimal"; }
        if (ratio <= 150) { return "high"; }
        return "risk";
    }
}
