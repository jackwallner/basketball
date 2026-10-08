"""
Per-player-per-game NBA ingest. Powers player profiles and the shared 1/2/4
week Trends windows.

Reads the per-player-game table (``playergames.py``: hoopR box scores joined to
team totals, shot-zone counts and the play-by-play On-Off replay) and upserts
one row per player per game into Supabase ``public.player_game_logs``. Regular
season and postseason rows are stored separately.

Metrics are stored as raw counts and the team context needed to turn them into
any rate, never pre-divided: minutes, field goals, the team's possessions and
rebounds while the player was on the floor, and so on. That is what lets
``rollup_recent_form.py`` recompute an exact window rate from summed numerators
and denominators instead of averaging already-averaged numbers (the same reason
the baseball and football game logs store counts).

Shot-zone counts are present only for games the shots feed covers, and the three
On-Off components (``on_margin``, ``off_margin``, ``off_poss``) only for
player-games where the play-by-play replay reproduced the box plus/minus; they
are ``null`` otherwise, never zero. ``plus_minus`` is ``null`` before 2009.

``week`` is the number of the week since the season's fixed epoch (the Monday on
or before October 1 of the season's first calendar year), so it is stable
between incremental runs and keeps counting through the postseason. Recent
Form's 1/2/4 week windows are windows on this number.

Incremental by default: starts from the latest game_date already in the DB for
the season. Pass ``--full`` to re-ingest the whole season (also needed after a
metric-set change, since incremental only reaches new games). ``--season N``
overrides the resolved season. ``--dry-run --out DIR`` writes JSON lines instead
of touching a database.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py).
"""

import argparse
import json
import logging
import math
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import pandas as pd
from dotenv import load_dotenv

import ingest
from ingest import resolve_season
from nbacodes import basketball_client, game_week

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Counts and context copied into ``metrics`` under the same names, in the order
# the contract lists them.
CONTEXT_KEYS = [
    "min", "pts", "fgm", "fga", "fg3m", "fg3a", "ftm", "fta", "oreb", "dreb", "reb",
    "ast", "stl", "blk", "tov", "pf",
]
TEAM_KEYS = [
    "team_poss", "player_poss", "tm_min", "tm_fgm", "tm_fga", "tm_fta", "tm_tov",
    "tm_oreb", "tm_dreb", "tm_reb", "opp_poss", "opp_fga", "opp_fg3a", "opp_oreb",
    "opp_dreb", "opp_reb",
]
ZONE_KEYS = [
    "rim_fga", "rim_fgm", "smid_fga", "smid_fgm", "lmid_fga", "lmid_fgm",
    "c3_fga", "c3_fgm", "nc3_fga", "nc3_fgm", "ast_fgm",
]
ON_OFF_KEYS = ["on_margin", "off_margin", "off_poss"]
FLOAT_PLACES = 3


def _clean(value: Any) -> Optional[float | int]:
    """JSON number, integer when whole, ``None`` for missing."""
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return None
    number = float(value)
    if number == int(number):
        return int(number)
    return round(number, FLOAT_PLACES)


def game_metrics(row: Any) -> dict[str, Any]:
    """The flat per-game metrics dict for one player-game row."""
    metrics: dict[str, Any] = {}
    for key in CONTEXT_KEYS:
        metrics[key] = _clean(getattr(row, key))
    metrics["plus_minus"] = _clean(row.plus_minus)
    metrics["starter"] = 1 if row.starter else 0
    for key in TEAM_KEYS:
        metrics[key] = _clean(getattr(row, key))
    for key in ZONE_KEYS:
        value = _clean(getattr(row, key))
        if value is not None:
            metrics[key] = value
    for key in ON_OFF_KEYS:
        metrics[key] = _clean(getattr(row, key))
    return metrics


def build_game_log_rows(frame: pd.DataFrame, season: int, now: datetime) -> list[dict]:
    """Build one player_game_logs row per player per game (pure)."""
    if frame.empty:
        return []
    now_str = now.isoformat()
    cohorts = {
        phase: ingest._identity(rows)["player_type"]
        for phase, rows in frame.groupby("season_type")
    }
    rows: list[dict] = []
    for row in frame.itertuples(index=False):
        player_type = cohorts[row.season_type].get(row.athlete_id, "unknown")
        plays = int(round(row.fga + ingest.FT_WEIGHT * row.fta + row.tov))
        rows.append({
            "player_id": int(row.athlete_id),
            "season": season,
            "season_type": row.season_type,
            # The upstream game identity rides alongside the date: the legacy
            # primary key is date based, and the refresh publisher uses this to
            # prove a new source generation did not drop a game already live.
            "game_id": str(row.game_id),
            "game_date": row.game_date,
            "player_type": player_type,
            "team": row.team,
            "opponent": row.opp,
            "week": game_week(row.game_date, season),
            "plays": plays,
            "touches": int(round(row.min)),
            "metrics": game_metrics(row),
            "updated_at": now_str,
        })
    return rows


def _latest_game_date(client, season: int) -> Optional[str]:
    resp = (
        client.table("player_game_logs")
        .select("game_date")
        .eq("season", season)
        .order("game_date", desc=True)
        .limit(1)
        .execute()
    )
    if not resp.data:
        return None
    return str(resp.data[0]["game_date"])[:10]


def _upsert(client, rows: list[dict]) -> None:
    batch_size = 200
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        try:
            client.table("player_game_logs").upsert(
                batch,
                on_conflict="player_id,season,season_type,game_date,player_type",
            ).execute()
        except Exception:
            logger.exception("Upsert failed for batch starting at %d", i)
            raise


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as handle:
        for row in rows:
            handle.write(json.dumps(row, separators=(",", ":"), default=str) + "\n")


def run(
    full: bool = False,
    cli_season: Optional[int] = None,
    dry_run: bool = False,
    out: Optional[str] = None,
) -> None:
    season = resolve_season(cli_season)
    now = datetime.now(UTC)
    client = None if dry_run else basketball_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    logger.info("Building the player-game table for %s...", season)
    built = ingest.build_season_frame(season)
    rows = build_game_log_rows(built.frame, season, now)
    logger.info("Built %d game-log rows for %s", len(rows), season)

    if dry_run:
        if out:
            write_jsonl(Path(out) / f"game_logs_{season}.jsonl", rows)
        return

    if not full:
        latest = _latest_game_date(client, season)
        if latest:
            # Re-ingest the latest known day too (late/updated games).
            before = len(rows)
            rows = [r for r in rows if r["game_date"] >= latest]
            logger.info("Incremental: keeping %d/%d rows on/after %s", len(rows), before, latest)

    if not rows:
        logger.info("Nothing to ingest for %s.", season)
        return

    _upsert(client, rows)
    if full:
        response = (
            client.table("player_game_logs").delete()
            .eq("season", season).lt("updated_at", now.isoformat()).execute()
        )
        logger.info("Pruned %d stale game-log rows for %s.", len(response.data or []), season)
    logger.info("Done. Upserted %d game-log rows for %s.", len(rows), season)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="Re-ingest the whole season, not incremental.")
    parser.add_argument("--season", type=int, default=None, help="hoopR season (the year it ends) to ingest.")
    parser.add_argument("--dry-run", action="store_true", help="Build rows and write JSON lines; touch no database.")
    parser.add_argument("--out", default=None, help="Directory for --dry-run output.")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    args = _parse_args()
    run(full=args.full, cli_season=args.season, dry_run=args.dry_run, out=args.out)
