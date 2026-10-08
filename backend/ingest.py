"""
NBA season-snapshot ingest.

Builds one ``player_snapshots`` row per player per season and phase (REG and
POST) from the hoopR-nba-data mirror, computing within-cohort percentiles among
qualified players. Powers the iOS player-percentile screens.

Pipeline (REG and POST are stored and ranked separately):
  1. Build the per-player-game table (``playergames.py``): box lines joined to
     team and opponent totals, shot-zone counts, On-Off components.
  2. Sum each player's games and derive every rate from summed numerators and
     denominators (never an average of per-game rates).
  3. Rank each metric within (season, season_type, player_type, category) among
     qualified players, the Cleaning the Glass convention: a center's
     rebounding is judged against centers.
  4. Upsert to Supabase ``player_snapshots`` on_conflict=(id, season, season_type),
     or, with ``--dry-run``, write the rows to JSON.

Metric availability is bounded by the sources, not by choice (see the coverage
table in ``handoff/NBA_CONTRACT.md``): every box-score metric runs the whole
range, shot zones need the shots feed, and On-Court +/- and On-Off need ESPN's
plus/minus (absent before 2009) and a play-by-play replay that reproduces it.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (not needed for ``--dry-run``).
STATCAST_SEASON overrides the season; ``--season N`` overrides both.
"""

import argparse
import json
import logging
import math
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional, Sequence

import numpy as np
import pandas as pd
from dotenv import load_dotenv

import hoopr
import playergames
from nbacodes import basketball_client
from boxscore import FT_WEIGHT

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)

_now = datetime.now(UTC)
# hoopR names a season for the year it ends: October 2026 is already 2027.
DEFAULT_SEASON = hoopr.season_for_date(_now)
MIN_SEASON = 2002
OLDEST_SUPPORTED_SEASON = 2003
# Sentinel season for the career rollup written by rollup_all_time.py. Zero
# rather than a future year so nothing that clamps to a maximum can mistake it
# for a real season; the app renders it as "All Time".
ALL_TIME_SEASON = 0
SOURCE = "hoopR"

# First season each source supports, verified by running the pipeline over the
# whole range (the coverage table in handoff/NBA_CONTRACT.md has the evidence).
# ESPN's box plus/minus is "--" before 2009, so On-Court +/- starts there.
ON_COURT_FIRST_SEASON = 2009
# The shots feed tracks >= 97% of box-score attempts from 2004 (2003 has 80% of
# them, in 82% of games, so it ships without zones rather than with a skew).
ZONES_FIRST_SEASON = 2004
# The lineup replay is attempted wherever box plus/minus exists to check it
# against. Whether On-Off is *published* is decided per season and phase by the
# 97% validation bar (lineups.VALIDATION_BAR): the regular season clears it in
# 2014, 2015 and 2021-2026, the postseason in 2009, 2010, 2012-2015 and 2021-2026.
ON_OFF_FIRST_SEASON = ON_COURT_FIRST_SEASON

# Qualification (see NBA_CONTRACT.md). Regular season: 15 minutes a game over
# the NBA's 58-game award threshold, and 20 games.
FULL_SEASON_GAMES = 82
QUAL_MINUTES = 870
QUAL_GAMES = 20
POST_QUAL_MINUTES = 60
POST_QUAL_GAMES = 3
# Career bars for the all-time rollup: roughly four starting seasons. The
# playoffs get their own, much lower bar, because a playoff career is measured
# in games rather than seasons.
CAREER_QUAL_MINUTES = 8000
CAREER_POST_QUAL_MINUTES = 500
# A player's On-Off is published only when this share of his games validated.
# The contract's first draft said every game (1.0), which left 73 of 310 qualified
# players with a number in 2025-26 (98.2% per game compounds over ~65 games); 0.95
# covers 291 of 310. The value is exact for the validated games either way, so the
# trade is a slightly smaller sample for coverage, and the games used are the ones
# the replay reproduced to the point.
ON_OFF_MIN_VALID_SHARE = 0.95
# Attempt gates on percentage metrics are prorated like the minutes bar. A
# postseason runs about a fifth of a season; a career about four.
POST_GATE_SCALE = 0.2
CAREER_GATE_SCALE = 4.0
MIN_SCALE = 0.1

