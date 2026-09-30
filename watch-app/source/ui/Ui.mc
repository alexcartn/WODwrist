import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// One color language across the app:
//   green = work / go / good, blue = rest, yellow = scores and targets,
//   orange = warnings, red = danger, grey = secondary.
module Theme {
    const WORK = Graphics.COLOR_GREEN;
    const REST = Graphics.COLOR_BLUE;
    const SCORE = Graphics.COLOR_YELLOW;
    const WARN = Graphics.COLOR_ORANGE;
    const DANGER = Graphics.COLOR_RED;
    const TEXT = Graphics.COLOR_WHITE;
    const MUTED = Graphics.COLOR_LT_GRAY;
    const DIM = Graphics.COLOR_DK_GRAY;
}

const ICON_CHECK = 0;
const ICON_CROSS = 1;
const ICON_PLAY = 2;

// Drawing helpers shared by the views: progress ring, page dots, Garmin-style
// button hints, text that fits.
module Ui {

    const CENTER = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function isRound() as Boolean {
        return System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_ROUND;
    }

    // Progress around the bezel, clockwise from 12 o'clock. On square screens,
    // a bar along the top edge.
    function ring(dc as Graphics.Dc, done as Number, total as Number, color as Number, width as Number) as Void {
        if (total <= 0) { return; }
        var w = dc.getWidth();
        var h = dc.getHeight();
        // float: ms x 1000 would overflow 32-bit integers on long WODs
        var f = (done.toFloat() * 1000 / total).toNumber();
        if (f > 1000) { f = 1000; }
        if (f < 0) { f = 0; }
        if (!isRound()) {
            dc.setColor(Theme.DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, 0, w, width);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, 0, w * f / 1000, width);
            return;
        }
        var r = w / 2 - width / 2 - 1;
        dc.setPenWidth(width);
        dc.setColor(Theme.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(w / 2, h / 2, r);
        if (f > 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            // Garmin angles: 0 = 3 o'clock, counterclockwise; 90 = 12 o'clock
            var end = 90 - f * 360 / 1000;
            if (f >= 1000) {
                dc.drawCircle(w / 2, h / 2, r);
            } else {
                dc.drawArc(w / 2, h / 2, r, Graphics.ARC_CLOCKWISE, 90, end);
            }
        }
        dc.setPenWidth(1);
    }

    // Small arc for a secondary progress (reps of the current set), inside the ring.
    function innerArc(dc as Graphics.Dc, done as Number, total as Number, color as Number, inset as Number) as Void {
        if (total <= 0 || !isRound()) { return; }
        var w = dc.getWidth();
        var f = (done.toFloat() * 1000 / total).toNumber();
        if (f > 1000) { f = 1000; }
        if (f <= 0) { return; }
        dc.setPenWidth(3);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        // bottom half, from 7 to 5 o'clock
        var span = 120 * f / 1000;
        dc.drawArc(w / 2, dc.getHeight() / 2, w / 2 - inset, Graphics.ARC_COUNTER_CLOCKWISE, 210, 210 + span);
        dc.setPenWidth(1);
    }

    // Vertical page dots on the right edge (3 o'clock).
    function pageDots(dc as Graphics.Dc, page as Number, count as Number) as Void {
        if (count < 2) { return; }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var gap = h / 30;
        var x = w - w / 25;
        var y0 = h / 2 - (count - 1) * gap / 2;
        for (var i = 0; i < count; i++) {
            dc.setColor(i == page ? Theme.TEXT : Theme.DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y0 + i * gap, i == page ? 4 : 3);
        }
    }

    // Garmin-style hint next to a physical button: a short colored arc on the
    // bezel and a small icon just inside it (no words: they would collide with
    // the content). top = START (upper right), else BACK (lower right).
    function buttonHint(dc as Graphics.Dc, top as Boolean, color as Number, icon as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var deg = top ? 30 : -30;
        var x;
        var y;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (isRound()) {
            dc.setPenWidth(6);
            dc.drawArc(w / 2, h / 2, w / 2 - 4, Graphics.ARC_COUNTER_CLOCKWISE, deg - 8, deg + 8);
            var rad = deg * Math.PI / 180;
            var r = w / 2 - w / 16;
            x = w / 2 + (r * Math.cos(rad)).toNumber();
            y = h / 2 - (r * Math.sin(rad)).toNumber();
        } else {
            dc.fillRectangle(w - 5, top ? h * 25 / 100 : h * 65 / 100, 5, h / 10);
            x = w - w / 12;
            y = top ? h * 30 / 100 : h * 70 / 100;
        }
        var k = w / 50;  // icon half size
        dc.setPenWidth(3);
        if (icon == ICON_CHECK) {
            dc.drawLine(x - k, y, x - k / 3, y + k * 2 / 3);
            dc.drawLine(x - k / 3, y + k * 2 / 3, x + k, y - k * 2 / 3);
        } else if (icon == ICON_CROSS) {
            dc.drawLine(x - k * 2 / 3, y - k * 2 / 3, x + k * 2 / 3, y + k * 2 / 3);
            dc.drawLine(x - k * 2 / 3, y + k * 2 / 3, x + k * 2 / 3, y - k * 2 / 3);
        } else {
            dc.fillPolygon([[x - k * 2 / 3, y - k], [x - k * 2 / 3, y + k], [x + k, y]]);
        }
        dc.setPenWidth(1);
    }

    // Text shortened with "…" to fit maxWidth pixels.
    function fit(dc as Graphics.Dc, text as String, font as Graphics.FontType, maxWidth as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) { return text; }
        var s = text;
        while (s.length() > 1) {
            s = Str.sub(s, 0, s.length() - 1);
            var t = Str.trim(s) + "…";
            if (dc.getTextWidthInPixels(t, font) <= maxWidth) { return t; }
        }
        return s;
    }

    // Usable width at height y on a round screen (chord), minus a margin.
    function widthAt(dc as Graphics.Dc, y as Number) as Number {
        var w = dc.getWidth();
        if (!isRound()) { return w * 90 / 100; }
        var r = w / 2;
        var dy = y - dc.getHeight() / 2;
        if (dy < 0) { dy = -dy; }
        if (dy >= r) { return 0; }
        return (2 * Math.sqrt(r * r - dy * dy)).toNumber() * 88 / 100;
    }
}
