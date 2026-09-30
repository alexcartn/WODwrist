import Toybox.Lang;
import Toybox.Math;
import Toybox.StringUtil;

// WOD text -> WOD dictionary (same shape as the JSON schema, docs/wod-schema.json).
// Port of web-editor/js/wod-parser.js; the JS file is the tested reference,
// keep both in sync (shared fixtures in docs/fixtures).
//
// parse() returns { "wod" => Dictionary } or { "error" => String, "line" => Number }.
module WodParser {

    const WEIGHT_UNITS = ["kg", "kgs", "lb", "lbs", "#", "pood", "pd"];

    // token -> [unit, multiplier]
    function unitFor(tok as String) as Array? {
        if (tok.equals("m") || tok.equals("meter") || tok.equals("meters") || tok.equals("metre") || tok.equals("metres")) { return ["m", 1]; }
        if (tok.equals("km")) { return ["m", 1000]; }
        if (tok.equals("ft") || tok.equals("feet") || tok.equals("foot")) { return ["m", 0.3048]; }
        if (tok.equals("cal") || tok.equals("cals") || tok.equals("calorie") || tok.equals("calories")) { return ["cal", 1]; }
        if (tok.equals("s") || tok.equals("sec") || tok.equals("secs") || tok.equals("second") || tok.equals("seconds")) { return ["sec", 1]; }
        if (tok.equals("min") || tok.equals("mins") || tok.equals("minute") || tok.equals("minutes")) { return ["sec", 60]; }
        if (tok.equals("rep") || tok.equals("reps")) { return ["reps", 1]; }
        return null;
    }

    // ---------- durations ----------

    // "12" (minutes), "12min", "12'", "90s", "12:30". Returns seconds or -1.
    function parseDuration(tok as String?) as Number {
        if (tok == null || tok.length() == 0) { return -1; }
        var colon = Str.indexOf(tok, ":");
        if (colon >= 0) {
            var m = Str.sub(tok, 0, colon);
            var s = Str.sub(tok, colon + 1, tok.length());
            if (!Str.isInt(m) || !Str.isInt(s)) { return -1; }
            return Str.toInt(m) * 60 + Str.toInt(s);
        }
        var cs = tok.toCharArray();
        var i = 0;
        while (i < cs.size() && Str.isDigitChar(cs[i])) { i++; }
        if (i == 0) { return -1; }
        var n = Str.toInt(Str.sub(tok, 0, i));
        var suffix = Str.sub(tok, i, tok.length());
        if (suffix.equals("") || suffix.equals("m") || suffix.equals("min") || suffix.equals("mins") || suffix.equals("minutes") || suffix.equals("'")) {
            return n * 60;
        }
        if (suffix.equals("s") || suffix.equals("sec") || suffix.equals("secs") || suffix.equals("\"")) {
            return n;
        }
        return -1;
    }

    // ---------- header ----------

    function emptyHeader(type as String) as Dictionary {
        return {
            "type" => type,
            "timeCapSec" => null,
            "intervalSec" => null,
            "workSec" => null,
            "restSec" => null,
            "rounds" => null,
            "inline" => null,
            "deathBy" => false,
            "sets" => 1,
            "setRestSec" => 0
        };
    }

    function isSecWord(t as String) as Boolean {
        return t.equals("s") || t.equals("sec") || t.equals("secs") || t.equals("second") || t.equals("seconds");
    }

    function isMinWord(t as String) as Boolean {
        return t.equals("min") || t.equals("mins") || t.equals("minute") || t.equals("minutes");
    }

    function isRoundWord(t as String) as Boolean {
        return t.equals("rounds") || t.equals("round") || t.equals("sets") || t.equals("set") || t.equals("intervals");
    }

    // Duration at t[k], possibly followed by a unit word ("90 sec", "3 min").
    // Returns [seconds, next index] or null.
    function durationAt(t as Array<String>, k as Number) as Array<Number>? {
        if (k >= t.size()) { return null; }
        if (k + 1 < t.size() && Str.isInt(t[k])) {
            if (isSecWord(t[k + 1])) { return [Str.toInt(t[k]), k + 2]; }
            if (isMinWord(t[k + 1])) { return [Str.toInt(t[k]) * 60, k + 2]; }
        }
        var d = parseDuration(t[k]);
        return d > 0 ? [d, k + 1] : null;
    }

    function err(msg as String) as Dictionary {
        return { "error" => msg };
    }

    // "4" -> 4, "3-4" -> 4, else -1
    function rangeHigh(tok as String) as Number {
        if (Str.isInt(tok)) { return Str.toInt(tok); }
        var d = Str.indexOf(tok, "-");
        if (d > 0 && Str.isInt(Str.sub(tok, 0, d)) && Str.isInt(Str.sub(tok, d + 1, tok.length()))) {
            return Str.toInt(Str.sub(tok, d + 1, tok.length()));
        }
        return -1;
    }

