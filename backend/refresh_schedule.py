"""Decide from the NBA schedule whether a refresh probe is worth running.

The workflow wakes up every 15 to 30 minutes, and this gate turns most of those
wake-ups into a two-second no-op. Tip-off times are known for the whole season,
so the useful moments are predictable: hoopR rebuilds its box scores, shots and
play-by-play from ESPN through the evening and night, a few hours after games
end.

Cadence, measured from the last recorded probe (``last_checked_at``):

* Any game in the post-game window (tip-off + 3h to + 8h) is checked every 30
  minutes, then hourly until + 30h.
* A game whose score is posted but whose player stats are not in yet is checked
  every 30 minutes for 12 hours after tip-off, hourly until 48 hours, then
  every 3 hours (the "late to post" backup, up to five days).
* Otherwise one check every 6 hours during the season (October through June) and
  one a day in the offseason (July through September).

The schedule itself is re-synced from hoopR every 15 minutes while a game is in
progress, and once a day otherwise (postponements, start-time changes).

The NBA plays most days from mid October to mid June, so unlike the football
planner there are few quiet stretches; the saving is mostly the hours between a
finished game's backfill and the next tip-off.

Stdlib only for planning, so the gate runs on the bare runner. Reading the
schedule file needs pyarrow, which the workflow installs in this step.
"""

from __future__ import annotations

import argparse
import io
import json
import logging
import os
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any, Iterable, Mapping, Optional
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from nbacodes import (
    PHASE_BY_ESPN_TYPE,
    game_week,
    is_nba_team,
    normalize_team,
    season_for_date,
    supabase_host_ok,
)

logger = logging.getLogger(__name__)
UTC = timezone.utc

SCHEDULE_URL = (
    "https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/main/nba/"
    "schedules/parquet/nba_schedule_{season}.parquet"
)
USER_AGENT = "Hardwood-StatScout/refresh-schedule"
TIMEOUT_SECONDS = 30

# GitHub delays scheduled runs by a few minutes, so a cadence counts as met a
# little early rather than slipping a whole cycle.
TOLERANCE = timedelta(minutes=4)

POST_GAME_START = timedelta(hours=3)
POST_GAME_DENSE_END = timedelta(hours=8)
POST_GAME_BACKUP_END = timedelta(hours=30)
MISSING_STATS_DENSE_END = timedelta(hours=12)
MISSING_STATS_BACKUP_END = timedelta(hours=48)
MISSING_STATS_GIVE_UP = timedelta(days=5)
LIVE_SCORE_START = timedelta(minutes=-15)
LIVE_SCORE_END = timedelta(hours=4)
IN_SEASON = timedelta(hours=6)
OFFSEASON = timedelta(hours=20)
OFFSEASON_MONTHS = frozenset({7, 8, 9})


@dataclass(frozen=True)
class Game:
    game_id: str
    season: int
    season_type: str
    game_type: str
    week: int
    game_date: date
    kickoff_at: Optional[datetime]
    away_team: str
    home_team: str
    away_score: Optional[int]
    home_score: Optional[int]
    overtime: bool
    stadium: Optional[str]

    @property
    def is_final(self) -> bool:
        return self.away_score is not None and self.home_score is not None

    def as_row(self, synced_at: datetime) -> dict[str, Any]:
        return {
            "game_id": self.game_id,
            "season": self.season,
            "season_type": self.season_type,
            "game_type": self.game_type,
            "week": self.week,
            "game_date": self.game_date.isoformat(),
            "kickoff_at": self.kickoff_at.isoformat() if self.kickoff_at else None,
            "away_team": self.away_team,
            "home_team": self.home_team,
            "away_score": self.away_score,
            "home_score": self.home_score,
            "overtime": self.overtime,
            "stadium": self.stadium,
            "synced_at": synced_at.isoformat(),
        }


@dataclass(frozen=True)
class Decision:
    probe: bool
    probe_reason: str
    sync_games: bool
    sync_reason: str
    next_check_at: Optional[datetime] = None


def resolve_season(now: datetime) -> int:
    raw = os.environ.get("STATCAST_SEASON", "").strip()
    if raw:
        return int(raw)
    return season_for_date(now)


