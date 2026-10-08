"""
Box-score plumbing: clean player rows, team and opponent context, possessions.

Every rate in the Scoring, Playmaking, Rebounding, Defense and Impact categories
is a share of something the team did while the player was on the floor (USG%,
AST%, REB%, STL%, BLK%) or a per-100-possession count. Both need each player's
game joined to his team's and opponent's totals, which is what this module
builds. The formulas themselves are pure functions so they can be checked by
hand (see tests): possessions, USG%, AST%, OREB%/DREB%/REB%, STL% and BLK%.

Conventions worth knowing:

* Team possessions are ``FGA - OREB + TOV + 0.44 * FTA`` from the team box.
* Team minutes are ``240 + 25 * overtimes``, inferred from the players' minutes
  (ESPN rounds each player to whole minutes, so the sum can be 238 to 242).
* ESPN's team ``turnovers`` column is the official team total in old seasons and
  the players' sum in recent ones, with ``total_turnovers`` adding team
  turnovers on top. The helper below picks the larger sensible one so USG%'s
  denominator is the same definition across seasons.
* Box ``plus_minus`` is the string ``"--"`` where ESPN has none (before 2009), so
  it is parsed to NaN and never to 0.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import polars as pl

import hoopr

FT_WEIGHT = 0.44
REGULATION_MINUTES = 240
OVERTIME_MINUTES = 25
TEAM_SIZE = 5

PLAYER_COLUMNS = [
    "game_id", "season_type", "game_date", "athlete_id", "athlete_display_name",
    "team_id", "team_abbreviation", "opponent_team_id", "opponent_team_abbreviation",
    "home_away", "minutes", "field_goals_made", "field_goals_attempted",
    "three_point_field_goals_made", "three_point_field_goals_attempted",
    "free_throws_made", "free_throws_attempted", "offensive_rebounds",
    "defensive_rebounds", "rebounds", "assists", "steals", "blocks", "turnovers",
    "fouls", "plus_minus", "points", "starter", "did_not_play",
    "athlete_position_abbreviation", "team_score", "opponent_team_score",
]
PLAYER_RENAMES = {
    "athlete_display_name": "name", "team_abbreviation": "team",
    "opponent_team_abbreviation": "opp", "opponent_team_id": "opp_team_id",
    "minutes": "min", "field_goals_made": "fgm", "field_goals_attempted": "fga",
    "three_point_field_goals_made": "fg3m", "three_point_field_goals_attempted": "fg3a",
    "free_throws_made": "ftm", "free_throws_attempted": "fta",
    "offensive_rebounds": "oreb", "defensive_rebounds": "dreb", "rebounds": "reb",
    "assists": "ast", "steals": "stl", "blocks": "blk", "turnovers": "tov",
    "fouls": "pf", "points": "pts", "athlete_position_abbreviation": "pos",
    "team_score": "tm_score", "opponent_team_score": "opp_score",
}
TEAM_COLUMNS = [
    "game_id", "team_id", "field_goals_made", "field_goals_attempted",
    "three_point_field_goals_attempted", "free_throws_attempted",
    "offensive_rebounds", "defensive_rebounds", "turnovers", "total_turnovers",
]
COUNT_COLUMNS = [
    "min", "pts", "fgm", "fga", "fg3m", "fg3a", "ftm", "fta", "oreb", "dreb",
    "reb", "ast", "stl", "blk", "tov", "pf",
]
POSITION_FOLD = {"G": "g", "PG": "g", "SG": "g", "F": "f", "SF": "f", "PF": "f", "C": "c"}


# --------------------------------------------------------------------------- #
# Pure formulas (unit-tested against hand-computed examples)
# --------------------------------------------------------------------------- #
def possessions(fga: float, oreb: float, tov: float, fta: float) -> float:
    """Estimated possessions: ``FGA - OREB + TOV + 0.44 * FTA``."""
    return fga - oreb + tov + FT_WEIGHT * fta


def usage_pct(fga: float, fta: float, tov: float, mp: float, tm_min: float,
              tm_fga: float, tm_fta: float, tm_tov: float) -> float:
    """USG%: share of team possessions a player ends while on the floor."""
    numer = (fga + FT_WEIGHT * fta + tov) * (tm_min / TEAM_SIZE)
    denom = mp * (tm_fga + FT_WEIGHT * tm_fta + tm_tov)
    return 100 * numer / denom


def assist_pct(ast: float, mp: float, tm_min: float, tm_fgm: float, fgm: float) -> float:
    """AST%: share of teammates' field goals a player assisted while on the floor."""
    return 100 * ast / ((mp / (tm_min / TEAM_SIZE)) * tm_fgm - fgm)


