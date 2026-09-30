import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// "My stats": everything is computed on the watch from Application.Storage
// (ScoreHistory), nothing to export.

function buildStatsMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => Tr.s("My stats") });
    var t = ScoreHistory.totals();
    var e = Perf.loads();
    var today = Perf.today();
    var a = Perf.acwr(e, today, Perf.loadIndex(e, today));
    var week = Perf.weekCompare(e, today, D_SESSIONS);
    menu.addItem(new WatchUi.MenuItem(Tr.s("This week"), weekReportIsNew() ? Tr.s("New report") : week[0].format("%d") + " " + Tr.s("workouts"), :week, {}));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Training load"), loadStatusLabel(Perf.status(e, today, a[2])), :load, {}));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Balance"), Tr.s("Gym") + " / " + Tr.s("Weights") + " / " + Tr.s("Mono"), :balance, {}));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Strong / weak"), null, :strength, {}));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Overall"), (t["n"] as Number).format("%d") + " " + Tr.s("workouts"), :overall, {}));
    menu.addItem(new WatchUi.MenuItem(Tr.s("Movements"), Tr.s("Pace per rep"), :moves, {}));
    var list = ScoreHistory.entries();
    for (var i = 0; i < list.size(); i++) {
        var e = list[i];
        var name = e["name"] instanceof String ? e["name"] as String : "WOD";
        var sub = "Best " + ScoreHistory.scoreText(e["best"] as Dictionary) + "  x" + (e["n"] as Number).format("%d");
        menu.addItem(new WatchUi.MenuItem(name, sub, i, {}));
    }
    return menu;
}

// A new week started and last week had workouts, report not opened yet.
function weekReportIsNew() as Boolean {
    var today = Perf.today();
    var seen = Application.Storage.getValue("weekSeen");
    if (seen instanceof Number && (seen as Number) == today / 7) { return false; }
    return Perf.sumDays(Perf.loads(), today - 7, 7, D_SESSIONS) > 0 && today % 7 < 3;
}

function pctChange(a as Number, b as Number) as String {
    if (b <= 0) { return ""; }
    var p = ((a - b) * 100.0 / b).toNumber();
    return " (" + (p >= 0 ? "+" : "") + p.format("%d") + "%)";
}

function loadStatusLabel(st as String) as String {
    if (st.equals("low")) { return "Low: room for more"; }
    if (st.equals("optimal")) { return "Optimal"; }
    if (st.equals("high")) { return "High: watch recovery"; }
    if (st.equals("risk")) { return "Very high: ease off"; }
    return "Building baseline";
}

class StatsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var view;
        if (id == :load) {
            view = new StatsView(STATS_LOAD, null);
        } else if (id == :week) {
            Application.Storage.setValue("weekSeen", Perf.today() / 7);
            view = new StatsView(STATS_WEEK, null);
        } else if (id == :balance) {
            view = new StatsView(STATS_BALANCE, null);
        } else if (id == :strength) {
            view = new StatsView(STATS_STRENGTH, null);
        } else if (id == :overall) {
            view = new StatsView(STATS_OVERALL, null);
        } else if (id == :moves) {
            view = new StatsView(STATS_MOVES, null);
        } else {
            var list = ScoreHistory.entries();
            var i = id as Number;
            if (i >= list.size()) { return; }
            view = new StatsView(STATS_WOD, list[i]);
        }
        WatchUi.pushView(view, new StatsDelegate(view), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        getApp().backToMenu(1);
    }
}

const STATS_OVERALL = 0;
const STATS_MOVES = 1;
const STATS_WOD = 2;
const STATS_LOAD = 3;
const STATS_BALANCE = 4;
const STATS_STRENGTH = 5;
const STATS_WEEK = 6;
const STATS_LINES = 5;

class StatsView extends WatchUi.View {

