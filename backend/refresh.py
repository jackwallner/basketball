"""Build and atomically publish one current NBA season refresh.

The source probe creates a ``data_refresh_runs`` row before this command is
started.  This command downloads the current season once, computes snapshots,
per-game logs, and Recent Form in memory, stages all rows under that refresh
ID, validates coverage, and asks Postgres to publish the three sets together.
The serving tables are never modified directly by this path.

The current season is deliberately rebuilt in full.  A season of box scores,
shots and play-by-play is small, and a full read is the safest inexpensive way
to capture late corrections (a stat fixed a day later, a shot re-logged) while
the durable game identity remains date-compatible with the existing app schema.

``ngs_status`` and ``pfr_status`` are the football columns of the shared status
view; here ``ngs_status`` reports the shots feed (zone metrics) and
``pfr_status`` the play-by-play feed (On-Off and game pages).  ``--dry-run``
builds the candidate and writes it to disk without touching any database.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import pandas as pd
from dotenv import load_dotenv

import hoopr
from ingest import (
    DEFAULT_SEASON,
    aggregate_player_games,
    build_season_frame,
    build_snapshot_rows,
    resolve_season,
    season_scale,
)
from ingest_game_logs import build_game_log_rows
from nbacodes import basketball_client, game_week, is_nba_team, supabase_host_ok
from rollup_recent_form import _routable_logs, build_rows
from source_probe import probe_sources

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc
STAGE_TABLES = (
    "player_snapshots_refresh",
    "player_game_logs_refresh",
    "player_recent_form_refresh",
)


class CandidateNotReady(RuntimeError):
    """Raised when a source read cannot produce a safe serving revision."""


@dataclass(frozen=True)
class Coverage:
    max_week: int | None
    max_game_date: str | None
    expected_games: int
    observed_games: int
    coverage_status: str


@dataclass(frozen=True)
class Candidate:
    season: int
    season_types: tuple[str, ...]
    snapshots: tuple[dict[str, Any], ...]
    game_logs: tuple[dict[str, Any], ...]
    recent_form: tuple[dict[str, Any], ...]
    coverage: Coverage
    ngs_status: str  # the shots feed (zone metrics); the column name is the status view's
    pfr_status: str  # the play-by-play feed (On-Off, game pages)


def _source_status_rank(status: str) -> int:
    return {
        "unknown": 0,
        "not_applicable": 1,
        "ready": 2,
        "pending": 3,
        "degraded": 4,
    }.get(status, 0)


def _merge_status(*statuses: str) -> str:
    return max(statuses, key=_source_status_rank, default="unknown")


def _safe_date(value: Any) -> date | None:
    if value is None or pd.isna(value):
        return None
    try:
        return pd.to_datetime(value, errors="coerce").date()
    except (TypeError, ValueError, OverflowError):
        return None


def _coverage(frame: pd.DataFrame, schedule: pd.DataFrame, season: int, now: datetime) -> Coverage:
    """Measure source coverage while allowing a day to arrive game by game.

    Expected games are the schedule's completed regular-season and postseason
    games between two NBA clubs (preseason, play-in and All-Star games belong to
    neither phase); observed games are those present in the box scores.
    """
    if frame is None or frame.empty:
        return Coverage(None, None, 0, 0, "partial")

    dates: dict[str, date] = {}
    expected: set[str] = set()
    for row in schedule.to_dict("records") if schedule is not None else []:
        game_id = row.get("game_id")
        game_date = _safe_date(row.get("game_date"))
        if game_id is None or game_date is None or pd.isna(game_id):
            continue
        if int(row.get("season_type") or 0) not in hoopr.PHASE_BY_ESPN_TYPE:
            continue
        if not (is_nba_team(row.get("home_abbreviation")) and is_nba_team(row.get("away_abbreviation"))):
            continue
        key = str(int(game_id))
        dates[key] = game_date
        completed = row.get("status_type_completed")
        if completed is None or pd.isna(completed):
            completed = game_date < now.date()
        if bool(completed):
            expected.add(key)

    observed = {str(int(g)) for g in frame["game_id"].unique()}.intersection(dates)
    observed_dates = [dates[g] for g in observed]
    max_date = max(observed_dates) if observed_dates else None
    max_week = game_week(max_date, season) if max_date else None
    status = "complete" if len(expected) <= len(observed) else "partial"
    return Coverage(max_week, max_date.isoformat() if max_date else None, len(expected), len(observed), status)


def _validate_unique(rows: Iterable[dict[str, Any]], keys: tuple[str, ...], label: str) -> None:
    seen: set[tuple[Any, ...]] = set()
    for row in rows:
        key = tuple(row.get(column) for column in keys)
        if any(value is None or value == "" for value in key):
            raise CandidateNotReady(f"{label} has an incomplete key: {key}")
        if key in seen:
            raise CandidateNotReady(f"{label} has duplicate key: {key}")
        seen.add(key)


def build_candidate(season: int, *, now: datetime | None = None, loader=hoopr.read_asset) -> Candidate:
    """Build all output rows without touching Supabase."""
    now = (now or datetime.now(UTC)).astimezone(UTC)
    logger.info("Loading box scores, shots, play-by-play and schedule for %s", season)
    built = build_season_frame(season, loader=loader, strict=False)
    frame, diagnostics = built.frame, built.diagnostics
    if frame.empty:
        raise CandidateNotReady(f"player box scores are empty for {season}")
    try:
        schedule = loader("schedule", season).to_pandas()
    except hoopr.AssetUnavailable as error:
        raise CandidateNotReady(f"schedule is not published for {season}") from error
    coverage = _coverage(frame, schedule, season, now)
    logger.info(
        "Source coverage: games=%d/%d max_week=%s max_game_date=%s (%s)",
        coverage.observed_games, coverage.expected_games, coverage.max_week,
        coverage.max_game_date, coverage.coverage_status,
    )

    live = season == DEFAULT_SEASON
    snapshot_rows: list[dict[str, Any]] = []
    for phase in ("REG", "POST"):
        agg = aggregate_player_games(frame, phase)
        if agg.empty:
            logger.info("No %s snapshot source rows for %s", phase, season)
            continue
        scale = season_scale(diagnostics, phase, live)
        rows = build_snapshot_rows(agg, season, now, phase, qual_scale=scale, live=live)
        if rows:
            snapshot_rows.extend(rows)
    if not snapshot_rows:
        raise CandidateNotReady(f"no snapshot rows built for {season}")

    game_log_rows = build_game_log_rows(frame, season, now)
    if not game_log_rows:
        raise CandidateNotReady(f"no game-log rows built for {season}")
    if coverage.observed_games == 0 or not coverage.max_game_date:
        raise CandidateNotReady("Source games do not resolve to the current schedule")
    if any(row.get("season") != season for row in snapshot_rows + game_log_rows):
        raise CandidateNotReady("Candidate contains a different season")

    snapshot_keys = {(int(row["id"]), str(row.get("season_type") or "REG")) for row in snapshot_rows}
    recent_rows = _routable_logs(build_rows(game_log_rows, now), snapshot_keys)
    if not recent_rows:
        raise CandidateNotReady(f"no Recent Form rows resolve for {season}")

    season_types = tuple(sorted({str(row.get("season_type") or "REG") for row in snapshot_rows}))
    game_log_rows = [r for r in game_log_rows if str(r.get("season_type") or "REG") in season_types]
    recent_rows = [r for r in recent_rows if str(r.get("season_type") or "REG") in season_types]
    _validate_unique(snapshot_rows, ("id", "season", "season_type"), "snapshots")
    _validate_unique(
        game_log_rows, ("player_id", "season", "season_type", "game_date", "player_type"), "game logs",
    )
    _validate_unique(
        recent_rows, ("player_id", "season", "season_type", "player_type", "window_weeks"), "Recent Form",
    )
    return Candidate(
        season=season,
        season_types=season_types,
        snapshots=tuple(snapshot_rows),
        game_logs=tuple(game_log_rows),
        recent_form=tuple(recent_rows),
        coverage=coverage,
        ngs_status=_merge_status(diagnostics.get("shots_status", "unknown")),
        pfr_status=_merge_status(diagnostics.get("pbp_status", "unknown")),
    )


# Build-time stamps differ on every run even when no stat changed.
VOLATILE_ROW_KEYS = frozenset({"updated_at", "refresh_id", "source_published_at", "published_at"})


def content_hash(candidate: Candidate) -> str:
    """Hash the serving output, ignoring build timestamps.

    Two builds of identical box scores produce the same hash, so a source
    re-upload that changes no stat can be recorded without republishing.
    """
    digest = hashlib.sha256()
    for label, rows in (
        ("snapshots", candidate.snapshots),
        ("game_logs", candidate.game_logs),
        ("recent_form", candidate.recent_form),
    ):
        normalized = sorted(
            json.dumps(
                {k: v for k, v in row.items() if k not in VOLATILE_ROW_KEYS},
                sort_keys=True,
                separators=(",", ":"),
                default=str,
            )
            for row in rows
        )
        digest.update(label.encode())
        for line in normalized:
            digest.update(line.encode())
            digest.update(b"\n")
    return digest.hexdigest()


def _live_content_hash(client: Any) -> str | None:
    response = (
        client.table("data_refresh_state")
        .select("last_success_content_hash")
        .eq("singleton", True)
        .limit(1)
        .execute()
    )
    rows = getattr(response, "data", None) or []
    return rows[0].get("last_success_content_hash") if rows else None


def _client():
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
    if not supabase_host_ok(url):
        raise RuntimeError("Refusing to publish outside the Basketball Supabase project")
    return basketball_client(url, key)


def _response_data(response: Any) -> Any:
    payload = getattr(response, "data", response)
    if isinstance(payload, list) and len(payload) == 1:
        return payload[0]
    return payload


RPC_ATTEMPTS = 3
TRANSIENT_MARKERS = ("504", "502", "503", "Gateway Timeout", "Bad Gateway", "Service Unavailable", "timed out")


def _is_transient(error: Exception) -> bool:
    text = str(error)
    return any(marker in text for marker in TRANSIENT_MARKERS)


def _rpc(client: Any, function: str, params: dict[str, Any], *, sleep=time.sleep) -> Any:
    """Call a publisher RPC, retrying gateway blips.

    On 2026-09-14 a two-row ``mark_data_refresh_unchanged`` call hit a 5s
    Supabase gateway timeout and failed the whole refresh. The RPCs lock the
    run row, so a retry after a call that did commit is refused with "is
    already <status>"; that means the first attempt landed and counts as done.
    """
    for attempt in range(RPC_ATTEMPTS):
        try:
            response = client.rpc(function, params).execute()
            return _response_data(response)
        except Exception as error:  # noqa: BLE001 - classify, then re-raise
            if attempt > 0 and "is already" in str(error):
                logger.info("%s already applied by an earlier attempt", function)
                return {"status": "already_applied"}
            if attempt + 1 >= RPC_ATTEMPTS or not _is_transient(error):
                raise
            logger.warning("%s transient failure (%s); retrying", function, str(error)[:120])
            sleep(2 + attempt * 4)
    raise RuntimeError("unreachable")


def _stage_rows(client: Any, table: str, refresh_id: str, rows: Iterable[dict[str, Any]]) -> int:
    values = [{"refresh_id": refresh_id, **row} for row in rows]
    if not values:
        return 0
    # Clear a previous attempt's payload before retrying the same refresh ID.
    client.table(table).delete().eq("refresh_id", refresh_id).execute()
    for offset in range(0, len(values), 250):
        client.table(table).insert(values[offset : offset + 250]).execute()
    return len(values)


def _run_metadata(client: Any, refresh_id: str) -> dict[str, Any]:
    response = (
        client.table("data_refresh_runs")
        .select("refresh_id,season,source_fingerprint,source_published_at,status")
        .eq("refresh_id", refresh_id)
        .limit(1)
        .execute()
    )
    rows = getattr(response, "data", None) or []
    if not rows:
        raise RuntimeError(f"refresh run {refresh_id} does not exist")
    return rows[0]


def publish(refresh_id: str, *, season: int | None = None, now: datetime | None = None) -> dict[str, Any]:
    """Build, stage, validate, and atomically publish a refresh."""
    client = _client()
    metadata = _run_metadata(client, refresh_id)
    target_season = int(season if season is not None else metadata["season"])
    if metadata.get("status") not in ("building", "validated"):
        raise RuntimeError(f"refresh run {refresh_id} is {metadata.get('status')}")
    try:
        source_before = probe_sources(target_season)
        if not source_before.ready or source_before.fingerprint != metadata["source_fingerprint"]:
            raise CandidateNotReady("Source generation changed after the probe; retry the new generation")
        candidate = build_candidate(target_season, now=now)
        source_after = probe_sources(target_season)
        if not source_after.ready or source_after.fingerprint != source_before.fingerprint:
            raise CandidateNotReady("Source changed during the build; keeping the live revision")
        output_hash = content_hash(candidate)
        if output_hash == _live_content_hash(client):
            result = _rpc(
                client,
                "mark_data_refresh_unchanged",
                {"p_refresh_id": refresh_id, "p_content_hash": output_hash},
            )
            logger.info("Source re-upload changed no stats; live revision kept: %s", result)
            return result
        snapshot_count = _stage_rows(client, STAGE_TABLES[0], refresh_id, candidate.snapshots)
        log_count = _stage_rows(client, STAGE_TABLES[1], refresh_id, candidate.game_logs)
        recent_count = _stage_rows(client, STAGE_TABLES[2], refresh_id, candidate.recent_form)
        _rpc(
            client,
            "update_data_refresh_build",
            {
                "p_refresh_id": refresh_id,
                "p_season_types": list(candidate.season_types),
                "p_max_week": candidate.coverage.max_week,
                "p_max_game_date": candidate.coverage.max_game_date,
                "p_expected_games": candidate.coverage.expected_games,
                "p_observed_games": candidate.coverage.observed_games,
                "p_snapshot_rows": snapshot_count,
                "p_game_log_rows": log_count,
                "p_recent_form_rows": recent_count,
                "p_ngs_status": candidate.ngs_status,
                "p_pfr_status": candidate.pfr_status,
            },
        )
        client.table("data_refresh_runs").update({"content_hash": output_hash}).eq(
            "refresh_id", refresh_id
        ).execute()
        result = _rpc(client, "publish_data_refresh", {"p_refresh_id": refresh_id})
        if not isinstance(result, dict) or result.get("status") not in ("published", "degraded"):
            raise RuntimeError(f"atomic publish rejected refresh {refresh_id}: {result}")
        logger.info("Published refresh %s: %s", refresh_id, result)
        return result
    except Exception as exc:
        detail = str(exc).strip()[:4000] or type(exc).__name__
        logger.exception("Refresh %s failed; serving data remains unchanged", refresh_id)
        try:
            _rpc(
                client,
                "fail_data_refresh",
                {
                    "p_refresh_id": refresh_id,
                    "p_error_code": type(exc).__name__,
                    "p_error_detail": detail,
                },
            )
        except Exception:
            logger.exception("Could not persist failed refresh status")
        raise


def write_candidate(candidate: Candidate, out: str) -> None:
    """Write a candidate to disk (``--dry-run``): the three row sets and a summary."""
    folder = Path(out)
    folder.mkdir(parents=True, exist_ok=True)
    season = candidate.season
    (folder / f"snapshots_{season}.json").write_text(
        json.dumps(list(candidate.snapshots), separators=(",", ":"), default=str)
    )
    for name, rows in (("game_logs", candidate.game_logs), ("recent_form", candidate.recent_form)):
        (folder / f"{name}_{season}.jsonl").write_text(
            "\n".join(json.dumps(r, separators=(",", ":"), default=str) for r in rows) + "\n"
        )
    summary = {
        "season": season,
        "season_types": list(candidate.season_types),
        "snapshots": len(candidate.snapshots),
        "game_logs": len(candidate.game_logs),
        "recent_form": len(candidate.recent_form),
        "coverage": candidate.coverage.__dict__,
        "shots_status": candidate.ngs_status,
        "pbp_status": candidate.pfr_status,
        "content_hash": content_hash(candidate),
    }
    (folder / f"summary_{season}.json").write_text(json.dumps(summary, indent=2))
    logger.info("Wrote candidate for %s to %s: %s", season, folder, summary)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh-id", default=None)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true", help="Build the candidate and write it to --out.")
    parser.add_argument("--out", default=None, help="Directory for --dry-run output.")
    args = parser.parse_args()
    if not args.dry_run and not args.refresh_id:
        parser.error("--refresh-id is required unless --dry-run")
    return args


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)   # one INFO line per PostgREST call drowns the log
    args = _parse_args()
    if args.dry_run:
        try:
            candidate = build_candidate(resolve_season(args.season))
        except CandidateNotReady as error:
            # The normal state between the October rollover and opening night.
            logger.warning("Nothing to publish for this season yet: %s", error)
            return 0
        if args.out:
            write_candidate(candidate, args.out)
        return 0
    publish(args.refresh_id, season=args.season)
    return 0


if __name__ == "__main__":
    sys.exit(main())