PERCENT_PLACES = {"pct1": 1, "dec1": 1, "dec2": 2, "signed1": 1, "comma": 0, "int": 0, "signed_comma": 0}


# --------------------------------------------------------------------------- #
# Metric catalog (labels, ids, categories and formulas are the contract)
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class Metric:
    id: str
    label: str
    kind: str  # "advanced" | "traditional"
    fmt: str
    inverted: bool = False
    gate: Optional[tuple[str, float]] = None  # (attempt column, full-season minimum)


METRIC_DEFS: dict[str, list[Metric]] = {
    "Scoring": [
        Metric("pts_per_100", "Pts/100", "advanced", "dec1"),
        Metric("usg_pct", "USG%", "advanced", "pct1"),
        Metric("ts_pct", "TS%", "advanced", "pct1"),
        Metric("efg_pct", "eFG%", "advanced", "pct1"),
        # FTA/FGA sits near 0.25 and AST:USG near 0.8: two places, not the one the
        # contract gives other ratios, or every player reads 0.2 or 0.3.
        Metric("ftr", "FT Rate", "advanced", "dec2"),
        Metric("three_par", "3PT Rate", "advanced", "pct1"),
        Metric("ppg", "PPG", "traditional", "dec1"),
        Metric("fg_pct", "FG%", "traditional", "pct1"),
        Metric("three_pct", "3P%", "traditional", "pct1", gate=("fg3a", 50)),
        Metric("ft_pct", "FT%", "traditional", "pct1", gate=("fta", 50)),
        Metric("three_pm", "3PM", "traditional", "comma"),
    ],
    "Shooting": [
        Metric("rim_freq", "Rim Freq", "advanced", "pct1"),
        Metric("rim_fg", "Rim FG%", "advanced", "pct1", gate=("rim_fga", 40)),
        Metric("short_mid_freq", "Short Mid Freq", "advanced", "pct1"),
        Metric("short_mid_fg", "Short Mid FG%", "advanced", "pct1", gate=("smid_fga", 40)),
        Metric("long_mid_freq", "Long Mid Freq", "advanced", "pct1"),
        Metric("long_mid_fg", "Long Mid FG%", "advanced", "pct1", gate=("lmid_fga", 40)),
        Metric("corner3_fg", "Corner 3%", "advanced", "pct1", gate=("c3_fga", 30)),
        Metric("nc3_fg", "Non-Corner 3%", "advanced", "pct1", gate=("nc3_fga", 50)),
        Metric("ast_fg_pct", "Assisted FG%", "advanced", "pct1"),
    ],
    "Playmaking": [
        Metric("ast_pct", "AST%", "advanced", "pct1"),
        Metric("ast_per_100", "AST/100", "advanced", "dec1"),
        Metric("tov_pct", "TOV%", "advanced", "pct1", inverted=True),
        Metric("ast_to", "AST:TO", "advanced", "dec1"),
        Metric("ast_usg", "AST:USG", "advanced", "dec2"),
        Metric("apg", "APG", "traditional", "dec1"),
        Metric("ast", "AST", "traditional", "comma"),
        Metric("tov_pg", "TOV/G", "traditional", "dec1", inverted=True),
    ],
    "Rebounding": [
        Metric("oreb_pct", "OREB%", "advanced", "pct1"),
        Metric("dreb_pct", "DREB%", "advanced", "pct1"),
        Metric("reb_pct", "REB%", "advanced", "pct1"),
        Metric("rpg", "RPG", "traditional", "dec1"),
        Metric("oreb", "OREB", "traditional", "comma"),
        Metric("dreb", "DREB", "traditional", "comma"),
    ],
    "Defense": [
        Metric("stl_pct", "STL%", "advanced", "pct1"),
        Metric("blk_pct", "BLK%", "advanced", "pct1"),
        Metric("stocks_per_100", "Stocks/100", "advanced", "dec1"),
        Metric("foul_per_100", "Fouls/100", "advanced", "dec1", inverted=True),
        Metric("spg", "SPG", "traditional", "dec1"),
        Metric("bpg", "BPG", "traditional", "dec1"),
        Metric("stl", "STL", "traditional", "comma"),
        Metric("blk", "BLK", "traditional", "comma"),
    ],
    "Impact": [
        Metric("on_net", "On-Court +/-", "advanced", "signed1"),
        Metric("on_off", "On-Off", "advanced", "signed1"),
        Metric("min_pct", "Min%", "advanced", "pct1"),
        Metric("mpg", "MPG", "traditional", "dec1"),
        Metric("gs", "GS", "traditional", "comma"),
        Metric("plus_minus", "+/-", "traditional", "signed_comma"),
    ],
}
ALL_METRICS: list[Metric] = [m for defs in METRIC_DEFS.values() for m in defs]
METRIC_BY_ID: dict[str, Metric] = {m.id: m for m in ALL_METRICS}