    // Returns a header dictionary, null when the line is not a header,
    // or { "error" => msg } for a known type with bad parameters.
    function parseHeader(line as String) as Dictionary? {
        var t = Str.tokens(Str.replaceChars(line.toLower(), "(),", ' '));
        if (t.size() == 0) { return null; }

        // AMRAP 12 | 12 min AMRAP | AMRAP 12:30
        var i = Str.indexIn(t, "amrap");
        if (i >= 0 && Str.indexIn(t, "death") >= 0) { i = -1; }
        if (i >= 0) {
            var d = i + 1 < t.size() ? parseDuration(t[i + 1]) : -1;
            if (d < 0 && i > 0) {
                var j = i - 1;
                if ((t[j].equals("min") || t[j].equals("mins") || t[j].equals("minutes")) && j > 0) { j--; }
                d = parseDuration(t[j]);
            }
            if (d <= 0) { return err("AMRAP needs a duration, e.g. AMRAP 12"); }
            var h = emptyHeader("AMRAP");
            h["timeCapSec"] = d;
            // sets: "3 x AMRAP 4", "3x AMRAP 4", "3 sets of AMRAP 4", optional "rest 1:00"
            var sets = 0;
            if (i >= 2 && t[i - 1].equals("x") && Str.isInt(t[i - 2])) {
                sets = Str.toInt(t[i - 2]);
            } else if (i >= 1 && t[i - 1].length() > 1 && Str.endsWith(t[i - 1], "x")
                    && Str.isInt(Str.sub(t[i - 1], 0, t[i - 1].length() - 1))) {
                sets = Str.toInt(Str.sub(t[i - 1], 0, t[i - 1].length() - 1));
            } else if (i >= 3 && t[i - 1].equals("of") && isRoundWord(t[i - 2]) && Str.isInt(t[i - 3])) {
                sets = Str.toInt(t[i - 3]);
            }
            if (sets > 1) {
                h["sets"] = sets;
                for (var r = i + 1; r < t.size(); r++) {
                    if (t[r].equals("rest")) {
                        var rd = durationAt(t, r + 1);
                        if (rd != null) { h["setRestSec"] = rd[0]; }
                        break;
                    }
                }
            }
            return h;
        }

        // DEATH BY burpees: 1 rep the first minute, 2 the second... until failure
        for (var k = 0; k + 1 < t.size(); k++) {
            if (t[k].equals("death") && (t[k + 1].equals("by") || t[k + 1].equals("by:"))) {
                var h = emptyHeader("EMOM");
                h["intervalSec"] = 60;
                h["rounds"] = 60;
                h["timeCapSec"] = 3600;
                h["deathBy"] = true;
                var low = line.toLower();
                var dPos = Str.indexOf(low, "death");
                var tail = Str.sub(low, dPos + 5, low.length());
                var at = dPos + 5 + Str.indexOf(tail, "by");
                var rest = Str.trim(Str.removeChars(Str.sub(line, at + 2, line.length()), ":"));
                h["inline"] = rest.length() > 0 ? rest : null;
                return h;
            }
        }

        // EVERY 2:30 x 6 | every 90 sec for 12 min | every 3 min for 5 rounds
        i = Str.indexIn(t, "every");
        if (i >= 0) {
            var d = durationAt(t, i + 1);
            if (d == null) { return err("EVERY needs an interval, e.g. EVERY 2:30 x 6"); }
            var h = emptyHeader("EMOM");
            var iv = d[0];
            var j = d[1];
            var rounds = 0;
            if (j + 1 < t.size() && t[j].equals("x") && Str.isInt(t[j + 1])) {
                rounds = Str.toInt(t[j + 1]);
            } else if (j < t.size() && Str.startsWith(t[j], "x") && Str.isInt(Str.sub(t[j], 1, t[j].length()))) {
                rounds = Str.toInt(Str.sub(t[j], 1, t[j].length()));
            } else if (j < t.size() && t[j].equals("for")) {
                if (j + 2 < t.size() && Str.isInt(t[j + 1]) && isRoundWord(t[j + 2])) {
                    rounds = Str.toInt(t[j + 1]);
                } else {
                    var total = durationAt(t, j + 1);
                    if (total != null) { rounds = total[0] / iv; }
                }
            } else if (j + 1 < t.size() && Str.isInt(t[j]) && isRoundWord(t[j + 1])) {
                rounds = Str.toInt(t[j]);
            }
            if (rounds <= 0) { return err("EVERY needs a number of rounds, e.g. EVERY 2:30 x 6"); }
            h["intervalSec"] = iv;
            h["rounds"] = rounds;
            h["timeCapSec"] = rounds * iv;
            return h;
        }

        // EMOM 10 | E2MOM 20 | E3MOM x 5
        for (var k = 0; k < t.size(); k++) {
            var tok = t[k];
            if (tok.length() >= 4 && Str.startsWith(tok, "e") && Str.endsWith(tok, "mom")) {
                var mid = Str.sub(tok, 1, tok.length() - 3);
                if (!mid.equals("") && !Str.isInt(mid)) { continue; }
                var every = mid.equals("") ? 1 : Str.toInt(mid);
                if (every <= 0) { return err("Invalid EMOM interval"); }
                var h = emptyHeader("EMOM");
                var iv = every * 60;
                var rounds;
                h["intervalSec"] = iv;
                if (k + 2 < t.size() && t[k + 1].equals("x") && Str.isInt(t[k + 2])) {
                    rounds = Str.toInt(t[k + 2]);
                } else {
                    var d = k + 1 < t.size() ? parseDuration(t[k + 1]) : -1;
                    if (d <= 0) { return err("EMOM needs a duration, e.g. EMOM 10"); }
                    rounds = d / iv;
                }
                if (rounds <= 0) { return err("EMOM duration shorter than one interval"); }
                h["rounds"] = rounds;
                h["timeCapSec"] = rounds * iv;
                return h;
            }
        }

        // FOR TIME | 3 ROUNDS FOR TIME | RFT | FOR TIME cap 15
        var forTime = false;
        for (var k = 0; k < t.size(); k++) {
            if (t[k].equals("fortime") || t[k].equals("rft")) { forTime = true; }
            if (t[k].equals("for") && k + 1 < t.size() && t[k + 1].equals("time")) { forTime = true; }
        }
        if (forTime) {
            var h = emptyHeader("FOR_TIME");
            for (var k = 0; k < t.size(); k++) {
                if ((t[k].equals("rounds") || t[k].equals("round") || t[k].equals("rft")) && k > 0 && Str.isInt(t[k - 1])) {
                    h["rounds"] = Str.toInt(t[k - 1]);
                }
                if ((t[k].equals("cap") || t[k].equals("tc") || t[k].equals("timecap")) && k + 1 < t.size()) {
                    var d = parseDuration(t[k + 1]);
                    if (d <= 0) { return err("Invalid time cap"); }
                    h["timeCapSec"] = d;
                }
            }
            return h;
        }

        // "4 Sets", "3-4 Sets", "3 Rounds": untimed sets, run as rounds for time (the higher count)
        if (t.size() == 2 && (t[1].equals("sets") || t[1].equals("set") || t[1].equals("rounds") || t[1].equals("round"))) {
            var rh = rangeHigh(t[0]);
            if (rh > 0) {
                var h = emptyHeader("FOR_TIME");
                h["rounds"] = rh;
                return h;
            }
        }

        // TABATA | TABATA 8x20/10
        i = Str.indexIn(t, "tabata");
        if (i >= 0) {
            var h = emptyHeader("TABATA");
            var rounds = 8;
            var work = 20;
            var rest = 10;
            var spec = Str.join(t.slice(i + 1, null), "");
            if (spec.length() > 0) {
                var fmt = "Tabata format is ROUNDSxWORK/REST, e.g. 8x20/10";
                var x = Str.indexOf(spec, "x");
                var sl = Str.indexOf(spec, "/");
                if (x <= 0 || sl <= x + 1) { return err(fmt); }
                var r = Str.sub(spec, 0, x);
                var w = Str.sub(spec, x + 1, sl);
                var z = Str.sub(spec, sl + 1, spec.length());
                if (!Str.isInt(r) || !Str.isInt(w) || !Str.isInt(z)) { return err(fmt); }
                rounds = Str.toInt(r);
                work = Str.toInt(w);
                rest = Str.toInt(z);
                if (rounds <= 0 || work <= 0) { return err("Tabata rounds and work must be > 0"); }
            }
            h["rounds"] = rounds;
            h["workSec"] = work;
            h["restSec"] = rest;
            h["intervalSec"] = work + rest;
            h["timeCapSec"] = rounds * (work + rest) - rest;
            return h;
        }
        return null;
    }

