"""Pre-aggregate per-game logs into rolling last-N-weeks windows.

Reads public.player_game_logs and writes public.player_recent_form: one row
per (player, phase, window length), holding the shared league window ending on
the latest available week, the equal-length window before it, and the delta
between them: the THEN / NOW / delta shape ported from the baseball app's
Baseball Savant-style rolling leaderboard.

The NBA plays three or four games a week, so windows are measured in weeks
(``WINDOW_WEEKS = (1, 2, 4)``, roughly the last 3-4, 7 and 14 games) and share a
league-wide anchor: the week of the latest game date in the phase. Players
without an appearance in the current span are omitted, which keeps an
early-season hot streak from lingering on Trends after an injury or a benching.
Regular season and postseason are anchored and ranked separately.

Game logs store raw counts and team context, never pre-divided rates (see
ingest_game_logs.py), so window rates are recomputed from summed numerators and
denominators through the same ``ingest.metric_values`` that builds the season
snapshot: exact rather than approximate, and the reason a metric with a zero
denominator is omitted rather than reported as a misleading 0. Metric keys in
``metrics`` / ``prior_metrics`` / ``delta`` are the season metric ids from
NBA_CONTRACT.md, so the client can point a "recent" bar at either table with
one shared key.

Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as ingest.py). ``--dry-run``
reads game logs from a JSON-lines file (or builds them from hoopR) and writes
the rows to ``--out`` instead.
"""

import argparse
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import numpy as np
import pandas as pd
from dotenv import load_dotenv

import ingest
from ingest import ALL_METRICS, PERCENT_PLACES, resolve_season
from nbacodes import basketball_client

load_dotenv()

logger = logging.getLogger(__name__)
UTC = timezone.utc

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

WINDOW_WEEKS = (1, 2, 4)

# Game-log metric keys the formulas read; missing ones (zones before the shots
# feed, On-Off where the replay failed) become NaN, never 0.
REQUIRED_KEYS = (
    ingest.BASE_COLUMNS
    + ["tm_min", "tm_fgm", "tm_fga", "tm_fta", "tm_tov", "tm_oreb", "tm_dreb", "tm_reb",
       "opp_poss", "opp_fga", "opp_fg3a", "opp_oreb", "opp_dreb", "opp_reb",
       "plus_minus", "starter", "on_margin", "off_margin", "off_poss"]
    + ingest.playergames.ZONE_COLUMNS
)


def _places(metric_id: str) -> int:
    return PERCENT_PLACES[ingest.METRIC_BY_ID[metric_id].fmt]


def _client():
    return basketball_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def logs_frame(logs: list[dict]) -> pd.DataFrame:
    """Flatten game-log rows (metrics dict spread into columns) into one frame."""
    records = []
    for log in logs:
        record = {
            "player_id": int(log["player_id"]),
            "season": int(log["season"]),
            "season_type": str(log.get("season_type") or "REG"),
            "player_type": log["player_type"],
            "game_date": str(log["game_date"])[:10],
            "week": log.get("week"),
            "team": log.get("team"),
            "plays": int(log.get("plays") or 0),
            "touches": int(log.get("touches") or 0),
        }
        record.update(log.get("metrics") or {})
        records.append(record)
    frame = pd.DataFrame(records)
    if frame.empty:
        return frame
    for key in REQUIRED_KEYS:
        frame[key] = pd.to_numeric(frame[key], errors="coerce") if key in frame else np.nan
    # Zone frequencies divide by the tracked total, which the game log does not store.
    zone_attempts = [f"{zone}_fga" for zone in ("rim", "smid", "lmid", "c3", "nc3")]
    frame["shot_fga"] = frame[zone_attempts].sum(axis=1, min_count=1)
    frame["week"] = pd.to_numeric(frame["week"], errors="coerce")
    return frame


def window_metrics(games: pd.DataFrame, keys: list[str]) -> dict[tuple, dict[str, Any]]:
    """Metrics per (player, phase, cohort) from the game rows in one window.

    Components are summed per key, then every rate is divided out of the sums
    in one vectorised pass (``ingest.metric_values``): exact, and fast enough to
    run for every player and window in seconds. A metric whose denominator is
    zero is absent, never 0.
    """
    if games.empty:
        return {}
    sums = ingest.sum_games(ingest.derive_game_terms(games), by=keys)
    values = ingest.metric_values(sums)
    out: dict[tuple, dict[str, Any]] = {}
    for key, row in zip(values.index, values.to_dict("records")):
        metrics: dict[str, Any] = {}
        for metric in ALL_METRICS:
            value = row.get(metric.id)
            if value is None or pd.isna(value) or not np.isfinite(value):
                continue
            places = _places(metric.id)
            metrics[metric.id] = int(round(value)) if places == 0 else round(float(value), places)
        out[key if isinstance(key, tuple) else (key,)] = metrics
    return out


def _delta(now: dict[str, Any], then: dict[str, Any]) -> dict[str, Any]:
    """Change from the prior window to the current one, for shared metrics."""
    out: dict[str, Any] = {}
    for metric, value in now.items():
        if metric in then:
            out[metric] = round(float(value) - float(then[metric]), _places(metric))
    return out


