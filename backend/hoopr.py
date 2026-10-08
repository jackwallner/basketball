"""
hoopR-nba-data access: asset URLs, cached parquet reads, season rule, team codes.

Every NBA number in this pipeline comes from the sportsdataverse ``hoopR-nba-data``
repository (an ESPN mirror rebuilt nightly): static parquet files on GitHub, no
key, cloud-IP friendly. This module is the one place that knows where those
files live and how ESPN's identifiers map onto the app's.

Two things here are easy to get wrong and are unit-tested:

* A hoopR season is named for the year it ENDS (``2026`` is 2025-26), so the
  rule is ``year + 1 if month >= 10 else year``. The football pipeline used the
  starting year; reusing that rule would resolve October 2026 to the season
  that just finished.
* ESPN's team abbreviations are not the fan-standard ones (``GS``, ``NO``,
  ``NY``, ``SA``, ``UTAH``, ``WSH``), and All-Star games share the regular
  season type with real games, so any row whose team is not an NBA franchise
  has to be dropped before it pollutes a leaderboard.

Set ``HOOPR_CACHE_DIR`` to keep downloads on disk. Local dry runs read the same
files hundreds of times across a backfill; CI leaves it unset and downloads
once per run.
"""

from __future__ import annotations

import io
import logging
import os
import time
from pathlib import Path
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import polars as pl

from nbacodes import (  # noqa: F401 - re-exported for the loaders and tests
    CURRENT_TEAMS,
    ESPN_POST,
    ESPN_REG,
    HISTORICAL_TEAMS,
    NBA_TEAMS,
    PHASE_BY_ESPN_TYPE,
    TEAM_CODE_MAP,
    game_week,
    season_epoch,
    is_nba_team,
    normalize_team,
    season_for_date,
)

logger = logging.getLogger(__name__)

BASE_URL = "https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/main/nba"
USER_AGENT = "Hardwood-StatScout/hoopr"
TIMEOUT_SECONDS = 120
DOWNLOAD_ATTEMPTS = 3

# kind -> (directory, filename pattern). The pattern is filled with the season.
ASSETS: dict[str, tuple[str, str]] = {
    "player_box": ("player_box/parquet", "player_box_{season}.parquet"),
    "team_box": ("team_box/parquet", "team_box_{season}.parquet"),
    "shots": ("shots/parquet", "shots_{season}.parquet"),
    "pbp": ("pbp/parquet", "play_by_play_{season}.parquet"),
    "schedule": ("schedules/parquet", "nba_schedule_{season}.parquet"),
    "player_core": ("player_core/parquet", "player_core_{season}.parquet"),
    "rosters": ("rosters/parquet", "rosters_{season}.parquet"),
    "draft": ("draft/parquet", "draft_{season}.parquet"),
    "standings": ("standings/parquet", "standings_{season}.parquet"),
}

class AssetUnavailable(RuntimeError):
    """The requested hoopR asset does not exist (yet) for that season."""


def asset_url(kind: str, season: int) -> str:
    directory, pattern = ASSETS[kind]
    return f"{BASE_URL}/{directory}/{pattern.format(season=season)}"


def asset_filename(kind: str, season: int) -> str:
    return ASSETS[kind][1].format(season=season)


def _download(url: str) -> bytes:
    last: Optional[BaseException] = None
    for attempt in range(1, DOWNLOAD_ATTEMPTS + 1):
        try:
            request = Request(url, headers={"User-Agent": USER_AGENT})
            with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                return response.read()
        except HTTPError as error:
            if error.code == 404:
                raise AssetUnavailable(url) from error
            last = error
        except (URLError, TimeoutError) as error:
            last = error
        if attempt < DOWNLOAD_ATTEMPTS:
            time.sleep(2 * attempt)
    raise RuntimeError(f"could not download {url}: {last}")


def _cache_path(kind: str, season: int) -> Optional[Path]:
    root = os.environ.get("HOOPR_CACHE_DIR", "").strip()
    return Path(root) / asset_filename(kind, season) if root else None


def read_asset(kind: str, season: int, columns: Optional[list[str]] = None) -> pl.DataFrame:
    """One hoopR parquet asset as a polars frame.

    Reads the local cache when ``HOOPR_CACHE_DIR`` is set and the file is
    there, otherwise downloads (and stores it when a cache directory is set).
    Raises ``AssetUnavailable`` for a 404 so callers can treat a season that has
    not been published yet as pending rather than as an error.
    """
    path = _cache_path(kind, season)
    if path is not None and path.exists():
        return pl.read_parquet(path, columns=columns)
    url = asset_url(kind, season)
    logger.info("Downloading %s", url)
    payload = _download(url)
    if path is not None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
    return pl.read_parquet(io.BytesIO(payload), columns=columns)
