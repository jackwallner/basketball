import numpy as np
import pandas as pd
import polars as pl
import pytest

import hoopr
import lineups
import playergames
from conftest import player_game


def frame(n_games, plus_minus):
    rows = []
    for game in range(n_games):
        for athlete, team in ((1, 1), (2, 2)):
            rows.append(player_game(athlete, 100 + game, f"2026-01-{game + 1:02d}", team_id=team,
                                    plus_minus=plus_minus[athlete], tm_score=100, opp_score=90))
    # The replay columns are added by add_on_off itself.
    return pd.DataFrame(rows).drop(columns=playergames.ON_OFF_COLUMNS)


def replay_with(valid_share, monkeypatch):
    """Stand in for the lineup replay: ``valid_share`` of player-games validate."""
    def fake(pbp, needed):
        out = needed[["game_id", "athlete_id"]].copy()
        out["on_margin"] = 5.0
        out["valid"] = (np.arange(len(out)) % 100) < valid_share * 100
        out["team_margin"] = 10.0
        return out
    monkeypatch.setattr(lineups, "reconstruct_season", fake)


def test_on_off_is_published_when_the_replay_clears_the_bar(monkeypatch):
    replay_with(0.98, monkeypatch)
    diagnostics = {}
    out = playergames.add_on_off(frame(100, {1: 5.0, 2: -5.0}), pl.DataFrame(), diagnostics)
    assert diagnostics["on_off_rate"]["REG"] >= 0.97
    published = out[out["on_margin"].notna()]
    assert len(published) == pytest.approx(0.98 * len(out), abs=2)
    row = published.iloc[0]
    assert row["off_margin"] == 10.0 - row["on_margin"]          # team margin minus the margin with him on
    assert row["off_poss"] == pytest.approx(row["team_poss"] - row["player_poss"])


def test_on_off_is_withheld_for_a_phase_under_97_percent(monkeypatch):
    replay_with(0.95, monkeypatch)
    diagnostics = {}
    out = playergames.add_on_off(frame(100, {1: 5.0, 2: -5.0}), pl.DataFrame(), diagnostics)
    assert diagnostics["on_off_rate"]["REG"] < lineups.VALIDATION_BAR
    assert out["on_margin"].isna().all() and out["off_margin"].isna().all() and out["off_poss"].isna().all()


def test_bar_is_applied_per_phase(monkeypatch):
    replay_with(1.0, monkeypatch)
    games = frame(50, {1: 5.0, 2: -5.0})
    playoffs = games.assign(season_type="POST", game_id=games["game_id"] + 1000)
    broken = lambda pbp, needed: pd.DataFrame({  # noqa: E731
        "game_id": needed["game_id"], "athlete_id": needed["athlete_id"], "on_margin": 5.0,
        "valid": needed["game_id"] < 1000, "team_margin": 10.0,
    })
    monkeypatch.setattr(lineups, "reconstruct_season", broken)
    out = playergames.add_on_off(pd.concat([games, playoffs], ignore_index=True), pl.DataFrame(), {})
    assert out[out["season_type"] == "REG"]["on_margin"].notna().all()
    assert out[out["season_type"] == "POST"]["on_margin"].isna().all()


def test_missing_optional_feeds_are_reported_pending_not_fatal():
    def loader(kind, season):
        if kind in ("shots", "pbp"):
            raise hoopr.AssetUnavailable(kind)
        return {"player_box": PLAYER_BOX, "team_box": TEAM_BOX}[kind]

    built = playergames.build_player_games(2027, loader=loader, strict=False)
    assert built.diagnostics["shots_status"] == "pending" and built.diagnostics["pbp_status"] == "pending"
    assert not built.frame.empty
    assert built.frame["rim_fga"].isna().all() and built.frame["on_margin"].isna().all()


def test_skipped_sources_are_not_applicable():
    built = playergames.build_player_games(2003, zones=False, on_off=False,
                                           loader=lambda kind, season: {"player_box": PLAYER_BOX, "team_box": TEAM_BOX}[kind])
    assert built.diagnostics["shots_status"] == "not_applicable" and built.diagnostics["pbp_status"] == "not_applicable"


def test_a_failing_optional_feed_degrades_the_build_instead_of_failing_it():
    def loader(kind, season):
        if kind == "shots":
            return pl.DataFrame({"type_text": ["Jump Shot"]})       # wrong shape: calibration will refuse it
        if kind == "pbp":
            raise hoopr.AssetUnavailable(kind)
        return {"player_box": PLAYER_BOX, "team_box": TEAM_BOX}[kind]

    built = playergames.build_player_games(2027, loader=loader, strict=False)
    assert built.diagnostics["shots_status"] == "degraded"
    assert not built.frame.empty
    with pytest.raises(Exception):
        playergames.build_player_games(2027, loader=loader, strict=True)


PLAYER_BOX = pl.DataFrame([
    {"game_id": 1, "season_type": 2, "game_date": pd.Timestamp("2026-11-02").date(), "athlete_id": a,
     "athlete_display_name": f"P{a}", "team_id": t, "team_abbreviation": code, "opponent_team_id": 3 - t,
     "opponent_team_abbreviation": opp, "home_away": "home" if t == 1 else "away", "minutes": 240.0,
     "field_goals_made": 40, "field_goals_attempted": 90, "three_point_field_goals_made": 10,
     "three_point_field_goals_attempted": 30, "free_throws_made": 15, "free_throws_attempted": 20,
     "offensive_rebounds": 10, "defensive_rebounds": 33, "rebounds": 43, "assists": 20, "steals": 7,
     "blocks": 4, "turnovers": 12, "fouls": 18, "plus_minus": "+5", "points": 105, "starter": True,
     "did_not_play": False, "athlete_position_abbreviation": "G", "team_score": 105, "opponent_team_score": 100}
    for a, t, code, opp in ((1, 1, "NY", "BOS"), (2, 2, "BOS", "NY"))
])
TEAM_BOX = pl.DataFrame([
    {"game_id": 1, "team_id": t, "field_goals_made": 40, "field_goals_attempted": 90,
     "three_point_field_goals_attempted": 30, "free_throws_attempted": 20, "offensive_rebounds": 10,
     "defensive_rebounds": 33, "turnovers": 12, "total_turnovers": 13}
    for t in (1, 2)
])
