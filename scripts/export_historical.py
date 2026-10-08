#!/usr/bin/env python3
"""Export current and historical NBA snapshots from Supabase for the iOS bundle.

Ahead of a September rollover, run this with next season's number to fold the
outgoing season into the historical archive before it becomes historical:

    STATCAST_SEASON=2027 python3 scripts/export_historical.py --historical-only

`--historical-only` is what makes that safe. The current-season export would
otherwise go looking for a season that has not kicked off yet and fail
validation on an empty result. The app tolerates a bundle carrying the still-live
season (`TwoTierPlayerCache.loadHistoricalPlayers` filters it out until the
calendar catches up), so the build can ship months early.
"""

import argparse
import json
import os
import plistlib
import time
import urllib.parse
import urllib.request
from collections import Counter
from datetime import date, datetime, timezone


def _resolve_season() -> int:
    """The season the pipeline is currently writing.

    Same rule as backend/ingest.py::resolve_season and the app's
    StatScoutSeason.current: hoopR names an NBA season for the year it ENDS, so
    October onward belongs to next year's season (2026-10-20 is season 2027,
    "2026-27"). Reusing the football rule (start year) would export the season
    that just finished as the current one and ship a bundle with a hole in it.
    """
    today = date.today()
    return today.year + 1 if today.month >= 10 else today.year


SUPABASE_URL = os.environ["SUPABASE_URL"]
KEY = os.environ["SUPABASE_ANON_KEY"]
CURRENT_SEASON = int(os.environ.get("STATCAST_SEASON") or _resolve_season())
OLDEST_SUPPORTED_SEASON = 2003
# Career rollup sentinel, written by backend/rollup_all_time.py. It ships in the
# historical bundle so "All Time" works on first launch rather than waiting on a
# fetch, the same as every other past season.
ALL_TIME_SEASON = 0
REQUIRED_TYPES = {"g", "f", "c"}
# The league had 29 clubs until the Charlotte Bobcats joined for 2004-05.
FIRST_THIRTY_TEAM_SEASON = 2005

URL = f"{SUPABASE_URL}/rest/v1/player_snapshots"
HEADERS = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Accept": "application/json",
    "Prefer": "count=exact",
}


def fetch_page(query: str, attempts: int = 4) -> list[dict]:
    """One page, retried on transient failure.

    The historical export walks ~15k rows a thousand at a time, so a single
    hiccup from the API used to throw away the whole multi-minute run. Retrying
    the page is cheaper than restarting the export.
    """
    for attempt in range(1, attempts + 1):
        try:
            request = urllib.request.Request(f"{URL}?{query}", headers=HEADERS)
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read())
        except Exception as error:  # noqa: BLE001 - any failure is worth a retry
            if attempt == attempts:
                raise
            delay = 2 ** attempt
            print(f"  page failed ({error}); retrying in {delay}s")
            time.sleep(delay)
    return []


def fetch_all(query_filters: list[tuple[str, str]]) -> list[dict]:
    page_size = 1000
    offset = 0
    players: list[dict] = []

    while True:
        query = urllib.parse.urlencode([
            ("select", "*"),
            *query_filters,
            ("order", "season.asc,season_type.asc,id.asc"),
            ("limit", str(page_size)),
            ("offset", str(offset)),
        ])
        page = fetch_page(query)
        players.extend(page)
        print(f"  fetched {len(page)} rows (total {len(players)})")
        if len(page) < page_size:
            return players
        offset += page_size


def validate_export(
    players: list[dict],
    expected_seasons: set[int],
    require_rate_metrics: bool,
) -> None:
    seasons = {player.get("season") for player in players}
    if seasons != expected_seasons:
        raise RuntimeError(f"Unexpected seasons: {sorted(seasons, key=str)}")

    keys = [
        (
            player.get("id"),
            player.get("season"),
            player.get("season_type", "REG"),
        )
        for player in players
    ]
    if len(keys) != len(set(keys)):
        raise RuntimeError("Duplicate player-season keys in export")

    for season in sorted(expected_seasons):
        season_players = [
            player for player in players
            if player.get("season") == season
            and player.get("season_type", "REG") == "REG"
        ]
        teams = {player.get("team") for player in season_players if player.get("team")}
        types = {str(player.get("player_type") or "").lower() for player in season_players}
        missing_types = REQUIRED_TYPES - types
        # The team floor is a real-season integrity check: a season missing a
        # franchise means a partial ingest (29 clubs before 2005, 30 after). It says nothing about the career
        # rollup, whose cohort is a few hundred players carrying whichever team
        # they last played for, so that one is checked on types and size instead.
        if season == ALL_TIME_SEASON:
            if missing_types or len(season_players) < 100:
                raise RuntimeError(
                    f"Incomplete career rollup: {len(season_players)} players, "
                    f"missing types={sorted(missing_types)}"
                )
        elif season == CURRENT_SEASON:
            # Opening week may contain only one completed game. Require both
            # teams and every position group, without inventing the other games.
            if len(teams) < 2 or len(season_players) < 20 or missing_types:
                raise RuntimeError(
                    f"Incomplete current season: {len(teams)} teams, "
                    f"{len(season_players)} players, missing types={sorted(missing_types)}"
                )
        elif len(teams) < (30 if season >= FIRST_THIRTY_TEAM_SEASON else 29) or missing_types:
            raise RuntimeError(
                f"Incomplete {season}: {len(teams)} teams, missing types={sorted(missing_types)}"
            )
        if any(not player.get("metrics") for player in season_players):
            raise RuntimeError(f"Season {season} contains rows without metrics")

    if require_rate_metrics:
        labels = {
            metric.get("label")
            for player in players
            for metric in player.get("metrics", [])
        }
        missing_rates = {"Pts/100", "TS%", "USG%"} - labels
        if missing_rates:
            raise RuntimeError(f"Missing current rate metrics: {sorted(missing_rates)}")


