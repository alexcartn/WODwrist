import Toybox.Lang;

// Lookup helpers over the generated MovementCatalog.
module Movements {

    var _aliases as Dictionary<String, String>? = null;
    var _names as Dictionary<String, String>? = null;
    var _profiles as Dictionary<String, Array<Number> >? = null;

    // The alias table is only needed while parsing: call release() after.
    function release() as Void {
        _aliases = null;
    }

    function normalize(s as String) as String {
        return Str.join(Str.tokens(Str.replaceChars(s.toLower(), "-_.", ' ')), " ");
    }

    function lookup(text as String) as String? {
        if (_aliases == null) { _aliases = MovementCatalog.aliases(); }
        var a = _aliases as Dictionary<String, String>;
        var n = normalize(text);
        var id = a.get(n);
        if (id != null) { return id; }
        var len = n.length();
        if (Str.endsWith(n, "es")) {
            id = a.get(Str.sub(n, 0, len - 2));
            if (id != null) { return id; }
        }
        if (Str.endsWith(n, "s")) {
            id = a.get(Str.sub(n, 0, len - 1));
            if (id != null) { return id; }
        }
        return null;
    }

    function name(id as String) as String? {
        if (_names == null) { _names = MovementCatalog.names(); }
        return (_names as Dictionary<String, String>).get(id);
    }

    // [alphaQ8, hiMg, loMg, minGapMs] or null when the movement is counted by hand.
    function profile(id as String) as Array<Number>? {
        if (_profiles == null) { _profiles = MovementCatalog.counterProfiles(); }
        return (_profiles as Dictionary<String, Array<Number> >).get(id);
    }
}
