import numpy as np
import pandas as pd
import polars as pl
import pytest

import boxscore


# One player-game worked by hand. Player: 36 MP, 18 FGA, 8 FGM, 6 FTA, 3 TOV,
# 7 AST, 2 OREB, 6 DREB, 2 STL, 1 BLK. Team: 240 min, 90 FGA, 40 FGM, 22 FTA,
# 14 TOV, 10 OREB, 34 DREB. Opponent: 33 DREB, 9 OREB, 88 FGA, 30 3PA, 96 poss.
def test_possessions_formula():
    # 90 - 10 + 14 + 0.44 * 22
    assert boxscore.possessions(90, 10, 14, 22) == pytest.approx(103.68)


def test_usage_pct_hand_computed():
    # 100 * (18 + 0.44*6 + 3) * (240/5) / (36 * (90 + 0.44*22 + 14))
    value = boxscore.usage_pct(fga=18, fta=6, tov=3, mp=36, tm_min=240, tm_fga=90, tm_fta=22, tm_tov=14)
    assert value == pytest.approx(27.72695, abs=1e-4)


def test_assist_pct_hand_computed():
    # 100 * 7 / ((36 / 48) * 40 - 8) = 700 / 22
    assert boxscore.assist_pct(ast=7, mp=36, tm_min=240, tm_fgm=40, fgm=8) == pytest.approx(31.81818, abs=1e-4)


def test_rebound_shares_hand_computed():
    assert boxscore.rebound_pct(2, 36, 240, tm_reb=10, opp_reb=33) == pytest.approx(6.20155, abs=1e-4)
    assert boxscore.rebound_pct(6, 36, 240, tm_reb=34, opp_reb=9) == pytest.approx(18.60465, abs=1e-4)
    assert boxscore.rebound_pct(8, 36, 240, tm_reb=44, opp_reb=42) == pytest.approx(12.40310, abs=1e-4)


def test_steal_and_block_pct_hand_computed():
    assert boxscore.steal_pct(stl=2, mp=36, tm_min=240, opp_poss=96) == pytest.approx(2.77778, abs=1e-4)
    # Blocks are measured against two-point attempts: 88 FGA - 30 3PA = 58.
    assert boxscore.block_pct(blk=1, mp=36, tm_min=240, opp_fga=88, opp_fg3a=30) == pytest.approx(2.29885, abs=1e-4)


def test_overtime_changes_the_minutes_every_share_is_scaled_by():
    # In a double-overtime game (290 minutes) the same 36 minutes is a smaller share.
    regulation = boxscore.usage_pct(18, 6, 3, 36, 240, 90, 22, 14)
    overtime = boxscore.usage_pct(18, 6, 3, 36, 290, 90, 22, 14)
    assert overtime == pytest.approx(regulation * 290 / 240)


def test_team_minutes_snap_to_regulation_plus_overtimes():
    assert boxscore.team_minutes(240) == 240
    assert boxscore.team_minutes(241) == 240
    assert boxscore.team_minutes(238) == 240
    assert boxscore.team_minutes(265) == 265
    assert boxscore.team_minutes(264) == 265
    assert boxscore.team_minutes(291) == 290
    assert boxscore.team_minutes(200) == 240  # never below regulation


def test_team_turnovers_handles_both_file_shapes():
    # Old files: official total in `turnovers`, doubled copy in `total_turnovers`.
    assert boxscore.team_turnovers_total(17, 34) == 17
    # Recent files: player sum in `turnovers`, plus team turnovers in `total_turnovers`.
    assert boxscore.team_turnovers_total(12, 14) == 14
    assert boxscore.team_turnovers_total(12, 12) == 12


def test_plus_minus_placeholder_is_missing_not_zero():
    parsed = boxscore.parse_plus_minus(pd.Series(["+2", "-4", "0", "--", None, ""]))
    assert parsed.iloc[0] == 2 and parsed.iloc[1] == -4 and parsed.iloc[2] == 0
    assert parsed.iloc[3:].isna().all()


