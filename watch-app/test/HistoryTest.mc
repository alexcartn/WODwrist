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

(:test)
function historyStats(logger as Test.Logger) as Boolean {
    Test.assertEqual(ScoreHistory.fadePct([90000, 185000, 290000]), 17);
    Test.assertEqual(ScoreHistory.fadePct([100000, 190000]), -10);
    Test.assert(ScoreHistory.fadePct([90000]) == null);
    Test.assertEqual(ScoreHistory.tenthsPerRep(10, 24000), 24);
    Test.assert(ScoreHistory.tenthsPerRep(0, 1000) == null);
    TestUtil.check(logger, ScoreHistory.formatTenths(24), "2.4 s", "tenths");
    return true;
}

// Ports of web-editor/test/coach.test.js
(:test)
function coachAlerts(logger as Test.Logger) as Boolean {
    var a = Coach.alertsDue(359000, 360000, 720000, true, true);
    Test.assertEqual(a.size(), 1);
    Test.assertEqual(a[0], ALERT_HALF);
    Test.assertEqual(Coach.alertsDue(360000, 361000, 720000, true, true).size(), 0);
    Test.assertEqual(Coach.alertsDue(659500, 660250, 720000, true, true)[0], ALERT_ONE_MIN);
    Test.assertEqual(Coach.alertsDue(0, 720000, 720000, true, true).size(), 2);
    Test.assertEqual(Coach.alertsDue(59000, 61000, 120000, false, true).size(), 0);
    Test.assertEqual(Coach.alertsDue(1000, 999999, 0, true, true).size(), 0);
    return true;
}

(:test)
function coachNextSlot(logger as Test.Logger) as Boolean {
    Test.assertEqual(Coach.secondsToNextSlot(18, 22, 10, 15, 30), 470);
    Test.assertEqual(Coach.secondsToNextSlot(18, 29, 50, 15, 30), 910);
    Test.assertEqual(Coach.secondsToNextSlot(18, 29, 50, 1, 30), 70);
    Test.assertEqual(Coach.secondsToNextSlot(23, 50, 0, 15, 30), 600);
    return true;
}
