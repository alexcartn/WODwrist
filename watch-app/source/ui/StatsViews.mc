import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// "My stats": everything is computed on the watch from Application.Storage
// (ScoreHistory), nothing to export.

function buildStatsMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({ :title => "My stats" });
    var t = ScoreHistory.totals();
    menu.addItem(new WatchUi.MenuItem("Overall", (t["n"] as Number).format("%d") + " workouts", :overall, {}));
    menu.addItem(new WatchUi.MenuItem("Movements", "Pace per rep", :moves, {}));
    var list = ScoreHistory.entries();
    for (var i = 0; i < list.size(); i++) {
        var e = list[i];
        var name = e["name"] instanceof String ? e["name"] as String : "WOD";
        var sub = "Best " + ScoreHistory.scoreText(e["best"] as Dictionary) + "  x" + (e["n"] as Number).format("%d");
        menu.addItem(new WatchUi.MenuItem(name, sub, i, {}));
    }
    return menu;
}

class StatsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var view;
        if (id == :overall) {
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
        if (_kind == STATS_WOD) { return 1 + tablePages; }
        return 1;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (_kind == STATS_OVERALL) {
            drawOverall(dc, cx, h);
        } else if (_kind == STATS_MOVES) {
            drawTable(dc, cx, h, "Pace per rep", page);
        } else if (page == 0) {
            drawWod(dc, cx, h);
        } else {
            drawTable(dc, cx, h, "Round  Best  Last", page - 1);
        }
        if (page < pageCount() - 1) {
            var s = w / 40;
            var y = h * 90 / 100;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cx - s, y - s / 2], [cx + s, y - s / 2], [cx, y + s]]);
        }
    }

    private function text(dc as Graphics.Dc, x as Number, y as Number, font, color, s as String) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawOverall(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var t = ScoreHistory.totals();
        text(dc, cx, h * 15 / 100, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "Overall");
        text(dc, cx, h * 32 / 100, Graphics.FONT_LARGE, Graphics.COLOR_YELLOW, (t["n"] as Number).format("%d"));
        text(dc, cx, h * 44 / 100, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "workouts");
        text(dc, cx, h * 58 / 100, Graphics.FONT_TINY, Graphics.COLOR_WHITE, "Time " + Str.clock(t["ms"] as Number, false));
        text(dc, cx, h * 68 / 100, Graphics.FONT_TINY, Graphics.COLOR_WHITE, "Reps " + (t["reps"] as Number).format("%d"));
        text(dc, cx, h * 78 / 100, Graphics.FONT_TINY, Graphics.COLOR_WHITE, ScoreHistory.entries().size().format("%d") + " different WODs");
    }

    private function drawWod(dc as Graphics.Dc, cx as Number, h as Number) as Void {
        var e = _entry as Dictionary;
        var best = e["best"] as Dictionary;
        var last = e["last"] as Dictionary;
        var name = e["name"] instanceof String ? e["name"] as String : "WOD";
        text(dc, cx, h * 13 / 100, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, name);
        text(dc, cx, h * 22 / 100, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, "BEST");
        text(dc, cx, h * 33 / 100, Graphics.FONT_LARGE, Graphics.COLOR_YELLOW, ScoreHistory.scoreText(best));

        var n = e["n"] as Number;
        var y = h * 48 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY);
        if (n > 1) {
            var diff = ScoreHistory.value(last) - ScoreHistory.value(best);
            var color = diff >= 0 ? Graphics.COLOR_GREEN : Graphics.COLOR_WHITE;
            text(dc, cx, y, Graphics.FONT_TINY, color, "Last " + ScoreHistory.scoreText(last) + "  (x" + n.format("%d") + ")");
            y += lh;
        }
        var fade = ScoreHistory.fadePct(last["laps"] as Array?);
        if (fade != null) {
            // > 10 % slower on the last round: probably went out too fast
            var f = fade as Number;
            var fc = f > 10 ? Graphics.COLOR_ORANGE : Graphics.COLOR_WHITE;
            text(dc, cx, y, Graphics.FONT_TINY, fc, "Fade " + (f >= 0 ? "+" : "") + f.format("%d") + "%");
            y += lh;
        }
        var hr = last["hr"];
        if (hr instanceof Number && (hr as Number) > 0) {
            text(dc, cx, y, Graphics.FONT_TINY, Graphics.COLOR_WHITE,
                "HR " + (hr as Number).format("%d") + " / " + (last["hrMax"] as Number).format("%d"));
        }
    }

    private function drawTable(dc as Graphics.Dc, cx as Number, h as Number, title as String, p as Number) as Void {
        text(dc, cx, h * 15 / 100, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, title);
        if (_rows.size() == 0) {
            text(dc, cx, h / 2, Graphics.FONT_TINY, Graphics.COLOR_LT_GRAY, "No data yet");
            return;
        }
        var y = h * 29 / 100;
        var lh = dc.getFontHeight(Graphics.FONT_TINY) + 2;
        for (var i = p * STATS_LINES; i < _rows.size() && i < (p + 1) * STATS_LINES; i++) {
            text(dc, cx, y, Graphics.FONT_TINY, Graphics.COLOR_WHITE, _rows[i]);
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
