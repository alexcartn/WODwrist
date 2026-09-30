import Toybox.Attention;
import Toybox.Lang;

// Tones only: the watch never vibrates (the athlete asked for no vibration).
// Every alert also shows on screen, so the tones are a bonus.
module Feedback {

    // kept for WorkoutSession (coach mode), no effect without vibration
    var strong as Boolean = false;

    function tone(t) as Void {
        if (Attention has :playTone) {
            Attention.playTone(t);
        }
    }

    // 3-2-1 before a segment ends / before start
    function warn(sec as Number) as Void {
        tone(Attention.TONE_KEY);
    }

    function go() as Void {
        tone(Attention.TONE_START);
    }

    function interval() as Void {
        tone(Attention.TONE_INTERVAL_ALERT);
    }

    function rest() as Void {
        tone(Attention.TONE_LAP);
    }

    function round() as Void {
        tone(Attention.TONE_LAP);
    }

    // Coach alerts (halfway, 1 min left, every-minute task)
    function alert() as Void {
        tone(Attention.TONE_ALERT_HI);
    }

    // new movement: the banner on screen is enough
    function block() as Void {
    }

    function done() as Void {
        tone(Attention.TONE_SUCCESS);
    }
}
