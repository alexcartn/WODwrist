import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

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

    // Every menu in the dark theme, whatever the watch setting: the menu
    // pictograms are white and vanish on a light menu.
    function menu(title as String) as WatchUi.Menu2 {
        var opts = { :title => title } as Dictionary;
        if (WatchUi has :MENU_THEME_DARK) { opts[:theme] = WatchUi.MENU_THEME_DARK; }
        return new WatchUi.Menu2(opts);
    }

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

    // ---------- 7-segment "gym timer" digits ----------

    // segments a b c d e f g per digit, as bits 0..6
    const SEGS = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F];

    function clockWidth(text as String, h as Number) as Number {
        var cs = text.toCharArray();
        var w = 0;
        for (var i = 0; i < cs.size(); i++) {
            w += charWidth(cs[i], h);
            if (i < cs.size() - 1) { w += h / 9; }
        }
        return w;
    }

    // "1" is narrow, like on real gym timers (no gap in "1:32").
    function charWidth(c as Char, h as Number) as Number {
        if (c == ':') { return h * 28 / 100; }
        if (c == '1') { return h * 58 / 100 / 3 + 2; }
        return h * 58 / 100;
    }

    // Digits and ':' centered on (cx, cy), h pixels tall.
    function drawClock(dc as Graphics.Dc, text as String, cx as Number, cy as Number, h as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var t = h / 9;                 // segment thickness
        if (t < 3) { t = 3; }
        var dw = h * 58 / 100;         // digit width
        var x = cx - clockWidth(text, h) / 2;
        var y = cy - h / 2;
        var cs = text.toCharArray();
        for (var i = 0; i < cs.size(); i++) {
            var c = cs[i];
            if (c == ':') {
                var cw = h * 28 / 100;
                dc.fillRoundedRectangle(x + (cw - t) / 2, y + h * 30 / 100 - t / 2, t, t, t / 3);
                dc.fillRoundedRectangle(x + (cw - t) / 2, y + h * 70 / 100 - t / 2, t, t, t / 3);
                x += cw + h / 9;
                continue;
            }
            var n = c.toNumber() - 48;
            var cw1 = charWidth(c, h);
            // a "1" keeps its segments on the right edge of its narrow cell
            if (n >= 0 && n <= 9) { digit(dc, SEGS[n] as Number, x + cw1 - dw, y, dw, h, t); }
            x += cw1 + h / 9;
        }
    }

    function digit(dc as Graphics.Dc, m as Number, x as Number, y as Number, w as Number, h as Number, t as Number) as Void {
        var g = t / 4 + 1;             // gap between segments
        var half = h / 2;
        var hl = w - 2 * g;            // horizontal length
        var vl = half - t / 2 - 2 * g; // vertical length
        var r = t / 2;
        if ((m & 0x01) != 0) { dc.fillRoundedRectangle(x + g, y, hl, t, r); }                               // a
        if ((m & 0x02) != 0) { dc.fillRoundedRectangle(x + w - t, y + g + t / 2, t, vl, r); }              // b
        if ((m & 0x04) != 0) { dc.fillRoundedRectangle(x + w - t, y + half + g, t, vl, r); }              // c
        if ((m & 0x08) != 0) { dc.fillRoundedRectangle(x + g, y + h - t, hl, t, r); }                       // d
        if ((m & 0x10) != 0) { dc.fillRoundedRectangle(x, y + half + g, t, vl, r); }                        // e
        if ((m & 0x20) != 0) { dc.fillRoundedRectangle(x, y + g + t / 2, t, vl, r); }                      // f
        if ((m & 0x40) != 0) { dc.fillRoundedRectangle(x + g, y + half - t / 2, hl, t, r); }               // g
    }

    // ---------- charts ----------

    // Bars from the bottom of the box. colors: one per bar (or null = MUTED).
    // lo = value drawn as a minimal bar (so small differences stay visible).
    function bars(dc as Graphics.Dc, v as Array<Number>, colors as Array<Number>?, x as Number, y as Number,
            w as Number, h as Number, lo as Number) as Void {
        var n = v.size();
        if (n == 0) { return; }
        var max = lo + 1;
        for (var i = 0; i < n; i++) { if (v[i] > max) { max = v[i]; } }
        var slot = w / n;
        var bw = slot * 7 / 10;
        if (bw < 2) { bw = 2; }
        for (var i = 0; i < n; i++) {
            var val = v[i] - lo;
            if (val < 0) { val = 0; }
            var bh = h / 8 + (h - h / 8) * val / (max - lo);
            dc.setColor(colors == null ? Theme.MUTED : (colors as Array<Number>)[i], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + i * slot + (slot - bw) / 2, y + h - bh, bw, bh);
        }
    }

    // Polyline scaled between the min and max of v.
    function line(dc as Graphics.Dc, v as Array<Number>, color as Number, x as Number, y as Number, w as Number, h as Number) as Void {
        var n = v.size();
        if (n < 2) { return; }
        var min = v[0];
        var max = v[0];
        for (var i = 1; i < n; i++) {
            if (v[i] < min) { min = v[i]; }
            if (v[i] > max) { max = v[i]; }
        }
        if (max == min) { max = min + 1; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        var px = x;
        var py = y + h - (v[0] - min) * h / (max - min);
        for (var i = 1; i < n; i++) {
            var qx = x + i * w / (n - 1);
            var qy = y + h - (v[i] - min) * h / (max - min);
            dc.drawLine(px, py, qx, qy);
            px = qx;
            py = qy;
        }
        dc.setPenWidth(1);
    }
}