STANDARD_STAT_LABELS = [
    "G", "GS", "MPG", "PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MIN",
]

# Per-game components summed across a player's games.
BASE_COLUMNS = [
    "min", "pts", "fgm", "fga", "fg3m", "fg3a", "ftm", "fta", "oreb", "dreb",
    "reb", "ast", "stl", "blk", "tov", "pf", "player_poss",
]
# Derived per-game numerators and denominators, summed then divided: the
# formulas in the contract are written "summed per game".
TERM_COLUMNS = [
    "usg_num", "usg_den", "ast_den", "oreb_num", "oreb_den", "dreb_num", "dreb_den",
    "reb_num", "reb_den", "stl_num", "stl_den", "blk_num", "blk_den", "avail_min",
    "pm_sum", "pm_poss", "oo_on", "oo_off", "oo_poss", "oo_off_poss", "oo_games",
]
SUM_COLUMNS = BASE_COLUMNS + TERM_COLUMNS + playergames.ZONE_COLUMNS


# --------------------------------------------------------------------------- #
# Pure helpers (unit-tested; no network)
# --------------------------------------------------------------------------- #
def resolve_season(cli_season: Optional[int] = None) -> int:
    """Resolve the season from CLI arg, then STATCAST_SEASON env, then default."""
    if cli_season is not None:
        candidate: Optional[int] = cli_season
    else:
        raw = os.environ.get("STATCAST_SEASON")
        if raw is None or raw == "":
            return DEFAULT_SEASON
        try:
            candidate = int(raw)
        except ValueError:
            return DEFAULT_SEASON
    if candidate is None or candidate < MIN_SEASON or candidate > DEFAULT_SEASON:
        return DEFAULT_SEASON
    return candidate


def player_type_from_position(position: Any) -> str:
    """ESPN position abbreviation -> ``g`` / ``f`` / ``c`` / ``unknown``."""
    from boxscore import fold_position
    return fold_position(position)


def format_value(value: Any, fmt: str) -> str:
    """Format a raw stat value for display per the contract conventions."""
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return ""
    try:
        v = float(value)
    except (ValueError, TypeError):
        return ""
    if fmt == "comma":
        return f"{int(round(v)):,}"
    if fmt == "int":
        return str(int(round(v)))
    if fmt == "signed_comma":
        return f"{int(round(v)):+,}"
    if fmt == "pct1":
        return f"{v:.1f}%"
    if fmt == "dec1":
        return f"{v:.1f}"
    if fmt == "dec2":
        return f"{v:.2f}"
    if fmt == "signed1":
        return f"{v:+.1f}"
    return str(v)


def midpoint_percentile(pool: np.ndarray, value: float, inverted: bool) -> int:
    """Percentile (1-100) of ``value`` against a sorted pool, midpoint rank.

    Ties count half: a value equal to ``k`` pool members sits halfway through
    them. ``inverted`` ranks lower values higher (turnovers, fouls). A player
    inside the pool is counted in it; a player outside (an unqualified
    live-season player) is placed against it.
    """
    n = len(pool)
    if n == 0:
        return 50
    below = int(np.searchsorted(pool, value, side="left"))
    at_or_below = int(np.searchsorted(pool, value, side="right"))
    equal = at_or_below - below
    if inverted:
        rank = n - at_or_below + 0.5 * equal
    else:
        rank = below + 0.5 * equal
    return max(1, min(100, int(math.floor(100 * rank / n + 0.5))))


def rank_percentiles(series: pd.Series, inverted: bool) -> dict[Any, int]:
    """Percentile (1-100) of each non-null value within the series."""
    values = pd.to_numeric(series, errors="coerce").dropna()
    if values.empty:
        return {}
    pool = np.sort(values.to_numpy(dtype=float))
    return {idx: midpoint_percentile(pool, float(v), inverted) for idx, v in values.items()}


