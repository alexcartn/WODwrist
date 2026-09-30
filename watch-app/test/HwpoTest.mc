import Toybox.Lang;
import Toybox.Test;

// Ports of web-editor/test/hwpo.test.js (the reference suite).

(:test)
function hwpoOptionLines(logger as Test.Logger) as Boolean {
    Test.assertEqual(WodParser.parseCapLine("Cap : 10:00"), 600);
    Test.assertEqual(WodParser.parseCapLine("Time cap 12 min"), 720);
    Test.assertEqual(WodParser.parseCapLine("Capture 10"), -1);
    var r = WodParser.parseRestLine("Rest 3:00 Between Sets") as Array;
    Test.assertEqual(r[0], 180);
    Test.assertEqual(r[1], true);
    var t = WodParser.parseTaskLine("Every minute on the minute (including 0:00), complete 8/6 Cal Ski") as Array;
    Test.assertEqual(t[0], 60);
    Test.assertEqual(t[1], true);
    TestUtil.check(logger, t[2], "8/6 Cal Ski", "task body");
    Test.assertEqual((WodParser.parseTaskLine("Every 2:00, 10 wall balls") as Array)[0], 120);
    Test.assertEqual(WodParser.parseTaskLine("10 burpees"), null);
    return true;
}

(:test)
function hwpoAmrapSets(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("3 x AMRAP 1\n5 burpees\nRest 0:30 between sets"), 0);
    e.start(0);
    for (var i = 0; i < 7; i++) { e.addRep(1, 10000 + i * 1000); }
    Test.assertEqual(e.clockMs(30000), 30000);
    var ev = EngineTestUtil.run(e, 0, 60000);
    Test.assertEqual(e.state, ST_REST);
    Test.assertEqual(EngineTestUtil.count(ev, EV_REST), 1);
    Test.assertEqual(e.clockMs(70000), 20000);
    Test.assertEqual(e.addRep(1, 70000).size(), 0);
    ev = EngineTestUtil.run(e, 60250, 90000);
    Test.assertEqual(EngineTestUtil.count(ev, EV_SET), 1);
    Test.assertEqual(e.state, ST_WORK);
    for (var i = 0; i < 3; i++) { e.addRep(1, 100000 + i * 1000); }
    EngineTestUtil.run(e, 90250, 240000);
    Test.assertEqual(e.state, ST_DONE);
    TestUtil.check(logger, e.scoreText(), "1 + 5", "score");
    return true;
}

(:test)
function hwpoForTimeTask(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("For Time\n50 ring push-ups\nEvery minute (including 0:00), 3 burpees\nCap: 10"), 0);
    var ev = e.start(0);
    ev.addAll(e.tick(0));
    Test.assertEqual(EngineTestUtil.count(ev, EV_TASK), 1);
    TestUtil.check(logger, (e.currentBlock() as Dictionary)["movement"], "burpee", "task block");
    e.addRep(1, 1000);
    e.addRep(1, 2000);
    ev = e.addRep(1, 3000);
    Test.assertEqual(EngineTestUtil.count(ev, EV_TASK_DONE), 1);
    TestUtil.check(logger, (e.currentBlock() as Dictionary)["movement"], "ring_push_up", "main block");
    for (var i = 0; i < 20; i++) { e.addRep(1, 4000 + i * 1000); }
    ev = EngineTestUtil.run(e, 30000, 60000);
    Test.assertEqual(EngineTestUtil.count(ev, EV_TASK), 1);
    Test.assertEqual(e.blockReps, 0);
    e.next(62000);
    Test.assertEqual(e.blockReps, 20);
    Test.assertEqual(e.totalReps, 26);
    for (var i = 0; i < 30; i++) { ev = e.addRep(1, 63000 + i * 1000); }
    Test.assertEqual(EngineTestUtil.count(ev, EV_DONE), 1);
    TestUtil.check(logger, e.scoreText(), "1:32", "score");
    return true;
}

(:test)
function hwpoSide(logger as Test.Logger) as Boolean {
    var w = EngineTestUtil.wod("AMRAP 10\n15/12 cal row");
    var f = WodParser.forSide(w, 1);
    Test.assertEqual(((f["blocks"] as Array<Dictionary>)[0])["reps"], 12);
    Test.assertEqual(((w["blocks"] as Array<Dictionary>)[0])["reps"], 15);
    TestUtil.check(logger, WodFormat.block((w["blocks"] as Array<Dictionary>)[0]), "15/12 cal Row", "format");
    return true;
}

(:test)
function hwpoStrengthLines(logger as Test.Logger) as Boolean {
    var w = EngineTestUtil.wod("3-4 Sets\n3 Deadlift @ 145-155 kg (72.5-77.5%)\nRPE 8\n1:00 Rest\n30 KB swings (53/35lbs || 24/16kg)\n100ft sled push");
    Test.assertEqual(w["type"], "FOR_TIME");
    Test.assertEqual(w["rounds"], 4);
    var b = w["blocks"] as Array<Dictionary>;
    Test.assertEqual(b.size(), 4);
    TestUtil.checkArray(logger, b[0]["load"], [145], "range");
    TestUtil.check(logger, b[1]["movement"], "rest", "rest id");
    Test.assertEqual(b[1]["reps"], 60);
    TestUtil.checkArray(logger, b[2]["load"], [24, 16], "kg first");
    Test.assertEqual(b[3]["reps"], 30);
    return true;
}

(:test)
function hwpoRestBlock(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("2 Sets\n2 deadlifts\n1:00 Rest"), 0);
    e.start(0);
    e.addRep(1, 1000);
    e.addRep(1, 5000);
    Test.assertEqual(e.restLeftMs(35000), 30000);
    var ev = EngineTestUtil.run(e, 5250, 64000);
    Test.assertEqual(EngineTestUtil.count(ev, EV_WARN), 3);
    Test.assertEqual(EngineTestUtil.count(ev, EV_ROUND), 0);
    ev = EngineTestUtil.run(e, 64250, 66000);
    Test.assertEqual(EngineTestUtil.count(ev, EV_ROUND), 1);
    Test.assertEqual(e.restLeftMs(66000), -1);
    return true;
}