    // ---------- movement lines ----------

    function stripBrackets(s as String) as String {
        var cs = s.toCharArray();
        var out = [] as Array<Char>;
        var depth = 0;
        for (var i = 0; i < cs.size(); i++) {
            var c = cs[i];
            if (c == '(' || c == '[') {
                depth++;
            } else if (c == ')' || c == ']') {
                if (depth > 0) { depth--; }
            } else if (depth == 0) {
                out.add(c);
            }
        }
        return StringUtil.charArrayToString(out);
    }

    function isWeightToken(tok as String) as Boolean {
        for (var u = 0; u < WEIGHT_UNITS.size(); u++) {
            var unit = WEIGHT_UNITS[u] as String;
            if (Str.endsWith(tok, unit) && tok.length() > unit.length()
                    && Str.isWeightNumber(Str.sub(tok, 0, tok.length() - unit.length()))) {
                return true;
            }
        }
        return false;
    }

    // ---------- loads: "43/30kg", "24 kg", "@60kg", "(53/35 lb)", "1.5 pood" ----------

    // kg per unit, x10000 to stay in integers
    function kgPer(unit as String) as Number {
        if (unit.equals("kg") || unit.equals("kgs")) { return 10000; }
        if (unit.equals("pood") || unit.equals("pd")) { return 163800; }
        return 4536;  // lb, lbs, #
    }

    function weightValues(num as String, unit as String) as Array<Number>? {
        var parts = Str.splitOn(num, '/');
        var out = [] as Array<Number>;
        for (var i = 0; i < parts.size(); i++) {
            if (parts[i].length() == 0 || !Str.isNumeric(parts[i])) { return null; }
            var f = parts[i].toFloat();
            if (f == null) { return null; }
            var kg = Math.round(f * kgPer(unit) / 10000.0).toNumber();
            if (kg <= 0) { return null; }
            out.add(kg);
        }
        return out.size() > 0 ? out : null;
    }

    function stripAt(tok as String) as String {
        return Str.startsWith(tok, "@") ? Str.sub(tok, 1, tok.length()) : tok;
    }

    // First load written in these tokens, in kg: [rx] or [rx, alternative].
    // Without a unit, loads are kg: "20/14", "@60". In brackets any number is a
    // load: "(24)", "(43/30)".
    // kg first: "(150/100lbs || 70/45kg)" gives 70/45.
    function findLoad(t as Array<String>, inBrackets as Boolean) as Array<Number>? {
        var v = findLoadUnits(t, ["kg", "kgs"] as Array<String>);
        if (v == null) { v = findLoadUnits(t, WEIGHT_UNITS as Array<String>); }
        if (v == null) { v = findLoadBare(t, inBrackets); }
        return v;
    }

    function findLoadUnits(t as Array<String>, units as Array<String>) as Array<Number>? {
        for (var k = 0; k < t.size(); k++) {
            var tok = stripAt(t[k]);
            for (var u = 0; u < units.size(); u++) {
                var unit = units[u];
                if (Str.endsWith(tok, unit) && tok.length() > unit.length()) {
                    var num = Str.sub(tok, 0, tok.length() - unit.length());
                    if (Str.isWeightNumber(num)) {
                        var v = weightValues(num, unit);
                        if (v != null) { return v; }
                    }
                }
            }
            if (Str.indexIn(units, tok) >= 0 && k > 0) {
                var prev = stripAt(t[k - 1]);
                if (Str.isWeightNumber(prev)) {
                    var v = weightValues(prev, tok);
                    if (v != null) { return v; }
                }
            }
        }
        return null;
    }

    // no unit written: kg
    function findLoadBare(t as Array<String>, inBrackets as Boolean) as Array<Number>? {
        for (var k = 0; k < t.size(); k++) {
            var at = Str.startsWith(t[k], "@");
            var tok = stripAt(t[k]);
            if (k + 1 < t.size() && Str.indexIn(WEIGHT_UNITS as Array<String>, t[k + 1]) >= 0) { continue; }
            if (Str.isWeightNumber(tok) && (at || inBrackets || Str.contains(tok, "/"))) {
                var v = weightValues(tok, "kg");
                if (v != null) { return v; }
            }
            if (t[k].equals("@") && k + 1 < t.size() && Str.isWeightNumber(t[k + 1])) {
                var v = weightValues(t[k + 1], "kg");
                if (v != null) { return v; }
            }
        }
        return null;
    }

    function bracketText(s as String) as String {
        var cs = s.toCharArray();
        var out = [] as Array<Char>;
        var depth = 0;
        for (var i = 0; i < cs.size(); i++) {
            var c = cs[i];
            if (c == '(' || c == '[') {
                depth++;
                out.add(' ');
            } else if (c == ')' || c == ']') {
                if (depth > 0) { depth--; }
                out.add(' ');
            } else if (depth > 0) {
                out.add(c);
            }
        }
        return StringUtil.charArrayToString(out);
    }

