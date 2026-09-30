import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;

// FIT field ids: must match resources/fit/fitcontributions.xml
const FIELD_LAP_REPS = 0;
const FIELD_TOTAL_REPS = 1;
const FIELD_ROUNDS = 2;
const FIELD_EXTRA_REPS = 3;
const FIELD_TIME_SEC = 4;
const FIELD_WOD_NAME = 5;

// Garmin activity: sport training / cardio, one lap per round or interval
// so Connect shows time and heart rate per round, plus custom rep fields.
class RecordingManager {

    private var _session as ActivityRecording.Session? = null;
    private var _lapReps as FitContributor.Field? = null;
    private var _totalReps as FitContributor.Field? = null;
    private var _rounds as FitContributor.Field? = null;
    private var _extraReps as FitContributor.Field? = null;
    private var _timeSec as FitContributor.Field? = null;
    private var _wodName as FitContributor.Field? = null;

    function initialize() {
    }

    function isRecording() as Boolean {
        return _session != null && (_session as ActivityRecording.Session).isRecording();
    }

    function hasSession() as Boolean {
        return _session != null;
    }

    function start(name as String) as Void {
        if (_session != null || !(Toybox has :ActivityRecording)) { return; }
        var title = name.length() > 20 ? Str.sub(name, 0, 20) : name;
        var s = ActivityRecording.createSession({
            :name => title,
            :sport => Activity.SPORT_TRAINING,
            :subSport => Activity.SUB_SPORT_CARDIO_TRAINING
        });
        _lapReps = s.createField("lap_reps", FIELD_LAP_REPS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_LAP, :units => "reps" });
        _totalReps = s.createField("total_reps", FIELD_TOTAL_REPS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "reps" });
        _rounds = s.createField("rounds", FIELD_ROUNDS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "rounds" });
        _extraReps = s.createField("extra_reps", FIELD_EXTRA_REPS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "reps" });
        _timeSec = s.createField("score_time", FIELD_TIME_SEC, FitContributor.DATA_TYPE_UINT32,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s" });
        _wodName = s.createField("wod_name", FIELD_WOD_NAME, FitContributor.DATA_TYPE_STRING,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :count => 32 });
        (_lapReps as FitContributor.Field).setData(0);
        (_wodName as FitContributor.Field).setData(name.length() > 31 ? Str.sub(name, 0, 31) : name);
        s.start();
        _session = s;
    }

    function pause() as Void {
        if (isRecording()) { (_session as ActivityRecording.Session).stop(); }
    }

    function resume() as Void {
        if (_session != null && !isRecording()) { (_session as ActivityRecording.Session).start(); }
    }

    function lap(reps as Number) as Void {
        if (_session == null) { return; }
        (_lapReps as FitContributor.Field).setData(reps);
        (_session as ActivityRecording.Session).addLap();
        (_lapReps as FitContributor.Field).setData(0);
    }

    // Stops the session; the open lap gets lastLapReps. timeSec = 0 when the
    // score is not a time.
    function finish(lastLapReps as Number, totalReps as Number, rounds as Number,
            extraReps as Number, timeSec as Number) as Void {
        if (_session == null) { return; }
        (_lapReps as FitContributor.Field).setData(lastLapReps);
        (_totalReps as FitContributor.Field).setData(totalReps);
        (_rounds as FitContributor.Field).setData(rounds);
        (_extraReps as FitContributor.Field).setData(extraReps);
        (_timeSec as FitContributor.Field).setData(timeSec);
        if (isRecording()) { (_session as ActivityRecording.Session).stop(); }
    }

    function save() as Void {
        if (_session == null) { return; }
        (_session as ActivityRecording.Session).save();
        _session = null;
    }

    function discard() as Void {
        if (_session == null) { return; }
        var s = _session as ActivityRecording.Session;
        if (s.isRecording()) { s.stop(); }
        s.discard();
        _session = null;
    }
}
