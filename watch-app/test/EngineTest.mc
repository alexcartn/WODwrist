import Toybox.Lang;
import Toybox.Test;

// Ports of web-editor/test/engine.test.js (the reference suite).

(:test)
module EngineTestUtil {
    function wod(text as String) as Dictionary {
        var r = WodParser.parse(text);
        Test.assertMessage(r.hasKey("wod"), "parse failed");
        return r["wod"] as Dictionary;
    }

    function count(ev as Array<Array<Number> >, code as Number) as Number {
        var n = 0;
        for (var i = 0; i < ev.size(); i++) {
            if (ev[i][0] == code) { n++; }
        }
        return n;
    }

    function run(e as TimerEngine, t0 as Number, t1 as Number) as Array<Array<Number> > {
        var ev = [] as Array<Array<Number> >;
        for (var t = t0; t <= t1; t += 250) {
            var x = e.tick(t);
            for (var i = 0; i < x.size(); i++) { ev.add(x[i]); }
        }
        return ev;
    }
}

(:test)
function engineCountdown(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("AMRAP 1\n5 burpees"), 10);
    e.start(0);
    Test.assertEqual(e.state, ST_COUNTDOWN);
    var ev = EngineTestUtil.run(e, 0, 10000);
    Test.assertEqual(EngineTestUtil.count(ev, EV_WARN), 3);
    Test.assertEqual(EngineTestUtil.count(ev, EV_START), 1);
    Test.assertEqual(e.state, ST_WORK);
    return true;
}

(:test)
function engineAmrap(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("AMRAP 2\n3 burpees\n2 wall balls"), 0);
    e.start(0);
    var laps = 0;
    for (var r = 0; r < 2; r++) {
        for (var i = 0; i < 5; i++) {
            laps += EngineTestUtil.count(e.addRep(1, 1000), EV_LAP);
        }
    }
    e.addRep(1, 1000);
    Test.assertEqual(laps, 2);
    EngineTestUtil.run(e, 1000, 120000);
    Test.assertEqual(e.state, ST_DONE);
    Test.assertEqual(e.roundsCompleted, 2);
    Test.assertEqual(e.lapReps, 1);
    TestUtil.check(logger, e.scoreText(), "2 + 1", "score");
    return true;
}

(:test)
function engineForTime(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("FOR TIME cap 15\n21-15-9\nthrusters\npull-ups"), 0);
    e.start(0);
    var now = 0;
    var scheme = [21, 15, 9];
    for (var r = 0; r < 3; r++) {
        Test.assertEqual(e.target(e.currentBlock()), scheme[r]);
        for (var i = 0; i < scheme[r] * 2; i++) {
            now += 1000;
            e.tick(now);
            e.addRep(1, now);
        }
    }
    Test.assertEqual(e.state, ST_DONE);
    Test.assert(e.hasTimeScore());
    Test.assertEqual(e.finalActiveMs(), 90000);
    TestUtil.check(logger, e.scoreText(), "1:30", "score");
    return true;
}

(:test)
function engineEmomAlternates(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("EMOM 4\nodd: 12 kb swings\neven: 10 burpees"), 0);
    e.start(0);
    var seen = [] as Array<String>;
    var laps = 0;
    var done = 0;
    for (var t = 0; t <= 240000; t += 250) {
        var ev = e.tick(t);
        laps += EngineTestUtil.count(ev, EV_LAP);
        done += EngineTestUtil.count(ev, EV_DONE);
        if (e.state == ST_WORK && t % 60000 == 1000) {
            seen.add((e.currentBlock() as Dictionary)["movement"] as String);
            e.addRep(3, t);
        }
    }
    TestUtil.checkArray(logger, seen, ["kb_swing", "burpee", "kb_swing", "burpee"], "movements");
    Test.assertEqual(laps, 3);
    Test.assertEqual(done, 1);
    Test.assertEqual(e.totalReps, 12);
    return true;
}

(:test)
function engineTabata(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("TABATA 8x20/10\nair squats\npush-ups"), 0);
    e.start(0);
    var ev = EngineTestUtil.run(e, 0, 240000);
    Test.assertEqual(EngineTestUtil.count(ev, EV_REST), 7);
    Test.assertEqual(EngineTestUtil.count(ev, EV_LAP), 7);
    Test.assertEqual(EngineTestUtil.count(ev, EV_DONE), 1);
    Test.assertEqual(e.activeMs(999999), 230000);
    return true;
}

(:test)
function enginePause(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("AMRAP 10\n5 burpees"), 0);
    e.start(0);
    e.tick(5000);
    e.pause(5000);
    Test.assertEqual(e.clockMs(60000), 595000);
    e.addRep(1, 60000);
    Test.assertEqual(e.totalReps, 0);
    e.resume(60000);
    Test.assertEqual(e.clockMs(61000), 594000);
    return true;
}

(:test)
function engineNextCredits(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("FOR TIME\n10 burpees\n5 wall balls"), 0);
    e.start(0);
    e.addRep(1, 0);
    e.next(0);
    Test.assertEqual(e.totalReps, 10);
    e.next(0);
    Test.assertEqual(e.state, ST_DONE);
    Test.assertEqual(e.totalReps, 15);
    return true;
}

(:test)
function engineNextBlocks(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("EMOM 3\nodd: 12 kb swings\neven: 10 burpees"), 0);
    e.start(0);
    TestUtil.check(logger, e.nextBlocks()[0]["movement"], "burpee", "next at min 1");
    e.tick(60000);
    TestUtil.check(logger, e.nextBlocks()[0]["movement"], "kb_swing", "next at min 2");
    e.tick(120000);
    Test.assertEqual(e.nextBlocks().size(), 0);
    return true;
}

(:test)
function engineOpenLadder(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("AMRAP 20\n3-6-9-...\nthrusters\nchest to bar"), 0);
    e.start(0);
    var want = [3, 6, 9, 12, 15];
    for (var r = 0; r < 5; r++) {
        Test.assertEqual(e.target(e.currentBlock()), want[r]);
        e.next(0);
        e.next(0);
    }
    Test.assertEqual(e.roundsCompleted, 5);
    return true;
}

(:test)
function engineDeathBy(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("DEATH BY burpees"), 0);
    e.start(0);
    Test.assertEqual(e.totalRounds(), 0);
    var done = 0;
    for (var m = 0; m < 5; m++) {
        var t = m * 60000 + 1000;
        done += EngineTestUtil.count(e.tick(t), EV_DONE);
        Test.assertEqual(e.target(e.currentBlock()), m + 1);
        e.addRep(m < 4 ? m + 1 : 3, t);
    }
    done += EngineTestUtil.count(e.tick(300000), EV_DONE);
    Test.assertEqual(done, 1);
    Test.assertEqual(e.state, ST_DONE);
    Test.assertEqual(e.roundsCompleted, 4);
    Test.assertEqual(e.lapReps, 3);
    TestUtil.check(logger, e.scoreText(), "4 + 3", "score");
    return true;
}