def rebound_pct(reb: float, mp: float, tm_min: float, tm_reb: float, opp_reb: float) -> float:
    """OREB%, DREB% or REB%: share of available rebounds a player grabbed."""
    return 100 * reb * (tm_min / TEAM_SIZE) / (mp * (tm_reb + opp_reb))


def steal_pct(stl: float, mp: float, tm_min: float, opp_poss: float) -> float:
    """STL%: steals per 100 opponent possessions while on the floor."""
    return 100 * stl * (tm_min / TEAM_SIZE) / (mp * opp_poss)


def block_pct(blk: float, mp: float, tm_min: float, opp_fga: float, opp_fg3a: float) -> float:
    """BLK%: share of opponent two-point attempts blocked while on the floor."""
    return 100 * blk * (tm_min / TEAM_SIZE) / (mp * (opp_fga - opp_fg3a))


def team_minutes(player_minutes_sum: float) -> int:
    """240 plus 25 per overtime, snapped from the sum of rounded player minutes."""
    overtimes = max(0, int(round((player_minutes_sum - REGULATION_MINUTES) / OVERTIME_MINUTES)))
    return REGULATION_MINUTES + OVERTIME_MINUTES * overtimes


def team_turnovers_total(turnovers: float, total_turnovers: float) -> float:
    """Team turnovers including team turnovers, whichever way the season stores them.

    Old files put the official total in ``turnovers`` and a doubled copy in
    ``total_turnovers``; recent files put the players' sum in ``turnovers`` and
    add team turnovers in ``total_turnovers``. A ratio under 1.5 identifies the
    recent shape.
    """
    if total_turnovers >= turnovers and total_turnovers < 1.5 * max(turnovers, 1):
        return total_turnovers
    return turnovers


def fold_position(abbreviation: object) -> str:
    """ESPN position abbreviation -> ``g`` / ``f`` / ``c`` / ``unknown``."""
    if abbreviation is None or (isinstance(abbreviation, float) and np.isnan(abbreviation)):
        return "unknown"
    return POSITION_FOLD.get(str(abbreviation).strip().upper(), "unknown")


def parse_plus_minus(series: pd.Series) -> pd.Series:
    """Box ``plus_minus`` strings ("+2", "-4", "0", "--") as floats, NaN for none."""
    text = series.astype("string").str.strip()
    return pd.to_numeric(text.str.replace("+", "", regex=False), errors="coerce").astype(float)