def qualification_scale(team_games: Sequence[int]) -> float:
    """Fraction of a full 82-game season played so far, floored at 0.1.

    Measured as the median club's games played so one early tip-off does not
    move the whole league's bar. A finished season always scales to 1 (callers
    pass nothing for past seasons), so every past season keeps the bar it was
    ranked on.
    """
    games = [g for g in team_games if g and g > 0]
    if not games:
        return 1.0
    return max(MIN_SCALE, min(1.0, float(np.median(games)) / FULL_SEASON_GAMES))


def _num(row: Any, column: str) -> float:
    value = row.get(column)
    try:
        return float(value) if value is not None and not pd.isna(value) else 0.0
    except (ValueError, TypeError):
        return 0.0


def qualifies(row: Any, season_type: str = "REG", career: bool = False, scale: float = 1.0) -> bool:
    """Whether a player clears the playing-time bar.

    Four tiers: a full season (870 minutes and 20 games, prorated by ``scale``
    while the season is being played), a postseason run (60 minutes, 3 games),
    a career (8,000 minutes) and a playoff career (500 minutes).
    """
    minutes = _num(row, "min")
    games = _num(row, "g")
    postseason = season_type == "POST"
    if career:
        return minutes >= (CAREER_POST_QUAL_MINUTES if postseason else CAREER_QUAL_MINUTES)
    if postseason:
        return minutes >= POST_QUAL_MINUTES and games >= POST_QUAL_GAMES
    if scale < 1:
        return minutes >= math.ceil(QUAL_MINUTES * scale) and games >= max(1, math.ceil(QUAL_GAMES * scale))
    return minutes >= QUAL_MINUTES and games >= QUAL_GAMES


def gate_threshold(base: float, season_type: str = "REG", career: bool = False, scale: float = 1.0) -> int:
    """Attempt minimum for a percentage metric, prorated like the minutes bar."""
    factor = 1.0
    if season_type == "POST":
        factor *= POST_GATE_SCALE
    elif not career:
        factor *= scale
    if career:
        factor *= CAREER_GATE_SCALE
    return max(1, math.ceil(base * factor))


def gate_met(row: Any, metric: Metric, season_type: str, career: bool, scale: float) -> bool:
    if metric.gate is None:
        return True
    column, base = metric.gate
    return _num(row, column) >= gate_threshold(base, season_type, career, scale)


# --------------------------------------------------------------------------- #
# Aggregation: per-game components -> season sums -> metric values
# --------------------------------------------------------------------------- #
def derive_game_terms(frame: pd.DataFrame) -> pd.DataFrame:
    """Add per-game numerators and denominators for the share metrics.

    Works on any frame with the game-log components (the player-game table or
    one rebuilt from stored game logs), so the season snapshot and Recent Form
    share a single definition of every formula.
    """
    df = frame.copy()
    avail = df["tm_min"] / 5
    df["avail_min"] = avail
    df["usg_num"] = (df["fga"] + FT_WEIGHT * df["fta"] + df["tov"]) * avail
    df["usg_den"] = df["min"] * (df["tm_fga"] + FT_WEIGHT * df["tm_fta"] + df["tm_tov"])
    df["ast_den"] = (df["min"] / avail) * df["tm_fgm"] - df["fgm"]
    df["oreb_num"] = df["oreb"] * avail
    df["oreb_den"] = df["min"] * (df["tm_oreb"] + df["opp_dreb"])
    df["dreb_num"] = df["dreb"] * avail
    df["dreb_den"] = df["min"] * (df["tm_dreb"] + df["opp_oreb"])
    df["reb_num"] = df["reb"] * avail
    df["reb_den"] = df["min"] * (df["tm_reb"] + df["opp_reb"])
    df["stl_num"] = df["stl"] * avail
    df["stl_den"] = df["min"] * df["opp_poss"]
    df["blk_num"] = df["blk"] * avail
    df["blk_den"] = df["min"] * (df["opp_fga"] - df["opp_fg3a"])
    has_pm = df["plus_minus"].notna()
    df["pm_sum"] = df["plus_minus"].fillna(0)
    df["pm_poss"] = df["player_poss"].where(has_pm, 0.0)
    has_oo = df["on_margin"].notna()
    df["oo_on"] = df["on_margin"].fillna(0)
    df["oo_off"] = df["off_margin"].fillna(0)
    df["oo_poss"] = df["player_poss"].where(has_oo, 0.0)
    df["oo_off_poss"] = df["off_poss"].fillna(0)
    df["oo_games"] = has_oo.astype(float)
    return df


