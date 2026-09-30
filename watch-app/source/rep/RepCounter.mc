import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

const RC_BASE_SHIFT = 7;
const RC_CONF_WINDOW = 5;
const RC_PERIOD_MS = 40;   // 25 Hz

// Accelerometer rep counter. Port of rep-lab/replab/counter.py, integer math
// so both give identical results. Parameters per movement come from
// docs/movements.json (tuned offline in rep-lab).
//
// In capture mode every batch is also written to the app log
// (APPS/LOGS/WODWRIST.TXT) for rep-lab: "A,<t>,x0,y0,z0,x1,y1,z1,..."
class RepCounter {

    private var _onRep as Method?;
    private var _capture as Boolean;
    private var _listening as Boolean = false;
    private var _enabled as Boolean = false;

    private var _alpha as Number = 64;
    private var _hi as Number = 450;
    private var _lo as Number = 100;
    private var _minGap as Number = 1000;

    private var _lp as Number = -1;
    private var _base as Number = -1;
    private var _high as Boolean = false;
    private var _peakV as Number = 0;
    private var _peakT as Number = 0;
    private var _lastRepT as Number = -1000000000;
    private var _count as Number = 0;
    private var _intervals as Array<Number> = [] as Array<Number>;

    // onRep is called with the rep timestamp (ms, System.getTimer clock).
    function initialize(onRep as Method?, capture as Boolean) {
        _onRep = onRep;
        _capture = capture;
    }

    // p = [alphaQ8, hiMg, loMg, minGapMs] or null to disable counting.
    function setProfile(p as Array<Number>?) as Void {
        _enabled = p != null;
        if (p != null) {
            _alpha = p[0];
            _hi = p[1];
            _lo = p[2];
            _minGap = p[3];
        }
        reset();
    }

    function isEnabled() as Boolean {
        return _enabled;
    }

    // New block: forget peaks, keep the gravity baseline.
    function reset() as Void {
        _lp = -1;
        _high = false;
        _peakV = 0;
        _peakT = 0;
        _lastRepT = -1000000000;
        _count = 0;
        _intervals = [] as Array<Number>;
    }

    private function toward(cur as Number, target as Number, alphaQ8 as Number) as Number {
        var d = target - cur;
        if (d >= 0) { return cur + ((d * alphaQ8) >> 8); }
        return cur - (((-d) * alphaQ8) >> 8);
    }

    private function towardShift(cur as Number, target as Number, shift as Number) as Number {
        var d = target - cur;
        if (d >= 0) { return cur + (d >> shift); }
        return cur - ((-d) >> shift);
    }

    // One sample. Returns the rep timestamp when a rep is detected, else -1.
    function feed(t as Number, x as Number, y as Number, z as Number) as Number {
        var m = Math.sqrt(x * x + y * y + z * z).toNumber();
        if (_lp < 0) { _lp = m; }
        if (_base < 0) { _base = m; }
        _lp = toward(_lp, m, _alpha);
        _base = towardShift(_base, _lp, RC_BASE_SHIFT);
        if (!_enabled) { return -1; }
        var dev = _lp - _base;

        if (!_high) {
            if (dev > _hi) {
                _high = true;
                _peakV = dev;
                _peakT = t;
            }
            return -1;
        }
        if (dev > _peakV) {
            _peakV = dev;
            _peakT = t;
        }
        if (dev < _lo) {
            _high = false;
            if (_peakT - _lastRepT >= _minGap) {
                if (_count > 0) {
                    _intervals.add(_peakT - _lastRepT);
                    if (_intervals.size() > RC_CONF_WINDOW) { _intervals = _intervals.slice(1, null); }
                }
                _lastRepT = _peakT;
                _count++;
                return _peakT;
            }
        }
        return -1;
    }

    // 0-100: share of recent rep intervals within 30 % of their median.
    function confidence() as Number {
        var n = _intervals.size();
        if (n < 2) { return 50; }
        var s = _intervals.slice(0, null);
        for (var i = 1; i < n; i++) {
            var v = s[i];
            var j = i - 1;
            while (j >= 0 && s[j] > v) {
                s[j + 1] = s[j];
                j--;
            }
            s[j + 1] = v;
        }
        var med = s[n / 2];
        var ok = 0;
        for (var i = 0; i < n; i++) {
            var d = _intervals[i] - med;
            if (d < 0) { d = -d; }
            if (d * 10 <= med * 3) { ok++; }
        }
        return ok * 100 / n;
    }

    // ---------- sensor plumbing ----------

    function start() as Void {
        if (_listening || !(Sensor has :registerSensorDataListener)) { return; }
        Sensor.registerSensorDataListener(method(:onSensorData), {
            :period => 1,
            :accelerometer => { :enabled => true, :sampleRate => 25 }
        });
        _listening = true;
    }

    function stop() as Void {
        if (!_listening) { return; }
        Sensor.unregisterSensorDataListener();
        _listening = false;
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        var acc = data.accelerometerData;
        if (acc == null) { return; }
        var xs = acc.x;
        var ys = acc.y;
        var zs = acc.z;
        if (xs == null || ys == null || zs == null) { return; }
        var n = xs.size();
        var t = System.getTimer();
        if (_capture) {
            var line = "A," + t;
            for (var i = 0; i < n; i++) {
                line += "," + xs[i] + "," + ys[i] + "," + zs[i];
            }
            System.println(line);
        }
        for (var i = 0; i < n; i++) {
            var r = feed(t - (n - 1 - i) * RC_PERIOD_MS, xs[i], ys[i], zs[i]);
            if (r >= 0 && _onRep != null) {
                (_onRep as Method).invoke(r);
            }
        }
    }
}
