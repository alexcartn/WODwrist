import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

const LOAD_KEEP_DAYS = 42;
// daily history fields
const D_TRIMP = 1;
const D_SRPE = 2;
const D_GYM = 3;
const D_WL = 4;
const D_MONO = 5;
const D_SESSIONS = 6;
const D_TONNAGE = 7;
const D_PRS = 8;

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

    // ---------- daily history: Storage "load" ----------
    // [day, trimp, sRPE, gymMs, wlMs, monoMs, sessions, tonnageKg, prs]
    // (older 2-field entries are padded with zeros when read)

    function today() as Number {
        return Time.today().value() / 86400;
    }

    function loads() as Array<Array<Number> > {
        var v = Application.Storage.getValue("load");
        return v instanceof Array ? v as Array<Array<Number> > : [] as Array<Array<Number> >;
    }

    function field(e as Array<Number>, idx as Number) as Number {
        return idx < e.size() ? e[idx] : 0;
    }

    // Add values (index 1..) to a day, keep LOAD_KEEP_DAYS days.
    function addDay(day as Number, values as Array<Number>) as Void {
        var e = loads();
        var out = [] as Array<Array<Number> >;
        var merged = false;
        for (var i = 0; i < e.size(); i++) {
            if (e[i][0] <= day - LOAD_KEEP_DAYS) { continue; }
            if (e[i][0] == day) {
                var row = [day] as Array<Number>;
                var n = values.size() + 1 > e[i].size() ? values.size() + 1 : e[i].size();
                for (var k = 1; k < n; k++) {
                    row.add(field(e[i], k) + (k - 1 < values.size() ? values[k - 1] : 0));
                }
                out.add(row);
                merged = true;
            } else {
                out.add(e[i]);
            }
        }
        if (!merged) {
            var row = [day] as Array<Number>;
            for (var k = 0; k < values.size(); k++) { row.add(values[k]); }
            out.add(row);
        }
        Application.Storage.setValue("load", out as Array<Application.PropertyValueType>);
    }

    function sumDays(e as Array<Array<Number> >, today as Number, days as Number, idx as Number) as Number {
        var s = 0;
        for (var i = 0; i < e.size(); i++) {
            if (e[i][0] > today - days && e[i][0] <= today) { s += field(e[i], idx); }
        }
        return s;
    }

    // [acute (7 days), chronic (weekly avg over 28 days), ratio in hundredths or -1]
    function acwr(e as Array<Array<Number> >, today as Number, idx as Number) as Array<Number> {
        var acute = sumDays(e, today, 7, idx);
        var chronic = (sumDays(e, today, 28, idx) + 2) / 4;
        var ratio = chronic > 0 ? (acute * 100 + chronic / 2) / chronic : -1;
        return [acute, chronic, ratio];
    }

    // Foster: [monotony in hundredths (cap 1000), strain], or null without load this week.
    function monotony(e as Array<Array<Number> >, today as Number, idx as Number) as Array<Number>? {
        var days = [] as Array<Number>;
        var week = 0;
        for (var i = 6; i >= 0; i--) {
            var v = sumDays(e, today - i, 1, idx);
            days.add(v);
            week += v;
        }
        if (week <= 0) { return null; }
        var mean = week / 7.0;
        var acc = 0.0;
        for (var i = 0; i < 7; i++) { acc += (days[i] - mean) * (days[i] - mean); }
        var sd = Math.sqrt(acc / 7);
        var mono = 1000;
        if (sd > 0) {
            mono = Math.round(mean * 100 / sd).toNumber();
            if (mono > 1000) { mono = 1000; }
        }
        return [mono, (week * mono + 50) / 100];
    }

    // [this 7 days, previous 7 days]
    function weekCompare(e as Array<Array<Number> >, today as Number, idx as Number) as Array<Number> {
        return [sumDays(e, today, 7, idx), sumDays(e, today - 7, 7, idx)];
    }

    // [gym %, weightlifting %, mono %] of time over `days`, or null.
    function domainShare(e as Array<Array<Number> >, today as Number, days as Number) as Array<Number>? {
        var g = sumDays(e, today, days, D_GYM);
        var w = sumDays(e, today, days, D_WL);
        var m = sumDays(e, today, days, D_MONO);
        var tot = g + w + m;
        if (tot <= 0) { return null; }
        return [pct(g, tot), pct(w, tot), pct(m, tot)];
    }

    function pct(a as Number, tot as Number) as Number {
        // ms totals can be large: go through Long-safe float
        return Math.round(a * 100.0 / tot).toNumber();
    }

    // ---------- movements & session analysis ----------

    // [[id, ratio %], ...] strongest first. mv = movement id -> [reps, ms].
    function rankMovements(mv as Dictionary, minReps as Number) as Array<Array> {
        var out = [] as Array<Array>;
        var ids = mv.keys();
        for (var i = 0; i < ids.size(); i++) {
            var id = ids[i] as String;
            var ref = Movements.refTenths(id);
            var v = mv[id] as Array<Number>;
            if (ref == null || v[0] < minReps) { continue; }
            var t = (v[1] + v[0] * 50) / (v[0] * 100);
            out.add([id, (t * 100 + (ref as Number) / 2) / (ref as Number)]);
        }
        // insertion sort by ratio
        for (var i = 1; i < out.size(); i++) {
            var x = out[i];
            var j = i - 1;
            while (j >= 0 && (out[j][1] as Number) > (x[1] as Number)) {
                out[j + 1] = out[j];
                j--;
            }
            out[j + 1] = x;
        }
        return out;
    }

    // Pace change first -> last occurrence of a movement, % (+25 = slower). occ = [[reps, ms], ...]
    function fatiguePct(occ as Array<Array<Number> >) as Number? {
        var v = [] as Array<Array<Number> >;
        for (var i = 0; i < occ.size(); i++) {
            if (occ[i][0] > 0 && occ[i][1] > 0) { v.add(occ[i]); }
        }
        if (v.size() < 2) { return null; }
        var first = v[0][1].toFloat() / v[0][0];
        var last = v[v.size() - 1][1].toFloat() / v[v.size() - 1][0];
        return Math.round((last - first) * 100 / first).toNumber();
    }

    function median(v as Array<Number>) as Number {
        if (v.size() == 0) { return 0; }
        var s = v.slice(0, null);
        for (var i = 1; i < s.size(); i++) {
            var x = s[i];
            var j = i - 1;
            while (j >= 0 && s[j] > x) {
                s[j + 1] = s[j];
                j--;
            }
            s[j + 1] = x;
        }
        return s[s.size() / 2];
    }

    // ---------- heart rate recovery history: Storage "hrr" = [[day, bpm], ...] ----------

    function hrrList() as Array<Array<Number> > {
        var v = Application.Storage.getValue("hrr");
        return v instanceof Array ? v as Array<Array<Number> > : [] as Array<Array<Number> >;
    }

    function addHrr(day as Number, bpm as Number) as Void {
        var l = hrrList();
        l.add([day, bpm]);
        if (l.size() > 30) { l = l.slice(l.size() - 30, null); }
        Application.Storage.setValue("hrr", l as Array<Application.PropertyValueType>);
    }

    // Average HRR over [today - from, today - to), or -1.
    function hrrAvg(today as Number, from as Number, to as Number) as Number {
        var l = hrrList();
        var s = 0;
        var n = 0;
        for (var i = 0; i < l.size(); i++) {
            if (l[i][0] > today - from && l[i][0] <= today - to) {
                s += l[i][1];
                n++;
            }
        }
        return n > 0 ? (s + n / 2) / n : -1;
    }

    // ---------- readiness: Garmin Body Battery and stress (newest sample) ----------

    // [bodyBattery, stress], -1 when not available on this device.
    function readiness() as Array<Number> {
        var out = [-1, -1];
        if (!(Toybox has :SensorHistory)) { return out; }
        if (SensorHistory has :getBodyBatteryHistory) {
            var it = SensorHistory.getBodyBatteryHistory({ :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST });
            var smp = it != null ? it.next() : null;
            if (smp != null && smp.data != null) { out[0] = (smp.data as Numeric).toNumber(); }
        }
        if (SensorHistory has :getStressHistory) {
            var it = SensorHistory.getStressHistory({ :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST });
            var smp = it != null ? it.next() : null;
            if (smp != null && smp.data != null) { out[1] = (smp.data as Numeric).toNumber(); }
        }
        return out;
    }

    // Training load index: session RPE when there is some in the last 4 weeks, else HR (TRIMP).
    function loadIndex(e as Array<Array<Number> >, today as Number) as Number {
        return sumDays(e, today, 28, D_SRPE) > 0 ? D_SRPE : D_TRIMP;
    }

    // Breaks inside a set: gaps longer than max(3 s, 2.5 x median gap).
    function countBreaks(t as Array<Number>) as Number {
        if (t.size() < 3) { return 0; }
        var gaps = [] as Array<Number>;
        for (var i = 1; i < t.size(); i++) { gaps.add(t[i] - t[i - 1]); }
        var s = gaps.slice(0, null);
        for (var i = 1; i < s.size(); i++) {
            var v = s[i];
            var j = i - 1;
            while (j >= 0 && s[j] > v) {
                s[j + 1] = s[j];
                j--;
            }
            s[j + 1] = v;
        }
        var limit = s[s.size() / 2] * 5 / 2;
        if (limit < 3000) { limit = 3000; }
        var n = 0;
        for (var i = 0; i < gaps.size(); i++) {
            if (gaps[i] > limit) { n++; }
        }
        return n;
    }

    // Heartbeats per round, last vs first completed round, %. laps = [[ms, reps, avgHr], ...]
    function beatsDriftPct(laps as Array<Array<Number> >) as Number? {
        var v = [] as Array<Array<Number> >;
        for (var i = 0; i < laps.size(); i++) {
            if (laps[i][0] > 0 && laps[i][2] > 0) { v.add(laps[i]); }
        }
        if (v.size() < 2) { return null; }
        var a = v[0][0].toFloat() * v[0][2];
        var b = v[v.size() - 1][0].toFloat() * v[v.size() - 1][2];
        return Math.round((b - a) * 100 / a).toNumber();
    }

    // Session RPE load (Foster): RPE x minutes.
    function srpeLoad(rpe as Number, activeMs as Number) as Number {
        return rpe * ((activeMs + 30000) / 60000);
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
