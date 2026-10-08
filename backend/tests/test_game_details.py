from datetime import datetime, timezone

import pandas as pd
import polars as pl
import pytest

import ingest_game_details as details

NOW = datetime(2026, 1, 10, tzinfo=timezone.utc)


def test_clock_and_elapsed_seconds():
    assert details.parse_clock("7:49") == 469
    assert details.parse_clock("0:51.6") == pytest.approx(51.6)
    assert details.parse_clock("12:00") == 720
    assert details.elapsed_seconds(1, "12:00") == 0
    assert details.elapsed_seconds(1, "11:00") == 60
    assert details.elapsed_seconds(2, "12:00") == 720
    assert details.elapsed_seconds(4, "0:00") == 2880
    assert details.elapsed_seconds(5, "5:00") == 2880          # overtime opens at 48:00
    assert details.elapsed_seconds(5, "0:00") == 3180
    assert details.elapsed_seconds(6, "2:30") == 3180 + 150


def test_four_factors_by_hand():
    factors = details.four_factors(fgm=40, fg3m=12, fga=90, fta=22, tov=14, oreb=10, opp_dreb=33)
    assert factors["efg_pct"] == pytest.approx(100 * (40 + 6) / 90, abs=0.06)
    assert factors["tov_pct"] == pytest.approx(100 * 14 / (90 + 0.44 * 22 + 14), abs=0.06)
    assert factors["oreb_pct"] == pytest.approx(100 * 10 / 43, abs=0.06)
    assert factors["ft_rate"] == pytest.approx(22 / 90, abs=0.001)
    assert details.four_factors(0, 0, 0, 0, 0, 0, 0) == {
        "efg_pct": None, "tov_pct": None, "oreb_pct": None, "ft_rate": None,
    }


def test_pace_is_possessions_per_48_minutes():
    assert details.pace(100, 96, 240) == pytest.approx(98.0)
    assert details.pace(100, 96, 290) == pytest.approx(98.0 * 240 / 290)


def test_percentiles_rank_across_games_and_invert_when_lower_is_better():
    rows = [{"ortg": v, "tov_pct": v} for v in (100.0, 110.0, 120.0, 130.0)]
    details.attach_percentiles(rows, [("ortg", True), ("tov_pct", False)])
    assert [r["ortg"]["pct"] for r in rows] == [13, 38, 63, 88]
    assert [r["tov_pct"]["pct"] for r in rows] == [88, 63, 38, 13]
    assert rows[0]["ortg"]["value"] == 100.0


def test_ineligible_lines_get_a_value_but_no_percentile():
    rows = [{"min": 30, "pts": 20}, {"min": 30, "pts": 10}, {"min": 4, "pts": 30}]
    details.attach_percentiles(rows, [("pts", True)], eligible=lambda r: r["min"] >= details.MIN_MINUTES)
    assert rows[2]["pts"] == {"value": 30, "pct": None}
    assert rows[0]["pts"]["pct"] > rows[1]["pts"]["pct"]


def pbp(rows):
    base = {"period_number": 4, "clock_display_value": "1:00", "scoring_play": False, "team_id": 1,
            "text": "", "home_score": 0, "away_score": 0}
    return pl.DataFrame([{**base, **r} for r in rows])


def test_margin_series_is_home_minus_away_and_ends_on_the_final():
    game = pbp([
        {"period_number": 1, "clock_display_value": "12:00"},
        {"period_number": 1, "clock_display_value": "11:00", "home_score": 2, "scoring_play": True},
        {"period_number": 2, "clock_display_value": "6:00", "home_score": 2, "away_score": 5, "scoring_play": True},
    ])
    assert details.margin_series(game) == [[0, 0], [60, 2], [1080, -3]]


def test_margin_series_is_downsampled_but_keeps_the_last_point():
    rows = [{"period_number": 1, "clock_display_value": "12:00", "home_score": n, "away_score": 0} for n in range(1000)]
    series = details.margin_series(pbp(rows))
    assert len(series) <= details.MARGIN_MAX_POINTS + 1 and series[-1][1] == 999


def test_big_plays_are_late_close_scores_plus_the_biggest_lead_change():
    game = pbp([
        # Q1: a lead change early in the game is still a candidate for "biggest lead change".
        {"period_number": 1, "clock_display_value": "9:00", "home_score": 0, "away_score": 3, "scoring_play": True, "team_id": 2, "text": "early three"},
        {"period_number": 1, "clock_display_value": "8:00", "home_score": 4, "away_score": 3, "scoring_play": True, "team_id": 1, "text": "early flip"},
        # Q4 with 6:00 left: late window not open yet.
        {"period_number": 4, "clock_display_value": "6:00", "home_score": 60, "away_score": 58, "scoring_play": True, "team_id": 1, "text": "too early"},
        # Last five minutes, margin within five: qualifies.
        {"period_number": 4, "clock_display_value": "4:30", "home_score": 60, "away_score": 61, "scoring_play": True, "team_id": 2, "text": "late flip"},
        # Blowout margin: does not.
        {"period_number": 4, "clock_display_value": "3:00", "home_score": 60, "away_score": 80, "scoring_play": True, "team_id": 2, "text": "blowout"},
        # Missed shots never count.
        {"period_number": 4, "clock_display_value": "0:20", "home_score": 60, "away_score": 80, "text": "miss"},
    ])
    plays = details.big_plays(game, {1: "NYK", 2: "BOS"})
    descriptions = [p["description"] for p in plays]
    assert "late flip" in descriptions and "too early" not in descriptions and "blowout" not in descriptions
    assert "miss" not in descriptions
    flip = next(p for p in plays if p["description"] == "late flip")
    assert flip["qtr"] == 4 and flip["clock"] == "4:30" and flip["team"] == "BOS"
    assert flip["points"] == 3
    assert flip["kind"] == "lead_change" and flip["home_margin"] == -1
    # The largest-swing lead change anywhere in the game rides along.
    early = [p for p in plays if p["description"] == "early flip"]
    assert early and early[0]["kind"] == "lead_change" and early[0]["points"] == 4


def test_overtime_scores_are_all_late():
    game = pbp([
        {"period_number": 5, "clock_display_value": "4:50", "home_score": 100, "away_score": 100, "scoring_play": True, "text": "tie"},
        {"period_number": 5, "clock_display_value": "4:30", "home_score": 102, "away_score": 100, "scoring_play": True, "text": "two"},
    ])
    plays = details.big_plays(game, {1: "NYK"})
    assert [p["qtr"] for p in plays] == [5]


def test_player_lines_use_per_game_usage_and_true_shooting():
    from conftest import player_game
    frame = pd.DataFrame([player_game(1, 7, "2026-01-05", name="Star", min=36.0)])
    [line] = details.player_rows(frame)
    assert line["role"] == "player" and line["player_id"] == 1 and line["name"] == "Star"
    assert line["ts_pct"] == pytest.approx(100 * 22 / (2 * (18 + 0.44 * 6)), abs=0.06)
    assert line["usg_pct"] == pytest.approx(27.7, abs=0.06)
    assert line["min"] == 36 and line["plus_minus"] == 5 and line["starter"] is True
