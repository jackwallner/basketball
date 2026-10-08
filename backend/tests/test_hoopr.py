from datetime import date

import pytest

import hoopr
import nbacodes


def test_season_is_named_for_the_year_it_ends():
    assert hoopr.season_for_date(date(2026, 1, 15)) == 2026
    assert hoopr.season_for_date(date(2026, 6, 14)) == 2026
    assert hoopr.season_for_date(date(2026, 9, 30)) == 2026
    assert hoopr.season_for_date(date(2026, 10, 1)) == 2027
    assert hoopr.season_for_date(date(2026, 10, 20)) == 2027
    assert hoopr.season_for_date(date(2026, 12, 31)) == 2027


def test_espn_codes_become_fan_codes():
    mapping = {"GS": "GSW", "NO": "NOP", "NY": "NYK", "SA": "SAS", "UTAH": "UTA", "WSH": "WAS"}
    for espn, fan in mapping.items():
        assert hoopr.normalize_team(espn) == fan
    for already_standard in ("LAL", "BKN", "PHX", "CHA", "OKC"):
        assert hoopr.normalize_team(already_standard) == already_standard
    assert hoopr.normalize_team(" ny ") == "NYK"
    assert hoopr.normalize_team(None) == ""
    assert hoopr.normalize_team(float("nan")) == ""


def test_historical_codes_keep_the_code_the_row_carried():
    assert hoopr.normalize_team("SEA") == "SEA"
    assert hoopr.normalize_team("NJ") == "NJN"
    assert hoopr.is_nba_team("SEA") and hoopr.is_nba_team("NJ")


def test_thirty_current_clubs():
    assert len(hoopr.CURRENT_TEAMS) == 30
    assert {hoopr.normalize_team(c) for c in ("GS", "NO", "NY", "SA", "UTAH", "WSH")} <= hoopr.CURRENT_TEAMS


@pytest.mark.parametrize("code", ["STARS", "STRIPES", "WORLD", "GIANNIS", "LEB", "DUR", "EAST", "WEST", "USA", "TBD", ""])
def test_all_star_and_exhibition_squads_are_not_clubs(code):
    assert not hoopr.is_nba_team(code)


def test_asset_urls_match_the_repository_layout():
    base = "https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/main/nba"
    assert hoopr.asset_url("player_box", 2026) == f"{base}/player_box/parquet/player_box_2026.parquet"
    assert hoopr.asset_url("pbp", 2026) == f"{base}/pbp/parquet/play_by_play_2026.parquet"
    assert hoopr.asset_url("schedule", 2026) == f"{base}/schedules/parquet/nba_schedule_2026.parquet"
    assert hoopr.asset_url("shots", 2012).endswith("shots/parquet/shots_2012.parquet")


def test_phases_exclude_preseason_and_play_in():
    assert nbacodes.PHASE_BY_ESPN_TYPE == {2: "REG", 3: "POST"}
    assert 1 not in nbacodes.PHASE_BY_ESPN_TYPE and 5 not in nbacodes.PHASE_BY_ESPN_TYPE


def test_week_counts_from_a_fixed_epoch_through_the_playoffs():
    # Season 2026's epoch is Monday 2025-09-29.
    assert nbacodes.season_epoch(2026) == date(2025, 9, 29)
    assert nbacodes.game_week("2025-09-29", 2026) == 1
    assert nbacodes.game_week("2025-10-05", 2026) == 1
    assert nbacodes.game_week("2025-10-06", 2026) == 2
    assert nbacodes.game_week("2026-06-13", 2026) == 37


def test_supabase_host_guard(monkeypatch):
    monkeypatch.delenv("BASKETBALL_SUPABASE_HOST", raising=False)
    assert nbacodes.supabase_host_ok("https://abcdefgh.supabase.co")
    assert not nbacodes.supabase_host_ok("https://qwkmpwnhrejsuplcwxrb.supabase.co")
    assert not nbacodes.supabase_host_ok("https://example.com")
    monkeypatch.setenv("BASKETBALL_SUPABASE_HOST", "pinned.supabase.co")
    assert nbacodes.supabase_host_ok("https://pinned.supabase.co")
    assert not nbacodes.supabase_host_ok("https://other.supabase.co")


def test_every_writer_goes_through_the_project_guard(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://qwkmpwnhrejsuplcwxrb.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "key")
    with pytest.raises(SystemExit, match="not the Basketball Supabase project"):
        nbacodes.basketball_client()
    monkeypatch.delenv("SUPABASE_URL")
    with pytest.raises(SystemExit, match="Missing SUPABASE_URL"):
        nbacodes.basketball_client()
