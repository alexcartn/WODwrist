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
            "deathBy" => false
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
    // Unitless numbers ("20/14") are ignored: kg or lb cannot be guessed.
    function findLoad(t as Array<String>) as Array<Number>? {
        for (var k = 0; k < t.size(); k++) {
            var tok = stripAt(t[k]);
            for (var u = 0; u < WEIGHT_UNITS.size(); u++) {
                var unit = WEIGHT_UNITS[u] as String;
                if (Str.endsWith(tok, unit) && tok.length() > unit.length()) {
                    var num = Str.sub(tok, 0, tok.length() - unit.length());
                    if (Str.isWeightNumber(num)) {
                        var v = weightValues(num, unit);
                        if (v != null) { return v; }
                    }
                }
            }
            if (Str.indexIn(WEIGHT_UNITS as Array<String>, tok) >= 0 && k > 0) {
                var prev = stripAt(t[k - 1]);
                if (Str.isWeightNumber(prev)) {
                    var v = weightValues(prev, tok);
                    if (v != null) { return v; }
                }
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

    function parseMovement(raw as String) as Dictionary {
        var t0 = Str.tokens(stripBrackets(raw).toLower());
        var load = findLoad(t0);
        if (load == null) { load = findLoad(Str.tokens(bracketText(raw).toLower())); }

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
            var mult = 1;
            used[k] = true;
            if (k + 1 < t.size()) {
                var u = unitFor(t[k + 1]);
                if (u != null) {
                    unit = u[0] as String;
                    mult = u[1] as Number;
                    used[k + 1] = true;
                }
                if (t[k + 1].equals("x")) { used[k + 1] = true; }
            }
            if (k > 0 && t[k - 1].equals("x")) { used[k - 1] = true; }
            reps = value == null ? 0 : Math.round(value * mult).toNumber();
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
        } else if (text.length() > 0) {
            name = Str.capitalize(text);
        } else {
            name = Str.trim(raw);
        }
        return {
            "movement" => id == null ? "custom" : id,
            "name" => name,
            "reps" => reps,
            "unit" => unit,
            "slot" => null,
            "load" => load
        };
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
        return { "wod" => wod };
    }

    // ---------- JSON validation (WODs fetched from a URL) ----------

    function isPosInt(v) as Boolean {
        return v instanceof Number && (v as Number) > 0;
    }

    function optInt(v) as Boolean {
        return v == null || v instanceof Number;
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
            if (!(rb[i] instanceof Dictionary)) { return err("Each block needs a movement"); }
            var b = rb[i] as Dictionary;
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
            var bname = b["name"];
            if (!(bname instanceof String) || (bname as String).length() == 0) {
                bname = Movements.name(mv as String);
                if (bname == null) { bname = mv; }
            }
            blocks.add({ "movement" => mv, "name" => bname, "reps" => reps, "unit" => unit, "slot" => b["slot"], "load" => bl });
        }
        wod["blocks"] = blocks;

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
