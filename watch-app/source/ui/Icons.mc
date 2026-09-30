import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Pictograms (movements, menus), loaded once and cached.
module Icons {

    var _cache as Dictionary<String, WatchUi.BitmapResource> = {} as Dictionary<String, WatchUi.BitmapResource>;
    var _ids as Dictionary<String, String>? = null;

    function get(name as String) as WatchUi.BitmapResource? {
        var b = _cache.get(name);
        if (b != null) { return b; }
        var id = IconRes.id(name);
        if (id == null) { return null; }
        var bmp = WatchUi.loadResource(id) as WatchUi.BitmapResource;
        _cache[name] = bmp;
        return bmp;
    }

    // Icon of a movement id, or null (custom movements).
    function forMovement(movement as String) as WatchUi.BitmapResource? {
        if (_ids == null) { _ids = MovementCatalog.icons(); }
        var n = (_ids as Dictionary<String, String>).get(movement);
        return n == null ? null : get(n);
    }

    // Draw centered at (x, y).
    function draw(dc as Graphics.Dc, bmp as WatchUi.BitmapResource?, x as Number, y as Number) as Void {
        if (bmp == null) { return; }
        var b = bmp as WatchUi.BitmapResource;
        dc.drawBitmap(x - b.getWidth() / 2, y - b.getHeight() / 2, b);
    }

    // Menu entry with a pictogram when the device supports it.
    function menuItem(label as String, sub as String?, id, icon as String) as WatchUi.MenuItem {
        var bmp = get(icon);
        if ((WatchUi has :IconMenuItem) && bmp != null) {
            // wrapped in a Drawable: a raw BitmapResource crashes Menu2 on venu3 (Symbol Not Found)
            return new WatchUi.IconMenuItem(label, sub, id, new WatchUi.Bitmap({ :bitmap => bmp as WatchUi.BitmapResource }), {});
        }
        return new WatchUi.MenuItem(label, sub, id, {});
    }
}
