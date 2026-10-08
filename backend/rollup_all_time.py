"""
Career ("All Time") rollup.

Writes one extra ``player_snapshots`` row per player under the sentinel season
``0``, aggregating every year from ``OLDEST_SUPPORTED_SEASON`` to the current
season into a single career line, with percentiles ranked inside the career
cohort rather than against any one season.

Why a stored row rather than an app-side mode: the leaderboards, Teams, Compare
and the player page all read from ``selectedSeason``, so modelling the career
view as just another season means every one of them gets it with no all-time
branch of its own, and the numbers are computed once here instead of on every
device. It also means the formatting, the qualification thresholds and the
percentile logic are literally the same code that produces a normal season,
which is the only way the two can't drift.

This deliberately re-reads the box-score feed rather than summing the season
snapshots already in Supabase. Snapshots hold *formatted* values ("61.2%") for
*qualified* players only, so summing them would compound rounding and silently
drop every season a player fell short of the cut: a career total that omits a
player's rookie year is worse than no career total. Seasons are summed
component by component (every share is a ratio of sums), never averaged.

Two honest limits, both consequences of the sources:

* Shot-zone metrics pool only the seasons the shots feed covers
  (``ZONES_FIRST_SEASON`` onward). Frequencies are shares of tracked attempts,
  so they stay consistent; they simply do not describe earlier years.
* Career On-Off is omitted. It needs a play-by-play replay of every season and
  only exists for the validated games of each season, which would make a career figure a patchwork
  over a whole career. On-Court +/- uses the games that have a box plus/minus.

Usage:
  python backend/rollup_all_time.py                 # 2003..current
  python backend/rollup_all_time.py --from 2010     # narrower window
  python backend/rollup_all_time.py --dry-run --out DIR   # build, write JSON

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (not needed for ``--dry-run``).
"""

import argparse
import logging
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import pandas as pd
from dotenv import load_dotenv

import playergames
from nbacodes import basketball_client
from ingest import (
    ALL_TIME_SEASON,
    OLDEST_SUPPORTED_SEASON,
    ZONES_FIRST_SEASON,
    BASE_COLUMNS,
    TERM_COLUMNS,
    _identity,
    build_snapshot_rows,
    chunks,
    derive_game_terms,
    metric_values,
    resolve_season,
    sum_games,
    write_json,
)

load_dotenv()

UTC = timezone.utc
logger = logging.getLogger(__name__)

Part = tuple[pd.DataFrame, pd.DataFrame]  # (summed components, identity) for one season


def season_part(frame: pd.DataFrame, season_type: str) -> Optional[Part]:
    """One season's per-player sums and identity for a phase (None when empty)."""
    phase = frame[frame["season_type"] == season_type]
    if phase.empty:
        return None
    return sum_games(derive_game_terms(phase)), _identity(phase)


def combine_parts(parts: list[Part]) -> pd.DataFrame:
    """Sum every season's components into one career row per player.

    ``parts`` is oldest first; a player's name, team and cohort come from the
    newest season he appears in. Components add, so every career rate is the
    ratio of career sums (a 20-game rookie year weighs 20 games, not one season).
    """
    if not parts:
        return pd.DataFrame()
    sums = pd.concat([p[0] for p in parts]).groupby(level=0).sum(min_count=1)
    for column in BASE_COLUMNS + TERM_COLUMNS + ["g", "gs"]:
        sums[column] = sums[column].fillna(0)
    identity = pd.concat([p[1] for p in parts])
    identity = identity[~identity.index.duplicated(keep="last")]
    agg = sums.join(identity)
    values = metric_values(agg)
    agg = agg.join(values.drop(columns=[c for c in values.columns if c in agg.columns]))
    # Career On-Off is deliberately never published (see module docstring).
    agg["on_off"] = float("nan")
    agg["image_url"] = [
        f"https://a.espncdn.com/i/headshots/nba/players/full/{int(pid)}.png" for pid in agg.index
    ]
    agg.index.name = "id"
    return agg


def build_career_parts(first: int, last: int, phases: tuple[str, ...]) -> dict[str, list[Part]]:
    """Per-season parts for each phase, one season at a time to bound memory."""
    parts: dict[str, list[Part]] = {phase: [] for phase in phases}
    for season in range(first, last + 1):
        try:
            built = playergames.build_player_games(
                season, zones=season >= ZONES_FIRST_SEASON, on_off=False,
            )
        except Exception:
            logger.exception("Failed to build %s; skipping it.", season)
            continue
        if built.frame.empty:
            logger.warning("No player games for %s.", season)
            continue
        logger.info("Loaded %s: %d player-games", season, len(built.frame))
        for phase in phases:
            part = season_part(built.frame, phase)
            if part is not None:
                parts[phase].append(part)
    return parts


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--from", dest="first", type=int, default=OLDEST_SUPPORTED_SEASON,
        help=f"Oldest season to include (default {OLDEST_SUPPORTED_SEASON}).",
    )
    parser.add_argument("--to", dest="last", type=int, default=None, help="Newest season to include.")
    parser.add_argument(
        "--season-type", choices=("REG", "POST", "all"), default="all",
        help="Phase(s) to roll up. Career playoffs are their own cohort.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Build rows without writing to a database.")
    parser.add_argument("--out", default=None, help="Directory for --dry-run JSON output.")
    args = parser.parse_args()

    last = args.last or resolve_season(None)
    first = max(args.first, OLDEST_SUPPORTED_SEASON)
    if first > last:
        logger.error("Empty range: %s..%s", first, last)
        sys.exit(1)

    now = datetime.now(UTC)
    phases = ("REG", "POST") if args.season_type == "all" else (args.season_type,)
    logger.info("=== Career rollup %s..%s (%s) ===", first, last, ", ".join(phases))

    client = None if args.dry_run else basketball_client()

    parts = build_career_parts(first, last, phases)
    for phase in phases:
        agg = combine_parts(parts[phase])
        if agg.empty:
            logger.warning("No career aggregate for %s.", phase)
            continue
        logger.info("Career aggregate for %s: %d players", phase, len(agg))
        rows = build_snapshot_rows(agg, ALL_TIME_SEASON, now, phase)
        if not rows:
            logger.warning("No career rows built for %s.", phase)
            continue
        logger.info("Built %d career %s rows.", len(rows), phase)

        if args.dry_run:
            if args.out:
                write_json(Path(args.out) / f"snapshots_{ALL_TIME_SEASON}_{phase}.json", rows)
            continue

        for i, batch in enumerate(chunks(rows, 150)):
            logger.info("Upserting career batch %d (%d rows) for %s...", i + 1, len(batch), phase)
            client.table("player_snapshots").upsert(batch, on_conflict="id,season,season_type").execute()

        # Prune players who no longer qualify for the career cohort, the same way
        # the per-season ingest does, so a threshold change can't leave orphans.
        kept = {row["id"] for row in rows}
        existing = (
            client.table("player_snapshots").select("id")
            .eq("season", ALL_TIME_SEASON).eq("season_type", phase).execute().data
        )
        orphans = [row["id"] for row in existing if row["id"] not in kept]
        for batch in chunks(orphans, 100):
            (
                client.table("player_snapshots").delete().in_("id", batch)
                .eq("season", ALL_TIME_SEASON).eq("season_type", phase).execute()
            )
        logger.info("Upserted %d, pruned %d career %s rows.", len(rows), len(orphans), phase)


if __name__ == "__main__":
    main()
