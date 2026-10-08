import numpy as np
import polars as pl
import pytest

import shots

RIM = 39.75


@pytest.mark.parametrize(
    ("x", "y", "three", "zone"),
    [
        (38.75, 1.0, False, "rim"),         # at the basket
        (41.75, 0.0, False, "rim"),         # behind the basket
        (-37.75, 2.0, False, "rim"),        # far end of the court, 2.8 ft out
        (35.75, 0.0, False, "smid"),        # 4 ft: the rim zone is strictly under 4
        (30.75, 0.0, False, "smid"),        # 9 ft
        (26.75, 0.0, False, "smid"),        # 13 ft
        (25.75, 0.0, False, "lmid"),        # 14 ft: long mid starts at 14
        (20.75, 0.0, False, "lmid"),        # 19 ft
        (40.75, 23.0, True, "c3"),          # corner three: |y| >= 22, level with the rim
        (-38.75, -22.0, True, "c3"),        # the other corner
        (34.75, 22.0, True, "c3"),          # top of the straight corner segment
        (15.75, 0.0, True, "nc3"),          # above the break
        (28.75, 24.0, True, "nc3"),         # sideline wing: past the corner segment's depth
        (-28.75, -24.0, True, "nc3"),
    ],
)
def test_zone_classification(x, y, three, zone):
    assert shots.classify_zone(x, y, three, RIM) == zone


def test_two_pointer_never_lands_in_a_three_zone():
    assert shots.classify_zone(30.0, 23.0, False, RIM) in {"rim", "smid", "lmid"}


def test_distance_folds_both_ends_of_the_court():
    assert shots.distance_to_rim(-39.75, 0.0, RIM) == pytest.approx(0.0)
    assert shots.distance_to_rim(39.75, 3.0, RIM) == pytest.approx(3.0)
    assert shots.distance_to_rim(0.0, 0.0, RIM) == pytest.approx(39.75)


def test_three_detection_by_distance_fallback():
    assert shots.is_three_by_distance(15.75, 0.0, RIM)        # 24 ft
    assert shots.is_three_by_distance(40.75, 22.0, RIM)       # corner, 22 ft
    assert not shots.is_three_by_distance(20.75, 0.0, RIM)    # 19 ft jumper
    assert not shots.is_three_by_distance(30.75, 21.0, RIM)   # long two near the baseline
    assert not shots.is_three_by_distance(17.75, 0.0, RIM)    # 22 ft top of the key is still a two


def _frame(rows):
    base = {
        "game_id": 1, "season": 2026, "period_number": 1, "clock_display_value": "10:00",
        "team_id": 1, "athlete_id_1": 10, "athlete_id_2": None, "type_id": 92,
        "type_text": "Jump Shot", "scoring_play": False, "score_value": 0,
        "coordinate_x": 0.0, "coordinate_y": 0.0,
    }
    return pl.DataFrame([{**base, **r} for r in rows], schema_overrides={"athlete_id_2": pl.Int32})


def test_free_throws_and_placeholders_are_not_field_goal_attempts():
    frame = _frame([
        {"type_text": "Jump Shot"},
        {"type_text": "Free Throw - 1 of 2"},
        {"type_text": "Free Throw - Technical"},
        {"type_text": "No Shot (Default Shot)"},
        {"type_text": "Layup Shot", "athlete_id_1": None},
    ])
    assert shots.field_goal_shots(frame).height == 1


def test_made_three_is_scored_three_and_made_two_is_not():
    frame = _frame([
        {"scoring_play": True, "score_value": 3, "coordinate_x": 20.0, "coordinate_y": 0.0},
        {"scoring_play": True, "score_value": 2, "coordinate_x": 20.0, "coordinate_y": 0.0},
    ])
    zoned = shots.with_zones(frame, RIM)
    assert zoned["is_three"].to_list() == [True, False]
    assert zoned["zone"].to_list() == ["nc3", "lmid"]