def _int(value: Any) -> Optional[int]:
    text = str(value).strip() if value is not None else ""
    if not text or text.upper() in {"NA", "NAN", "NONE"}:
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def tip_off_utc(value: Any) -> Optional[datetime]:
    """Scheduled tip-off from hoopR's UTC timestamp ("2026-06-14T00:30Z")."""
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def parse_schedule_records(records: Iterable[Mapping[str, Any]], seasons: Iterable[int]) -> list[Game]:
    """Games from hoopR schedule rows for the requested seasons.

    Only regular-season and postseason games between two NBA clubs are kept:
    preseason, play-in and All-Star games belong to neither phase, and a
    postseason game whose teams are not decided yet has no club to show.
    Scores are set only for a completed game.
    """
    wanted = set(seasons)
    games: list[Game] = []
    for row in records:
        season = _int(row.get("season"))
        game_id = _int(row.get("game_id"))
        phase = PHASE_BY_ESPN_TYPE.get(_int(row.get("season_type")) or 0)
        if season not in wanted or game_id is None or phase is None:
            continue
        away = normalize_team(row.get("away_abbreviation"))
        home = normalize_team(row.get("home_abbreviation"))
        if not (is_nba_team(away) and is_nba_team(home)):
            continue
        day = row.get("game_date")
        try:
            game_date = day if isinstance(day, date) and not isinstance(day, datetime) else date.fromisoformat(str(day)[:10])
        except ValueError:
            continue
        completed = bool(row.get("status_type_completed"))
        games.append(Game(
            game_id=str(game_id),
            season=season,
            season_type=phase,
            game_type=phase,
            week=game_week(game_date, season),
            game_date=game_date,
            kickoff_at=tip_off_utc(row.get("date")),
            away_team=away,
            home_team=home,
            away_score=_int(row.get("away_score")) if completed else None,
            home_score=_int(row.get("home_score")) if completed else None,
            overtime=(_int(row.get("status_period")) or 0) > 4,
            stadium=(str(row.get("venue_full_name") or "").strip() or None),
        ))
    return games


def parse_schedule_parquet(payload: bytes, seasons: Iterable[int]) -> list[Game]:
    import pyarrow.parquet as pq  # installed by the workflow; the rest of this module is stdlib

    columns = [
        "game_id", "season", "season_type", "game_date", "date", "home_abbreviation",
        "away_abbreviation", "home_score", "away_score", "status_type_completed",
        "status_period", "venue_full_name",
    ]
    table = pq.read_table(io.BytesIO(payload), columns=columns)
    return parse_schedule_records(table.to_pylist(), seasons)


def games_from_rows(rows: Iterable[Mapping[str, Any]]) -> list[Game]:
    """Rebuild games read back from the Supabase table."""
    games: list[Game] = []
    for row in rows:
        kickoff = row.get("kickoff_at")
        games.append(Game(
            game_id=str(row["game_id"]),
            season=int(row["season"]),
            season_type=str(row.get("season_type") or "REG"),
            game_type=str(row.get("game_type") or "REG"),
            week=int(row["week"]),
            game_date=date.fromisoformat(str(row["game_date"])[:10]),
            kickoff_at=datetime.fromisoformat(str(kickoff).replace("Z", "+00:00")) if kickoff else None,
            away_team=str(row.get("away_team") or ""),
            home_team=str(row.get("home_team") or ""),
            away_score=_int(row.get("away_score")),
            home_score=_int(row.get("home_score")),
            overtime=bool(row.get("overtime")),
            stadium=row.get("stadium"),
        ))
    return games


def _due(last: Optional[datetime], now: datetime, cadence: timedelta) -> bool:
    return last is None or now - last >= cadence - TOLERANCE


def _cadence(label: str, cadence: timedelta) -> tuple[str, timedelta]:
    return label, cadence


def baseline_cadence(now: datetime) -> tuple[str, timedelta]:
    """The quiet-day cadence: every 6 hours in season, daily July through September."""
    if now.month in OFFSEASON_MONTHS:
        return _cadence("offseason daily check", OFFSEASON)
    return _cadence("in-season check", IN_SEASON)


