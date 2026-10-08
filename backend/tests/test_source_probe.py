from datetime import datetime, timezone

from source_probe import (
    AssetProbe,
    AssetSpec,
    current_asset_specs,
    fingerprint_assets,
    parse_source_timestamp,
    probe_asset,
    probe_sources,
    resolve_season,
)


class Response:
    def __init__(self, status_code, headers=None):
        self.status_code = status_code
        self.headers = headers or {}


class FakeHTTP:
    """HEAD-only fake: every asset answers with the same strong ETag unless overridden."""

    def __init__(self, *, etag='"generation-1"', status=200, missing=(), last_modified=None):
        self.etag = etag
        self.status = status
        self.missing = missing
        self.last_modified = last_modified
        self.seen = []

    def head(self, url, *, timeout):
        self.seen.append(url)
        if any(name in url for name in self.missing):
            return Response(404)
        headers = {"ETag": self.etag, "Content-Length": "71654"}
        if self.last_modified:
            headers["Last-Modified"] = self.last_modified
        return Response(self.status, headers)


def probe(etag="one", **extra):
    return AssetProbe("player_box", "player_box/parquet/player_box_2026.parquet", True, "url", 200, etag, None, "10", **extra)


def test_the_five_consumed_assets_are_probed_for_the_season():
    specs = {s.name: s for s in current_asset_specs(2026)}
    assert set(specs) == {"player_box", "team_box", "shots", "pbp", "schedule"}
    assert specs["player_box"].path == "player_box/parquet/player_box_2026.parquet"
    assert specs["team_box"].path == "team_box/parquet/team_box_2026.parquet"
    assert specs["shots"].path == "shots/parquet/shots_2026.parquet"
    assert specs["pbp"].path == "pbp/parquet/play_by_play_2026.parquet"
    assert specs["schedule"].path == "schedules/parquet/nba_schedule_2026.parquet"
    assert specs["player_box"].asset_url == (
        "https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/main/nba/player_box/parquet/player_box_2026.parquet"
    )
    assert {n for n, s in specs.items() if s.required} == {"player_box", "team_box", "schedule"}


def test_probing_makes_one_head_request_per_asset_and_nothing_else():
    http = FakeHTTP()
    probe_sources(2026, client=http)
    assert len(http.seen) == 5 and len(set(http.seen)) == 5


def test_season_follows_the_year_the_season_ends():
    assert resolve_season(now=datetime(2026, 10, 8, tzinfo=timezone.utc)) == 2027
    assert resolve_season(now=datetime(2026, 7, 8, tzinfo=timezone.utc)) == 2026
    assert resolve_season(2025) == 2025


def test_last_modified_is_normalized_to_utc_when_a_mirror_sends_it():
    assert parse_source_timestamp("Sat, 12 Sep 2026 12:52:18 GMT") == datetime(2026, 9, 12, 12, 52, 18, tzinfo=timezone.utc)
    assert parse_source_timestamp("2026-10-08T03:52:00Z") == datetime(2026, 10, 8, 3, 52, tzinfo=timezone.utc)
    assert parse_source_timestamp(None) is None
    assert parse_source_timestamp("garbage") is None


def test_fingerprint_tracks_the_asset_generation():
    base = probe()
    assert fingerprint_assets([base]) == fingerprint_assets([probe()])
    assert fingerprint_assets([base]) != fingerprint_assets([probe(etag="two")])


def test_fingerprint_changes_when_any_one_asset_changes():
    a = AssetProbe("shots", "shots/p", False, "u", 200, '"1"', None, "5")
    b = AssetProbe("pbp", "pbp/p", False, "u", 200, '"1"', None, "5")
    b2 = AssetProbe("pbp", "pbp/p", False, "u", 200, '"2"', None, "5")
    assert fingerprint_assets([a, b]) != fingerprint_assets([a, b2])
    assert fingerprint_assets([a, b]) == fingerprint_assets([b, a])        # order does not matter


def test_a_schedule_only_republish_does_start_a_new_generation():
    one = probe_sources(2026, client=FakeHTTP(etag='"a"'))
    two = probe_sources(2026, client=FakeHTTP(etag='"b"'))
    assert one.fingerprint != two.fingerprint
    assert one.fingerprint == probe_sources(2026, client=FakeHTTP(etag='"a"')).fingerprint


def test_optional_asset_failure_does_not_block_the_core_probe():
    result = probe_sources(2026, client=FakeHTTP(missing=("shots", "play_by_play")))
    assert result.ready and result.error_code is None
    assert {a.name for a in result.assets if not a.available} == {"shots", "pbp"}


def test_required_asset_failure_is_reported_as_pending():
    result = probe_sources(2027, client=FakeHTTP(missing=("player_box",)))
    assert not result.ready
    assert result.error_code == "http_404"


def test_unpublished_season_is_pending_not_an_error():
    result = probe_sources(2028, client=FakeHTTP(status=404))
    assert not result.ready and result.error_code == "http_404"      # nothing published at all


def test_new_season_with_a_schedule_but_no_box_scores_is_season_pending():
    result = probe_sources(2027, client=FakeHTTP(missing=("player_box", "team_box", "shots", "play_by_play")))
    assert not result.ready and result.error_code == "season_pending"
    assert "2027" in result.error_detail
    # A missing schedule, or box scores that are only partly missing, stays an outage.
    assert probe_sources(2027, client=FakeHTTP(missing=("player_box", "nba_schedule"))).error_code == "http_404"
    assert probe_sources(2027, client=FakeHTTP(missing=("player_box",))).error_code == "http_404"


def test_network_errors_become_a_durable_status():
    class Broken:
        def head(self, url, *, timeout):
            raise TimeoutError("slow")

    asset = probe_asset(Broken(), AssetSpec("player_box", "p", True))
    assert asset.status_code is None and asset.error_code == "network_error" and not asset.available


def test_source_published_at_uses_last_modified_when_present():
    result = probe_sources(2026, client=FakeHTTP(last_modified="Sat, 12 Sep 2026 12:52:18 GMT"))
    assert result.source_published_at == "2026-09-12T12:52:18+00:00"
    assert probe_sources(2026, client=FakeHTTP()).source_published_at is None