def test_missed_three_comes_from_play_by_play_not_distance():
    # A 25-footer logged at a distance that looks like a two on the grid.
    frame = _frame([{"coordinate_x": 21.75, "coordinate_y": 0.0}])
    pbp = pl.DataFrame({
        "game_id": [1], "period_number": [1], "clock_display_value": ["10:00"],
        "athlete_id_1": [10], "type_id": [92], "shooting_play": [True],
        "points_attempted": [3], "text": ["A misses 25-foot three point jumper"],
    })
    assert shots.with_zones(frame, RIM)["is_three"].to_list() == [False]           # fallback alone
    assert shots.with_zones(frame, RIM, pbp)["is_three"].to_list() == [True]       # joined


def test_missed_three_text_fallback_when_points_attempted_is_absent():
    frame = _frame([{"coordinate_x": 21.75}, {"coordinate_x": 21.75, "type_id": 93}])
    pbp = pl.DataFrame({
        "game_id": [1, 1], "period_number": [1, 1], "clock_display_value": ["10:00", "10:00"],
        "athlete_id_1": [10, 10], "type_id": [92, 93], "shooting_play": [True, True],
        "text": ["A misses 25-foot 3PT jumper", "A misses 14-foot jumper"],
    })
    assert shots.with_zones(frame, RIM, pbp)["is_three"].to_list() == [True, False]


def test_zone_counts_per_player_game_include_assisted_makes():
    frame = _frame([
        {"scoring_play": True, "score_value": 2, "coordinate_x": 38.75, "coordinate_y": 0.0, "athlete_id_2": 11},
        {"coordinate_x": 38.75, "coordinate_y": 0.0},                                              # missed rim shot
        {"scoring_play": True, "score_value": 3, "coordinate_x": 40.75, "coordinate_y": 23.0},    # unassisted corner 3
        {"coordinate_x": 15.75},                                                                   # missed 24 footer
    ])
    counts = shots.zone_counts(shots.with_zones(frame, RIM)).to_dicts()[0]
    assert (counts["rim_fga"], counts["rim_fgm"]) == (2, 1)
    assert (counts["c3_fga"], counts["c3_fgm"]) == (1, 1)
    assert counts["nc3_fga"] == 1 and counts["smid_fga"] == 0 and counts["lmid_fga"] == 0
    assert counts["ast_fgm"] == 1
    assert counts["shot_fga"] == 4
    assert counts["shot_fga"] == sum(counts[f"{z}_fga"] for z in shots.ZONES)  # shares sum to 100%


def _dunks(n, centre, y=0.0, jitter=0.4):
    rng = np.random.default_rng(1)
    xs = rng.choice([-1, 1], n) * (centre + rng.normal(0, jitter, n))
    return _frame([
        {"type_text": "Driving Dunk Shot", "coordinate_x": float(x), "coordinate_y": float(y + rng.normal(0, 0.5))}
        for x in xs
    ])


def test_rim_calibration_finds_the_espn_frame_not_the_textbook_one():
    assert shots.calibrate_basket(_dunks(800, 39.75)) == pytest.approx(39.75, abs=0.1)
    assert shots.calibrate_basket(_dunks(800, 41.6)) == pytest.approx(41.6, abs=0.1)  # 2003-2010 frames


def test_rim_calibration_fails_the_build_on_a_broken_feed():
    with pytest.raises(shots.CalibrationError, match="centre line"):
        shots.calibrate_basket(_dunks(800, 39.75, y=4.0))
    with pytest.raises(shots.CalibrationError, match="from 41.75"):
        shots.calibrate_basket(_dunks(800, 30.0))
    with pytest.raises(shots.CalibrationError, match="only 10"):
        shots.calibrate_basket(_dunks(10, 39.75))


def test_a_new_season_borrows_the_recent_rim_until_it_has_enough_shots():
    few = _dunks(40, 39.75)
    assert shots.calibrate_basket(few, fallback=shots.RECENT_RIM_X) == shots.RECENT_RIM_X
    with pytest.raises(shots.CalibrationError):
        shots.calibrate_basket(few)
    # Enough shots: the data wins over the fallback.
    assert shots.calibrate_basket(_dunks(800, 41.6), fallback=shots.RECENT_RIM_X) == pytest.approx(41.6, abs=0.1)