    // "Tough set of", "Max", "In remaining time, max": the movement is done for max reps.
    const MAX_PREFIXES = [
        "in the remaining time", "in remaining time", "with the remaining time", "with remaining time",
        "tough set of", "tough set", "max reps of", "max reps", "max rep", "max effort", "max set of", "max"
    ];
    // Words that name a variant of a catalog movement: "strict HSPU" is still HSPU.
    const VARIANT_WORDS = ["strict", "kipping", "butterfly", "unbroken", "tempo", "deficit", "banded", "heel", "elevated", "weighted", "paused", "pause"];

    function isLetter(c as Char) as Boolean {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }

    // "3 Deadlift @ 145-155 kg (72.5-77.5%)", "20 goblet squats @ RPE 7-8": the
    // intensity notes are not part of the movement. Cuts at "RPE", keeps the load.
    function cutNotes(raw as String) as String {
        var low = raw.toLower();
        var cs = low.toCharArray();
        for (var i = 0; i + 3 <= cs.size(); i++) {
            if (cs[i] != 'r' || cs[i + 1] != 'p' || cs[i + 2] != 'e') { continue; }
            if (i > 0 && isLetter(cs[i - 1])) { continue; }
            if (i + 3 < cs.size() && isLetter(cs[i + 3])) { continue; }
            var s = Str.sub(raw, 0, i);
            while (s.length() > 0) {
                var last = s.toCharArray()[s.length() - 1];
                if (last != ' ' && last != '@' && last != '[' && last != '(') { break; }
                s = Str.sub(s, 0, s.length() - 1);
            }
            return s;
        }
        return raw;
    }

    // "145-155" before a weight unit (or after @): the lower value.
    function loadRange(tok as String) as String? {
        var d = Str.indexOf(tok, "-");
        if (d <= 0) { return null; }
        var a = Str.sub(tok, 0, d);
        var b = Str.sub(tok, d + 1, tok.length());
        return Str.isNumeric(a) && Str.isNumeric(b) ? a : null;
    }

    function isSepChar(c as Char) as Boolean {
        return c == ' ' || c == ',' || c == ':';
    }

    // [rest of the line, true] when it starts with a max qualifier.
    function stripMax(raw as String) as Array {
        var s = Str.trim(raw);
        var found = false;
        var again = true;
        while (again) {
            again = false;
            var low = s.toLower();
            for (var i = 0; i < MAX_PREFIXES.size(); i++) {
                var p = MAX_PREFIXES[i] as String;
                if (Str.startsWith(low, p) && (low.length() == p.length() || isSepChar(low.toCharArray()[p.length()]))) {
                    s = Str.sub(s, p.length(), s.length());
                    while (s.length() > 0 && isSepChar(s.toCharArray()[0])) { s = Str.sub(s, 1, s.length()); }
                    found = true;
                    again = true;
                    break;
                }
            }
        }
        return [s, found];
    }

    // "8/6 cal ski": men / women reps, left first. Returns [reps, alt] or null.
    function repsPair(tok as String) as Array<Number>? {
        var parts = Str.splitOn(tok, '/');
        if (parts.size() != 2 || !Str.isInt(parts[0]) || !Str.isInt(parts[1])) { return null; }
        return [Str.toInt(parts[0]), Str.toInt(parts[1])];
    }

    function parseMovement(raw0 as String) as Dictionary {
        var sm = stripMax(cutNotes(raw0));
        var raw = sm[0] as String;
        var isMax = sm[1] as Boolean;
        var t0 = Str.tokens(stripBrackets(raw).toLower());
        // load ranges: "@ 145-155 kg", "145-155kg" -> 145
        for (var k = 0; k < t0.size(); k++) {
            var tok = t0[k];
            var at = Str.startsWith(tok, "@");
            if (at) { tok = Str.sub(tok, 1, tok.length()); }
            var wunit = "";
            for (var u = 0; u < WEIGHT_UNITS.size(); u++) {
                var wu = WEIGHT_UNITS[u] as String;
                if (Str.endsWith(tok, wu) && tok.length() > wu.length()) {
                    wunit = wu;
                    break;
                }
            }
            var core = wunit.length() > 0 ? Str.sub(tok, 0, tok.length() - wunit.length()) : tok;
            var lo = loadRange(core);
            if (lo == null) { continue; }
            var nextUnit = k + 1 < t0.size() && Str.indexIn(WEIGHT_UNITS as Array<String>, t0[k + 1]) >= 0;
            var prevAt = at || (k > 0 && t0[k - 1].equals("@"));
            if (wunit.length() > 0 || nextUnit || prevAt) { t0[k] = (at ? "@" : "") + lo + wunit; }
        }
        // a pair first on the line is a men / women rep count, not a load
        var pair = null;
        if (t0.size() > 1 && Str.indexIn(WEIGHT_UNITS as Array<String>, t0[1]) < 0) {
            pair = repsPair(t0[0]);
            if (pair != null) { t0 = t0.slice(1, null); }
        }
        var load = findLoad(t0, false);
        if (load == null) { load = findLoad(Str.tokens(bracketText(raw).toLower()), true); }

        // drop loads: "43/30kg", "20/14", "24 kg", "@", "@60kg"
        var t1 = [] as Array<String>;
        for (var k = 0; k < t0.size(); k++) {
            var tok = t0[k];
            if (Str.startsWith(tok, "@")) { continue; }
            if (Str.contains(tok, "/") && Str.isWeightNumber(tok)) { continue; }
            if (isWeightToken(tok)) { continue; }
            if (Str.indexIn(WEIGHT_UNITS as Array<String>, tok) >= 0 && t1.size() > 0 && Str.isWeightNumber(t1[t1.size() - 1])) {
                t1 = t1.slice(0, t1.size() - 1);
                continue;
            }
            t1.add(tok);
        }

        if (pair != null) {
            var withPair = [(pair as Array<Number>)[0].format("%d")] as Array<String>;
            withPair.addAll(t1);
            t1 = withPair;
        }

        // split "200m" -> "200" "m", "10x" -> "10" "x"
        var t = [] as Array<String>;
        for (var k = 0; k < t1.size(); k++) {
            var tok = t1[k];
            var cs = tok.toCharArray();
            var i = 0;
            while (i < cs.size() && (Str.isDigitChar(cs[i]) || cs[i] == '.')) { i++; }
            if (i > 0 && i < cs.size() && Str.isNumeric(Str.sub(tok, 0, i))) {
                t.add(Str.sub(tok, 0, i));
                t.add(Str.sub(tok, i, tok.length()));
            } else {
                t.add(tok);
            }
        }

        var reps = 0;
        var unit = "reps";
        var used = new [t.size()];
        for (var k = 0; k < t.size(); k++) { used[k] = false; }
        for (var k = 0; k < t.size(); k++) {
            if (!Str.isNumeric(t[k])) { continue; }
            var value = t[k].toFloat();
            var mult = 1 as Numeric;
            used[k] = true;
            if (k + 1 < t.size()) {
                var u = unitFor(t[k + 1]);
                if (u != null) {
                    unit = u[0] as String;
                    mult = u[1] as Numeric;
                    used[k + 1] = true;
                }
                if (t[k + 1].equals("x")) { used[k + 1] = true; }
            }
            if (k > 0 && t[k - 1].equals("x")) { used[k - 1] = true; }
            reps = value == null ? 0 : Math.round(value * mult).toNumber();
            if (pair != null) { (pair as Array<Number>)[1] = Math.round((pair as Array<Number>)[1] * mult).toNumber(); }
            break;
        }

        var rest = [] as Array<String>;
        for (var k = 0; k < t.size(); k++) {
            if (!used[k]) { rest.add(t[k]); }
        }
        var text = Str.join(rest, " ");
        var id = Movements.lookup(text);
        var name;
        if (id != null) {
            name = Movements.name(id);
        } else {
            name = text.length() > 0 ? Str.capitalize(text) : Str.trim(raw);
            // "strict ring dip": the catalog movement, the written name
            var core = [] as Array<String>;
            for (var k = 0; k < rest.size(); k++) {
                if (Str.indexIn(VARIANT_WORDS as Array<String>, rest[k]) < 0) { core.add(rest[k]); }
            }
            var coreText = Str.join(core, " ");
            if (coreText.length() > 0 && !coreText.equals(text)) { id = Movements.lookup(coreText); }
        }
        if (isMax) {
            reps = 0;
            pair = null;
        }
        // "max hold": a time, not reps
        if (reps == 0 && unit.equals("reps") && rest.size() > 0 && rest[rest.size() - 1].equals("hold")) { unit = "sec"; }
        var b = {
            "movement" => id == null ? "custom" : id,
            "name" => name,
            "reps" => reps,
            "unit" => unit,
            "slot" => null,
            "load" => load
        };
        if (pair != null && reps > 0) { b["repsAlt"] = (pair as Array<Number>)[1]; }
        return b;
    }

