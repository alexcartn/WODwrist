import Toybox.Attention;
import Toybox.Lang;

// Vibration + tones. Coach mode vibrates longer so the whole class feels it
// on the coach's wrist even while moving around.
module Feedback {

    var strong as Boolean = false;

    function vibe(ms as Number) as Void {
        if (!(Attention has :vibrate)) { return; }
        var d = strong ? ms * 2 : ms;
        Attention.vibrate([new Attention.VibeProfile(100, d)]);
    }

    function tone(t) as Void {
        if (Attention has :playTone) {
            Attention.playTone(t);
        }
    }

    // 3-2-1 before a segment ends / before start
    function warn(sec as Number) as Void {
        vibe(120);
        tone(Attention.TONE_KEY);
    }

    function go() as Void {
        vibe(600);
        tone(Attention.TONE_START);
    }

    function interval() as Void {
        vibe(500);
        tone(Attention.TONE_INTERVAL_ALERT);
    }

    function rest() as Void {
        vibe(300);
        tone(Attention.TONE_LAP);
    }

    function round() as Void {
        vibe(400);
        tone(Attention.TONE_LAP);
    }

    function block() as Void {
        vibe(150);
    }

    function done() as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 400),
                new Attention.VibeProfile(0, 200),
                new Attention.VibeProfile(100, 400),
                new Attention.VibeProfile(0, 200),
                new Attention.VibeProfile(100, 800)
            ]);
        }
        tone(Attention.TONE_SUCCESS);
    }
}
