"""
Team power ratings: schedule-adjusted net rating, split into offense and defense.

"What you do minus what you allow, adjusted for who you played", in points per
100 possessions: the Simple Rating System applied to offensive and defensive
rating separately.

* Offense: a club's points per 100 possessions in each game, relative to the
  league average, credited for the quality of the defenses it faced.
* Defense: the league average minus the points per 100 possessions the club
  allowed (positive is good), credited for the offenses it faced.
* Rating is offense plus defense, the schedule-adjusted net rating.

The schedule adjustment is iterated to a fixed point with the league re-centred
on zero each pass, and phased in over a club's first ``FULL_SOS_GAMES`` games
(the same early-season caution the football ratings use: three games say little
about who anyone played).

Early in a season the rating is shrunk 20% and blended with last season's final
rating (itself regressed halfway to average) as if last season were worth
``PRIOR_GAMES`` games, so a club with ten games played is about two thirds this
season. That blend is the football pipeline's, with the prior stretched to a
longer schedule.

Ratings are per 100 possessions, which at today's pace is within a percent of
points per game, so ``rating diff + home court`` reads as a point spread. Home
court is worth about 2.5 points and the margin around a spread has a standard
deviation of about 12.

Pure functions; no network. ``ingest_enrichment.py`` feeds them.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

import pandas as pd

HOME_COURT = 2.5
# Standard deviation of NBA final margins around the spread, for turning a
# projected margin into a win probability.
MARGIN_SIGMA = 12.0
FULL_SOS_GAMES = 20
# Last season counts as this many games of evidence about this one.
PRIOR_GAMES = 20.0
# Last season's rating is regressed toward average before it anchors this one:
# rosters turn over, and a +9 team rarely starts the next year at +9.
PRIOR_REGRESSION = 0.5
# This season's descriptive rating overstates what it predicts.
CURRENT_SHRINK = 0.8
SOS_ITERATIONS = 60


@dataclass
class TeamRating:
    team: str
    games: int
    rating: float
    offense: float
    defense: float
    schedule: float
    prior_weight: float
    points_for: float
    points_against: float
    wins: int
    losses: int
    ties: int


def team_game_rows(team_box: pd.DataFrame) -> pd.DataFrame:
    """One row per club per completed regular-season game.

    ``team_box`` is the cleaned team-game table with ``game_id``, ``game_date``,
    ``team``, ``opp``, ``home``, ``points_for``, ``points_against``, ``poss`` and
    ``opp_poss``. Possessions are the box-score estimate, so offensive and
    defensive rating are exact for the points and possessions the box reports.
    """
    if team_box is None or team_box.empty:
        return pd.DataFrame()
    rows = team_box.copy()
    rows["off_rtg"] = 100 * rows["points_for"] / rows["poss"]
    rows["def_rtg"] = 100 * rows["points_against"] / rows["opp_poss"]
    return rows.sort_values(["game_date", "game_id"]).reset_index(drop=True)


def sos_weight(games: int) -> float:
    """Zero before the first game, full from ``FULL_SOS_GAMES``: early schedules say little."""
    return max(0.0, min(1.0, games / FULL_SOS_GAMES))


def prior_weight(games: int) -> float:
    """Last season's share of the rating: all of it before a game, a third after ten."""
    return PRIOR_GAMES / (max(games, 0) + PRIOR_GAMES)


def rate(
    rows: pd.DataFrame,
    through_game: Optional[int] = None,
    prior: Optional[dict[str, TeamRating]] = None,
    full_schedule_weight: bool = False,
) -> dict[str, TeamRating]:
    """Ratings from every game up to the ``through_game``-th of each club."""
    if rows.empty:
        return {}
    data = rows
    if through_game is not None:
        data = rows[rows.groupby("team").cumcount() < through_game]
    if data.empty:
        return {}

    league_off = float(data["off_rtg"].mean())
    league_def = float(data["def_rtg"].mean())
    raw_off: dict[str, float] = {}
    raw_def: dict[str, float] = {}
    games: dict[str, int] = {}
    opponents: dict[str, list[str]] = {}
    summary: dict[str, dict[str, float]] = {}
    for team, g in data.groupby("team"):
        raw_off[team] = float(g["off_rtg"].mean()) - league_off
        raw_def[team] = league_def - float(g["def_rtg"].mean())
        games[team] = int(len(g))
        opponents[team] = list(g["opp"])
        margin = g["points_for"] - g["points_against"]
        summary[team] = {
            "pf": float(g["points_for"].sum()), "pa": float(g["points_against"].sum()),
            "w": int((margin > 0).sum()), "l": int((margin < 0).sum()), "t": int((margin == 0).sum()),
        }

    typical = int(round(sum(games.values()) / len(games)))
    weight = 1.0 if full_schedule_weight else sos_weight(typical)
    off = dict(raw_off)
    dfn = dict(raw_def)
    for _ in range(SOS_ITERATIONS):
        next_off = {t: raw_off[t] + weight * _mean([dfn.get(o, 0.0) for o in opponents[t]]) for t in raw_off}
        next_def = {t: raw_def[t] + weight * _mean([off.get(o, 0.0) for o in opponents[t]]) for t in raw_def}
        # Keep the league centred on zero so the numbers stay a point spread.
        off = _centre(next_off)
        dfn = _centre(next_def)

    out: dict[str, TeamRating] = {}
    for team in raw_off:
        base = prior.get(team) if prior else None
        # With no prior (last season's own final rating), the rating is the
        # plain descriptive one.
        pw = prior_weight(games[team]) if base else 0.0
        shrink = CURRENT_SHRINK if base else 1.0
        prior_off = base.offense * PRIOR_REGRESSION if base else 0.0
        prior_def = base.defense * PRIOR_REGRESSION if base else 0.0
        blended_off = (1 - pw) * shrink * off[team] + pw * prior_off
        blended_def = (1 - pw) * shrink * dfn[team] + pw * prior_def
        schedule = (off[team] - raw_off[team]) + (dfn[team] - raw_def[team])
        s = summary[team]
        out[team] = TeamRating(
            team=team, games=games[team], rating=blended_off + blended_def,
            offense=blended_off, defense=blended_def, schedule=schedule, prior_weight=pw,
            points_for=s["pf"], points_against=s["pa"], wins=s["w"], losses=s["l"], ties=s["t"],
        )
    return out


def preseason(prior: dict[str, TeamRating]) -> dict[str, TeamRating]:
    """Before a game: last season, regressed."""
    return {
        team: TeamRating(
            team=team, games=0,
            rating=(r.offense + r.defense) * PRIOR_REGRESSION,
            offense=r.offense * PRIOR_REGRESSION,
            defense=r.defense * PRIOR_REGRESSION,
            schedule=0.0, prior_weight=1.0,
            points_for=0.0, points_against=0.0, wins=0, losses=0, ties=0,
        )
        for team, r in prior.items()
    }


def project(home: TeamRating, away: TeamRating, neutral: bool = False) -> tuple[float, float]:
    """(home margin, home win probability)."""
    margin = home.rating - away.rating + (0.0 if neutral else HOME_COURT)
    win = 0.5 * (1 + math.erf(margin / (MARGIN_SIGMA * math.sqrt(2))))
    return margin, win


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _centre(values: dict[str, float]) -> dict[str, float]:
    mean = _mean(list(values.values()))
    return {k: v - mean for k, v in values.items()}
