"""Probe hoopR-nba-data file metadata without downloading the data files.

The refresh workflow runs this module on the schedule planner's cadence while the
NBA season is active. A probe makes one small HEAD request per asset the
builders consume and records the source generation through the Supabase RPC when
credentials are available, then tells GitHub Actions whether a full refresh is
needed.

hoopR publishes plain files in a Git repository, so there is no release
``timestamp.json`` to read. ``raw.githubusercontent.com`` answers a HEAD with a
strong ``ETag`` (a content hash, so it changes exactly when the bytes do) and a
``Content-Length``; ``Last-Modified`` is used when a mirror sends it. The
fingerprint combines those for the five assets a build reads: player box scores,
team box scores, shots, play-by-play and the season schedule. A hoopR rebuild
that changes no file therefore changes no fingerprint.

The probe intentionally does not decide that a season is complete. A source can
publish a valid early date while another recently finished game is still
missing. The full builder computes coverage from the schedule and the publisher
protects any already-live games from regression.

Environment:
    SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are optional for local probes
    and required by the scheduled workflow so the last successful fingerprint
    survives runner replacement.
    STATCAST_SEASON optionally selects the season; the calendar is used by
    default to preserve the existing workflow contract.
    BASKETBALL_SUPABASE_HOST optionally pins the Supabase project host.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import sys
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Iterable, Mapping, Optional, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from nbacodes import season_for_date, supabase_host_ok

logger = logging.getLogger(__name__)
UTC = timezone.utc

SOURCE_BASE = "https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/main/nba"
SOURCE_REPOSITORY = "https://github.com/sportsdataverse/hoopR-nba-data"
DEFAULT_TIMEOUT_SECONDS = 20
USER_AGENT = "Hardwood-StatScout/source-probe"


class HTTPClient(Protocol):
    """Small interface that keeps probe tests independent of the network."""

    def head(self, url: str, *, timeout: int) -> "HTTPResponse": ...


class HTTPResponse(Protocol):
    status_code: int
    headers: Mapping[str, str]


class UrllibResponse:
    """Adapter exposing the response fields used by ``UrllibHTTPClient``."""

    def __init__(self, status: int, headers: Mapping[str, str]) -> None:
        self.status_code = int(status)
        self.headers = {str(k): str(v) for k, v in headers.items()}


class UrllibHTTPClient:
    """Dependency-free HTTP client for the lightweight probe job."""

    def head(self, url: str, *, timeout: int) -> UrllibResponse:
        request = Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
        with urlopen(request, timeout=timeout) as response:
            return UrllibResponse(response.status, response.headers)


@dataclass(frozen=True)
class AssetSpec:
    """One hoopR file a build reads."""

    name: str
    path: str  # relative to SOURCE_BASE, e.g. "player_box/parquet/player_box_2026.parquet"
    required: bool = False

    @property
    def filename(self) -> str:
        return self.path.rsplit("/", 1)[-1]

    @property
    def asset_url(self) -> str:
        return f"{SOURCE_BASE}/{self.path}"


@dataclass(frozen=True)
class AssetProbe:
    name: str
    path: str
    required: bool
    asset_url: str
    status_code: int | None
    etag: str | None
    last_modified: str | None
    content_length: str | None
    error_code: str | None = None
    error_detail: str | None = None

    @property
    def source_published_at(self) -> datetime | None:
        return parse_source_timestamp(self.last_modified)

    @property
    def available(self) -> bool:
        return self.status_code is not None and 200 <= self.status_code < 300


@dataclass(frozen=True)
class SourceProbeResult:
    season: int
    checked_at: str
    assets: tuple[AssetProbe, ...]
    fingerprint: str
    source_published_at: str | None
    ready: bool
    error_code: str | None = None
    error_detail: str | None = None
    refresh_id: str | None = None
    changed: bool = False

    def as_dict(self) -> dict[str, Any]:
        result = asdict(self)
        result["assets"] = [asdict(asset) for asset in self.assets]
        return result


def resolve_season(value: Optional[int] = None, *, now: datetime | None = None) -> int:
    """hoopR names a season for the year it ends: October rolls it over."""
    if value is not None:
        return int(value)
    raw = os.environ.get("STATCAST_SEASON", "").strip()
    if raw:
        return int(raw)
    return season_for_date(now or datetime.now(UTC))


def current_asset_specs(season: int) -> tuple[AssetSpec, ...]:
    """The five assets a current-season build reads.

    Player and team box scores and the schedule are required: without them
    there is nothing to publish. Shots (zone metrics) and play-by-play (On-Off
    and the game pages) are optional, so a late upload cannot hold back the
    core feed; they still participate in the fingerprint, so a shots-only or
    pbp-only upload triggers a refresh.
    """
    return (
        AssetSpec("player_box", f"player_box/parquet/player_box_{season}.parquet", required=True),
        AssetSpec("team_box", f"team_box/parquet/team_box_{season}.parquet", required=True),
        AssetSpec("schedule", f"schedules/parquet/nba_schedule_{season}.parquet", required=True),
        AssetSpec("shots", f"shots/parquet/shots_{season}.parquet"),
        AssetSpec("pbp", f"pbp/parquet/play_by_play_{season}.parquet"),
    )


def parse_source_timestamp(value: str | None) -> datetime | None:
    """Parse an HTTP ``Last-Modified`` (or ISO) timestamp to UTC."""
    if not value:
        return None
    text = str(value).strip()
    try:
        parsed = parsedate_to_datetime(text)
    except (TypeError, ValueError, OverflowError):
        parsed = None
    if parsed is None:
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _header(headers: Mapping[str, str], name: str) -> str | None:
    for key, value in headers.items():
        if key.lower() == name.lower():
            return str(value).strip() or None
    return None


def _error_code(exc: BaseException) -> str:
    if isinstance(exc, HTTPError):
        return f"http_{exc.code}"
    if isinstance(exc, (URLError, TimeoutError)):
        return "network_error"
    return "probe_error"


def _error_detail(exc: BaseException) -> str:
    detail = str(exc).strip()
    return detail[:500] if detail else type(exc).__name__


def probe_asset(client: HTTPClient, spec: AssetSpec) -> AssetProbe:
    """One HEAD request for one asset; failures become a durable pending status."""
    common = dict(name=spec.name, path=spec.path, required=spec.required, asset_url=spec.asset_url)
    try:
        response = client.head(spec.asset_url, timeout=DEFAULT_TIMEOUT_SECONDS)
        status = int(response.status_code)
        ok = 200 <= status < 300
        return AssetProbe(
            **common,
            status_code=status,
            etag=_header(response.headers, "etag"),
            last_modified=_header(response.headers, "last-modified"),
            content_length=_header(response.headers, "content-length"),
            error_code=None if ok else f"http_{status}",
            error_detail=None if ok else f"asset status {status}",
        )
    except HTTPError as exc:
        # A 404 is the normal "not published yet" answer for a new season.
        return AssetProbe(**common, status_code=exc.code, etag=None, last_modified=None, content_length=None,
                          error_code=f"http_{exc.code}", error_detail=_error_detail(exc))
    except Exception as exc:  # noqa: BLE001 - return a durable pending status
        return AssetProbe(**common, status_code=None, etag=None, last_modified=None, content_length=None,
                          error_code=_error_code(exc), error_detail=_error_detail(exc))


def fingerprint_assets(assets: Iterable[AssetProbe]) -> str:
    """Return a stable content generation from file metadata.

    ``date`` is deliberately absent. GitHub response dates change on every
    probe, while the ETag (a content hash), Last-Modified and length change when
    an asset is replaced. Including the status and the optional assets also
    makes shots-only and pbp-only corrections trigger a refresh.
    """
    values = [
        {
            "name": asset.name,
            "path": asset.path,
            "required": asset.required,
            "status_code": asset.status_code,
            "etag": asset.etag,
            "last_modified": asset.last_modified,
            "content_length": asset.content_length,
        }
        for asset in sorted(assets, key=lambda item: item.name)
    ]
    encoded = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


SEASON_PENDING = "season_pending"


def season_pending(assets: Iterable[AssetProbe]) -> bool:
    """A new season whose schedule is out but whose box scores are not yet.

    This is the normal state from the October rollover to opening night (the
    season rule moves on October 1, tip-off is about October 20), not an outage:
    the status view says ``source_pending`` with ``last_error_code`` of
    ``season_pending`` and keeps serving the last published season.
    """
    by_name = {asset.name: asset for asset in assets}
    schedule, boxes = by_name.get("schedule"), [by_name.get("player_box"), by_name.get("team_box")]
    return bool(
        schedule is not None and schedule.available
        and all(box is not None and box.status_code == 404 for box in boxes)
    )


def probe_sources(
    season: int,
    *,
    client: HTTPClient | None = None,
    checked_at: datetime | None = None,
) -> SourceProbeResult:
    """Probe all current-season assets and return a JSON-safe result."""
    http = client or UrllibHTTPClient()
    assets = tuple(probe_asset(http, spec) for spec in current_asset_specs(season))
    required_failures = [asset for asset in assets if asset.required and not asset.available]
    source_times = [asset.source_published_at for asset in assets if asset.source_published_at]
    source_published_at = max(source_times).isoformat() if source_times else None
    error_code = required_failures[0].error_code if required_failures else None
    error_detail = required_failures[0].error_detail if required_failures else None
    if season_pending(assets):
        error_code = SEASON_PENDING
        error_detail = f"hoopR has the {season} schedule but no box scores yet; the slate has not started"
    return SourceProbeResult(
        season=season,
        checked_at=(checked_at or datetime.now(UTC)).astimezone(UTC).isoformat(),
        assets=assets,
        fingerprint=fingerprint_assets(assets),
        source_published_at=source_published_at,
        ready=not required_failures,
        error_code=error_code,
        error_detail=error_detail,
    )


def _rpc_url(base_url: str, function: str) -> str:
    return f"{base_url.rstrip('/')}/rest/v1/rpc/{function}"


def _rpc(base_url: str, service_key: str, function: str, params: Mapping[str, Any]) -> Any:
    request = Request(
        _rpc_url(base_url, function),
        data=json.dumps(dict(params), separators=(",", ":")).encode("utf-8"),
        method="POST",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    with urlopen(request, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
        payload = response.read()
    if not payload:
        return None
    return json.loads(payload.decode("utf-8"))


def record_probe(result: SourceProbeResult, *, force: bool = False) -> SourceProbeResult:
    """Persist probe state and, when needed, create a building refresh run."""
    base_url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not base_url or not service_key:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            raise RuntimeError("Scheduled probe requires Basketball Supabase credentials")
        if result.ready:
            return SourceProbeResult(
                **{**result.as_dict(), "assets": result.assets, "refresh_id": str(uuid.uuid4()), "changed": True}
            )
        return result
    if not supabase_host_ok(base_url):
        raise RuntimeError("Refusing to update a different Supabase project")

    params = {
        "p_season": result.season,
        "p_source_fingerprint": result.fingerprint,
        "p_source_assets": [asdict(asset) for asset in result.assets],
        "p_source_published_at": result.source_published_at,
        "p_ready": result.ready,
        "p_force": force,
        "p_error_code": result.error_code,
        "p_error_detail": result.error_detail,
    }
    try:
        payload = _rpc(base_url, service_key, "record_data_refresh_probe", params)
        if isinstance(payload, list):
            payload = payload[0] if payload else {}
        payload = payload if isinstance(payload, dict) else {}
        return SourceProbeResult(
            **{
                **result.as_dict(),
                "assets": result.assets,
                "refresh_id": payload.get("refresh_id"),
                "changed": bool(payload.get("changed", False)),
            }
        )
    except Exception as exc:
        raise RuntimeError("Could not persist the source probe state") from exc


def write_github_output(path: str, result: SourceProbeResult) -> None:
    """Write stable step outputs without relying on shell interpolation."""
    values = {
        "season": result.season,
        "ready": str(result.ready).lower(),
        "changed": str(result.changed).lower(),
        "refresh_id": result.refresh_id or "",
        "fingerprint": result.fingerprint,
        "source_published_at": result.source_published_at or "",
        "error_code": result.error_code or "",
    }
    with open(path, "a", encoding="utf-8") as output:
        for key, value in values.items():
            output.write(f"{key}={value}\n")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=None)
    parser.add_argument("--force", action="store_true", help="Refresh even when the fingerprint is unchanged.")
    parser.add_argument("--github-output", default=None, help="Write GitHub Actions step outputs to this path.")
    parser.add_argument("--json", action="store_true", help="Print the complete probe result as JSON.")
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = _parse_args()
    failed = False
    try:
        result = probe_sources(resolve_season(args.season))
        result = record_probe(result, force=args.force)
    except Exception as exc:  # noqa: BLE001 - the scheduled probe must not hide a source outage
        failed = True
        logger.exception("Source probe failed")
        result = SourceProbeResult(
            season=resolve_season(args.season),
            checked_at=datetime.now(UTC).isoformat(),
            assets=(),
            fingerprint="",
            source_published_at=None,
            ready=False,
            error_code=_error_code(exc),
            error_detail=_error_detail(exc),
        )
    if args.github_output:
        write_github_output(args.github_output, result)
    print(json.dumps(result.as_dict(), sort_keys=True))
    if args.json:
        print(json.dumps(result.as_dict(), indent=2, sort_keys=True))
    # A source being unavailable is an expected pending state. It is stored
    # for the status endpoint and retried on the next scheduled probe.
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
