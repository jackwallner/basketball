"""
One row per player per game, with every component the pipeline needs.

The season snapshot, the game logs, Recent Form, the career rollup and the
game-detail pages all derive from the same table, so it is built exactly once
per season and everything else reads it. Each row carries:

* the box line (minutes, shooting, rebounds, ...) and plus/minus,
* the team and opponent totals the share metrics divide by (``tm_*``, ``opp_*``)
  and the possession estimates,
* shot-zone counts from the shots parquet (``rim_fga`` ... ``ast_fgm``), and
* On-Off components replayed from the play-by-play (``on_margin``,
  ``off_margin``, ``off_poss``), present only where the replay reproduced the
  box score's plus/minus.

Zones and On-Off are optional because the sources only cover part of the range
(see ``ZONES_FIRST_SEASON`` / ``ON_OFF_FIRST_SEASON`` in ``ingest.py``); a season
without them simply has those columns empty, never zero.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Callable, Optional

import numpy as np
import pandas as pd
import polars as pl

import boxscore
import hoopr
import lineups
import shots as shotzones

logger = logging.getLogger(__name__)

Loader = Callable[[str, int], pl.DataFrame]

ZONE_COLUMNS = [
    f"{zone}_{kind}" for zone in shotzones.ZONES for kind in ("fga", "fgm")
] + ["ast_fgm", "shot_fga"]
ON_OFF_COLUMNS = ["on_margin", "off_margin", "off_poss"]


@dataclass
class PlayerGames:
    """The per-game table plus what was learned while building it."""

    frame: pd.DataFrame
    diagnostics: dict[str, Any] = field(default_factory=dict)


def _read(loader: Loader, kind: str, season: int) -> Optional[pl.DataFrame]:
    try:
        return loader(kind, season)
    except hoopr.AssetUnavailable:
        logger.warning("hoopR %s asset for %s is not published", kind, season)
        return None


def add_zone_counts(
    frame: pd.DataFrame,
    shots: pl.DataFrame,
    pbp: Optional[pl.DataFrame],
    diagnostics: dict[str, Any],
    season: int = 0,
) -> pd.DataFrame:
    """Merge per-game zone counts; games with no tracked shots stay empty."""
    field_goals = shotzones.field_goal_shots(shots)
    fallback = shotzones.RECENT_RIM_X if season >= shotzones.RECENT_RIM_FIRST_SEASON else None
    rim_x = shotzones.calibrate_basket(field_goals, fallback=fallback)
    diagnostics["rim_x"] = round(rim_x, 3)
    zoned = shotzones.with_zones(field_goals, rim_x, pbp)
    counts = shotzones.zone_counts(zoned).to_pandas()
    tracked_games = set(counts["game_id"].astype("int64"))
    merged = frame.merge(counts, on=["game_id", "athlete_id"], how="left")
    covered = merged["game_id"].isin(tracked_games)
    merged.loc[covered, ZONE_COLUMNS] = merged.loc[covered, ZONE_COLUMNS].fillna(0)
    box_fga = float(frame["fga"].sum())
    games = frame["game_id"].unique()
    diagnostics["shots_coverage"] = round(float(counts["shot_fga"].sum()) / box_fga, 4) if box_fga else 0.0
    diagnostics["shots_games_share"] = round(len(tracked_games.intersection(games)) / len(games), 4)
    return merged


def add_on_off(
    frame: pd.DataFrame,
    pbp: pl.DataFrame,
    diagnostics: dict[str, Any],
    bar: float = lineups.VALIDATION_BAR,
) -> pd.DataFrame:
    """Merge the lineup replay; blank it for a phase that misses the 97% bar."""
    needed = frame[["game_id", "athlete_id", "team_id", "starter", "plus_minus", "tm_score", "opp_score"]]
    replayed = lineups.reconstruct_season(pbp, needed)
    merged = frame.merge(replayed, on=["game_id", "athlete_id"], how="left")
    rates: dict[str, float] = {}
    for phase, rows in merged.groupby("season_type"):
        rates[phase] = round(float(rows["valid"].fillna(False).mean()), 4)
    diagnostics["on_off_rate"] = rates
    publishable = merged["valid"].fillna(False).astype(bool)
    for phase, rate in rates.items():
        if rate < bar:
            logger.warning("On-Off omitted for %s: only %.1f%% of player-games validate", phase, 100 * rate)
            publishable &= merged["season_type"] != phase
    merged["on_margin"] = np.where(publishable, merged["on_margin"], np.nan)
    merged["off_margin"] = np.where(publishable, merged["team_margin"] - merged["on_margin"], np.nan)
    merged["off_poss"] = np.where(publishable, merged["team_poss"] - merged["player_poss"], np.nan)
    return merged.drop(columns=["valid", "team_margin"])


def build_player_games(
    season: int,
    *,
    zones: bool = True,
    on_off: bool = True,
    loader: Loader = hoopr.read_asset,
    strict: bool = True,
) -> PlayerGames:
    """Build the per-game table for one hoopR season (REG and POST rows).

    ``diagnostics["shots_status"]`` / ``["pbp_status"]`` report each optional
    feed as ``ready``, ``pending`` (not published yet), ``degraded`` (it failed
    and the table was built without it; only when ``strict`` is False, which is
    how the publisher runs so a late optional feed cannot block core stats) or
    ``not_applicable`` (the season predates the source or the caller skipped it).
    """
    diagnostics: dict[str, Any] = {
        "season": season,
        "shots_status": "ready" if zones else "not_applicable",
        "pbp_status": "ready" if on_off else "not_applicable",
    }
    player_box = _read(loader, "player_box", season)
    team_box = _read(loader, "team_box", season)
    if player_box is None or team_box is None:
        return PlayerGames(pd.DataFrame(), diagnostics)

    players = boxscore.clean_player_box(player_box)
    teams = boxscore.team_game_table(team_box, players)
    frame = boxscore.attach_team_context(players, teams)
    diagnostics["player_games"] = int(len(frame))
    diagnostics["team_games"] = {
        phase: sorted(rows.groupby("team_id")["game_id"].nunique().tolist())
        for phase, rows in frame.groupby("season_type")
    }
    if frame.empty:
        return PlayerGames(frame, diagnostics)

    pbp: Optional[pl.DataFrame] = None
    if zones or on_off:
        pbp = _read(loader, "pbp", season)
        if pbp is not None and pbp.is_empty():
            pbp = None

    if zones:
        shots = _read(loader, "shots", season)
        if shots is None or shots.is_empty():
            diagnostics["shots_status"] = "pending"
        else:
            try:
                frame = add_zone_counts(frame, shots, pbp, diagnostics, season)
            except Exception:
                if strict:
                    raise
                logger.exception("Shot zones failed for %s; building without them.", season)
                diagnostics["shots_status"] = "degraded"
    for column in ZONE_COLUMNS:
        if column not in frame.columns:
            frame[column] = np.nan

    if on_off:
        if pbp is None:
            diagnostics["pbp_status"] = "pending"
        else:
            try:
                frame = add_on_off(frame, pbp, diagnostics)
            except Exception:
                if strict:
                    raise
                logger.exception("On-Off replay failed for %s; building without it.", season)
                diagnostics["pbp_status"] = "degraded"
    for column in ON_OFF_COLUMNS:
        if column not in frame.columns:
            frame[column] = np.nan
    return PlayerGames(frame.reset_index(drop=True), diagnostics)
