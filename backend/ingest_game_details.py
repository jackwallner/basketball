"""
Per-game advanced box scores from hoopR box scores and play-by-play.

One ``public.game_details`` row per game: both teams' four factors (eFG%, TOV%,
OREB%, FT Rate), offensive and defensive rating, pace, points in the paint,
fast-break points, bench points and biggest lead; every player's line (points,
rebounds, assists, TS%, USG%, +/-); the score margin through the game; and the
plays that decided it. The layout follows the advanced box scores fans already
read on Basketball-Reference and Cleaning the Glass: efficiency first, counts
second.

Every team and player value carries a percentile against all of this season's
team games (or qualifying player games, 10 minutes or more), recomputed on every
run, so an October game is ranked against October and a May game against the
whole year.

The football table shape is kept so the publish path and the Swift decoder carry
over, with these basketball meanings:

* ``team_stats``: ``{"away": {...}, "home": {...}}`` of metric -> ``{value, pct}``
  (or a plain count).
* ``players``: one line per player who played.
* ``win_probability``: the score margin series ``[[elapsed_seconds, home_margin], ...]``
  (home score minus away score), downsampled to ``MARGIN_MAX_POINTS`` points and
  ending on the final margin. The column name is kept; basketball has no public
  win-probability feed.
* ``big_plays``: scoring plays in the last five minutes of the fourth quarter or
  overtime that left the margin within five, plus the lead change worth the most
  points, each ``{qtr, clock, team, description, points, home_margin, kind}``.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (not needed for ``--dry-run``).
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

import pandas as pd
import polars as pl
from dotenv import load_dotenv

import hoopr
import ingest
import playergames
from ingest_game_logs import game_week
from ingest import FT_WEIGHT, resolve_season
from nbacodes import basketball_client

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

MARGIN_MAX_POINTS = 160
BIG_PLAYS = 6
CLOSE_MARGIN = 5
LATE_SECONDS = 300
REGULATION_PERIOD_SECONDS = 720
OVERTIME_PERIOD_SECONDS = 300
# Player-game percentiles only rank lines with real minutes behind them.
MIN_MINUTES = 10

# (key, higher_is_better)
TEAM_METRICS: list[tuple[str, bool]] = [
    ("pts", True),
    ("ortg", True),
    ("drtg", False),
    ("pace", True),
    ("efg_pct", True),
    ("tov_pct", False),
    ("oreb_pct", True),
    ("ft_rate", True),
    ("points_in_paint", True),
    ("fast_break_points", True),
    ("bench_points", True),
    ("largest_lead", True),
]
PLAYER_METRICS: list[tuple[str, bool]] = [
    ("pts", True), ("reb", True), ("ast", True),
    ("ts_pct", True), ("usg_pct", True), ("plus_minus", True),
]


def _f(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(number) or math.isinf(number) else number


def _round(value: Optional[float], places: int = 1) -> Optional[float]:
    return None if value is None else round(value, places)


def _rate(numerator: float, denominator: float) -> Optional[float]:
    return numerator / denominator if denominator else None


def parse_clock(clock: Any) -> float:
    """Seconds left in the period from a clock display ("7:49", "0:51.6")."""
    text = str(clock or "0:00")
    minutes, _, seconds = text.partition(":")
    try:
        return int(minutes) * 60 + float(seconds or 0)
    except ValueError:
        return 0.0


def elapsed_seconds(period: int, clock: Any) -> float:
    """Game seconds elapsed at a clock reading (regulation 12 min, overtime 5)."""
    remaining = parse_clock(clock)
    if period <= 4:
        return (period - 1) * REGULATION_PERIOD_SECONDS + (REGULATION_PERIOD_SECONDS - remaining)
    return 4 * REGULATION_PERIOD_SECONDS + (period - 5) * OVERTIME_PERIOD_SECONDS + (
        OVERTIME_PERIOD_SECONDS - remaining
    )


def _pct(numerator: float, denominator: float, places: int = 1) -> Optional[float]:
    return _round(100 * numerator / denominator, places) if denominator else None


def four_factors(fgm: float, fg3m: float, fga: float, fta: float, tov: float,
                 oreb: float, opp_dreb: float) -> dict[str, Optional[float]]:
    """eFG%, TOV%, OREB% and FT Rate from team totals."""
    return {
        "efg_pct": _pct(fgm + 0.5 * fg3m, fga),
        "tov_pct": _pct(tov, fga + FT_WEIGHT * fta + tov),
        "oreb_pct": _pct(oreb, oreb + opp_dreb),
        "ft_rate": _round(fta / fga, 3) if fga else None,
    }


def pace(team_poss: float, opp_poss: float, team_minutes: float) -> Optional[float]:
    """Possessions per 48 minutes."""
    return _rate(48 * (team_poss + opp_poss) / 2, team_minutes / 5)


def _int_or_none(value: Any) -> Optional[int]:
    number = _f(value)
    return None if number is None else int(number)


def team_rows(team_box: pd.DataFrame, frame: pd.DataFrame) -> list[dict[str, Any]]:
    """One row per team-game of metrics (before percentiles are attached)."""
    box = team_box.copy()
    for column in ("points_in_paint", "fast_break_points", "largest_lead"):
        box[column] = pd.to_numeric(box.get(column), errors="coerce")
    bench = (
        frame[~frame["starter"]].groupby(["game_id", "team_id"])["pts"].sum().rename("bench_points")
    )
    by_team = frame.groupby(["game_id", "team_id"]).first()
    rows: list[dict[str, Any]] = []
    for team in box.itertuples(index=False):
        key = (int(team.game_id), int(team.team_id))
        if key not in by_team.index:
            continue
        context = by_team.loc[key]
        poss, opp_poss = float(context["team_poss"]), float(context["opp_poss"])
        row: dict[str, Any] = {
            "_game": key[0], "_team": key[1], "_side": team.team_home_away,
            "pts": _int_or_none(team.team_score),
            "ortg": _pct(float(team.team_score), poss),
            "drtg": _pct(float(team.opponent_team_score), opp_poss),
            "pace": _round(_f(pace(poss, opp_poss, float(context["tm_min"])))),
            "points_in_paint": _int_or_none(team.points_in_paint),
            "fast_break_points": _int_or_none(team.fast_break_points),
            "bench_points": _int_or_none(bench.get(key, 0)),
            "largest_lead": _int_or_none(team.largest_lead),
        }
        row.update(four_factors(
            float(team.field_goals_made), float(team.three_point_field_goals_made),
            float(team.field_goals_attempted), float(team.free_throws_attempted),
            float(context["tm_tov"]), float(team.offensive_rebounds), float(context["opp_dreb"]),
        ))
        rows.append(row)
    return rows


def player_rows(frame: pd.DataFrame) -> list[dict[str, Any]]:
    """One line per player-game (before percentiles are attached)."""
    terms = ingest.derive_game_terms(frame)
    rows: list[dict[str, Any]] = []
    for g in terms.itertuples(index=False):
        shooting = g.fga + FT_WEIGHT * g.fta
        rows.append({
            "_game": int(g.game_id),
            "role": "player",
            "player_id": int(g.athlete_id),
            "name": g.name,
            "team": g.team,
            "starter": bool(g.starter),
            "min": _int_or_none(g.min),
            "pts": int(g.pts),
            "reb": int(g.reb),
            "ast": int(g.ast),
            "ts_pct": _pct(g.pts, 2 * shooting),
            "usg_pct": _pct(g.usg_num, g.usg_den),
            "plus_minus": _int_or_none(g.plus_minus),
        })
    return rows


def margin_series(game: pl.DataFrame) -> list[list[float]]:
    """[elapsed_seconds, home_margin] points, downsampled, ending on the result."""
    points: list[list[float]] = []
    for period, clock, home, away in zip(
        game["period_number"], game["clock_display_value"], game["home_score"], game["away_score"],
    ):
        if home is None or away is None or period is None:
            continue
        points.append([round(elapsed_seconds(int(period), clock)), int(home) - int(away)])
    if len(points) > MARGIN_MAX_POINTS:
        stride = math.ceil(len(points) / MARGIN_MAX_POINTS)
        points = points[::stride] + [points[-1]]
    return points


def big_plays(game: pl.DataFrame, abbreviations: dict[int, str]) -> list[dict[str, Any]]:
    """Late scoring plays inside five points, plus the biggest lead change."""
    plays: list[dict[str, Any]] = []
    previous = 0
    for row in game.iter_rows(named=True):
        home, away = row["home_score"], row["away_score"]
        if home is None or away is None:
            continue
        margin = int(home) - int(away)
        points = abs(margin - previous)
        if row["scoring_play"] and points > 0:
            period = int(row["period_number"])
            remaining = parse_clock(row["clock_display_value"])
            plays.append({
                "qtr": period,
                "clock": str(row["clock_display_value"]),
                "team": abbreviations.get(int(row["team_id"]), "") if row["team_id"] is not None else "",
                "description": str(row["text"] or "")[:240],
                "points": points,
                "home_margin": margin,
                "_before": previous,
                "_remaining": remaining,
                "_late": period >= 4 and (period > 4 or remaining <= LATE_SECONDS),
            })
        previous = margin

    late = [p for p in plays if p["_late"] and abs(p["home_margin"]) <= CLOSE_MARGIN]
    changes = [p for p in plays if p["_before"] * p["home_margin"] < 0]
    # The last BIG_PLAYS qualifying plays are the ones that decided it.
    chosen = sorted(late, key=lambda p: (p["qtr"], -p["_remaining"]))[-BIG_PLAYS:]
    if changes:
        swing = max(changes, key=lambda p: (p["points"], -p["_remaining"], p["qtr"]))
        if not any(swing is p for p in chosen):
            chosen.append(swing)
    change_ids = {id(p) for p in changes}
    return [
        {
            **{k: v for k, v in play.items() if not k.startswith("_")},
            "kind": "lead_change" if id(play) in change_ids else "late_score",
        }
        for play in sorted(chosen, key=lambda p: (p["qtr"], -p["_remaining"]))
    ]


def attach_percentiles(rows: list[dict[str, Any]], metrics: Iterable[tuple[str, bool]],
                       eligible=lambda row: True) -> None:
    """Replace each metric value with {"value", "pct"} ranked across ``rows``."""
    for key, higher in metrics:
        pool = [row[key] for row in rows if eligible(row) and row.get(key) is not None]
        series = pd.Series(pool, dtype=float)
        for row in rows:
            value = row.get(key)
            if value is None:
                row[key] = None
                continue
            pct = None
            if eligible(row) and len(series) > 1:
                below = float((series < value).sum()) if higher else float((series > value).sum())
                equal = float((series == value).sum())
                pct = max(1, min(100, int(math.floor((below + equal / 2) / len(series) * 100 + 0.5))))
            row[key] = {"value": value, "pct": pct}


def build_rows(
    frame: pd.DataFrame,
    team_box: pd.DataFrame,
    pbp: pl.DataFrame,
    season: int,
    now: datetime,
) -> list[dict[str, Any]]:
    """One game_details row per final game."""
    teams = team_rows(team_box, frame)
    players = player_rows(frame)
    attach_percentiles(teams, TEAM_METRICS)
    attach_percentiles(players, PLAYER_METRICS, eligible=lambda r: (r["min"] or 0) >= MIN_MINUTES)

    sides: dict[int, dict[str, dict[str, Any]]] = {}
    for row in teams:
        game = row.pop("_game")
        row.pop("_team")
        side = row.pop("_side")
        sides.setdefault(game, {})[side] = row
    roster: dict[int, list[dict[str, Any]]] = {}
    for row in players:
        roster.setdefault(row.pop("_game"), []).append(row)

    info = frame.groupby("game_id").first()
    stamp = now.isoformat()
    events = {
        key[0] if isinstance(key, tuple) else key: part
        for key, part in pbp.sort("game_id", "game_play_number").partition_by("game_id", as_dict=True).items()
    }
    rows: list[dict[str, Any]] = []
    for game_id, row in info.iterrows():
        if game_id not in sides or "home" not in sides[game_id] or "away" not in sides[game_id]:
            continue
        game_events = events.get(int(game_id))
        home = _team_code(game_events, "home") if game_events is not None else ""
        away = _team_code(game_events, "away") if game_events is not None else ""
        if not home or not away:
            home, away = _codes_from_frame(frame, int(game_id))
        abbreviations = _abbreviations(game_events) if game_events is not None else {}
        rows.append({
            "game_id": str(int(game_id)),
            "season": season,
            "season_type": row["season_type"],
            "week": game_week(row["game_date"], season),
            "away_team": away,
            "home_team": home,
            "team_stats": sides[game_id],
            "players": roster.get(int(game_id), []),
            "win_probability": margin_series(game_events) if game_events is not None else [],
            "big_plays": big_plays(game_events, abbreviations) if game_events is not None else [],
            "updated_at": stamp,
        })
    return rows


def _team_code(game: pl.DataFrame, side: str) -> str:
    return hoopr.normalize_team(game[f"{side}_team_abbrev"][0])


def _abbreviations(game: pl.DataFrame) -> dict[int, str]:
    return {
        int(game["home_team_id"][0]): hoopr.normalize_team(game["home_team_abbrev"][0]),
        int(game["away_team_id"][0]): hoopr.normalize_team(game["away_team_abbrev"][0]),
    }


def _codes_from_frame(frame: pd.DataFrame, game_id: int) -> tuple[str, str]:
    rows = frame[frame["game_id"] == game_id]
    home = rows.loc[rows["home"], "team"]
    away = rows.loc[~rows["home"], "team"]
    return (home.iloc[0] if len(home) else "", away.iloc[0] if len(away) else "")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true", help="Build rows and write JSON lines; touch no database.")
    parser.add_argument("--out", default=None, help="Directory for --dry-run output.")
    args = parser.parse_args()
    season = resolve_season(args.season)

    try:
        pbp = hoopr.read_asset("pbp", season)
        team_box = hoopr.read_asset("team_box", season).to_pandas()
    except hoopr.AssetUnavailable:
        logger.info("No play-by-play for %s yet", season)
        return 0
    built = playergames.build_player_games(season, zones=False, on_off=False)
    if built.frame.empty:
        logger.info("No box scores for %s yet", season)
        return 0
    rows = build_rows(built.frame, team_box, pbp, season, datetime.now(UTC))
    logger.info("Built %d game detail rows for %s", len(rows), season)

    if args.dry_run:
        if args.out:
            path = Path(args.out) / f"game_details_{season}.jsonl"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("\n".join(json.dumps(r, separators=(",", ":"), default=str) for r in rows) + "\n")
        return 0

    client = basketball_client()
    for start in range(0, len(rows), 50):
        client.table("game_details").upsert(rows[start:start + 50], on_conflict="game_id").execute()
    return 0


if __name__ == "__main__":
    sys.exit(main())