    // ---------- option lines: time cap, rest, every-minute task ----------

    // Tokens of a line without brackets, commas, lone colons and trailing colons.
    function optionTokens(line as String) as Array<String> {
        var out = [] as Array<String>;
        var t = Str.tokens(Str.replaceChars(line.toLower(), "()[],", ' '));
        for (var k = 0; k < t.size(); k++) {
            var tok = t[k];
            while (Str.endsWith(tok, ":")) { tok = Str.sub(tok, 0, tok.length() - 1); }
            if (tok.length() > 0) { out.add(tok); }
        }
        return out;
    }

    // "Cap: 10:00", "Time cap 12 min", "TC 15" -> seconds, or -1.
    function parseCapLine(line as String) as Number {
        var t = optionTokens(line);
        var k = -1;
        if (t.size() >= 2 && t[0].equals("time") && t[1].equals("cap")) {
            k = 2;
        } else if (t.size() >= 1 && (t[0].equals("cap") || t[0].equals("tc") || t[0].equals("timecap"))) {
            k = 1;
        }
        if (k < 0) { return -1; }
        var d = durationAt(t, k);
        return d != null && d[1] == t.size() ? d[0] : -1;
    }

    // "Rest 3:00 between sets", "Rest 90 sec" -> [sec, betweenSets], or null.
    function parseRestLine(line as String) as Array? {
        var t = optionTokens(line);
        if (t.size() < 2) { return null; }
        // "1:00 Rest" -> "rest 1:00"
        if (!t[0].equals("rest")) {
            var d0 = durationAt(t, 0);
            if (d0 == null || d0[1] >= t.size() || !t[d0[1]].equals("rest")) { return null; }
            var moved = ["rest"] as Array<String>;
            moved.addAll(t.slice(0, d0[1]));
            moved.addAll(t.slice(d0[1] + 1, null));
            t = moved;
        }
        var d = durationAt(t, 1);
        if (d == null) { return null; }
        var ok = ["between", "sets", "set", "rounds", "round", "each", "after"] as Array<String>;
        for (var k = d[1]; k < t.size(); k++) {
            if (Str.indexIn(ok, t[k]) < 0) { return null; }
        }
        return [d[0], d[1] < t.size()];
    }

    // "Every minute on the minute (including 0:00), complete 8/6 cal ski",
    // "EMOM: 5 burpees", "Every 2:00, 10 wall balls" inside an AMRAP / For time.
    // Returns [everySec, at0, body] or null.
    function parseTaskLine(line as String) as Array? {
        var low = line.toLower();
        var cs = low.toCharArray();
        // split at the first "," or ":" that is not inside a time like 2:00
        var p = -1;
        for (var i = 0; i < cs.size(); i++) {
            var c = cs[i];
            if (c == ',' || (c == ':' && !(i > 0 && Str.isDigitChar(cs[i - 1]) && i + 1 < cs.size() && Str.isDigitChar(cs[i + 1])))) {
                p = i;
                break;
            }
        }
        if (p <= 0) { return null; }
        var head = optionTokens(Str.sub(low, 0, p));
        var every = -1;
        for (var k = 0; k < head.size(); k++) {
            var tok = head[k];
            if (tok.length() >= 4 && Str.startsWith(tok, "e") && Str.endsWith(tok, "mom")) {
                var mid = Str.sub(tok, 1, tok.length() - 3);
                if (mid.length() == 0) {
                    every = 60;
                } else if (Str.isInt(mid)) {
                    every = Str.toInt(mid) * 60;
                }
                break;
            }
            if (tok.equals("every") && k + 1 < head.size()) {
                var nx = head[k + 1];
                if (nx.equals("minute") || nx.equals("min")) {
                    every = 60;
                } else if (nx.equals("other") && k + 2 < head.size() && (head[k + 2].equals("minute") || head[k + 2].equals("min"))) {
                    every = 120;
                } else {
                    var d = durationAt(head, k + 1);
                    if (d != null) { every = d[0]; }
                }
                break;
            }
        }
        if (every <= 0) { return null; }
        var body = Str.trim(Str.sub(line, p + 1, line.length()));
        var bt = Str.tokens(body);
        if (bt.size() > 0) {
            var f = bt[0].toLower();
            if (f.equals("complete") || f.equals("do") || f.equals("perform")) { body = Str.join(bt.slice(1, null), " "); }
        }
        if (body.length() == 0) { return null; }
        return [every, Str.indexIn(head, "0:00") >= 0, body];
    }