def export(
    name: str,
    query_filters: list[tuple[str, str]],
    expected_seasons: set[int],
    require_rate_metrics: bool = False,
) -> None:
    filters_description = ", ".join(f"{name}={value}" for name, value in query_filters)
    print(f"\nExporting {name} ({filters_description})...")
    players = fetch_all(query_filters)
    validate_export(players, expected_seasons, require_rate_metrics)
    # The app never renders player photos, and league headshot URLs aren't ours
    # to redistribute in a shipped bundle. `created_at` is pipeline bookkeeping
    # the client has no use for. Drop both rather than baking them into every
    # build. (They stay in Supabase; this only trims the bundled snapshot.)
    for player in players:
        player.pop("image_url", None)
        player.pop("created_at", None)
    output = f"StatScout/Data/{name}.plist"
    write_plist(players, output)

    teams = {player.get("team") for player in players if player.get("team")}
    types = Counter(player.get("player_type") for player in players if player.get("player_type"))
    size = os.path.getsize(output) / 1e6
    print(f"Saved {len(players)} rows, {len(teams)} teams, types={dict(sorted(types.items()))}, {size:.1f} MB")


# Keys whose string values are ISO8601 timestamps: stored as native dates, since
# PropertyListDecoder has no date strategy and needs them native in the plist.
PLIST_DATE_KEYS = {"updated_at", "date"}


def _plist_ready(value, key=None):
    """Drop nulls (plists have none) and turn known timestamp strings into dates."""
    if isinstance(value, dict):
        return {k: v for k, v in ((k, _plist_ready(v, k)) for k, v in value.items()) if v is not None}
    if isinstance(value, list):
        return [v for v in (_plist_ready(v, key) for v in value) if v is not None]
    if isinstance(value, str) and key in PLIST_DATE_KEYS:
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
        # plistlib stores naive datetimes as UTC.
        return parsed.astimezone(timezone.utc).replace(tzinfo=None) if parsed.tzinfo else parsed
    return value


def write_plist(players: list[dict], path: str) -> None:
    """Write the bundle as a binary property list.

    Written with plistlib rather than scripts/convert_historical_to_plist.swift:
    plistlib stores each distinct string once, and the 11k-row NBA bundle (about
    46 metrics per row, every one repeating the same label and category) comes
    out ~30% smaller that way (about 35 MB against 49 MB), with the same
    semantics for the decoder.
    """
    with open(path, "wb") as file:
        plistlib.dump(_plist_ready(players), file, fmt=plistlib.FMT_BINARY)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--historical-only", action="store_true",
        help="Skip the current-season export (for a pre-rollover STATCAST_SEASON).",
    )
    mode.add_argument(
        "--current-only", action="store_true",
        help="Refresh the shipped current snapshot without replacing historical data.",
    )
    args = parser.parse_args()
    os.makedirs("StatScout/Data", exist_ok=True)
    if not args.current_only:
        export(
            "players-historical",
            [("or", f"(season.eq.{ALL_TIME_SEASON},"
              f"and(season.gte.{OLDEST_SUPPORTED_SEASON},season.lt.{CURRENT_SEASON}))")],
            {ALL_TIME_SEASON} | set(range(OLDEST_SUPPORTED_SEASON, CURRENT_SEASON)),
        )
    if not args.historical_only:
        export(
            "players-current", [("season", f"eq.{CURRENT_SEASON}")],
            {CURRENT_SEASON}, require_rate_metrics=True,
        )


if __name__ == "__main__":
    main()
