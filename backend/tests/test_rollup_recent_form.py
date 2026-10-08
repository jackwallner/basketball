from datetime import datetime, timezone

import pytest

import rollup_recent_form as rf
from conftest import player_game

import ingest_game_logs as logs
import pandas as pd

NOW = datetime(2026, 1, 20, tzinfo=timezone.utc)


def logs_for(player, specs, season_type="REG", **common):
    """Game-log dicts for (date, overrides) specs, built the way the ingest builds them."""
    frame = pd.DataFrame([
        player_game(player, 100 + n, date, season_type=season_type, **{**common, **extra})
        for n, (date, extra) in enumerate(specs)
    ])
    return logs.build_game_log_rows(frame, 2026, NOW)


def by_window(rows, player):
    return {r["window_weeks"]: r for r in rows if r["player_id"] == player}


def test_window_lengths_are_one_two_and_four_weeks():
    assert rf.WINDOW_WEEKS == (1, 2, 4)


def test_windows_are_anchored_on_the_leagues_latest_week_not_the_players():
    # Week of 2026-01-12 (week 16) is the league's latest; player 1 last played the week before.
    rows = logs_for(1, [("2026-01-05", {}), ("2026-01-07", {})]) + logs_for(2, [("2026-01-13", {})])
    out = rf.build_rows(rows, NOW)
    assert set(by_window(out, 2)) == {1, 2, 4}
    # Player 1 has no games in the latest week: omitted from the 1-week window, present in 2 and 4.
    assert set(by_window(out, 1)) == {2, 4}
    window = by_window(out, 2)[1]
    assert window["end_week"] == 16 and window["start_week"] == 16


def test_current_and_prior_windows_do_not_overlap():
    rows = logs_for(1, [("2026-01-13", {}), ("2026-01-06", {}), ("2025-12-30", {})])
    two_week = by_window(rf.build_rows(rows, NOW), 1)[2]
    assert two_week["games"] == 2                      # weeks 15-16
    assert two_week["start_week"] == 15 and two_week["end_week"] == 16
    assert two_week["as_of"] == "2026-01-13"
    assert two_week["metrics"]["ppg"] == pytest.approx(22.0)
    assert set(two_week["prior_metrics"]) and two_week["delta"]["ppg"] == pytest.approx(0.0)


def test_rates_are_recomputed_from_summed_components_not_averaged():
    # A 40-minute game at 50% TS and a 4-minute garbage-time game at 100% TS.
    rows = logs_for(1, [
        ("2026-01-13", dict(min=40.0, pts=20, fga=20, fta=0, fgm=10, fg3m=0)),
        ("2026-01-14", dict(min=4.0, pts=4, fga=2, fta=0, fgm=2, fg3m=0)),
    ])
    metrics = by_window(rf.build_rows(rows, NOW), 1)[1]["metrics"]
    assert metrics["ts_pct"] == pytest.approx(100 * 24 / (2 * 22), abs=0.06)  # 54.5, not the 75 an average of rates gives
    assert metrics["fg_pct"] == pytest.approx(100 * 12 / 22, abs=0.06)
    assert metrics["ppg"] == pytest.approx(12.0)


def test_usage_uses_per_game_numerators_and_denominators():
    rows = logs_for(1, [("2026-01-13", {}), ("2026-01-14", dict(min=12.0, fga=4, fta=0, tov=1))])
    metrics = by_window(rf.build_rows(rows, NOW), 1)[1]["metrics"]
    game_a = (18 + 0.44 * 6 + 3) * 48, 36 * (90 + 0.44 * 22 + 14)
    game_b = (4 + 0 + 1) * 48, 12 * (90 + 0.44 * 22 + 14)
    assert metrics["usg_pct"] == pytest.approx(100 * (game_a[0] + game_b[0]) / (game_a[1] + game_b[1]), abs=0.06)


def test_zero_denominators_are_omitted_not_reported_as_zero():
    rows = logs_for(1, [("2026-01-13", dict(fg3a=0, fg3m=0, fta=0, ftm=0))])
    metrics = by_window(rf.build_rows(rows, NOW), 1)[1]["metrics"]
    assert "three_pct" not in metrics and "ft_pct" not in metrics
    assert "rim_freq" not in metrics and "on_off" not in metrics       # no shots, no replay
    assert metrics["three_pm"] == 0


def test_zone_and_on_off_components_flow_through_when_present():
    zones = dict(rim_fga=8, rim_fgm=5, smid_fga=4, smid_fgm=2, lmid_fga=2, lmid_fgm=1, c3_fga=1,
                 c3_fgm=0, nc3_fga=3, nc3_fgm=1, ast_fgm=4, on_margin=6.0, off_margin=-2.0, off_poss=26.0)
    rows = logs_for(1, [("2026-01-13", zones)])
    metrics = by_window(rf.build_rows(rows, NOW), 1)[1]["metrics"]
    assert metrics["rim_freq"] == pytest.approx(100 * 8 / 18, abs=0.06)
    assert metrics["rim_fg"] == pytest.approx(62.5)
    player_poss = 103.68 * 36 / 48
    assert metrics["on_off"] == pytest.approx(100 * 6 / player_poss - 100 * -2 / 26, abs=0.06)


def test_regular_season_and_playoffs_are_anchored_separately():
    rows = logs_for(1, [("2026-01-13", {})]) + logs_for(1, [("2026-04-20", {})], season_type="POST")
    out = [r for r in rf.build_rows(rows, NOW) if r["player_id"] == 1]
    anchors = {r["season_type"]: r["end_week"] for r in out}
    assert anchors == {"REG": 16, "POST": 30}
    assert {r["season_type"] for r in out if r["window_weeks"] == 1} == {"REG", "POST"}


def test_a_player_in_two_cohorts_gets_a_row_per_cohort():
    rows = logs_for(1, [("2026-01-13", {})], pos="G", player_type="g")
    out = rf.build_rows(rows, NOW)
    assert {r["player_type"] for r in out} == {"g"}


def test_delta_is_now_minus_then():
    rows = logs_for(1, [("2026-01-13", dict(pts=30, fgm=11)), ("2026-01-06", dict(pts=20, fgm=8))])
    one_week = by_window(rf.build_rows(rows, NOW), 1)[1]
    assert one_week["metrics"]["ppg"] == 30 and one_week["prior_metrics"]["ppg"] == 20
    assert one_week["delta"]["ppg"] == 10


def test_routable_logs_drop_players_without_a_profile():
    rows = [{"player_id": 1, "season_type": "REG"}, {"player_id": 2, "season_type": "REG"}]
    assert rf._routable_logs(rows, {(1, "REG")}) == [rows[0]]
    assert rf._routable_logs(rows, {1}) == [rows[0]]


def test_empty_input():
    assert rf.build_rows([], NOW) == []


def test_output_rows_have_the_table_shape():
    row = rf.build_rows(logs_for(1, [("2026-01-13", {})]), NOW)[0]
    assert set(row) == {
        "player_id", "season", "season_type", "player_type", "window_weeks", "as_of", "start_week",
        "end_week", "team", "games", "plays", "touches", "metrics", "prior_metrics", "delta", "updated_at",
    }