def _ratio(numer: pd.Series, denom: pd.Series) -> pd.Series:
    return numer / denom.where(denom > 0)


def metric_values(s: pd.DataFrame) -> pd.DataFrame:
    """Every contract metric from summed components (``s`` has one row per player).

    ``s`` carries the summed ``BASE_COLUMNS``, ``TERM_COLUMNS`` and zone columns
    plus ``g`` (games) and ``gs`` (games started). Values are NaN where the
    inputs do not exist, never 0: that is how an unavailable metric is omitted.
    """
    out = pd.DataFrame(index=s.index)
    shot_fga = s["shot_fga"]
    tracked_made = s[[f"{z}_fgm" for z in ("rim", "smid", "lmid", "c3", "nc3")]].sum(axis=1, min_count=1)
    scoring_poss = s["fga"] + FT_WEIGHT * s["fta"]

    out["pts_per_100"] = 100 * _ratio(s["pts"], s["player_poss"])
    out["usg_pct"] = 100 * _ratio(s["usg_num"], s["usg_den"])
    out["ts_pct"] = 100 * _ratio(s["pts"], 2 * scoring_poss)
    out["efg_pct"] = 100 * _ratio(s["fgm"] + 0.5 * s["fg3m"], s["fga"])
    out["ftr"] = _ratio(s["fta"], s["fga"])
    out["three_par"] = 100 * _ratio(s["fg3a"], s["fga"])
    out["ppg"] = _ratio(s["pts"], s["g"])
    out["fg_pct"] = 100 * _ratio(s["fgm"], s["fga"])
    out["three_pct"] = 100 * _ratio(s["fg3m"], s["fg3a"])
    out["ft_pct"] = 100 * _ratio(s["ftm"], s["fta"])
    out["three_pm"] = s["fg3m"]

    out["rim_freq"] = 100 * _ratio(s["rim_fga"], shot_fga)
    out["rim_fg"] = 100 * _ratio(s["rim_fgm"], s["rim_fga"])
    out["short_mid_freq"] = 100 * _ratio(s["smid_fga"], shot_fga)
    out["short_mid_fg"] = 100 * _ratio(s["smid_fgm"], s["smid_fga"])
    out["long_mid_freq"] = 100 * _ratio(s["lmid_fga"], shot_fga)
    out["long_mid_fg"] = 100 * _ratio(s["lmid_fgm"], s["lmid_fga"])
    out["corner3_fg"] = 100 * _ratio(s["c3_fgm"], s["c3_fga"])
    out["nc3_fg"] = 100 * _ratio(s["nc3_fgm"], s["nc3_fga"])
    out["ast_fg_pct"] = 100 * _ratio(s["ast_fgm"], tracked_made)

    out["ast_pct"] = 100 * _ratio(s["ast"], s["ast_den"])
    out["ast_per_100"] = 100 * _ratio(s["ast"], s["player_poss"])
    out["tov_pct"] = 100 * _ratio(s["tov"], scoring_poss + s["tov"])
    out["ast_to"] = _ratio(s["ast"], s["tov"])
    out["ast_usg"] = _ratio(out["ast_pct"], out["usg_pct"])
    out["apg"] = _ratio(s["ast"], s["g"])
    out["ast"] = s["ast"]
    out["tov_pg"] = _ratio(s["tov"], s["g"])

    out["oreb_pct"] = 100 * _ratio(s["oreb_num"], s["oreb_den"])
    out["dreb_pct"] = 100 * _ratio(s["dreb_num"], s["dreb_den"])
    out["reb_pct"] = 100 * _ratio(s["reb_num"], s["reb_den"])
    out["rpg"] = _ratio(s["reb"], s["g"])
    out["oreb"] = s["oreb"]
    out["dreb"] = s["dreb"]

    out["stl_pct"] = 100 * _ratio(s["stl_num"], s["stl_den"])
    out["blk_pct"] = 100 * _ratio(s["blk_num"], s["blk_den"])
    out["stocks_per_100"] = 100 * _ratio(s["stl"] + s["blk"], s["player_poss"])
    out["foul_per_100"] = 100 * _ratio(s["pf"], s["player_poss"])
    out["spg"] = _ratio(s["stl"], s["g"])
    out["bpg"] = _ratio(s["blk"], s["g"])
    out["stl"] = s["stl"]
    out["blk"] = s["blk"]

    out["on_net"] = 100 * _ratio(s["pm_sum"], s["pm_poss"])
    # On-Off needs ON_OFF_MIN_VALID_SHARE of the player's games replayed and validated.
    complete = (s["oo_games"] >= ON_OFF_MIN_VALID_SHARE * s["g"]) & (s["oo_poss"] > 0) & (s["oo_off_poss"] > 0)
    on_rating = 100 * _ratio(s["oo_on"], s["oo_poss"])
    off_rating = 100 * _ratio(s["oo_off"], s["oo_off_poss"])
    out["on_off"] = (on_rating - off_rating).where(complete)
    out["min_pct"] = 100 * _ratio(s["min"], s["avail_min"])
    out["mpg"] = _ratio(s["min"], s["g"])
    out["gs"] = s["gs"]
    out["plus_minus"] = s["pm_sum"].where(s["pm_poss"] > 0)
    return out


