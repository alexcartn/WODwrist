import Toybox.Lang;

// Short human strings for menus, preview and summary.
module WodFormat {

    function minutes(sec as Number) as String {
        if (sec % 60 == 0) { return (sec / 60).format("%d") + " min"; }
        return Str.clock(sec * 1000, false);
    }

    // "AMRAP 12 min", "EMOM 10 x 1:00", "For time 21-15-9, cap 15 min", "Tabata 8 x 20/10"
    function headline(wod as Dictionary) as String {
        var type = wod["type"] as String;
        if (type.equals("AMRAP")) {
            return "AMRAP " + minutes(wod["timeCapSec"] as Number);
        }
        if (type.equals("EMOM")) {
            var iv = wod["intervalSec"] as Number;
            var label = iv == 60 ? "EMOM" : "E" + (iv / 60).format("%d") + "MOM";
            return label + " " + minutes(wod["timeCapSec"] as Number);
        }
        if (type.equals("FOR_TIME")) {
            var s = "For time";
            var rs = wod["repScheme"];
            if (rs != null) {
                var parts = [] as Array<String>;
                for (var i = 0; i < (rs as Array).size(); i++) { parts.add(((rs as Array)[i] as Number).format("%d")); }
                s += " " + Str.join(parts, "-");
            } else if ((wod["rounds"] as Number) > 1) {
                s = (wod["rounds"] as Number).format("%d") + " RFT";
            }
            if (wod["timeCapSec"] != null) { s += ", cap " + minutes(wod["timeCapSec"] as Number); }
            return s;
        }
        return "Tabata " + (wod["rounds"] as Number).format("%d") + " x "
            + (wod["workSec"] as Number).format("%d") + "/" + (wod["restSec"] as Number).format("%d");
    }

    // "10 Wall balls", "200 m Run", "Air squats" (max reps)
    function block(b as Dictionary) as String {
        var reps = b["reps"] as Number;
        var name = b["name"] as String;
        if (reps == 0) { return name; }
        var unit = b["unit"] as String;
        if (unit.equals("m")) { return reps.format("%d") + " m " + name; }
        if (unit.equals("cal")) { return reps.format("%d") + " cal " + name; }
        if (unit.equals("sec")) { return reps.format("%d") + " s " + name; }
        return reps.format("%d") + " " + name;
    }

    // Target text for the run screen: "10", "200 m", "30 s", "max"
    function target(unit as String, n as Number) as String {
        if (n == 0) { return "max"; }
        if (unit.equals("m")) { return n.format("%d") + " m"; }
        if (unit.equals("cal")) { return n.format("%d") + " cal"; }
        if (unit.equals("sec")) { return n.format("%d") + " s"; }
        return n.format("%d");
    }
}
