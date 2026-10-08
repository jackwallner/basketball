"""
NBA calendar and team-code rules, stdlib only.

The season rule and the ESPN-to-fan team-code mapping are needed by the schedule
planner, which runs first in every workflow on a bare runner with nothing
installed, as well as by the polars-based loaders in ``hoopr.py``, which
re-exports everything here. Keeping them in one dependency-free module means the
planner and the builders can never disagree about which season it is or which
rows are real NBA games.
"""

from __future__ import annotations

import os
from datetime import date, datetime, timedelta
from typing import Any
from urllib.parse import urlparse

# ESPN abbreviation -> the fan-standard code the app shows. ``NJ`` becomes the
# three-letter ``NJN`` so every code in the table is the same width.
TEAM_CODE_MAP = {
    "GS": "GSW",
    "NO": "NOP",
    "NY": "NYK",
    "SA": "SAS",
    "UTAH": "UTA",
    "WSH": "WAS",
    "NJ": "NJN",
}

CURRENT_TEAMS = frozenset({
    "ATL", "BKN", "BOS", "CHA", "CHI", "CLE", "DAL", "DEN", "DET", "GSW",
    "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NOP", "NYK",
    "OKC", "ORL", "PHI", "PHX", "POR", "SAC", "SAS", "TOR", "UTA", "WAS",
})
# Franchises that played under another code in the seasons this pipeline
# covers (2002 onward). The row keeps the code it carried then.
HISTORICAL_TEAMS = frozenset({"SEA", "NJN", "NOH", "NOK", "VAN"})
NBA_TEAMS = CURRENT_TEAMS | HISTORICAL_TEAMS

# ESPN season_type ids. 2 = regular season, 3 = postseason; 1 (preseason) and
# 5 (play-in) belong to neither phase and are never ingested.
ESPN_REG = 2
ESPN_POST = 3
PHASE_BY_ESPN_TYPE = {ESPN_REG: "REG", ESPN_POST: "POST"}



def season_for_date(day: date | datetime) -> int:
    """hoopR season containing ``day``: named for the year the season ends.

    The NBA season starts in October, so October through December belong to the
    NEXT calendar year's season: 2026-10-20 is in season 2027 (2026-27).
    """
    return day.year + 1 if day.month >= 10 else day.year


def normalize_team(code: Any) -> str:
    """ESPN's abbreviation as the app's team code ("" for a missing value)."""
    if code is None:
        return ""
    text = str(code).strip().upper()
    if text in {"", "NAN", "NONE"}:
        return ""
    return TEAM_CODE_MAP.get(text, text)


def is_nba_team(code: Any) -> bool:
    """Whether a (normalised) code is an NBA franchise, not an All-Star squad."""
    return normalize_team(code) in NBA_TEAMS


# The Football app's Supabase project. The football and basketball repos share a
# workflow lineage and the same RPC names, so an environment pointed at the wrong
# project would happily overwrite the other app's data. Refuse it by name.
FOOTBALL_SUPABASE_HOST = "qwkmpwnhrejsuplcwxrb.supabase.co"


def supabase_host_ok(url: str) -> bool:
    """Whether ``url`` is the Basketball Supabase project (or at least not Football's).

    Set ``BASKETBALL_SUPABASE_HOST`` (a repository variable in CI) to pin the
    exact project host; without it any ``*.supabase.co`` host except Football's
    is accepted.
    """
    host = urlparse(url).hostname or ""
    if host == FOOTBALL_SUPABASE_HOST:
        return False
    pinned = os.environ.get("BASKETBALL_SUPABASE_HOST", "").strip()
    if pinned:
        return host == pinned
    return host.endswith(".supabase.co")


def season_epoch(season: int) -> date:
    """The Monday on or before October 1 of the season's first calendar year."""
    first = date(season - 1, 10, 1)
    return first - timedelta(days=first.weekday())


def game_week(game_date: Any, season: int) -> int:
    """1-based week number since the season epoch (continues through the playoffs).

    The NBA has no league weeks, so Recent Form's windows, the publisher's
    coverage guard and the ``week`` columns all count calendar weeks from one
    fixed epoch per season. It is stable between incremental runs.
    """
    day = date.fromisoformat(str(game_date)[:10])
    return (day - season_epoch(season)).days // 7 + 1


def basketball_client(url: str = "", key: str = ""):
    """A Supabase client for the Basketball project, or a clear refusal.

    Every script that writes goes through this. The environment can carry a
    stale ``.env`` copied from the football repo, and ``load_dotenv()`` would
    happily load its credentials, so the project host is checked before a client
    exists rather than trusted.
    """
    url = (url or os.environ.get("SUPABASE_URL", "")).strip()
    key = (key or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")).strip()
    if not url or not key:
        raise SystemExit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.")
    if not supabase_host_ok(url):
        raise SystemExit(f"Refusing to use {urlparse(url).hostname}: not the Basketball Supabase project.")
    from supabase import create_client

    return create_client(url, key)