def sum_games(frame: pd.DataFrame, by: str | list[str] = "athlete_id") -> pd.DataFrame:
    """Sum the components of every group's games (``frame`` has the game terms)."""
    grouped = frame.groupby(by)
    sums = grouped[SUM_COLUMNS].sum(min_count=1)
    sums["g"] = grouped.size()
    sums["gs"] = grouped["starter"].sum().astype(float)
    # Zero-sum columns that are really "no data" stay NaN; the others are real zeros.
    for column in BASE_COLUMNS + TERM_COLUMNS:
        sums[column] = sums[column].fillna(0)
    return sums


def _identity(frame: pd.DataFrame, by: str = "athlete_id") -> pd.DataFrame:
    """Name, team, position and cohort from each player's most recent game."""
    ordered = frame.sort_values(["game_date", "game_id"])
    latest = ordered.groupby(by).tail(1).set_index(by)
    known = ordered[ordered["player_type"] != "unknown"].groupby(by).tail(1).set_index(by)
    identity = latest[["name", "team", "pos"]].copy()
    identity["player_type"] = known["player_type"].reindex(identity.index).fillna("unknown")
    identity["position"] = known["pos"].reindex(identity.index).map(
        lambda pos: _folded_position(pos)
    ).fillna("")
    return identity.drop(columns=["pos"])


def _folded_position(pos: Any) -> str:
    return {"g": "G", "f": "F", "c": "C"}.get(player_type_from_position(pos), "")


def aggregate_player_games(frame: pd.DataFrame, season_type: str) -> pd.DataFrame:
    """One total row per player (indexed by id) for one phase, metrics attached."""
    phase = frame[frame["season_type"] == season_type] if season_type else frame
    if phase.empty:
        return pd.DataFrame()
    games = derive_game_terms(phase)
    agg = sum_games(games).join(_identity(phase))
    values = metric_values(agg)
    # Counting metrics (AST, STL, GS ...) are the summed columns themselves.
    agg = agg.join(values.drop(columns=[c for c in values.columns if c in agg.columns]))
    agg["image_url"] = [f"https://a.espncdn.com/i/headshots/nba/players/full/{int(pid)}.png" for pid in agg.index]
    agg.index.name = "id"
    return agg


# --------------------------------------------------------------------------- #
# Snapshot rows
# --------------------------------------------------------------------------- #
def build_standard_stats(row: Any) -> list[dict[str, str]]:
    """Assemble the standard_stats jsonb array from an aggregated row."""
    g = _num(row, "g")
    if g <= 0:
        return []

    def per_game(column: str) -> str:
        return f"{_num(row, column) / g:.1f}"

    def pair(made: str, att: str) -> str:
        return f"{int(_num(row, made)):,}/{int(_num(row, att)):,}"

    values = {
        "G": str(int(g)),
        "GS": str(int(_num(row, "gs"))),
        "MPG": per_game("min"),
        "PPG": per_game("pts"),
        "RPG": per_game("reb"),
        "APG": per_game("ast"),
        "SPG": per_game("stl"),
        "BPG": per_game("blk"),
        "FG": pair("fgm", "fga"),
        "3P": pair("fg3m", "fg3a"),
        "FT": pair("ftm", "fta"),
        "TOV": f"{int(_num(row, 'tov')):,}",
        "PF": f"{int(_num(row, 'pf')):,}",
        "MIN": f"{int(round(_num(row, 'min'))):,}",
    }
    if _num(row, "pm_poss") > 0:
        values["+/-"] = f"{int(round(_num(row, 'pm_sum'))):+,}"
    return [
        {"id": f"std-{label}", "label": label, "value": values[label]}
        for label in STANDARD_STAT_LABELS if label in values
    ]


