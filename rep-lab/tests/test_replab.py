import json

from replab.counter import Profile, RepCounter, count_reps
from replab.evaluate import best_offset, score
from replab.labels import load_labels
from replab.logparse import parse_lines
from replab.synth import deterministic_pulses, synth_session, to_log_lines
from replab.tune import Session, candidates, dev_series, evaluate_profile, gap_filter, search

WB = Profile(alphaQ8=64, hiMg=300, loMg=100, minGapMs=1100)


def test_counts_synthetic_session():
    samples, reps = synth_session(n_reps=30)
    det = count_reps(samples, WB)
    s = score(det, reps)
    assert s.count_accuracy >= 0.95, s
    assert s.f1 >= 0.95, s


def test_min_gap_merges_catch_peak():
    samples, reps = synth_session(n_reps=20, catch_mg=700)
    loose = count_reps(samples, Profile(64, 300, 100, 200))
    strict = count_reps(samples, Profile(64, 300, 100, 1100))
    assert len(loose) > len(reps)
    assert abs(len(strict) - len(reps)) <= 1


def test_deterministic_vector_shared_with_monkey_c():
    # watch-app/test/RepCounterTest.mc asserts the same numbers.
    samples = deterministic_pulses(10)
    det = count_reps(samples, Profile(128, 300, 100, 800))
    assert len(det) == 10
    assert det[0] == 1960


def test_fast_path_matches_reference():
    samples, _ = synth_session(n_reps=25, seed=7)
    for p in [WB, Profile(32, 250, 50, 700), Profile(128, 600, 200, 1500)]:
        ts = [s[0] for s in samples]
        fast = gap_filter(candidates(ts, dev_series(samples, p.alphaQ8), p.hiMg, p.loMg), p.minGapMs)
        assert fast == count_reps(samples, p)


def test_batch_feed_equals_sample_feed():
    samples, _ = synth_session(n_reps=10)
    cap = parse_lines(to_log_lines(samples))
    assert [s[1:] for s in cap.samples] == [s[1:] for s in samples]
    c = RepCounter(WB)
    got = []
    for i in range(0, len(samples), 25):
        ch = samples[i : i + 25]
        got += c.feed_batch(ch[-1][0], [s[1] for s in ch], [s[2] for s in ch], [s[3] for s in ch])
    assert got == count_reps(samples, WB)


def test_log_parsing_and_segments():
    lines = [
        "S,1000,AMRAP 12",
        "B,1000,wall_ball",
        "A,2000," + ",".join(["0,0,1000"] * 25),
        "M,2100,1",
        "M,2200,1",
        "M,2300,-1",
        "R,2150,1",
        "B,3000,burpee",
        "M,3500,1",
        "L,4000,12",
        "garbage line",
    ]
    cap = parse_lines(lines)
    assert len(cap.samples) == 25 and cap.samples[0][0] == 2000 - 24 * 40
    assert cap.rep_marks() == [2100, 3500]
    wb = cap.segment("wall_ball")
    assert wb.rep_marks() == [2100]
    assert wb.detected == [2150]
    assert cap.laps == [(4000, 12)]


def test_offset_recovery():
    video = [5000 + 2100 * i for i in range(20)]
    watch = [v + 1_234_560 for v in video]
    watch[3] += 150
    del watch[7]
    off = best_offset(video, watch, 1_200_000, 1_300_000)
    assert abs(off - 1_234_560) <= 40


def test_labels_formats(tmp_path):
    (tmp_path / "a.csv").write_text("t,movement\n1.5,wall_ball\n2.0,burpee\n3.25,wall_ball\n")
    assert load_labels(tmp_path / "a.csv", "wall_ball") == [1500, 3250]
    (tmp_path / "b.json").write_text(json.dumps({"reps": [{"t": 1}, {"time": 2.5}]}))
    assert load_labels(tmp_path / "b.json") == [1000, 2500]
    (tmp_path / "c.json").write_text("[0.5, 1.0]")
    assert load_labels(tmp_path / "c.json") == [500, 1000]


def test_search_finds_good_params():
    sessions = []
    for seed in (1, 2):
        samples, reps = synth_session(n_reps=20, seed=seed)
        sessions.append(Session(f"s{seed}", samples, reps))
    grid = {"alphaQ8": [64, 128], "hiMg": [300, 450, 700], "loMg": [100], "minGapMs": [300, 1100]}
    (f1, acc), p, scores = search(sessions, grid)
    assert f1 >= 0.95 and acc >= 0.95
    assert [round(s.f1, 4) for s in evaluate_profile(sessions, p)] == [round(s.f1, 4) for s in scores]