def probe_cadence(
    games: Iterable[Game],
    now: datetime,
    games_with_stats: set[str],
) -> tuple[str, timedelta]:
    """The shortest cadence any game currently asks for, with its reason."""
    best = baseline_cadence(now)
    for game in games:
        if game.kickoff_at is None:
            continue
        since = now - game.kickoff_at
        if since < timedelta(0):
            continue
        candidates: list[tuple[str, timedelta]] = []
        if game.is_final and game.game_id not in games_with_stats and since < MISSING_STATS_GIVE_UP:
            if since < MISSING_STATS_DENSE_END:
                candidates.append(_cadence(f"{game.game_id} final, stats not in", timedelta(minutes=30)))
            elif since < MISSING_STATS_BACKUP_END:
                candidates.append(_cadence(f"{game.game_id} stats late", timedelta(hours=1)))
            else:
                candidates.append(_cadence(f"{game.game_id} stats very late", timedelta(hours=3)))
        if POST_GAME_START <= since < POST_GAME_DENSE_END:
            candidates.append(_cadence(f"{game.game_id} post-game window", timedelta(minutes=30)))
        elif POST_GAME_DENSE_END <= since < POST_GAME_BACKUP_END:
            candidates.append(_cadence(f"{game.game_id} post-game backup", timedelta(hours=1)))
        for candidate in candidates:
            if candidate[1] < best[1]:
                best = candidate
    return best


def sync_cadence(games: Iterable[Game], now: datetime) -> tuple[str, timedelta]:
    best = _cadence("daily schedule sync", OFFSEASON)
    for game in games:
        if game.kickoff_at is None or game.is_final:
            continue
        since = now - game.kickoff_at
        if LIVE_SCORE_START <= since < LIVE_SCORE_END:
            return _cadence(f"{game.game_id} in progress", timedelta(minutes=15))
    return best


def decide(
    *,
    now: datetime,
    games: list[Game],
    games_with_stats: set[str],
    last_probe_at: Optional[datetime],
    last_sync_at: Optional[datetime],
    force: bool = False,
) -> Decision:
    sync_reason, sync_every = sync_cadence(games, now)
    if not games:
        sync_reason, sync_every = "schedule table empty", timedelta(0)
    probe_reason, probe_every = probe_cadence(games, now, games_with_stats)
    if force:
        return Decision(True, "forced", True, "forced")
    return Decision(
        probe=_due(last_probe_at, now, probe_every),
        probe_reason=f"{probe_reason} (every {int(probe_every.total_seconds() // 60)}m)",
        sync_games=_due(last_sync_at, now, sync_every),
        sync_reason=f"{sync_reason} (every {int(sync_every.total_seconds() // 60)}m)",
    )


STEP = timedelta(minutes=5)
HORIZON = timedelta(hours=24)


def next_check_at(
    *,
    now: datetime,
    games: list[Game],
    games_with_stats: set[str],
    last_probe_at: Optional[datetime],
    last_sync_at: Optional[datetime],
) -> datetime:
    """The first moment after ``now`` when a probe or a schedule sync is due.

    GitHub drops scheduled runs under load, so the workflow schedules its own
    next run from this answer instead of trusting cron. Callers pass ``last_*``
    as ``now`` for anything that ran this time.
    """
    t = now + STEP
    while t <= now + HORIZON:
        _, probe_every = probe_cadence(games, t, games_with_stats)
        _, sync_every = sync_cadence(games, t)
        if _due(last_probe_at, t, probe_every) or _due(last_sync_at, t, sync_every):
            return t
        t += STEP
    return now + HORIZON


# ---------------------------------------------------------------------------
# Network


