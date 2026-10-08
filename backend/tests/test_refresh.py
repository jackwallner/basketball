from datetime import datetime, timezone

import pandas as pd
import pytest

from conftest import player_game
from refresh import _coverage, _validate_unique

NOW = datetime(2026, 1, 12, 18, 0, tzinfo=timezone.utc)


def schedule(*games):
    rows = []
    for game_id, day, completed, extra in games:
        rows.append({
            "game_id": game_id, "game_date": pd.Timestamp(day).date(), "season_type": 2,
            "status_type_completed": completed, "home_abbreviation": "NY", "away_abbreviation": "BOS",
            **extra,
        })
    return pd.DataFrame(rows)


def box(*game_ids):
    return pd.DataFrame([player_game(1, g, "2026-01-10") for g in game_ids])


def test_coverage_allows_a_valid_early_day_when_another_game_is_pending():
    sched = schedule((1, "2026-01-10", True, {}), (2, "2026-01-12", False, {}))
    coverage = _coverage(box(1), sched, 2026, NOW)
    assert coverage.expected_games == 1 and coverage.observed_games == 1
    assert coverage.coverage_status == "complete"
    assert coverage.max_game_date == "2026-01-10"
    assert coverage.max_week == 15        # week of Mon 2026-01-05 counted from the 2025-09-29 epoch


def test_coverage_marks_missing_completed_source_games_partial():
    sched = schedule((1, "2026-01-10", True, {}), (2, "2026-01-11", True, {}))
    coverage = _coverage(box(1), sched, 2026, NOW)
    assert coverage.expected_games == 2 and coverage.observed_games == 1
    assert coverage.coverage_status == "partial"


def test_coverage_ignores_preseason_playin_and_allstar_games():
    sched = schedule(
        (1, "2026-01-10", True, {}),
        (2, "2025-10-05", True, {"season_type": 1}),
        (3, "2026-04-14", True, {"season_type": 5}),
        (4, "2026-02-15", True, {"home_abbreviation": "STARS", "away_abbreviation": "STRIPES"}),
    )
    coverage = _coverage(box(1), sched, 2026, NOW)
    assert coverage.expected_games == 1


def test_coverage_without_a_completed_flag_falls_back_to_the_date():
    sched = schedule((1, "2026-01-10", None, {}), (2, "2026-01-12", None, {}))
    coverage = _coverage(box(1), sched, 2026, NOW)
    assert coverage.expected_games == 1      # same-day fixtures are not completed games


def test_coverage_of_an_empty_feed_is_partial():
    assert _coverage(pd.DataFrame(), pd.DataFrame(), 2026, NOW).coverage_status == "partial"


def test_candidate_key_validation_rejects_duplicate_rows():
    rows = [{"id": 1, "season": 2026, "season_type": "REG"}]
    _validate_unique(rows, ("id", "season", "season_type"), "snapshots")
    with pytest.raises(RuntimeError, match="duplicate key"):
        _validate_unique(rows * 2, ("id", "season", "season_type"), "snapshots")


def _candidate(stamp: str, points: int = 22):
    from refresh import Candidate, Coverage

    return Candidate(
        season=2026,
        season_types=("REG",),
        snapshots=({"id": 1, "season": 2026, "updated_at": stamp, "standard_stats": [{"label": "PPG", "value": points}]},),
        game_logs=({"player_id": 1, "game_date": "2026-01-10", "updated_at": stamp},),
        recent_form=({"player_id": 1, "window_weeks": 1, "updated_at": stamp},),
        coverage=Coverage(15, "2026-01-10", 2, 2, "complete"),
        ngs_status="ready",
        pfr_status="pending",
    )


def test_content_hash_ignores_build_timestamps():
    from refresh import content_hash

    assert content_hash(_candidate("2026-01-13T10:00:00Z")) == content_hash(_candidate("2026-01-13T17:49:00Z"))


def test_content_hash_changes_with_a_stat():
    from refresh import content_hash

    assert content_hash(_candidate("x", 22)) != content_hash(_candidate("x", 23))


def test_status_columns_keep_their_names_with_basketball_meanings():
    candidate = _candidate("x")
    assert (candidate.ngs_status, candidate.pfr_status) == ("ready", "pending")   # shots feed, play-by-play feed
    from refresh import _merge_status
    assert _merge_status("ready", "degraded") == "degraded"
    assert _merge_status("not_applicable", "ready") == "ready"
    assert _merge_status("ready", "pending") == "pending"


def test_dry_run_writes_the_candidate(tmp_path):
    import json
    from refresh import write_candidate

    write_candidate(_candidate("x"), str(tmp_path))
    summary = json.loads((tmp_path / "summary_2026.json").read_text())
    assert summary["snapshots"] == 1 and summary["shots_status"] == "ready" and summary["pbp_status"] == "pending"
    assert (tmp_path / "game_logs_2026.jsonl").exists() and (tmp_path / "recent_form_2026.jsonl").exists()


class _FlakyRPC:
    def __init__(self, errors):
        self.errors = list(errors)
        self.calls = 0

    def rpc(self, function, params):
        return self

    def execute(self):
        self.calls += 1
        if self.errors:
            raise self.errors.pop(0)
        return type("R", (), {"data": [{"status": "unchanged"}]})()


def test_rpc_retries_gateway_timeouts():
    from refresh import _rpc
    client = _FlakyRPC([RuntimeError("{'code': 504, 'details': 'Gateway Timeout'}")])
    assert _rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None) == {"status": "unchanged"}
    assert client.calls == 2


def test_rpc_treats_already_applied_retry_as_done():
    from refresh import _rpc
    client = _FlakyRPC([RuntimeError("504 Gateway Timeout"), RuntimeError("refresh x is already unchanged")])
    assert _rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None) == {"status": "already_applied"}


def test_rpc_does_not_retry_real_errors():
    from refresh import _rpc
    client = _FlakyRPC([RuntimeError("refresh output differs from the live revision")])
    with pytest.raises(RuntimeError):
        _rpc(client, "mark_data_refresh_unchanged", {}, sleep=lambda _: None)
    assert client.calls == 1


def test_publisher_refuses_the_football_project(monkeypatch):
    import refresh
    monkeypatch.setenv("SUPABASE_URL", "https://qwkmpwnhrejsuplcwxrb.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "x")
    with pytest.raises(RuntimeError, match="Basketball Supabase"):
        refresh._client()