def test_positions_fold_into_three_cohorts():
    for abbreviation, cohort in [("G", "g"), ("PG", "g"), ("F", "f"), ("SF", "f"), ("PF", "f"), ("C", "c")]:
        assert boxscore.fold_position(abbreviation) == cohort
    assert boxscore.fold_position(None) == "unknown"
    assert boxscore.fold_position(float("nan")) == "unknown"
    assert boxscore.fold_position("X") == "unknown"


def _player_box(rows):
    base = {
        "game_id": 1, "season_type": 2, "game_date": pd.Timestamp("2026-01-05").date(),
        "athlete_id": 10, "athlete_display_name": "A", "team_id": 1, "team_abbreviation": "NY",
        "opponent_team_id": 2, "opponent_team_abbreviation": "SA", "home_away": "home",
        "minutes": 30.0, "field_goals_made": 5, "field_goals_attempted": 10,
        "three_point_field_goals_made": 1, "three_point_field_goals_attempted": 3,
        "free_throws_made": 2, "free_throws_attempted": 2, "offensive_rebounds": 1,
        "defensive_rebounds": 4, "rebounds": 5, "assists": 3, "steals": 1, "blocks": 0,
        "turnovers": 2, "fouls": 1, "plus_minus": "+3", "points": 13, "starter": True,
        "did_not_play": False, "athlete_position_abbreviation": "G", "team_score": 100,
        "opponent_team_score": 90,
    }
    return pl.DataFrame([{**base, **row} for row in rows])


def test_clean_player_box_drops_all_star_preseason_playin_and_dnps():
    raw = _player_box([
        {"athlete_id": 1},                                                    # real game
        {"athlete_id": 2, "team_abbreviation": "STARS", "opponent_team_abbreviation": "STRIPES"},
        {"athlete_id": 3, "season_type": 1},                                  # preseason
        {"athlete_id": 4, "season_type": 5},                                  # play-in
        {"athlete_id": 5, "did_not_play": True, "minutes": None},             # DNP
        {"athlete_id": 6, "minutes": 0.0},                                    # on the floor for no time
        {"athlete_id": 7, "season_type": 3},                                  # postseason
        {"athlete_id": 8, "team_abbreviation": "GS", "opponent_team_abbreviation": "NO"},
    ])
    frame = boxscore.clean_player_box(raw)
    assert sorted(frame["athlete_id"]) == [1, 7, 8]
    assert dict(zip(frame["athlete_id"], frame["season_type"])) == {1: "REG", 7: "POST", 8: "REG"}
    row = frame[frame["athlete_id"] == 8].iloc[0]
    assert (row["team"], row["opp"]) == ("GSW", "NOP")


def test_clean_player_box_dedupes_and_parses():
    raw = _player_box([{"athlete_id": 1, "plus_minus": "--"}, {"athlete_id": 1, "plus_minus": "--"}])
    frame = boxscore.clean_player_box(raw)
    assert len(frame) == 1
    assert np.isnan(frame.iloc[0]["plus_minus"])
    assert frame.iloc[0]["player_type"] == "g"
    assert frame.iloc[0]["game_date"] == "2026-01-05"


def test_player_possessions_scale_with_minutes():
    teams = pd.DataFrame([
        {"game_id": 1, "team_id": 1, "fgm": 40, "fga": 90, "fg3a": 30, "fta": 22, "tov": 14,
         "oreb": 10, "dreb": 34, "reb": 44, "poss": 103.68, "tm_min": 240},
        {"game_id": 1, "team_id": 2, "fgm": 38, "fga": 88, "fg3a": 30, "fta": 20, "tov": 12,
         "oreb": 9, "dreb": 33, "reb": 42, "poss": 96.0, "tm_min": 240},
    ])
    players = boxscore.clean_player_box(_player_box([{"athlete_id": 1, "minutes": 48.0}]))
    frame = boxscore.attach_team_context(players, teams)
    # A player on the floor the full 48 minutes sees every one of the team's possessions.
    assert frame.iloc[0]["player_poss"] == pytest.approx(103.68 * 48 / 48)
    assert frame.iloc[0]["opp_poss"] == 96.0 and frame.iloc[0]["opp_dreb"] == 33
