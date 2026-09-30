import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

const ALERT_HALF = 1;
const ALERT_ONE_MIN = 2;

// Start options (property "coachStart")
const START_NOW = 0;
const START_NEXT_MIN = 1;
const START_NEXT_QUARTER = 2;
const START_IN_2 = 3;
const START_IN_5 = 4;

// Coach helpers. Pure parts ported from web-editor/js/coach.js (tested there).
module Coach {

    // Alerts crossed between two ticks. totalMs = 0: WOD without fixed length.
    function alertsDue(prevMs as Number, nowMs as Number, totalMs as Number,
            halfway as Boolean, oneMin as Boolean) as Array<Number> {
        var out = [] as Array<Number>;
        if (totalMs <= 0 || nowMs <= prevMs) { return out; }
        var half = totalMs / 2;
        if (halfway && prevMs < half && nowMs >= half) { out.add(ALERT_HALF); }
        var one = totalMs - 60000;
        if (oneMin && totalMs > 120000 && prevMs < one && nowMs >= one) { out.add(ALERT_ONE_MIN); }
        return out;
    }

    // Seconds until the next multiple of stepMin minutes on the wall clock
    // (at least minLeadSec away).
    function secondsToNextSlot(hour as Number, min as Number, sec as Number,
            stepMin as Number, minLeadSec as Number) as Number {
        var now = hour * 3600 + min * 60 + sec;
        var step = stepMin * 60;
        var next = (now / step + 1) * step;
        if (next - now < minLeadSec) { next += step; }
        return next - now;
    }

    // ---------- settings ----------

    function startOption() as Number {
        return WorkoutSession.propNumber("coachStart", START_NOW);
    }

    function startLabel(opt as Number) as String {
        if (opt == START_NEXT_MIN) { return "Next full minute"; }
        if (opt == START_NEXT_QUARTER) { return "Next :00 :15 :30 :45"; }
        if (opt == START_IN_2) { return "In 2 min"; }
        if (opt == START_IN_5) { return "In 5 min"; }
        return "Now (10 s countdown)";
    }

    // Countdown in seconds for the chosen start option.
    function startDelaySec() as Number {
        var opt = startOption();
        var c = System.getClockTime();
        if (opt == START_NEXT_MIN) { return secondsToNextSlot(c.hour, c.min, c.sec, 1, 10); }
        if (opt == START_NEXT_QUARTER) { return secondsToNextSlot(c.hour, c.min, c.sec, 15, 30); }
        if (opt == START_IN_2) { return 120; }
        if (opt == START_IN_5) { return 300; }
        return WorkoutSession.propNumber("countdownSec", 10);
    }

    function restSec() as Number {
        return WorkoutSession.propNumber("planRestSec", 60);
    }

    // Stored class plan (the "wods" list of the coach file, in order).
    function plan() as Array<Dictionary> {
        var v = Application.Storage.getValue("plan");
        return v instanceof Array ? v as Array<Dictionary> : [] as Array<Dictionary>;
    }
}