class Supabase:
    def __init__(self, url: str, key: str) -> None:
        if not supabase_host_ok(url):
            raise RuntimeError("Refusing to use a different Supabase project")
        self.url = url.rstrip("/")
        self.key = key

    def _request(self, method: str, path: str, *, params: Mapping[str, str] | None = None,
                 body: Any = None, prefer: str | None = None) -> Any:
        query = f"?{urlencode(params)}" if params else ""
        headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        }
        if prefer:
            headers["Prefer"] = prefer
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = Request(f"{self.url}/rest/v1/{path}{query}", data=data, method=method, headers=headers)
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            payload = response.read()
        return json.loads(payload) if payload else None

    def games(self, seasons: Iterable[int]) -> list[dict[str, Any]]:
        listed = ",".join(str(s) for s in seasons)
        rows: list[dict[str, Any]] = []
        offset = 0
        while True:
            page = self._request("GET", "games", params={
                "select": "*", "season": f"in.({listed})", "order": "game_id.asc",
                "limit": "1000", "offset": str(offset),
            }) or []
            rows.extend(page)
            if len(page) < 1000:
                return rows
            offset += 1000

    def last_sync_at(self) -> Optional[datetime]:
        rows = self._request("GET", "games", params={"select": "synced_at", "order": "synced_at.desc", "limit": "1"}) or []
        return _parse_ts(rows[0].get("synced_at")) if rows else None

    def last_probe_at(self) -> Optional[datetime]:
        rows = self._request("GET", "data_refresh_status", params={"select": "last_checked_at", "limit": "1"}) or []
        return _parse_ts(rows[0].get("last_checked_at")) if rows else None

    def games_with_stats(self, game_ids: list[str]) -> set[str]:
        """Game ids that already have player_game_logs rows (any player)."""
        if not game_ids:
            return set()
        listed = ",".join(game_ids)
        found: set[str] = set()
        offset = 0
        while True:
            rows = self._request("GET", "player_game_logs", params={
                "select": "game_id", "game_id": f"in.({listed})", "order": "game_id.asc",
                "limit": "1000", "offset": str(offset),
            }) or []
            found.update(str(row["game_id"]) for row in rows if row.get("game_id"))
            if len(rows) < 1000:
                return found
            offset += 1000

    def upsert_games(self, rows: list[dict[str, Any]]) -> None:
        for start in range(0, len(rows), 500):
            self._request(
                "POST", "games",
                params={"on_conflict": "game_id"},
                body=rows[start:start + 500],
                prefer="resolution=merge-duplicates,return=minimal",
            )


def _parse_ts(value: Any) -> Optional[datetime]:
    if not value:
        return None
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


def fetch_schedule(season: int) -> bytes:
    request = Request(SCHEDULE_URL.format(season=season), headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return response.read()


def recent_game_ids(games: Iterable[Game], now: datetime) -> list[str]:
    return [
        g.game_id for g in games
        if g.is_final and g.kickoff_at is not None
        and timedelta(0) <= now - g.kickoff_at < MISSING_STATS_GIVE_UP
    ]


def run(now: datetime, *, force: bool, dry_run: bool) -> Decision:
    db = Supabase(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    season = resolve_season(now)
    seasons = (season - 1, season)

    games = games_from_rows(db.games(seasons))
    decision = decide(
        now=now,
        games=games,
        games_with_stats=db.games_with_stats(recent_game_ids(games, now)),
        last_probe_at=db.last_probe_at(),
        last_sync_at=db.last_sync_at(),
        force=force,
    )
    last_sync_at = db.last_sync_at()
    if decision.sync_games:
        games = []
        for year in seasons:
            try:
                games.extend(parse_schedule_parquet(fetch_schedule(year), [year]))
            except Exception:  # noqa: BLE001 - a season hoopR has not published yet is not an error
                logger.warning("No schedule for %s yet", year)
        if not dry_run and games:
            db.upsert_games([g.as_row(now) for g in games])
        logger.info("Synced %d games (%s)", len(games), decision.sync_reason)
        last_sync_at = now
        # A score that just landed can shorten the probe cadence.
        decision = decide(
            now=now,
            games=games,
            games_with_stats=db.games_with_stats(recent_game_ids(games, now)),
            last_probe_at=db.last_probe_at(),
            last_sync_at=now,
            force=force,
        )
    with_stats = db.games_with_stats(recent_game_ids(games, now))
    upcoming = next_check_at(
        now=now,
        games=games,
        games_with_stats=with_stats,
        last_probe_at=now if decision.probe else db.last_probe_at(),
        last_sync_at=last_sync_at,
    )
    return Decision(decision.probe, decision.probe_reason, decision.sync_games, decision.sync_reason, upcoming)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="Decide without writing the games table.")
    parser.add_argument("--github-output", default=None)
    args = parser.parse_args()

    now = datetime.now(UTC)
    try:
        decision = run(now, force=args.force, dry_run=args.dry_run)
    except Exception:  # noqa: BLE001 - never let the planner block a probe
        logger.exception("Schedule planner failed; probing anyway")
        decision = Decision(True, "planner error", False, "planner error", now + timedelta(minutes=30))

    wait = int(((decision.next_check_at or now + timedelta(minutes=30)) - now).total_seconds())
    logger.info("probe=%s (%s); next check in %dm", decision.probe, decision.probe_reason, wait // 60)
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as output:
            output.write(f"probe={str(decision.probe).lower()}\n")
            output.write(f"reason={decision.probe_reason}\n")
            output.write(f"wait_seconds={max(60, wait)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
