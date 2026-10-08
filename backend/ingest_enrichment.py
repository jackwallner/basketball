"""
Context the stat snapshots do not carry: who a player is, plus team power
ratings and a projected margin for every game still to be played.

Writes three tables, none of which the snapshot screens depend on, so this job
can fail, lag or be rerun without touching the published snapshots:

* ``player_profiles``: bio from hoopR ``player_core`` (height, weight, birth
  date, jersey, experience, draft class, round and overall pick), with ``rosters``
  as a fallback. One row per player per season. ``draft_team`` stays null: hoopR's
  ``draft`` files are sparse (a handful of classes) and their athlete ids do not
  match ESPN's player ids, so there is nothing to join.
  The contract, snap-count and injury columns the football pipeline filled have
  no public hoopR source and stay null (the app hides null lines).
* ``team_ratings``: schedule-adjusted net rating with an offense/defense split,
  see ``team_ratings.py``.
* ``game_projections``: projected home margin and win probability for each
  unplayed game this season.

Every source is optional: a missing or late table leaves its columns null for
this run rather than failing the others.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (not needed for ``--dry-run``).
"""

from __future__ import annotations

import argparse
import json
import logging
import math
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Optional

import pandas as pd
from dotenv import load_dotenv

import hoopr
import playergames
import team_ratings as tr
from ingest_game_logs import game_week
from ingest import resolve_season
from nbacodes import basketball_client

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc
BATCH = 500
# PostgREST rejects a bulk upsert whose objects carry different keys, so every
# profile row carries every optional column, null when its source had nothing.
PROFILE_OPTIONAL_COLUMNS = [
    "contract_apy", "contract_cap_pct", "contract_years", "contract_year_signed",
    "contract_value", "contract_guaranteed",
    "snap_games", "team_games", "off_snaps", "def_snaps", "st_snaps",
    "off_snap_pct", "def_snap_pct",
    "injury_week", "injury_status", "injury", "practice_status",
]


