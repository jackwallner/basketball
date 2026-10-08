from datetime import date, datetime, timedelta, timezone

from refresh_schedule import Game, decide, next_check_at, parse_schedule_records, tip_off_utc

UTC = timezone.utc
TIP = datetime(2026, 1, 13, 0, 30, tzinfo=UTC)   # 7:30 PM Eastern on 2026-01-12


def game(game_id="401800001", tip=TIP, away=None, home=None):
    return Game(
        game_id=game_id, season=2026, season_type="REG", game_type="REG", week=16,
        game_date=date(2026, 1, 12), kickoff_at=tip, away_team="BOS", home_team="NYK",
        away_score=away, home_score=home, overtime=False, stadium=None,
    )


def run(now, games, with_stats=(), last_probe=None, last_sync=None):
    return decide(
        now=now, games=games, games_with_stats=set(with_stats),
        last_probe_at=last_probe, last_sync_at=last_sync,
    )


def test_tip_off_comes_from_hoopr_in_utc():
    assert tip_off_utc("2026-06-14T00:30Z") == datetime(2026, 6, 14, 0, 30, tzinfo=UTC)
    assert tip_off_utc("") is None and tip_off_utc("soon") is None


def record(**extra):
    base = {
        "game_id": 401800001, "season": 2026, "season_type": 2, "game_date": date(2026, 1, 12),
        "date": "2026-01-13T00:30Z", "home_abbreviation": "NY", "away_abbreviation": "BOS",
        "home_score": 110, "away_score": 104, "status_type_completed": True, "status_period": 4,
        "venue_full_name": "Madison Square Garden",
    }
    base.update(extra)
    return base


def test_schedule_records_map_codes_phases_and_scores():
    games = parse_schedule_records([
        record(),
        record(game_id=2, season_type=3, status_period=5),
        record(game_id=3, status_type_completed=False, home_score=0, away_score=0),
        record(game_id=4, season_type=1),                                              # preseason
        record(game_id=5, season_type=5),                                              # play-in
        record(game_id=6, home_abbreviation="STARS", away_abbreviation="STRIPES"),     # All-Star
        record(game_id=7, season=2025),
    ], [2026])
    by_id = {g.game_id: g for g in games}
    assert set(by_id) == {"401800001", "2", "3"}
    first = by_id["401800001"]
    assert first.home_team == "NYK" and first.away_team == "BOS" and first.season_type == "REG"
    assert first.is_final and (first.home_score, first.away_score) == (110, 104) and not first.overtime
    assert first.kickoff_at == TIP and first.week == 16 and first.stadium == "Madison Square Garden"
    assert by_id["2"].season_type == "POST" and by_id["2"].overtime
    assert not by_id["3"].is_final and by_id["3"].home_score is None
    assert first.as_row(TIP)["game_date"] == "2026-01-12"


def test_quiet_stretch_checks_every_six_hours_in_season():
    now = TIP + timedelta(days=5)
    games = [game(away=104, home=110)]
    assert not run(now, games, with_stats=["401800001"], last_probe=now - timedelta(hours=3)).probe
    assert run(now, games, with_stats=["401800001"], last_probe=now - timedelta(hours=6)).probe


def test_offseason_checks_once_a_day():
    now = datetime(2026, 8, 10, 15, 0, tzinfo=UTC)
    games = [game(away=104, home=110)]
    assert not run(now, games, with_stats=["401800001"], last_probe=now - timedelta(hours=7)).probe
    assert run(now, games, with_stats=["401800001"], last_probe=now - timedelta(hours=21)).probe


def test_post_game_window_probes_every_thirty_minutes():
    now = TIP + timedelta(hours=4)
    assert run(now, [game()], last_probe=now - timedelta(minutes=29)).probe
    assert not run(now, [game()], last_probe=now - timedelta(minutes=10)).probe
    assert run(TIP + timedelta(hours=3), [game()], last_probe=TIP).probe        # the window opens at +3h
    assert not run(TIP + timedelta(hours=2, minutes=30), [game()], last_probe=TIP + timedelta(hours=2, minutes=20)).probe


def test_after_eight_hours_the_window_relaxes_to_hourly_until_thirty():
    games = [game(away=104, home=110)]
    stats = ["401800001"]
    now = TIP + timedelta(hours=10)
    assert not run(now, games, with_stats=stats, last_probe=now - timedelta(minutes=40)).probe
    assert run(now, games, with_stats=stats, last_probe=now - timedelta(minutes=60)).probe
    late = TIP + timedelta(hours=31)
    assert not run(late, games, with_stats=stats, last_probe=late - timedelta(hours=3)).probe   # back to the 6 hour check


def test_game_in_progress_does_not_probe_but_syncs_scores():
    now = TIP + timedelta(hours=1)
    decision = run(now, [game()], last_probe=now - timedelta(hours=2), last_sync=now - timedelta(minutes=15))
    assert not decision.probe
    assert decision.sync_games


def test_final_without_stats_keeps_backup_checks():
    games = [game(away=104, home=110)]
    late = TIP + timedelta(hours=20)
    assert run(late, games, last_probe=late - timedelta(minutes=60)).probe
    assert not run(late, games, with_stats=["401800001"], last_probe=late - timedelta(minutes=40)).probe
    very_late = TIP + timedelta(hours=60)
    assert not run(very_late, games, last_probe=very_late - timedelta(hours=2)).probe
    assert run(very_late, games, last_probe=very_late - timedelta(hours=3)).probe


def test_stats_backup_gives_up_after_five_days():
    games = [game(away=104, home=110)]
    now = TIP + timedelta(days=6)
    assert not run(now, games, last_probe=now - timedelta(hours=3)).probe


def test_empty_schedule_syncs_immediately_and_force_wins():
    assert run(TIP, [], last_sync=TIP).sync_games
    forced = decide(now=TIP, games=[], games_with_stats=set(), last_probe_at=TIP, last_sync_at=TIP, force=True)
    assert forced.probe and forced.sync_games


def test_cron_delay_tolerance():
    now = TIP + timedelta(hours=4)
    assert run(now, [game()], last_probe=now - timedelta(minutes=27)).probe


def test_next_check_lands_on_the_post_game_window():
    now = TIP + timedelta(hours=1)
    at = next_check_at(now=now, games=[game()], games_with_stats=set(), last_probe_at=now, last_sync_at=now)
    assert at - now <= timedelta(minutes=15)            # in progress: scores re-sync in 15 minutes
    at = next_check_at(now=now, games=[game(away=1, home=2)], games_with_stats={"401800001"},
                       last_probe_at=now, last_sync_at=now)
    assert TIP + timedelta(hours=3) - timedelta(minutes=5) <= at <= TIP + timedelta(hours=3, minutes=5)


def test_next_check_is_six_hours_when_quiet_in_season():
    now = TIP + timedelta(days=6)
    at = next_check_at(now=now, games=[game(away=1, home=2)], games_with_stats={"401800001"},
                       last_probe_at=now, last_sync_at=now)
    assert timedelta(hours=5) <= at - now <= timedelta(hours=6)