# --------------------------------------------------------------------------- #
# Frame builders
# --------------------------------------------------------------------------- #
def clean_player_box(player_box: pl.DataFrame) -> pd.DataFrame:
    """Player-game rows for NBA games in the REG and POST phases that were played.

    Drops preseason and play-in games, All-Star games (any team that is not an
    NBA franchise), players who did not play, and duplicate rows.
    """
    available = [c for c in PLAYER_COLUMNS if c in player_box.columns]
    frame = player_box.select(available).to_pandas()
    frame = frame[frame["season_type"].isin(hoopr.PHASE_BY_ESPN_TYPE)].copy()
    frame["season_type"] = frame["season_type"].map(hoopr.PHASE_BY_ESPN_TYPE)
    frame["team_abbreviation"] = frame["team_abbreviation"].map(hoopr.normalize_team)
    frame["opponent_team_abbreviation"] = frame["opponent_team_abbreviation"].map(hoopr.normalize_team)
    keep = frame["team_abbreviation"].isin(hoopr.NBA_TEAMS) & frame["opponent_team_abbreviation"].isin(hoopr.NBA_TEAMS)
    frame = frame[keep]
    minutes = pd.to_numeric(frame["minutes"], errors="coerce")
    played = ~frame["did_not_play"].fillna(False).astype(bool) & minutes.notna() & (minutes > 0)
    frame = frame[played].rename(columns=PLAYER_RENAMES)
    frame["min"] = pd.to_numeric(frame["min"], errors="coerce")
    for column in COUNT_COLUMNS[1:]:
        frame[column] = pd.to_numeric(frame[column], errors="coerce").fillna(0)
    frame["plus_minus"] = parse_plus_minus(frame["plus_minus"])
    frame["starter"] = frame["starter"].fillna(False).astype(bool)
    frame["player_type"] = frame["pos"].map(fold_position)
    frame["home"] = frame["home_away"].eq("home")
    frame["game_date"] = pd.to_datetime(frame["game_date"]).dt.strftime("%Y-%m-%d")
    for column in ("game_id", "athlete_id", "team_id", "opp_team_id"):
        frame[column] = frame[column].astype("int64")
    frame = frame.drop(columns=["home_away", "did_not_play"])
    return frame.drop_duplicates(["game_id", "athlete_id"], keep="last").reset_index(drop=True)


def team_game_table(team_box: pl.DataFrame, players: pd.DataFrame) -> pd.DataFrame:
    """One row per team-game with totals, possessions and minutes."""
    teams = team_box.select([c for c in TEAM_COLUMNS if c in team_box.columns]).to_pandas()
    teams = teams.rename(columns={
        "field_goals_made": "fgm", "field_goals_attempted": "fga",
        "three_point_field_goals_attempted": "fg3a", "free_throws_attempted": "fta",
        "offensive_rebounds": "oreb", "defensive_rebounds": "dreb",
    })
    teams["tov"] = [
        team_turnovers_total(t, tt) for t, tt in zip(teams["turnovers"], teams["total_turnovers"])
    ]
    teams["reb"] = teams["oreb"] + teams["dreb"]
    teams["poss"] = possessions(teams["fga"], teams["oreb"], teams["tov"], teams["fta"])
    minutes = players.groupby(["game_id", "team_id"])["min"].sum().rename("player_minutes").reset_index()
    teams = teams.merge(minutes, on=["game_id", "team_id"], how="left")
    teams["tm_min"] = [
        team_minutes(m) if pd.notna(m) else REGULATION_MINUTES for m in teams["player_minutes"]
    ]
    columns = ["game_id", "team_id", "fgm", "fga", "fg3a", "fta", "tov", "oreb", "dreb", "reb", "poss", "tm_min"]
    for column in columns[2:-1]:
        teams[column] = pd.to_numeric(teams[column], errors="coerce")
    return teams[columns].drop_duplicates(["game_id", "team_id"], keep="last")


def attach_team_context(players: pd.DataFrame, teams: pd.DataFrame) -> pd.DataFrame:
    """Join each player-game to his team's and his opponent's totals.

    Games with no team-box row for either side are dropped: every share needs
    both. Adds the contract's game-log context columns.
    """
    own = teams.rename(columns={
        "fgm": "tm_fgm", "fga": "tm_fga", "fta": "tm_fta", "tov": "tm_tov",
        "oreb": "tm_oreb", "dreb": "tm_dreb", "reb": "tm_reb", "poss": "team_poss",
        "fg3a": "tm_fg3a",
    })
    opp = teams.rename(columns={
        "team_id": "opp_team_id", "fga": "opp_fga", "fg3a": "opp_fg3a", "oreb": "opp_oreb",
        "dreb": "opp_dreb", "reb": "opp_reb", "poss": "opp_poss",
    })[["game_id", "opp_team_id", "opp_fga", "opp_fg3a", "opp_oreb", "opp_dreb", "opp_reb", "opp_poss"]]
    frame = players.merge(own, on=["game_id", "team_id"], how="inner")
    frame = frame.merge(opp, on=["game_id", "opp_team_id"], how="inner")
    frame["player_poss"] = frame["team_poss"] * frame["min"] / (frame["tm_min"] / TEAM_SIZE)
    return frame
