from datetime import datetime, timezone

import numpy as np
import pandas as pd

import ingest_game_logs as logs
from conftest import player_game

NOW = datetime(2026, 1, 10, tzinfo=timezone.utc)

CONTRACT_KEYS = [
    "min", "pts", "fgm", "fga", "fg3m", "fg3a", "ftm", "fta", "oreb", "dreb", "reb", "ast", "stl",
    "blk", "tov", "pf", "plus_minus", "starter", "team_poss", "player_poss", "tm_min", "tm_fgm",
    "tm_fga", "tm_fta", "tm_tov", "tm_oreb", "tm_dreb", "tm_reb", "opp_poss", "opp_fga", "opp_fg3a",
    "opp_oreb", "opp_dreb", "opp_reb", "rim_fga", "rim_fgm", "smid_fga", "smid_fgm", "lmid_fga",
    "lmid_fgm", "c3_fga", "c3_fgm", "nc3_fga", "nc3_fgm", "ast_fgm", "on_margin", "off_margin", "off_poss",
]


def zoned(**overrides):
    values = dict(rim_fga=8, rim_fgm=5, smid_fga=4, smid_fgm=2, lmid_fga=2, lmid_fgm=1, c3_fga=1,
                  c3_fgm=0, nc3_fga=3, nc3_fgm=1, ast_fgm=4, shot_fga=18,
                  on_margin=5.0, off_margin=-3.0, off_poss=26.0)
    values.update(overrides)
    return values


def build(rows):
    return logs.build_game_log_rows(pd.DataFrame(rows), 2026, NOW)


def test_row_keys_and_identity():
    [row] = build([player_game(7, 401810001, "2026-01-05", **zoned())])
    assert row["player_id"] == 7 and row["season"] == 2026 and row["season_type"] == "REG"
    assert row["game_id"] == "401810001" and row["game_date"] == "2026-01-05"
    assert row["team"] == "NYK" and row["opponent"] == "BOS" and row["player_type"] == "g"
    assert row["updated_at"] == NOW.isoformat()


def test_metrics_dict_has_every_contract_key():
    [row] = build([player_game(7, 1, "2026-01-05", **zoned())])
    assert list(row["metrics"]) == CONTRACT_KEYS


def test_plays_are_possessions_used_and_touches_are_minutes():
    [row] = build([player_game(7, 1, "2026-01-05", fga=18, fta=6, tov=3, min=35.6)])
    assert row["plays"] == round(18 + 0.44 * 6 + 3) == 24
    assert row["touches"] == 36


def test_unavailable_components_are_null_never_zero():
    [row] = build([player_game(7, 1, "2026-01-05", plus_minus=np.nan)])
    metrics = row["metrics"]
    assert metrics["plus_minus"] is None
    assert metrics["on_margin"] is None and metrics["off_margin"] is None and metrics["off_poss"] is None
    assert "rim_fga" not in metrics                       # no shots feed for the game


def test_counts_stay_integers_and_possessions_keep_decimals():
    [row] = build([player_game(7, 1, "2026-01-05", **zoned())])
    assert row["metrics"]["fga"] == 18 and isinstance(row["metrics"]["fga"], int)
    assert row["metrics"]["starter"] == 1
    assert row["metrics"]["team_poss"] == 103.68
    assert row["metrics"]["on_margin"] == 5


def test_cohort_is_the_players_known_position_for_every_game():
    rows = [
        player_game(7, 1, "2026-01-05", pos="F", player_type="f"),
        player_game(7, 2, "2026-01-07", pos=None, player_type="unknown"),
    ]
    assert [r["player_type"] for r in build(rows)] == ["f", "f"]


def test_week_numbers_count_from_a_fixed_season_epoch():
    # Season 2026's epoch is Monday 2025-09-29; the number never depends on the data loaded.
    assert logs.game_week("2025-10-21", 2026) == 4
    assert logs.game_week("2026-04-12", 2026) == 28
    assert logs.game_week("2026-06-13", 2026) == 37
    rows = build([player_game(7, 1, "2025-10-21"), player_game(7, 2, "2026-04-12", season_type="REG")])
    assert [r["week"] for r in rows] == [4, 28]


def test_empty_frame_builds_nothing():
    assert logs.build_game_log_rows(pd.DataFrame(), 2026, NOW) == []


def test_rows_are_json_serialisable():
    import json
    json.dumps(build([player_game(7, 1, "2026-01-05", **zoned())]))