def build_snapshot_rows(
    agg: pd.DataFrame,
    season: int,
    now: datetime,
    season_type: str = "REG",
    qual_scale: float = 1.0,
    live: bool = False,
) -> list[dict]:
    """Build player_snapshots rows from an aggregated (id-indexed) DataFrame.

    Past seasons: only qualified players get a row, and a percentage metric
    below its attempt gate is omitted. The live season ships every player who
    has played, each metric carrying ``qualified`` so the app can grey out the
    ones under the bar; percentiles are always computed against the qualified
    pool, so an early-season fluke cannot move anyone else's rank.
    """
    if agg.empty:
        return []
    now_str = now.isoformat()
    career = season == ALL_TIME_SEASON
    flags = [qualifies(row, season_type, career, qual_scale) for row in agg.to_dict("records")]
    agg = agg.assign(_qualified=flags)
    cohort_rows = agg if live else agg[agg["_qualified"]]
    players: dict[int, dict] = {}

    for player_type, cohort in cohort_rows.groupby("player_type"):
        records = cohort.to_dict("index")
        everyone = agg[agg["player_type"] == player_type]
        pools = _metric_pools(everyone, season_type, career, qual_scale)
        for category, defs in METRIC_DEFS.items():
            for pid, row in records.items():
                for metric in defs:
                    raw = row.get(metric.id)
                    if raw is None or pd.isna(raw):
                        continue
                    row_qualified = bool(row["_qualified"]) and gate_met(row, metric, season_type, career, qual_scale)
                    if not live and not row_qualified:
                        continue
                    pool = pools[metric.id]
                    entry = {
                        "id": f"{category.lower()}-{int(pid)}-{metric.id}",
                        "label": metric.label,
                        "value": format_value(raw, metric.fmt),
                        "percentile": midpoint_percentile(pool, float(raw), metric.inverted),
                        "category": category,
                    }
                    if live:
                        entry["qualified"] = row_qualified
                    player = players.get(int(pid))
                    if player is None:
                        player = players[int(pid)] = _new_snapshot(int(pid), row, season, season_type, now_str)
                    player["metrics"].append(entry)

    return sorted((p for p in players.values() if p["metrics"]), key=lambda p: p["id"])


def _metric_pools(
    cohort: pd.DataFrame, season_type: str, career: bool, scale: float,
) -> dict[str, np.ndarray]:
    """Sorted value pool per metric: qualified players who clear the attempt gate.

    Falls back to everyone with a value when nobody qualifies yet (the first
    games of a season) so early-season percentiles still mean something.
    """
    qualified = cohort[cohort["_qualified"]]
    pools: dict[str, np.ndarray] = {}
    for metric in ALL_METRICS:
        if metric.id not in cohort.columns:
            pools[metric.id] = np.array([])
            continue
        gated = qualified
        if metric.gate is not None:
            column, base = metric.gate
            gated = qualified[qualified[column].fillna(0) >= gate_threshold(base, season_type, career, scale)]
        values = pd.to_numeric(gated[metric.id], errors="coerce").dropna().to_numpy(dtype=float)
        if len(values) == 0:
            values = pd.to_numeric(cohort[metric.id], errors="coerce").dropna().to_numpy(dtype=float)
        pools[metric.id] = np.sort(values)
    return pools


def _new_snapshot(pid: int, row: Any, season: int, season_type: str, now_str: str) -> dict:
    image = row.get("image_url")
    return {
        "id": pid,
        "name": str(row.get("name") or ""),
        "team": str(row.get("team") or "TBD"),
        "position": str(row.get("position") or ""),
        "handedness": "",
        "image_url": image if isinstance(image, str) and image else None,
        "player_type": row.get("player_type") or "unknown",
        "season": season,
        "season_type": season_type,
        "source": SOURCE,
        "metrics": [],
        "standard_stats": build_standard_stats(row),
        "games": [],
        "updated_at": now_str,
    }


