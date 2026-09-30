import Toybox.Lang;
import Toybox.Test;

// Same deterministic vector as rep-lab/tests/test_replab.py
// (test_deterministic_vector_shared_with_monkey_c): both must agree.
(:test)
function repCounterDeterministic(logger as Test.Logger) as Boolean {
    var c = new RepCounter(null, false);
    c.setProfile([128, 300, 100, 800]);
    var t = 0;
    var reps = [] as Array<Number>;
    for (var i = 0; i < 40; i++) {
        c.feed(t, 0, 0, 1000);
        t += 40;
    }
    for (var r = 0; r < 10; r++) {
        for (var k = 0; k < 50; k++) {
            var z = 1000;
            if (k >= 5 && k < 12) {
                z = k < 9 ? 1000 + (k - 4) * 150 : 1000 + (12 - k) * 200;
            }
            var hit = c.feed(t, 0, 0, z);
            if (hit >= 0) { reps.add(hit); }
            t += 40;
        }
    }
    for (var i = 0; i < 40; i++) {
        var hit = c.feed(t, 0, 0, 1000);
        if (hit >= 0) { reps.add(hit); }
        t += 40;
    }
    Test.assertEqual(reps.size(), 10);
    Test.assertEqual(reps[0], 1960);
    Test.assert(c.confidence() >= 80);
    return true;
}

(:test)
function repCounterDisabledCountsNothing(logger as Test.Logger) as Boolean {
    var c = new RepCounter(null, false);
    c.setProfile(null);
    var n = 0;
    for (var i = 0; i < 500; i++) {
        if (c.feed(i * 40, 0, 0, i % 50 < 7 ? 2000 : 1000) >= 0) { n++; }
    }
    Test.assertEqual(n, 0);
    return true;
}

(:test)
function parserErrors(logger as Test.Logger) as Boolean {
    Test.assert(WodParser.parse("").hasKey("error"));
    Test.assert(WodParser.parse("10 burpees").hasKey("error"));
    Test.assert(WodParser.parse("AMRAP\n10 burpees").hasKey("error"));
    Test.assert(WodParser.parse("AMRAP 10").hasKey("error"));
    Test.assert(WodParser.parse("TABATA 8x20\nsquats").hasKey("error"));
    return true;
}

(:test)
function parserSamplesAreValid(logger as Test.Logger) as Boolean {
    for (var i = 0; i < SampleWods.count(); i++) {
        Test.assertMessage(SampleWods.get(i) != null, "sample " + i);
    }
    return true;
}

(:test)
function sampleLabelsMatchTheParsedNames(logger as Test.Logger) as Boolean {
    for (var i = 0; i < SampleWods.count(); i++) {
        var l = SampleWods.label(i);
        Test.assertEqualMessage(l[0], (SampleWods.get(i) as Dictionary)["name"], "sample " + i);
        Test.assertMessage(l[1].length() > 0, "format line " + i);
    }
    return true;
}

(:test)
function validateJson(logger as Test.Logger) as Boolean {
    var r = WodParser.validate({
        "version" => 1, "type" => "EMOM", "intervalSec" => 60, "timeCapSec" => 600,
        "blocks" => [{ "movement" => "burpee", "reps" => 10 }]
    });
    Test.assert(r.hasKey("wod"));
    var w = r["wod"] as Dictionary;
    Test.assertEqual(w["rounds"], 10);
    var b = (w["blocks"] as Array<Dictionary>)[0];
    Test.assertEqual(b["slot"], 0);
    TestUtil.check(logger, b["name"], "Burpees", "name");
    TestUtil.check(logger, b["unit"], "reps", "unit");
    Test.assert(WodParser.validate({ "version" => 2 }).hasKey("error"));
    return true;
}