    // ---------- rep scheme / slots / lines ----------

    // "21-15-9" -> [[21, 15, 9], null]
    // "3-6-9-..." or "3-6-9..." (open ladder) -> [[3, 6, 9], 3]
    function parseRepScheme(line as String) as Array? {
        var s = Str.removeChars(line, " ");
        var open = false;
        var tails = ["...", "…", "+"];  // "…" = the ellipsis character
        for (var k = 0; k < tails.size(); k++) {
            var tail = tails[k] as String;
            if (Str.endsWith(s, tail)) {
                open = true;
                s = Str.sub(s, 0, s.length() - tail.length());
                if (Str.endsWith(s, "-")) { s = Str.sub(s, 0, s.length() - 1); }
                break;
            }
        }
        if (!Str.contains(s, "-") && !(open && Str.isInt(s))) { return null; }
        var parts = Str.splitOn(s, '-');
        var out = [] as Array<Number>;
        for (var i = 0; i < parts.size(); i++) {
            if (!Str.isInt(parts[i])) { return null; }
            out.add(Str.toInt(parts[i]));
        }
        var step = null;
        if (open) {
            var n = out.size();
            step = n >= 2 ? out[n - 1] - out[n - 2] : out[0];
            if (step <= 0) { return null; }
        }
        return [out, step];
    }

    // "odd: x" -> [0, "x"], "even: x" -> [1, "x"], "min 3: x" -> [2, "x"]
    function parseSlot(line as String) as Array? {
        var c = Str.indexOf(line, ":");
        if (c <= 0) { return null; }
        var head = Str.tokens(Str.sub(line, 0, c).toLower());
        var body = Str.trim(Str.sub(line, c + 1, line.length()));
        if (head.size() == 1 && head[0].equals("odd")) { return [0, body]; }
        if (head.size() == 1 && head[0].equals("even")) { return [1, body]; }
        if (head.size() == 2 && (head[0].equals("min") || head[0].equals("minute")) && Str.isInt(head[1]) && Str.toInt(head[1]) > 0) {
            return [Str.toInt(head[1]) - 1, body];
        }
        return null;
    }

    function splitLines(text as String) as Array<String> {
        var out = [] as Array<String>;
        var cur = [] as Array<Char>;
        var cs = text.toCharArray();
        for (var i = 0; i <= cs.size(); i++) {
            var end = i == cs.size();
            // "(150/100lbs || 70/45kg)": two loads, not two lines
            if (!end && cs[i] == '|' && ((i + 1 < cs.size() && cs[i + 1] == '|') || (i > 0 && cs[i - 1] == '|'))) {
                cur.add(' ');
                continue;
            }
            if (end || cs[i] == '\n' || cs[i] == '\r' || cs[i] == ';' || cs[i] == '|') {
                var line = Str.trim(StringUtil.charArrayToString(cur));
                if (line.length() > 0) { out.add(line); }
                cur = [] as Array<Char>;
            } else {
                cur.add(cs[i]);
            }
        }
        return out;
    }

    // ---------- main entry ----------

