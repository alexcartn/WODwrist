import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Widget list glance: today's WOD and your last score on it, without opening
// the app. Reads Storage "glance" = [title, line], written by the full app
// (Glance.update). Glance code must stay tiny and self-contained.
(:glance)
class WodGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var title = "WODwrist";
        var line = "";
        var g = Application.Storage.getValue("glance");
        if (g instanceof Array && (g as Array).size() >= 2) {
            title = (g as Array)[0] as String;
            line = (g as Array)[1] as String;
        }
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h / 3, Graphics.FONT_GLANCE, title, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 3 / 4, Graphics.FONT_GLANCE, line, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

// Full app side: keep the glance text fresh.
module Glance {
    function update(title as String, line as String) as Void {
        Application.Storage.setValue("glance", [title, line]);
    }
}
