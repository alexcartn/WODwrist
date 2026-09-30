import Toybox.Lang;
import Toybox.Test;

// Ports of web-editor/test/quick.test.js (the reference suite).

(:test)
function quickDefaults(logger as Test.Logger) as Boolean {
    var w = QuickTimer.wod(QuickTimer.defaults());
    TestUtil.check(logger, w["name"] as String, "AMRAP 20", "name");
    Test.assertEqual(w["timeCapSec"], 1200);
    Test.assertEqual(QuickTimer.isQuick(w), true);
    return true;
}

(:test)
function quickNames(logger as Test.Logger) as Boolean {
    var c = QuickTimer.defaults();
    c["type"] = 2;
    c["emomEverySec"] = 2;
    TestUtil.check(logger, QuickTimer.wod(c)["name"] as String, "E2MOM 20", "e2mom");
    c["emomEverySec"] = 1;
    TestUtil.check(logger, QuickTimer.wod(c)["name"] as String, "EVERY 1:30 x 10", "every");
    c["type"] = 3;
    var t = QuickTimer.wod(c);
    TestUtil.check(logger, t["name"] as String, "TABATA 8x20/10", "tabata");
    Test.assertEqual(t["timeCapSec"], 230);
    for (var i = 0; i < 4; i++) { QuickTimer.cycle(c, "type"); }
    Test.assertEqual(c["type"], 3);
    return true;
}

(:test)
function quickAmrapRounds(logger as Test.Logger) as Boolean {
    var c = QuickTimer.defaults();
    c["amrapMin"] = 0;   // 5 min
    var e = new TimerEngine(QuickTimer.wod(c), 0);
    e.start(0);
    var rounds = 0;
    rounds += EngineTestUtil.count(e.addRep(1, 60000), EV_ROUND);
    rounds += EngineTestUtil.count(e.addRep(1, 120000), EV_ROUND);
    rounds += EngineTestUtil.count(e.addRep(1, 190000), EV_ROUND);
    Test.assertEqual(rounds, 3);
    e.tick(300000);
    Test.assertEqual(e.state, ST_DONE);
    TestUtil.check(logger, e.scoreText(), "3 + 0", "score");
    return true;
}

(:test)
function quickChrono(logger as Test.Logger) as Boolean {
    var c = QuickTimer.defaults();
    c["type"] = 1;       // For time, rounds "Chrono", no cap
    var e = new TimerEngine(QuickTimer.wod(c), 0);
    Test.assertEqual(e.totalRounds(), 0);
    e.start(0);
    var laps = 0;
    for (var i = 1; i <= 25; i++) { laps += EngineTestUtil.count(e.addRep(1, i * 1000), EV_LAP); }
    Test.assertEqual(laps, 25);
    Test.assertEqual(e.state, ST_WORK);
    e.finish(90000);
    Test.assertEqual(e.hasTimeScore(), true);
    TestUtil.check(logger, e.scoreText(), "1:30", "score");
    return true;
}

(:test)
function quickForTimeEarlyFinishIsCapped(logger as Test.Logger) as Boolean {
    var e = new TimerEngine(EngineTestUtil.wod("3 ROUNDS FOR TIME\n10 burpees"), 0);
    e.start(0);
    e.finish(5000);
    Test.assertEqual(e.hasTimeScore(), false);
    return true;
}
