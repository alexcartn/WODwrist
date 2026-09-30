import Toybox.Lang;
import Toybox.StringUtil;

// String helpers. Monkey C has no regex, so the parser works on tokens.
// Mirrors the helpers at the top of web-editor/js/wod-parser.js.
module Str {

    // substring() is typed String? in recent SDKs; indices here are always valid.
    function sub(s as String, a as Number, b as Number) as String {
        return s.substring(a, b) as String;
    }

    function isDigitChar(c as Char) as Boolean {
        var n = c.toNumber();
        return n >= 48 && n <= 57;
    }

    function isNumeric(s as String) as Boolean {
        if (s.length() == 0 || s.equals(".")) { return false; }
        var dots = 0;
        var cs = s.toCharArray();
        for (var i = 0; i < cs.size(); i++) {
            if (cs[i] == '.') {
                dots++;
                if (dots > 1) { return false; }
            } else if (!isDigitChar(cs[i])) {
                return false;
            }
        }
        return true;
    }

    function isInt(s as String) as Boolean {
        if (s.length() == 0) { return false; }
        var cs = s.toCharArray();
        for (var i = 0; i < cs.size(); i++) {
            if (!isDigitChar(cs[i])) { return false; }
        }
        return true;
    }

    // Only digits, dots and slashes, with at least one digit: "43/30", "9.5".
    function isWeightNumber(s as String) as Boolean {
        var digit = false;
        var cs = s.toCharArray();
        for (var i = 0; i < cs.size(); i++) {
            if (isDigitChar(cs[i])) {
                digit = true;
            } else if (cs[i] != '.' && cs[i] != '/') {
                return false;
            }
        }
        return digit;
    }

    function toInt(s as String) as Number {
        var n = s.toNumber();
        return n == null ? 0 : n;
    }

    function isSpace(c as Char) as Boolean {
        return c == ' ' || c == '\t';
    }

    function trim(s as String) as String {
        var cs = s.toCharArray();
        var a = 0;
        var b = cs.size();
        while (a < b && isSpace(cs[a])) { a++; }
        while (b > a && isSpace(cs[b - 1])) { b--; }
        return sub(s, a, b);
    }

    function tokens(s as String) as Array<String> {
        var out = [] as Array<String>;
        var cur = [] as Array<Char>;
        var cs = s.toCharArray();
        for (var i = 0; i < cs.size(); i++) {
            if (isSpace(cs[i])) {
                if (cur.size() > 0) {
                    out.add(StringUtil.charArrayToString(cur));
                    cur = [] as Array<Char>;
                }
            } else {
                cur.add(cs[i]);
            }
        }
        if (cur.size() > 0) { out.add(StringUtil.charArrayToString(cur)); }
        return out;
    }

    // Split on one character, keeping empty parts.
    function splitOn(s as String, sep as Char) as Array<String> {
        var out = [] as Array<String>;
        var cur = [] as Array<Char>;
        var cs = s.toCharArray();
        for (var i = 0; i < cs.size(); i++) {
            if (cs[i] == sep) {
                out.add(StringUtil.charArrayToString(cur));
                cur = [] as Array<Char>;
            } else {
                cur.add(cs[i]);
            }
        }
        out.add(StringUtil.charArrayToString(cur));
        return out;
    }

    function join(parts as Array<String>, sep as String) as String {
        var s = "";
        for (var i = 0; i < parts.size(); i++) {
            if (i > 0) { s += sep; }
            s += parts[i];
        }
        return s;
    }

    function replaceChars(s as String, chars as String, by as Char) as String {
        var cs = s.toCharArray();
        var set = chars.toCharArray();
        for (var i = 0; i < cs.size(); i++) {
            for (var j = 0; j < set.size(); j++) {
                if (cs[i] == set[j]) {
                    cs[i] = by;
                    break;
                }
            }
        }
        return StringUtil.charArrayToString(cs);
    }

    function removeChars(s as String, chars as String) as String {
        var cs = s.toCharArray();
        var set = chars.toCharArray();
        var out = [] as Array<Char>;
        for (var i = 0; i < cs.size(); i++) {
            var keep = true;
            for (var j = 0; j < set.size(); j++) {
                if (cs[i] == set[j]) { keep = false; break; }
            }
            if (keep) { out.add(cs[i]); }
        }
        return StringUtil.charArrayToString(out);
    }

    function indexOf(s as String, sub as String) as Number {
        var i = s.find(sub);
        return i == null ? -1 : i;
    }

    function contains(s as String, sub as String) as Boolean {
        return s.find(sub) != null;
    }

    function startsWith(s as String, prefix as String) as Boolean {
        return s.length() >= prefix.length() && sub(s, 0, prefix.length()).equals(prefix);
    }

    function endsWith(s as String, suffix as String) as Boolean {
        var n = s.length();
        var k = suffix.length();
        return n >= k && sub(s, n - k, n).equals(suffix);
    }

    function indexIn(arr as Array<String>, s as String) as Number {
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i].equals(s)) { return i; }
        }
        return -1;
    }

    function capitalize(s as String) as String {
        if (s.length() == 0) { return s; }
        return sub(s, 0, 1).toUpper() + sub(s, 1, s.length());
    }

    // 754000 -> "12:34", 3723000 -> "1:02:03"
    function clock(ms as Number, roundUp as Boolean) as String {
        var sec = roundUp ? (ms + 999) / 1000 : ms / 1000;
        if (sec < 0) { sec = 0; }
        var h = sec / 3600;
        var m = (sec % 3600) / 60;
        var s = sec % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%d") + ":" + s.format("%02d");
    }
}