    function parse(text as String?) as Dictionary {
        var lines = splitLines(text == null ? "" : text);
        var name = null;
        var header = null;
        var headerLine = null;
        var repScheme = null;
        var repStep = null;
        var blocks = [] as Array<Dictionary>;
        var nextSlot = 0;
        var task = null;

        for (var n = 0; n < lines.size(); n++) {
            var line = lines[n];
            if (Str.startsWith(line, "#")) {
                name = Str.trim(Str.sub(line, 1, line.length()));
                continue;
            }
            if (Str.startsWith(line.toLower(), "name:")) {
                name = Str.trim(Str.sub(line, 5, line.length()));
                continue;
            }

            if (header == null) {
                var h = parseHeader(line);
                if (h == null) {
                    return { "error" => "Unknown WOD type: " + line, "line" => n + 1 };
                }
                if (h.hasKey("error")) {
                    h["line"] = n + 1;
                    return h;
                }
                header = h;
                headerLine = line;
                if (h["inline"] != null) {
                    var ip = Str.splitOn(h["inline"] as String, '+');
                    for (var q = 0; q < ip.size(); q++) {
                        if (Str.trim(ip[q]).length() == 0) { continue; }
                        var ib = parseMovement(ip[q]);
                        ib["slot"] = 0;
                        blocks.add(ib);
                    }
                    nextSlot = 1;
                }
                continue;
            }

            var scheme = parseRepScheme(line);
            if (scheme != null) {
                repScheme = scheme[0];
                repStep = scheme[1];
                continue;
            }

            // "RPE 8", "@ RPE 7-8" on its own line: an intensity note, not a movement
            if (Str.trim(cutNotes(line)).length() == 0) { continue; }

            var htype = header["type"] as String;
            var cap = parseCapLine(line);
            if (cap > 0) {
                if (htype.equals("FOR_TIME")) { header["timeCapSec"] = cap; }
                continue;
            }
            var restLine = parseRestLine(line);
            if (restLine != null) {
                if ((header["sets"] as Number) > 1) {
                    header["setRestSec"] = restLine[0];
                } else {
                    blocks.add({ "movement" => "rest", "name" => "Rest", "reps" => restLine[0], "unit" => "sec", "slot" => null, "load" => null });
                }
                continue;
            }
            if (htype.equals("AMRAP") || htype.equals("FOR_TIME")) {
                var tl = parseTaskLine(line);
                if (tl != null) {
                    var tb = [] as Array<Dictionary>;
                    var tp = Str.splitOn(tl[2] as String, '+');
                    for (var q = 0; q < tp.size(); q++) {
                        if (Str.trim(tp[q]).length() > 0) { tb.add(parseMovement(tp[q])); }
                    }
                    task = { "everySec" => tl[0], "at0" => tl[1], "blocks" => tb };
                    continue;
                }
            }

            var slot = null;
            var body = line;
            var sp = parseSlot(line);
            if (sp != null) {
                slot = sp[0] as Number;
                body = sp[1] as String;
            }
            var type = header["type"] as String;
            var interval = type.equals("EMOM") || type.equals("TABATA");
            if (header["deathBy"] == true) { slot = 0; }
            if (interval && slot == null) { slot = nextSlot; }

            var parts = Str.splitOn(body, '+');
            for (var p = 0; p < parts.size(); p++) {
                if (Str.trim(parts[p]).length() == 0) { continue; }
                var b = parseMovement(parts[p]);
                b["slot"] = interval ? slot : null;
                blocks.add(b);
            }
            if (interval && (slot as Number) + 1 > nextSlot) { nextSlot = (slot as Number) + 1; }
        }
        Movements.release();

        if (header == null) { return { "error" => "Empty WOD", "line" => 0 }; }
        if (blocks.size() == 0) { return { "error" => "No movements found", "line" => lines.size() }; }

        var wod = {
            "version" => 1,
            "name" => name != null ? name : headerLine,
            "type" => header["type"],
            "timeCapSec" => header["timeCapSec"],
            "intervalSec" => header["intervalSec"],
            "workSec" => header["workSec"],
            "restSec" => header["restSec"],
            "rounds" => header["rounds"],
            "repScheme" => null,
            "repStep" => null,
            "blocks" => blocks
        };
        if ((header["type"] as String).equals("FOR_TIME") && repStep != null) {
            return { "error" => "An open ladder (3-6-9-...) needs an AMRAP", "line" => lines.size() };
        }
        if ((header["type"] as String).equals("AMRAP") && repScheme != null) {
            wod["repScheme"] = repScheme;
            wod["repStep"] = repStep;
        }
        if (header["deathBy"] == true) {
            // start at the written reps (1 by default) and add that much every minute
            for (var i = 0; i < blocks.size(); i++) {
                if ((blocks[i]["reps"] as Number) == 0) { blocks[i]["reps"] = 1; }
            }
            wod["repStep"] = blocks[0]["reps"];
        }
        if ((header["type"] as String).equals("FOR_TIME")) {
            if (repScheme != null) {
                wod["repScheme"] = repScheme;
                wod["rounds"] = (repScheme as Array).size();
            } else if (wod["rounds"] == null) {
                wod["rounds"] = 1;
            }
        }
        // optional keys, only when used (older files stay valid)
        if ((header["sets"] as Number) > 1) {
            wod["sets"] = header["sets"];
            wod["setRestSec"] = header["setRestSec"];
        }
        if (task != null && ((task as Dictionary)["blocks"] as Array).size() > 0) { wod["task"] = task; }
        return { "wod" => wod };
    }

    // ---------- JSON validation (WODs fetched from a URL) ----------

    function isPosInt(v) as Boolean {
        return v instanceof Number && (v as Number) > 0;
    }

    function optInt(v) as Boolean {
        return v == null || v instanceof Number;
    }

    // The athlete's side of "15/12 cal": side 1 takes the second number.
    // Returns a copy, the stored WOD is left as written.
    function forSide(wod as Dictionary, side as Number) as Dictionary {
        if (side != 1) { return wod; }
        var out = {} as Dictionary;
        var keys = wod.keys();
        for (var i = 0; i < keys.size(); i++) { out[keys[i]] = wod[keys[i]]; }
        out["blocks"] = sideBlocks(wod["blocks"] as Array<Dictionary>);
        var tk = wod["task"];
        if (tk instanceof Dictionary) {
            out["task"] = { "everySec" => (tk as Dictionary)["everySec"], "at0" => (tk as Dictionary)["at0"],
                "blocks" => sideBlocks((tk as Dictionary)["blocks"] as Array<Dictionary>) };
        }
        return out;
    }

    function sideBlocks(blocks as Array<Dictionary>) as Array<Dictionary> {
        var out = [] as Array<Dictionary>;
        for (var i = 0; i < blocks.size(); i++) {
            var b = blocks[i];
            if (b["repsAlt"] instanceof Number) {
                b = { "movement" => b["movement"], "name" => b["name"], "reps" => b["repsAlt"], "unit" => b["unit"],
                    "slot" => b["slot"], "load" => b["load"] };
            }
            out.add(b);
        }
        return out;
    }

    function validateBlock(raw) as Dictionary {
        if (!(raw instanceof Dictionary)) { return err("Each block needs a movement"); }
        var b = raw as Dictionary;
        var mv = b["movement"];
        if (!(mv instanceof String)) { return err("Each block needs a movement"); }
        var reps = b["reps"] == null ? 0 : b["reps"];
        if (!(reps instanceof Number) || (reps as Number) < 0) { return err("Block reps must be an integer >= 0"); }
        var unit = b["unit"] == null ? "reps" : b["unit"];
        if (!(unit instanceof String)
                || !((unit as String).equals("reps") || unit.equals("m") || unit.equals("cal") || unit.equals("sec"))) {
            return err("Unknown unit");
        }
        if (!optInt(b["slot"])) { return err("Block slot must be an integer or null"); }
        var bl = b["load"];
        if (bl != null) {
            if (!(bl instanceof Array) || (bl as Array).size() < 1 || (bl as Array).size() > 2) {
                return err("Block load must be a list of 1 or 2 positive integers (kg)");
            }
            for (var j = 0; j < (bl as Array).size(); j++) {
                if (!isPosInt((bl as Array)[j])) { return err("Block load must be a list of 1 or 2 positive integers (kg)"); }
            }
        }
        var alt = b["repsAlt"];
        if (alt != null && (!(alt instanceof Number) || (alt as Number) < 0)) { return err("Block repsAlt must be an integer >= 0"); }
        var bname = b["name"];
        if (!(bname instanceof String) || (bname as String).length() == 0) {
            bname = Movements.name(mv as String);
            if (bname == null) { bname = mv; }
        }
        var out = { "movement" => mv, "name" => bname, "reps" => reps, "unit" => unit, "slot" => b["slot"], "load" => bl };
        if (alt != null) { out["repsAlt"] = alt; }
        return out;
    }

