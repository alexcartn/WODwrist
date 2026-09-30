import Toybox.Lang;
import Toybox.Test;

// Null-safe equality asserts for the unit tests.
(:test)
module TestUtil {

    function eq(a, b) as Boolean {
        if (a == null || b == null) { return a == null && b == null; }
        return a.equals(b);
    }

    function check(logger as Test.Logger, got, want, what as String) as Void {
        if (!eq(got, want)) {
            logger.error(what + ": got " + got + ", want " + want);
        }
        Test.assertMessage(eq(got, want), what);
    }

    function checkArray(logger as Test.Logger, got, want as Array, what as String) as Void {
        Test.assertMessage(got instanceof Array, what + " is not an array");
        var g = got as Array;
        check(logger, g.size(), want.size(), what + " size");
        for (var i = 0; i < want.size(); i++) {
            check(logger, g[i], want[i], what + "[" + i + "]");
        }
    }
}