# --------------------------------------------------------------------------- #
# Season build
# --------------------------------------------------------------------------- #
def build_season_frame(
    season: int, loader=hoopr.read_asset, strict: bool = True,
) -> playergames.PlayerGames:
    """The per-game table for a season, with zones and On-Off where supported."""
    return playergames.build_player_games(
        season,
        zones=season >= ZONES_FIRST_SEASON,
        on_off=season >= ON_OFF_FIRST_SEASON,
        loader=loader,
        strict=strict,
    )


def season_scale(diagnostics: dict[str, Any], season_type: str, live: bool) -> float:
    """Qualification scale for a phase: prorated only for the live regular season."""
    if not live or season_type != "REG":
        return 1.0
    return qualification_scale(diagnostics.get("team_games", {}).get("REG", []))


def chunks(lst: list, n: int) -> Iterator[list]:
    for i in range(0, len(lst), n):
        yield lst[i:i + n]


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, separators=(",", ":"), default=str))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None, help="hoopR season (the year it ends) to ingest.")
    parser.add_argument(
        "--season-type", choices=("REG", "POST", "all"), default="REG",
        help="Season phase to ingest. Nightly refresh uses all.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Build rows and write JSON; touch no database.")
    parser.add_argument("--out", default=None, help="Directory for --dry-run JSON output.")
    parser.add_argument(
        "--live", choices=("auto", "yes", "no"), default="auto",
        help="Ship every player with a qualified flag (live) or only qualified players.",
    )
    args = parser.parse_args()

    season = resolve_season(args.season)
    live = season == DEFAULT_SEASON if args.live == "auto" else args.live == "yes"
    now = datetime.now(UTC)
    client = None if args.dry_run else basketball_client()

    phases = ("REG", "POST") if args.season_type == "all" else (args.season_type,)
    logger.info("=== Ingesting NBA season %s (%s)%s ===", season, ", ".join(phases), " live" if live else "")
    built = build_season_frame(season)
    logger.info("Diagnostics: %s", {k: v for k, v in built.diagnostics.items() if k != "team_games"})
    any_rows = False
    for phase in phases:
        agg = aggregate_player_games(built.frame, phase)
        scale = season_scale(built.diagnostics, phase, live)
        rows = build_snapshot_rows(agg, season, now, phase, qual_scale=scale, live=live)
        if not rows:
            if phase == "POST":
                logger.info("No postseason rows for %s yet.", season)
                continue
            logger.error("No rows to upsert for %s %s.", season, phase)
            sys.exit(1)
        any_rows = True
        by_type: dict[str, int] = {}
        for row in rows:
            by_type[row["player_type"]] = by_type.get(row["player_type"], 0) + 1
        logger.info("Built %d %s snapshots by type: %s (qualification scale %.2f)", len(rows), phase, by_type, scale)
        if args.dry_run:
            if args.out:
                write_json(Path(args.out) / f"snapshots_{season}_{phase}.json", rows)
            continue
        for i, batch in enumerate(chunks(rows, 150)):
            logger.info("Upserting batch %d (%d rows) for %s %s...", i + 1, len(batch), season, phase)
            client.table("player_snapshots").upsert(batch, on_conflict="id,season,season_type").execute()
        _prune_orphans(client, rows, season, phase)
    if not any_rows:
        logger.error("No snapshots built for %s.", season)
        sys.exit(1)


def _prune_orphans(client: Any, rows: list[dict], season: int, phase: str) -> None:
    sanity_floor = 20 if phase == "POST" else 150
    if len(rows) < sanity_floor:
        logger.warning("Only %d %s rows built, skipping prune.", len(rows), phase)
        return
    kept = {row["id"] for row in rows}
    existing = (
        client.table("player_snapshots").select("id")
        .eq("season", season).eq("season_type", phase).execute().data
    )
    orphans = [row["id"] for row in existing if row["id"] not in kept]
    for batch in chunks(orphans, 100):
        (
            client.table("player_snapshots").delete()
            .in_("id", batch).eq("season", season).eq("season_type", phase).execute()
        )
    logger.info("Pruned %d stale/unqualified rows for %s %s.", len(orphans), season, phase)


if __name__ == "__main__":
    main()
