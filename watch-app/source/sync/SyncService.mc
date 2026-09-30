import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;

const MAX_WODS = 8;

// WOD sources and local cache.
//  A) settings text (Garmin Connect app > WODwrist > Settings), parsed on the watch
//  B) JSON URL (coach page on GitHub Pages), fetched through the phone
// The last WODs are kept in Application.Storage so the watch works alone.
class SyncService {

    private var _callback as Method? = null;
    var lastMessage as String = "";
    // parse error of the settings text, shown in the main menu until fixed
    var settingsError as String? = null;

    function initialize() {
    }

    // ---------- cache ----------

    function wods() as Array<Dictionary> {
        var v = Application.Storage.getValue("wods");
        return v instanceof Array ? v as Array<Dictionary> : [] as Array<Dictionary>;
    }

    // Newest first; a WOD with the same name and type replaces the old one.
    function addWod(wod as Dictionary) as Void {
        var list = wods();
        var out = [wod] as Array<Dictionary>;
        for (var i = 0; i < list.size() && out.size() < MAX_WODS; i++) {
            var w = list[i];
            if ((w["name"] as String).equals(wod["name"] as String) && (w["type"] as String).equals(wod["type"] as String)) {
                continue;
            }
            out.add(w);
        }
        Application.Storage.setValue("wods", out as Array<Application.PropertyValueType>);
    }

    function removeWod(index as Number) as Void {
        var list = wods();
        if (index < 0 || index >= list.size()) { return; }
        list.remove(list[index]);
        Application.Storage.setValue("wods", list as Array<Application.PropertyValueType>);
    }

    // ---------- source A: settings text ----------

    // Parses the settings text when it changed since last import.
    // Returns an error message, or null.
    function importSettingsText() as String? {
        var text = Application.Properties.getValue("wodText");
        if (!(text instanceof String) || (text as String).length() == 0) { return null; }
        var last = Application.Storage.getValue("lastText");
        if (last instanceof String && (last as String).equals(text as String)) { return null; }
        Application.Storage.setValue("lastText", text as String);
        var r = WodParser.parse(text as String);
        if (r.hasKey("error")) {
            settingsError = r["error"] as String;
            return settingsError;
        }
        settingsError = null;
        addWod(r["wod"] as Dictionary);
        lastMessage = "Imported " + ((r["wod"] as Dictionary)["name"] as String);
        return null;
    }

    // ---------- source B: URL ----------

    function hasUrl() as Boolean {
        var url = Application.Properties.getValue("wodUrl");
        return url instanceof String && (url as String).length() > 0;
    }

    // callback(ok as Boolean, message as String), may be null for a silent sync.
    function fetch(callback as Method?) as Void {
        _callback = callback;
        if (!hasUrl()) {
            done(false, "Set a WOD URL in the app settings");
            return;
        }
        if (!(Toybox has :Communications)) {
            done(false, "No phone link");
            return;
        }
        var url = Application.Properties.getValue("wodUrl") as String;
        // GitHub Pages caches ~10 min: bust it so the coach's update shows up.
        url += (Str.contains(url, "?") ? "&" : "?") + "t=" + Time.now().value().format("%d");
        Communications.makeWebRequest(url, null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onReceive));
    }

    function onReceive(code as Number, data) as Void {
        if (code != 200) {
            done(false, code < 0 ? "Phone not connected (" + code.format("%d") + ")" : "HTTP " + code.format("%d"));
            return;
        }
        if (!(data instanceof Dictionary)) {
            done(false, "Not a WOD JSON");
            return;
        }
        var d = data as Dictionary;
        var items = [] as Array;
        if (d["wods"] instanceof Array) {
            items = d["wods"] as Array;
        } else {
            items = [d];
        }
        var ok = 0;
        var err = "";
        // add oldest first so the first item of the file ends up on top
        for (var i = items.size() - 1; i >= 0; i--) {
            var r = WodParser.validate(items[i]);
            if (r.hasKey("wod")) {
                addWod(r["wod"] as Dictionary);
                ok++;
            } else {
                err = r["error"] as String;
            }
        }
        Movements.release();
        if (ok == 0) {
            done(false, err.length() > 0 ? err : "No WOD in file");
            return;
        }
        Application.Storage.setValue("lastSync", Time.now().value());
        done(true, ok == 1 ? "WOD updated" : ok.format("%d") + " WODs updated");
    }

    private function done(ok as Boolean, msg as String) as Void {
        lastMessage = msg;
        var cb = _callback;
        _callback = null;
        if (cb != null) { cb.invoke(ok, msg); }
    }
}