    var page as Number = 0;
    private var _kind as Number;
    private var _entry as Dictionary?;
    private var _rows as Array<String> = [] as Array<String>;  // paged table (moves, splits)

    function initialize(kind as Number, entry as Dictionary?) {
        View.initialize();
        _kind = kind;
        _entry = entry;
        if (kind == STATS_MOVES) {
            _rows = movementRows();
        } else if (kind == STATS_WOD) {
            _rows = splitRows(entry as Dictionary);
        }
    }

    function pageCount() as Number {
        var tablePages = (_rows.size() + STATS_LINES - 1) / STATS_LINES;
        if (_kind == STATS_MOVES) { return tablePages > 0 ? tablePages : 1; }
        if (_kind == STATS_WOD) { return 2 + tablePages; }
        if (_kind == STATS_LOAD) { return 2; }
        return 1;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (_kind == STATS_LOAD && page == 1) {
            drawMonotony(dc, h, cx);
        } else if (_kind == STATS_LOAD) {
            drawLoad(dc, w, h, cx);
        } else if (_kind == STATS_BALANCE) {
            drawBalance(dc, w, h, cx);
        } else if (_kind == STATS_STRENGTH) {
            drawStrength(dc, h, cx);
        } else if (_kind == STATS_WEEK) {
            drawWeek(dc, h, cx);
        } else if (_kind == STATS_OVERALL) {
            drawOverall(dc, cx, h);
        } else if (_kind == STATS_MOVES) {
            drawTable(dc, cx, h, "Pace per rep", page);
        } else if (page == 0) {
            drawWod(dc, cx, h);
        } else if (page == 1) {
            drawProgress(dc, w, h, cx);
        } else {
            drawTable(dc, cx, h, "Round  Best  Last", page - 2);
        }
        Ui.pageDots(dc, page, pageCount());
    }