    function validate(obj) as Dictionary {
        if (!(obj instanceof Dictionary)) { return err("WOD must be an object"); }
        var o = obj as Dictionary;
        if (o["version"] != 1) { return err("Unsupported WOD version"); }
        var type = o["type"];
        if (!(type instanceof String)
                || !((type as String).equals("AMRAP") || type.equals("EMOM") || type.equals("FOR_TIME") || type.equals("TABATA"))) {
            return err("Unknown WOD type");
        }
        var keys = ["timeCapSec", "intervalSec", "workSec", "restSec", "rounds", "repStep"];
        for (var i = 0; i < keys.size(); i++) {
            if (!optInt(o[keys[i]])) { return err(keys[i] + " must be an integer or null"); }
        }
        var rawBlocks = o["blocks"];
        if (!(rawBlocks instanceof Array) || (rawBlocks as Array).size() == 0) {
            return err("WOD needs at least one block");
        }
        var name = o["name"];
        var wod = {
            "version" => 1,
            "name" => (name instanceof String && (name as String).length() > 0) ? name : "WOD",
            "type" => type,
            "timeCapSec" => o["timeCapSec"],
            "intervalSec" => o["intervalSec"],
            "workSec" => o["workSec"],
            "restSec" => o["restSec"],
            "rounds" => o["rounds"],
            "repScheme" => null,
            "repStep" => isPosInt(o["repStep"]) ? o["repStep"] : null,
            "blocks" => []
        };
        var rs = o["repScheme"];
        if (rs != null) {
            if (!(rs instanceof Array) || (rs as Array).size() == 0) { return err("repScheme must be a list of positive integers"); }
            for (var i = 0; i < (rs as Array).size(); i++) {
                if (!isPosInt((rs as Array)[i])) { return err("repScheme must be a list of positive integers"); }
            }
            wod["repScheme"] = rs;
        }
        var blocks = [] as Array<Dictionary>;
        var rb = rawBlocks as Array;
        for (var i = 0; i < rb.size(); i++) {
            var v = validateBlock(rb[i]);
            if (v.hasKey("error")) { return v; }
            blocks.add(v);
        }
        wod["blocks"] = blocks;
        if ((type as String).equals("AMRAP") && o["sets"] != null) {
            if (!isPosInt(o["sets"])) { return err("sets must be an integer >= 1"); }
            var sr = o["setRestSec"] == null ? 0 : o["setRestSec"];
            if (!(sr instanceof Number) || (sr as Number) < 0) { return err("setRestSec must be an integer >= 0"); }
            if ((o["sets"] as Number) > 1) {
                wod["sets"] = o["sets"];
                wod["setRestSec"] = sr;
            }
        }
        if (((type as String).equals("AMRAP") || type.equals("FOR_TIME")) && o["task"] != null) {
            var tk = o["task"];
            if (!(tk instanceof Dictionary) || !isPosInt((tk as Dictionary)["everySec"])) { return err("task needs everySec > 0"); }
            var trb = (tk as Dictionary)["blocks"];
            if (!(trb instanceof Array) || (trb as Array).size() == 0) { return err("task needs at least one block"); }
            var tbs = [] as Array<Dictionary>;
            for (var i = 0; i < (trb as Array).size(); i++) {
                var v = validateBlock((trb as Array)[i]);
                if (v.hasKey("error")) { return v; }
                v["slot"] = null;
                tbs.add(v);
            }
            wod["task"] = { "everySec" => (tk as Dictionary)["everySec"], "at0" => (tk as Dictionary)["at0"] == true, "blocks" => tbs };
        }

        var t = type as String;
        if (t.equals("AMRAP")) {
            if (!isPosInt(wod["timeCapSec"])) { return err("AMRAP needs timeCapSec"); }
            if (wod["repScheme"] == null) { wod["repStep"] = null; }
        } else if (t.equals("EMOM")) {
            if (!isPosInt(wod["intervalSec"])) { return err("EMOM needs intervalSec"); }
            var iv = wod["intervalSec"] as Number;
            if (!isPosInt(wod["rounds"])) {
                if (!isPosInt(wod["timeCapSec"])) { return err("EMOM needs rounds or timeCapSec"); }
                wod["rounds"] = (wod["timeCapSec"] as Number) / iv;
            }
            wod["timeCapSec"] = (wod["rounds"] as Number) * iv;
        } else if (t.equals("FOR_TIME")) {
            wod["repStep"] = null;
            if (wod["repScheme"] != null) { wod["rounds"] = (wod["repScheme"] as Array).size(); }
            if (!isPosInt(wod["rounds"])) { wod["rounds"] = 1; }
        } else {
            wod["repStep"] = null;
            if (!isPosInt(wod["workSec"])) { wod["workSec"] = 20; }
            if (wod["restSec"] == null || (wod["restSec"] as Number) < 0) { wod["restSec"] = 10; }
            if (!isPosInt(wod["rounds"])) { wod["rounds"] = 8; }
            var w = wod["workSec"] as Number;
            var r = wod["restSec"] as Number;
            wod["intervalSec"] = w + r;
            wod["timeCapSec"] = (wod["rounds"] as Number) * (w + r) - r;
        }

        var interval = t.equals("EMOM") || t.equals("TABATA");
        var next = 0;
        for (var i = 0; i < blocks.size(); i++) {
            if (!interval) {
                blocks[i]["slot"] = null;
                continue;
            }
            if (blocks[i]["slot"] == null) { blocks[i]["slot"] = next; }
            var s = blocks[i]["slot"] as Number;
            if (s + 1 > next) { next = s + 1; }
        }
        return { "wod" => wod };
    }
}
