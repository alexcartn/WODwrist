import Toybox.Lang;
import Toybox.Test;

// Ports of web-editor/test/history.test.js (pure functions only).

(:test)
function historySignature(logger as Test.Logger) as Boolean {
    var a = EngineTestUtil.wod("# Monday\nAMRAP 12\n10 wall balls\n10 burpees");
    var b = EngineTestUtil.wod("# Friday\nAMRAP 12\n10 wall balls\n10 burpees");
    var c = EngineTestUtil.wod("AMRAP 12\n10 wall balls\n12 burpees");
    Test.assert(ScoreHistory.signature(a).equals(ScoreHistory.signature(b)));
    Test.assert(!ScoreHistory.signature(a).equals(ScoreHistory.signature(c)));
    return true;
}

(:test)
function historyCompare(logger as Test.Logger) as Boolean {
    var r1 = { "kind" => "rounds", "rounds" => 7, "reps" => 12 };
    var r2 = { "kind" => "rounds", "rounds" => 7, "reps" => 3 };
    Test.assert(ScoreHistory.isBetter(r1, r2));
    Test.assert(!ScoreHistory.isBetter(r2, r1));
    Test.assert(ScoreHistory.isBetter({ "kind" => "time", "ms" => 900000 }, { "kind" => "reps", "reps" => 400 }));
    Test.assert(ScoreHistory.isBetter(r2, null));
    return true;
}

(:test)
function historyPace(logger as Test.Logger) as Boolean {
    var ref = [90000, 185000, 283000];
    Test.assert(ScoreHistory.paceDelta([] as Array<Number>, ref) == null);
    Test.assertEqual(ScoreHistory.paceDelta([85000], ref), -5000);
    Test.assertEqual(ScoreHistory.paceDelta([85000, 199000], ref), 14000);
    Test.assert(ScoreHistory.paceDelta([1, 2, 3, 4], ref) == null);
    TestUtil.check(logger, ScoreHistory.formatDelta(-8400), "-0:08", "delta");
    TestUtil.check(logger, ScoreHistory.formatDelta(75000), "+1:15", "delta");
    TestUtil.check(logger, ScoreHistory.scoreText({ "kind" => "rounds", "rounds" => 7, "reps" => 12 }), "7 + 12", "score");
    return true;
}
