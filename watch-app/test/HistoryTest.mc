import Toybox.Lang;
import Toybox.Test;

// Ports of web-editor/test/history.test.js (pure functions only).

(:test)
function historySignature(logger as Test.Logger) as Boolean {
    var a = EngineTestUtil.wod("# Monday\nAMRAP 12\n10 wall balls\n10 burpees");
    var b = EngineTestUtil.wod("# Friday\nAMRAP 12\n10 wall balls\n10 burpees");
    var c = EngineTestUtil.wod("AMRAP 12\n10 wall balls\n12 burpees");
    Test.assert(ScoreHistory.signature(a, false).equals(ScoreHistory.signature(b, false)));
    Test.assert(!ScoreHistory.signature(a, false).equals(ScoreHistory.signature(c, false)));
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

// Ports of web-editor/test/perf.test.js
(:test)
function perfZonesAndLoad(logger as Test.Logger) as Boolean {
    var b = Perf.defaultBounds(190);
    TestUtil.checkArray(logger, b, [95, 114, 133, 152, 171, 190], "bounds");
    Test.assertEqual(Perf.zoneOf(80, b), 0);
    Test.assertEqual(Perf.zoneOf(114, b), 1);
    Test.assertEqual(Perf.zoneOf(160, b), 4);
    Test.assertEqual(Perf.zoneOf(185, b), 5);
    Test.assertEqual(Perf.trimp([0, 0, 0, 600, 300, 120]), 60);
    Test.assertEqual(Perf.cvPct([90000, 100000, 110000]), 8);
    Test.assert(Perf.cvPct([1]) == null);
    Test.assertEqual(Perf.densityPct([40000, 45000, 50000], 60000), 75);
    return true;
}

(:test)
function perfAcwr(logger as Test.Logger) as Boolean {
    var e = [] as Array<Array<Number> >;
    for (var d = 100; d < 128; d += 2) { e.add([d, d == 126 ? 100 : 60]); }
    var a = Perf.acwr(e, 127, 1);
    Test.assertEqual(a[0], 220);
    Test.assertEqual(a[1], 220);
    Test.assertEqual(a[2], 100);
    TestUtil.check(logger, Perf.status(e, 127, a[2]), "optimal", "status");
    TestUtil.check(logger, Perf.status(e, 110, 200), "building", "status");
    TestUtil.check(logger, Perf.status(e, 127, 160), "risk", "status");
    return true;
}

(:test)
function perfSessionAnalysis(logger as Test.Logger) as Boolean {
    Test.assertEqual(Perf.fatiguePct([[10, 30000], [10, 33000], [10, 37500]]), 25);
    Test.assert(Perf.fatiguePct([[10, 30000]]) == null);
    Test.assertEqual(Perf.countBreaks([0, 2000, 4000, 6000, 12000, 14000, 16000]), 1);
    Test.assertEqual(Perf.countBreaks([0, 2000]), 0);
    Test.assertEqual(Perf.beatsDriftPct([[90000, 30, 150], [95000, 30, 160], [100000, 30, 170]]), 26);
    Test.assertEqual(Perf.srpeLoad(8, 12 * 60000 + 20000), 96);
    Test.assertEqual(Perf.median([5, 1, 3]), 3);
    return true;
}

(:test)
function perfWeekPattern(logger as Test.Logger) as Boolean {
    // days 1..14, sRPE 300 on odd days, 60/30/10 % domain time
    var e = [] as Array<Array<Number> >;
    for (var d = 1; d <= 14; d++) { e.add([d, 0, d % 2 == 1 ? 300 : 0, 600000, 300000, 100000]); }
    var w = Perf.weekCompare(e, 14, D_SRPE);
    Test.assertEqual(w[0], 900);
    Test.assertEqual(w[1], 1200);
    TestUtil.checkArray(logger, Perf.domainShare(e, 14, 28), [60, 30, 10], "domains");
    Test.assert(Perf.monotony(e, 100, D_SRPE) == null);
    return true;
}