def build_rows(logs: list[dict], now: Optional[datetime] = None) -> list[dict]:
    """Build every active (player, phase, week-window) row."""
    frame = logs_frame(logs)
    if frame.empty:
        return []
    stamp = (now or datetime.now(UTC)).isoformat()
    keys = ["player_id", "season", "season_type", "player_type"]
    frame = frame.sort_values(["game_date", "week"]).reset_index(drop=True)
    anchors = frame.groupby(["season", "season_type"])["week"].max().to_dict()
    latest = frame.groupby(["season", "season_type"])["week"].transform("max")
    rows: list[dict] = []
    for window in WINDOW_WEEKS:
        current_start = latest - window + 1
        prior_start = latest - 2 * window + 1
        in_current = (frame["week"] >= current_start) & (frame["week"] <= latest)
        in_prior = (frame["week"] >= prior_start) & (frame["week"] < current_start)
        current = frame[in_current]
        if current.empty:
            continue
        now_metrics = window_metrics(current, keys)
        then_metrics = window_metrics(frame[in_prior], keys)
        summary = current.groupby(keys).agg(
            as_of=("game_date", "last"), team=("team", "last"), games=("game_date", "size"),
            plays=("plays", "sum"), touches=("touches", "sum"),
        )
        for key, line in zip(summary.index, summary.to_dict("records")):
            player_id, season, season_type, player_type = key
            anchor = int(anchors[(season, season_type)])
            metrics = now_metrics.get(key, {})
            prior = then_metrics.get(key, {})
            rows.append({
                "player_id": int(player_id),
                "season": int(season),
                "season_type": season_type,
                "player_type": player_type,
                "window_weeks": window,
                "as_of": line["as_of"],
                "start_week": anchor - window + 1,
                "end_week": anchor,
                "team": line["team"],
                "games": int(line["games"]),
                "plays": int(line["plays"]),
                "touches": int(line["touches"]),
                "metrics": metrics,
                "prior_metrics": prior,
                "delta": _delta(metrics, prior),
                "updated_at": stamp,
            })
    return rows


def _fetch_logs(client, season: int) -> list[dict]:
    """Page through every game log for the season (both windows, both phases)."""
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_game_logs").select("*").eq("season", season)
            .order("game_date", desc=True).range(offset, offset + page_size - 1).execute()
        )
        page = resp.data or []
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows


def _fetch_snapshot_player_ids(client, season: int) -> set[tuple[int, str]]:
    """Player and phase keys the app can resolve into a profile."""
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        resp = (
            client.table("player_snapshots").select("id,season_type").eq("season", season)
            .range(offset, offset + page_size - 1).execute()
        )
        page = resp.data or []
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return {(int(row["id"]), str(row.get("season_type") or "REG")) for row in rows}


def _routable_logs(logs: list[dict], snapshot_ids: set[Any]) -> list[dict]:
    """Drop feed rows that cannot resolve to a player profile in the app."""
    return [
        row for row in logs
        if int(row["player_id"]) in snapshot_ids
        or (int(row["player_id"]), str(row.get("season_type") or "REG")) in snapshot_ids
    ]


def _upsert(client, rows: list[dict]) -> None:
    if not rows:
        return
    batch_size = 500
    for i in range(0, len(rows), batch_size):
        batch = rows[i : i + batch_size]
        try:
            client.table("player_recent_form").upsert(
                batch, on_conflict="player_id,season,season_type,player_type,window_weeks",
            ).execute()
        except Exception:
            logger.exception("Upsert failed for batch starting at %d", i)
            raise


def _table_exists(client) -> bool:
    """True once the player_recent_form migration has been applied.

    Between shipping this script and applying the migration, the table
    legitimately doesn't exist yet. Failing the whole nightly for that would
    also fail the snapshot and game-log ingests that share the job, so this
    one condition is a warn-and-skip. Every other error still fails loudly.
    """
    try:
        client.table("player_recent_form").select("player_id").limit(1).execute()
        return True
    except Exception as exc:  # noqa: BLE001 - inspecting the provider's message
        message = str(exc)
        if "player_recent_form" in message and (
            "PGRST205" in message or "does not exist" in message or "schema cache" in message
        ):
            return False
        raise


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def run(
    season: Optional[int] = None,
    dry_run: bool = False,
    logs_file: Optional[str] = None,
    out: Optional[str] = None,
) -> None:
    season = resolve_season(season)
    if dry_run:
        if logs_file:
            logs = read_jsonl(Path(logs_file))
        else:
            import ingest_game_logs
            built = ingest.build_season_frame(season)
            logs = ingest_game_logs.build_game_log_rows(built.frame, season, datetime.now(UTC))
        rows = build_rows(logs)
        logger.info("Built %d recent-form rows from %d game logs", len(rows), len(logs))
        if out:
            path = Path(out) / f"recent_form_{season}.jsonl"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("\n".join(json.dumps(r, separators=(",", ":"), default=str) for r in rows) + "\n")
        return

    client = _client()
    if not _table_exists(client):
        logger.warning(
            "public.player_recent_form is missing; apply "
            "supabase/migrations/20260727000000_create_player_recent_form.sql. "
            "Skipping the rollup so the rest of the nightly still completes."
        )
        return

    logger.info("Fetching game logs for %d...", season)
    logs = _fetch_logs(client, season)
    logger.info("  %d game-log rows", len(logs))
    if not logs:
        logger.warning("No game logs for %d, nothing to roll up.", season)
        return

    logs = _routable_logs(logs, _fetch_snapshot_player_ids(client, season))
    logger.info("  %d routable game-log rows", len(logs))
    rows = build_rows(logs)
    logger.info("Built %d recent-form rows", len(rows))

    client.table("player_recent_form").delete().eq("season", season).execute()
    _upsert(client, rows)
    logger.info("Done.")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None, help="Season to roll up (default: current).")
    parser.add_argument("--dry-run", action="store_true", help="Build rows and write JSON lines; touch no database.")
    parser.add_argument("--logs", default=None, help="Game-log JSON lines for --dry-run (default: build from hoopR).")
    parser.add_argument("--out", default=None, help="Directory for --dry-run output.")
    return parser.parse_args()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    args = _parse_args()
    run(season=args.season, dry_run=args.dry_run, logs_file=args.logs, out=args.out)