    // Centered, translated when the whole text is a known label, shortened to fit.
    private function text(dc as Graphics.Dc, x as Number, y as Number, font, color, s as String) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var t = Ui.fit(dc, Tr.s(s), font as Graphics.FontType, Ui.widthAt(dc, y));
        dc.drawText(x, y, font, t, Ui.CENTER);
    }

    // Acute (7 days) vs chronic (weekly average over 28 days) training load.
    private function drawLoad(dc as Graphics.Dc, w as Number, h as Number, cx as Number) as Void {
        var e = Perf.loads();
        var today = Perf.today();
        var idx = Perf.loadIndex(e, today);
        var a = Perf.acwr(e, today, idx);
        var st = Perf.status(e, today, a[2]);
        text(dc, cx, h * 13 / 100, Graphics.FONT_XTINY, Theme.MUTED,
            idx == D_SRPE ? "TRAINING LOAD (RPE)" : "TRAINING LOAD (HR)");
        var color = Theme.MUTED;
        if (st.equals("low")) { color = Graphics.COLOR_BLUE; }
        if (st.equals("optimal")) { color = Graphics.COLOR_GREEN; }
        if (st.equals("high")) { color = Theme.WARN; }
        if (st.equals("risk")) { color = Graphics.COLOR_RED; }
        var big = a[2] < 0 || st.equals("building") ? "--" : (a[2] / 100).format("%d") + "." + (a[2] % 100).format("%02d");
        text(dc, cx, h * 28 / 100, Graphics.FONT_LARGE, color, big);
        text(dc, cx, h * 39 / 100, Graphics.FONT_XTINY, color, loadStatusLabel(st));
        text(dc, cx, h * 49 / 100, Graphics.FONT_XTINY, Theme.TEXT,
            "7 days " + a[0].format("%d") + "   4 wk avg " + a[1].format("%d"));

        // last 7 days, today on the right
        var day = [] as Array<Number>;
        var max = 1;
        for (var i = 6; i >= 0; i--) {
            var v = Perf.sumDays(e, today - i, 1, idx);
            day.add(v);
            if (v > max) { max = v; }
        }
        var x0 = w * 22 / 100;
        var slot = w * 56 / 100 / 7;
        var base = h * 80 / 100;
        var hmax = h * 20 / 100;
        for (var i = 0; i < 7; i++) {
            var bh = day[i] * hmax / max;
            dc.setColor(i == 6 ? Theme.SCORE : Theme.MUTED, Graphics.COLOR_TRANSPARENT);
            if (bh > 0) { dc.fillRectangle(x0 + i * slot + slot / 5, base - bh, slot * 3 / 5, bh); }
            dc.fillRectangle(x0 + i * slot + slot / 5, base, slot * 3 / 5, 2);
        }
    }

    // Score of each attempt at this WOD (last 12), best in green.
    private function drawProgress(dc as Graphics.Dc, w as Number, h as Number, cx as Number) as Void {
        var e = _entry as Dictionary;
        text(dc, cx, h * 14 / 100, Graphics.FONT_XTINY, Theme.MUTED, "PROGRESS");
        var hist = e["hist"];
        if (!(hist instanceof Array) || (hist as Array).size() < 2) {
            text(dc, cx, h / 2, Graphics.FONT_TINY, Theme.MUTED, "No data yet");
            return;
        }
        var kind = (e["best"] as Dictionary)["kind"] as String;
        var v = [] as Array<Number>;
        var hs = hist as Array;
        var lo = ((hs[0] as Array)[1]) as Number;
        var hi = lo;
        for (var i = 0; i < hs.size(); i++) {
            var x = ((hs[i] as Array)[1]) as Number;
            v.add(x);
            if (x < lo) { lo = x; }
            if (x > hi) { hi = x; }
        }
        var colors = [] as Array<Number>;
        for (var i = 0; i < v.size(); i++) { colors.add(v[i] == hi ? Theme.WORK : (i == v.size() - 1 ? Theme.SCORE : Theme.MUTED)); }
        // bars start a bit under the worst score so progress is visible
        var span = hi - lo;
        Ui.bars(dc, v, colors, w * 18 / 100, h * 24 / 100, w * 64 / 100, h * 34 / 100, lo - span / 3 - 1);
        text(dc, cx, h * 67 / 100, Graphics.FONT_TINY, Theme.WORK, Tr.s("Best") + " " + ScoreHistory.valueText(kind, hi));
        text(dc, cx, h * 77 / 100, Graphics.FONT_XTINY, Theme.SCORE, Tr.s("Last") + " " + ScoreHistory.valueText(kind, v[v.size() - 1]));
    }

    // Foster monotony and strain of the last 7 days.
    private function drawMonotony(dc as Graphics.Dc, h as Number, cx as Number) as Void {
        var e = Perf.loads();
        var today = Perf.today();
        text(dc, cx, h * 13 / 100, Graphics.FONT_XTINY, Theme.MUTED, "WEEK PATTERN");
        var m = Perf.monotony(e, today, Perf.loadIndex(e, today));
        if (m == null) {
            text(dc, cx, h / 2, Graphics.FONT_TINY, Theme.MUTED, "No load this week");
            return;
        }
        var mono = (m as Array<Number>)[0];
        var color = mono <= 150 ? Graphics.COLOR_GREEN : (mono <= 200 ? Theme.SCORE : Theme.WARN);
        text(dc, cx, h * 30 / 100, Graphics.FONT_LARGE, color, (mono / 100).format("%d") + "." + (mono % 100).format("%02d"));
        text(dc, cx, h * 41 / 100, Graphics.FONT_XTINY, color, "Monotony");
        text(dc, cx, h * 53 / 100, Graphics.FONT_TINY, Theme.TEXT, "Strain " + (m as Array<Number>)[1].format("%d"));
        text(dc, cx, h * 66 / 100, Graphics.FONT_XTINY, Theme.MUTED,
            mono > 200 ? "Same load every day:" : "Good mix of hard");
        text(dc, cx, h * 73 / 100, Graphics.FONT_XTINY, Theme.MUTED,
            mono > 200 ? "add easy and rest days" : "and easy days");
    }

    // Time per domain over 4 weeks, as three bars.
    private function drawBalance(dc as Graphics.Dc, w as Number, h as Number, cx as Number) as Void {
        text(dc, cx, h * 13 / 100, Graphics.FONT_XTINY, Theme.MUTED, "BALANCE, 4 WEEKS");
        var sh = Perf.domainShare(Perf.loads(), Perf.today(), 28);
        if (sh == null) {
            text(dc, cx, h / 2, Graphics.FONT_TINY, Theme.MUTED, "No data yet");
            return;
        }
        var names = ["Gym", "Weights", "Mono"];
        var colors = [Graphics.COLOR_BLUE, Theme.WARN, Graphics.COLOR_GREEN];
        var x0 = w * 20 / 100;
        var bw = w * 60 / 100;
        var low = -1;
        for (var i = 0; i < 3; i++) {
            var y = h * (27 + i * 17) / 100;
            var v = (sh as Array<Number>)[i];
            dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x0, y, Graphics.FONT_XTINY, names[i] as String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(x0 + bw, y, Graphics.FONT_XTINY, v.format("%d") + "%", Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Theme.DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0, y + h * 4 / 100, bw, h * 3 / 100);
            dc.setColor(colors[i] as Number, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x0, y + h * 4 / 100, bw * v / 100, h * 3 / 100);
            if (v < 15 && (low < 0 || v < (sh as Array<Number>)[low])) { low = i; }
        }
        if (low >= 0) {
            text(dc, cx, h * 82 / 100, Graphics.FONT_XTINY, Theme.WARN, "Little " + (names[low] as String).toLower() + " lately");
        }
    }

    // Best and worst movements vs the reference pace (30+ reps done).
    private function drawStrength(dc as Graphics.Dc, h as Number, cx as Number) as Void {
        text(dc, cx, h * 13 / 100, Graphics.FONT_XTINY, Theme.MUTED, "STRONG / WEAK");
        var r = Perf.rankMovements(ScoreHistory.movementStats(), 30);
        if (r.size() == 0) {
            text(dc, cx, h * 45 / 100, Graphics.FONT_TINY, Theme.MUTED, "Do 30+ reps");
            text(dc, cx, h * 55 / 100, Graphics.FONT_TINY, Theme.MUTED, "of a movement");
            return;
        }
        var rows = [] as Array;
        var n = r.size();
        var top = n < 3 ? n : 3;
        for (var i = 0; i < top; i++) { rows.add(r[i]); }
        for (var i = (n - 3 > top ? n - 3 : top); i < n; i++) { rows.add(r[i]); }
        var y = h * 27 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < rows.size(); i++) {
            var id = (rows[i] as Array)[0] as String;
            var ratio = (rows[i] as Array)[1] as Number;
            var name = Movements.name(id);
            var diff = ratio - 100;
            var txt = (name == null ? id : name as String) + " " + (diff <= 0 ? (-diff).format("%d") + "% fast" : diff.format("%d") + "% slow");
            text(dc, cx, y, Graphics.FONT_TINY, diff <= 0 ? Graphics.COLOR_GREEN : Theme.WARN, txt);
            y += lh;
        }
    }

    // Last 7 days vs the 7 before.
    private function drawWeek(dc as Graphics.Dc, h as Number, cx as Number) as Void {
        var e = Perf.loads();
        var today = Perf.today();
        text(dc, cx, h * 13 / 100, Graphics.FONT_XTINY, Theme.MUTED, "LAST 7 DAYS");
        var lines = [] as Array<String>;
        var n = Perf.weekCompare(e, today, D_SESSIONS);
        lines.add(Tr.s("Workouts") + " " + n[0].format("%d") + " (" + Tr.s("was") + " " + n[1].format("%d") + ")");
        var t0 = Perf.sumDays(e, today, 7, D_GYM) + Perf.sumDays(e, today, 7, D_WL) + Perf.sumDays(e, today, 7, D_MONO);
        var t1 = Perf.sumDays(e, today - 7, 7, D_GYM) + Perf.sumDays(e, today - 7, 7, D_WL) + Perf.sumDays(e, today - 7, 7, D_MONO);
        lines.add(Tr.s("Time") + " " + Str.clock(t0, false) + pctChange(t0, t1));
        var l = Perf.weekCompare(e, today, Perf.loadIndex(e, today));
        lines.add(Tr.s("Load") + " " + l[0].format("%d") + pctChange(l[0], l[1]));
        var kg = Perf.sumDays(e, today, 7, D_TONNAGE);
        if (kg > 0) { lines.add(Tr.s("Moved") + " " + kg.format("%d") + " kg"); }
        var prs = Perf.sumDays(e, today, 7, D_PRS);
        if (prs > 0) { lines.add(Tr.s("New bests") + " " + prs.format("%d")); }
        var h0 = Perf.hrrAvg(today, 7, 0);
        var h1 = Perf.hrrAvg(today, 14, 7);
        if (h0 >= 0) { lines.add(Tr.s("HR recovery") + " " + h0.format("%d") + (h1 >= 0 ? " (" + Tr.s("was") + " " + h1.format("%d") + ")" : "")); }
        var sh = Perf.domainShare(e, today, 7);
        if (sh != null) {
            var names = ["gym", "weights", "mono"];
            for (var i = 0; i < 3; i++) {
                if ((sh as Array<Number>)[i] == 0) {
                    lines.add("No " + (names[i] as String) + " this week");
                    break;
                }
            }
        }
        var y = h * 23 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        for (var i = 0; i < lines.size() && i < 7; i++) {
            text(dc, cx, y, Graphics.FONT_TINY, Str.startsWith(lines[i], "No ") ? Theme.WARN : Theme.TEXT, lines[i]);
            y += lh;
        }
    }

    private function drawOverall(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var t = ScoreHistory.totals();
        text(dc, cx, h * 15 / 100, Graphics.FONT_XTINY, Theme.MUTED, "Overall");
        text(dc, cx, h * 32 / 100, Graphics.FONT_LARGE, Theme.SCORE, (t["n"] as Number).format("%d"));
        text(dc, cx, h * 44 / 100, Graphics.FONT_XTINY, Theme.MUTED, "workouts");
        text(dc, cx, h * 58 / 100, Graphics.FONT_TINY, Theme.TEXT, "Time " + Str.clock(t["ms"] as Number, false));
        text(dc, cx, h * 68 / 100, Graphics.FONT_TINY, Theme.TEXT, "Reps " + (t["reps"] as Number).format("%d"));
        text(dc, cx, h * 78 / 100, Graphics.FONT_TINY, Theme.TEXT, ScoreHistory.entries().size().format("%d") + " different WODs");
    }

    private function drawWod(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var e = _entry as Dictionary;
        var best = e["best"] as Dictionary;
        var last = e["last"] as Dictionary;
        var name = e["name"] instanceof String ? e["name"] as String : "WOD";
        text(dc, cx, h * 13 / 100, Graphics.FONT_XTINY, Theme.MUTED, name);
        text(dc, cx, h * 22 / 100, Graphics.FONT_XTINY, Theme.MUTED, "BEST");
        text(dc, cx, h * 33 / 100, Graphics.FONT_LARGE, Theme.SCORE, ScoreHistory.scoreText(best));

        var n = e["n"] as Number;
        var y = h * 48 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        if (n > 1) {
            var diff = ScoreHistory.value(last) - ScoreHistory.value(best);
            var color = diff >= 0 ? Graphics.COLOR_GREEN : Theme.TEXT;
            text(dc, cx, y, Graphics.FONT_TINY, color, "Last " + ScoreHistory.scoreText(last) + "  (x" + n.format("%d") + ")");
            y += lh;
        }
        var fade = ScoreHistory.fadePct(last["laps"] as Array?);
        if (fade != null) {
            // > 10 % slower on the last round: probably went out too fast
            var f = fade as Number;
            var fc = f > 10 ? Theme.WARN : Theme.TEXT;
            text(dc, cx, y, Graphics.FONT_TINY, fc, "Fade " + (f >= 0 ? "+" : "") + f.format("%d") + "%");
            y += lh;
        }
        var hr = last["hr"];
        if (hr instanceof Number && (hr as Number) > 0) {
            text(dc, cx, y, Graphics.FONT_TINY, Theme.TEXT,
                "HR " + (hr as Number).format("%d") + " / " + (last["hrMax"] as Number).format("%d"));
        }
    }

    private function drawTable(dc as Graphics.Dc, cx as Number, h as Number, title as String, p as Number) as Void {
        text(dc, cx, h * 15 / 100, Graphics.FONT_XTINY, Theme.MUTED, title);
        if (_rows.size() == 0) {
            text(dc, cx, h / 2, Graphics.FONT_TINY, Theme.MUTED, "No data yet");
            return;
        }
        var y = h * 29 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY) + 2;
        for (var i = p * STATS_LINES; i < _rows.size() && i < (p + 1) * STATS_LINES; i++) {
            text(dc, cx, y, Graphics.FONT_TINY, Theme.TEXT, _rows[i]);
            y += lh;
        }
    }

    // "Wall balls 2.4 s" sorted by reps done
    private function movementRows() as Array<String> {
        var m = ScoreHistory.movementStats();
        var ids = m.keys();
        // selection sort by reps, lists are short
        var order = [] as Array;
        for (var i = 0; i < ids.size(); i++) { order.add(ids[i]); }
        for (var i = 0; i < order.size(); i++) {
            var best = i;
            for (var j = i + 1; j < order.size(); j++) {
                if (((m[order[j]] as Array<Number>)[0]) > ((m[order[best]] as Array<Number>)[0])) { best = j; }
            }
            var tmp = order[i];
            order[i] = order[best];
            order[best] = tmp;
        }
        var rows = [] as Array<String>;
        for (var i = 0; i < order.size(); i++) {
            var v = m[order[i]] as Array<Number>;
            var t = ScoreHistory.tenthsPerRep(v[0], v[1]);
            var name = Movements.name(order[i] as String);
            if (t == null) { continue; }
            rows.add((name == null ? order[i] as String : name as String) + "  " + ScoreHistory.formatTenths(t as Number));
        }
        return rows;
    }

    // "R3  1:38  1:44": round durations, best vs last attempt
    private function splitRows(e as Dictionary) as Array<String> {
        var bl = (e["best"] as Dictionary)["laps"];
        var ll = (e["last"] as Dictionary)["laps"];
        var b = bl instanceof Array ? bl as Array<Number> : [] as Array<Number>;
        var l = ll instanceof Array ? ll as Array<Number> : [] as Array<Number>;
        var n = b.size() > l.size() ? b.size() : l.size();
        var rows = [] as Array<String>;
        for (var i = 0; i < n; i++) {
            var bs = i < b.size() ? Str.clock(b[i] - (i > 0 ? b[i - 1] : 0), false) : "-";
            var ls = i < l.size() ? Str.clock(l[i] - (i > 0 ? l[i - 1] : 0), false) : "-";
            rows.add("R" + (i + 1).format("%d") + "  " + bs + "  " + ls);
        }
        return rows;
    }
}

class StatsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as StatsView;

    function initialize(view as StatsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        if (_view.page < _view.pageCount() - 1) {
            _view.page++;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view.page > 0) {
            _view.page--;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
