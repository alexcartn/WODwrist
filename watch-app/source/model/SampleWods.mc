import Toybox.Lang;

// Built-in WODs so the app is usable before any import (and to test the parser).
module SampleWods {

    function texts() as Array<String> {
        return [
            "# Wall ball AMRAP\nAMRAP 12\n10 wall balls\n10 burpees\n200m run",
            "# Swing EMOM\nEMOM 10\nodd: 12 kb swings\neven: 10 burpees",
            "# Fran-ish\nFOR TIME cap 10\n21-15-9\nthrusters\npull-ups",
            "# Tabata squats\nTABATA 8x20/10\nair squats",
            "# DB snatch E2MOM\nE2MOM 12\n20 alt db snatches + 10 burpees"
        ] as Array<String>;
    }

    function count() as Number {
        return texts().size();
    }

    function get(i as Number) as Dictionary? {
        var r = WodParser.parse(texts()[i]);
        return r.hasKey("wod") ? r["wod"] as Dictionary : null;
    }
}