def _num(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(number) or math.isinf(number) else number


def _int(value: Any) -> Optional[int]:
    number = _num(value)
    return None if number is None else int(round(number))


def _text(value: Any) -> Optional[str]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    text = str(value).strip()
    return text or None


def _date(value: Any) -> Optional[str]:
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    if isinstance(value, (datetime, date)):
        return value.isoformat()[:10]
    text = str(value).strip()
    return text[:10] if len(text) >= 10 else None


def parse_height_inches(value: Any) -> Optional[int]:
    """Inches from a number (81.0) or ESPN's display form (6' 9\")."""
    number = _num(value)
    if number is not None:
        return int(round(number))
    text = _text(value)
    if not text or "'" not in text:
        return None
    feet, _, inches = text.partition("'")
    try:
        return int(feet.strip()) * 12 + int(inches.replace('"', "").strip() or 0)
    except ValueError:
        return None


def parse_weight_pounds(value: Any) -> Optional[int]:
    """Pounds from a number (250.0) or ESPN's display form ("250 lbs")."""
    number = _num(value)
    if number is not None:
        return int(round(number))
    text = _text(value)
    if not text:
        return None
    digits = "".join(ch for ch in text.split()[0] if ch.isdigit())
    return int(digits) if digits else None


# --------------------------------------------------------------------------- #
# Player profiles
# --------------------------------------------------------------------------- #
def team_codes(frame: pd.DataFrame) -> dict[int, str]:
    """ESPN team id -> app team code, from the games already loaded."""
    pairs = frame[["team_id", "team"]].drop_duplicates()
    return {int(t): c for t, c in zip(pairs["team_id"], pairs["team"])}


def build_player_profiles(
    season: int,
    player_ids: set[int],
    player_core: pd.DataFrame,
    rosters: pd.DataFrame,
    drafts: pd.DataFrame,
    codes: dict[int, str],
    now: datetime,
) -> list[dict[str, Any]]:
    """One row per player the app ships for ``season``."""
    core = {int(r.athlete_id): r for r in player_core.itertuples(index=False)} if not player_core.empty else {}
    roster = {int(r.athlete_id): r for r in rosters.itertuples(index=False)} if not rosters.empty else {}
    picks = {int(r.athlete_id): r for r in drafts.itertuples(index=False)} if not drafts.empty else {}
    stamp = now.isoformat()

    rows: list[dict[str, Any]] = []
    for pid in sorted(player_ids):
        info, fallback, pick = core.get(pid), roster.get(pid), picks.get(pid)
        experience = _int(getattr(info, "experience_years", None)) if info else None
        if experience is None and fallback:
            experience = _int(getattr(fallback, "experience_years", None))
        draft_team_id = _int(getattr(pick, "team_id", None)) if pick else None
        row: dict[str, Any] = {
            "player_id": pid,
            "season": season,
            "jersey": _int(getattr(info, "jersey", None)) if info else None,
            "birth_date": _date(getattr(info, "date_of_birth", None)) if info else None,
            "height_in": parse_height_inches(getattr(info, "height", None)) if info else None,
            "weight_lb": parse_weight_pounds(getattr(info, "weight", None)) if info else None,
            "college": None,
            "years_exp": experience,
            # hoopR seasons are named for the year they end, and ESPN's
            # experience counts the current season as a year.
            "rookie_season": season - experience + 1 if experience else None,
            "draft_year": _int(getattr(info, "draft_year", None)) if info else None,
            "draft_round": _int(getattr(info, "draft_round", None)) if info else None,
            "draft_pick": _int(getattr(info, "draft_selection", None)) if info else None,
            "draft_team": codes.get(draft_team_id) if draft_team_id is not None else None,
            "updated_at": stamp,
        }
        if fallback:
            row["jersey"] = row["jersey"] if row["jersey"] is not None else _int(getattr(fallback, "jersey", None))
            row["birth_date"] = row["birth_date"] or _date(getattr(fallback, "date_of_birth", None))
            row["height_in"] = row["height_in"] or parse_height_inches(getattr(fallback, "height", None))
            row["weight_lb"] = row["weight_lb"] or parse_weight_pounds(getattr(fallback, "weight", None))
        row.update(dict.fromkeys(PROFILE_OPTIONAL_COLUMNS))
        rows.append(row)
    return rows


# --------------------------------------------------------------------------- #
# Team ratings and projections
# --------------------------------------------------------------------------- #
def team_game_table(frame: pd.DataFrame) -> pd.DataFrame:
    """One row per club per regular-season game from the player-game table."""
    if frame.empty:
        return pd.DataFrame()      # a season whose box scores are not out yet
    reg = frame[frame["season_type"] == "REG"]
    if reg.empty:
        return pd.DataFrame()
    teams = reg.groupby(["game_id", "team_id"]).first().reset_index()
    return teams.rename(columns={
        "tm_score": "points_for", "opp_score": "points_against", "team_poss": "poss",
    })[["game_id", "game_date", "team", "opp", "home", "points_for", "points_against", "poss", "opp_poss"]]


def build_team_ratings(
    season: int,
    games: pd.DataFrame,
    prior_games: pd.DataFrame,
    schedule: pd.DataFrame,
    now: datetime,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    prior_rows = tr.team_game_rows(prior_games)
    prior = tr.rate(prior_rows, full_schedule_weight=True) if not prior_rows.empty else {}
    rows = tr.team_game_rows(games)
    ratings = tr.rate(rows, prior=prior) if not rows.empty else {}
    through_week = int(max(game_week(d, season) for d in rows["game_date"])) if not rows.empty else 0
    if prior:
        # Clubs yet to play start from last season.
        for team, start in tr.preseason(prior).items():
            ratings.setdefault(team, start)

    stamp = now.isoformat()
    ordered = sorted(ratings.values(), key=lambda r: r.rating, reverse=True)
    team_rows = [
        {
            "season": season, "team": r.team, "rank": index + 1, "games": r.games,
            "through_week": through_week,
            "rating": round(r.rating, 2), "offense": round(r.offense, 2),
            "defense": round(r.defense, 2), "schedule": round(r.schedule, 2),
            "prior_weight": round(r.prior_weight, 3),
            "wins": r.wins, "losses": r.losses, "ties": r.ties,
            "points_for": int(r.points_for), "points_against": int(r.points_against),
            "updated_at": stamp,
        }
        for index, r in enumerate(ordered)
    ]
    return team_rows, build_projections(season, schedule, ratings, stamp, now.date())


def build_projections(
    season: int, schedule: pd.DataFrame, ratings: dict[str, tr.TeamRating], stamp: str,
    today: Optional[date] = None,
) -> list[dict[str, Any]]:
    """Projected margin and win probability for every game still to be played.

    A game dated before ``today`` that never finished (postponed and not
    replayed, or a placeholder) is not upcoming and is skipped.
    """
    if schedule is None or schedule.empty:
        return []
    upcoming = schedule[
        ~schedule["status_type_completed"].fillna(False).astype(bool)
        & schedule["season_type"].isin(hoopr.PHASE_BY_ESPN_TYPE)
    ]
    projections: list[dict[str, Any]] = []
    for game in upcoming.itertuples(index=False):
        if today is not None and pd.Timestamp(game.game_date).date() < today:
            continue
        home_code = hoopr.normalize_team(game.home_abbreviation)
        away_code = hoopr.normalize_team(game.away_abbreviation)
        home, away = ratings.get(home_code), ratings.get(away_code)
        if home is None or away is None:
            continue
        margin, win = tr.project(home, away, neutral=bool(game.neutral_site))
        projections.append({
            "game_id": str(int(game.game_id)),
            "season": season,
            "week": game_week(str(game.game_date), season),
            "home_team": home_code,
            "away_team": away_code,
            "home_margin": round(margin, 1),
            "home_win_prob": round(win, 3),
            "updated_at": stamp,
        })
    return projections


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def _load(name: str, season: int) -> pd.DataFrame:
    try:
        frame = hoopr.read_asset(name, season).to_pandas()
        logger.info("Loaded %s %s: %d rows", name, season, len(frame))
        return frame
    except hoopr.AssetUnavailable:
        logger.info("hoopR has no %s file for %s", name, season)
        return pd.DataFrame()
    except Exception as error:  # noqa: BLE001 - one late source must not sink the rest
        logger.warning("Skipping %s %s: %s", name, season, error)
        return pd.DataFrame()


def _live_player_ids(client: Any, season: int) -> set[int]:
    ids: set[int] = set()
    offset = 0
    while True:
        page = (
            client.table("player_snapshots").select("id").eq("season", season)
            .range(offset, offset + 999).execute().data
        )
        ids.update(int(row["id"]) for row in page)
        if len(page) < 1000:
            return ids
        offset += 1000


def _upsert(client: Any, table: str, rows: list[dict[str, Any]], conflict: str) -> None:
    for start in range(0, len(rows), BATCH):
        client.table(table).upsert(rows[start:start + BATCH], on_conflict=conflict).execute()
    logger.info("Upserted %d %s rows", len(rows), table)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true", help="Build rows and write JSON lines; touch no database.")
    parser.add_argument("--out", default=None, help="Directory for --dry-run output.")
    args = parser.parse_args()
    season = resolve_season(args.season)
    now = datetime.now(UTC)

    client = None if args.dry_run else basketball_client()

    built = playergames.build_player_games(season, zones=False, on_off=False)
    prior_built = playergames.build_player_games(season - 1, zones=False, on_off=False)
    schedule = _load("schedule", season)
    team_rows, projections = build_team_ratings(
        season, team_game_table(built.frame), team_game_table(prior_built.frame), schedule, now,
    )
    logger.info("Built %d team ratings, %d projections", len(team_rows), len(projections))

    player_core = _load("player_core", season)
    rosters = _load("rosters", season)
    player_ids = _live_player_ids(client, season) if client else set()
    if not player_ids and args.dry_run and not built.frame.empty:
        # Dry run: every player who appeared, so the build is exercised end to end.
        player_ids = {int(p) for p in built.frame["athlete_id"].unique()}
    codes = team_codes(built.frame) if not built.frame.empty else {}
    profiles = build_player_profiles(
        season, player_ids, player_core, rosters, pd.DataFrame(), codes, now,
    )
    logger.info("Built %d player profiles", len(profiles))

    if client is None:
        if args.out:
            out = Path(args.out)
            out.mkdir(parents=True, exist_ok=True)
            for name, rows in (("team_ratings", team_rows), ("game_projections", projections), ("player_profiles", profiles)):
                (out / f"{name}_{season}.jsonl").write_text(
                    "\n".join(json.dumps(r, separators=(",", ":"), default=str) for r in rows) + "\n"
                )
        return 0
    if team_rows:
        _upsert(client, "team_ratings", team_rows, "season,team")
    if projections:
        _upsert(client, "game_projections", projections, "game_id")
    if profiles:
        _upsert(client, "player_profiles", profiles, "player_id,season")
    return 0


if __name__ == "__main__":
    sys.exit(main())
