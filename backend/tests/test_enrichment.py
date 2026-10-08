from datetime import datetime, timezone

import pandas as pd
import pytest

import ingest_enrichment as enrichment
import team_ratings as tr

NOW = datetime(2026, 1, 10, tzinfo=timezone.utc)


# ---- profiles ---------------------------------------------------------------------------

def test_height_and_weight_parse_both_shapes():
    assert enrichment.parse_height_inches(81.0) == 81
    assert enrichment.parse_height_inches("6' 9\"") == 81
    assert enrichment.parse_height_inches("7' 0\"") == 84
    assert enrichment.parse_height_inches(None) is None
    assert enrichment.parse_height_inches("tall") is None
    assert enrichment.parse_weight_pounds(250.0) == 250
    assert enrichment.parse_weight_pounds("250 lbs") == 250
    assert enrichment.parse_weight_pounds(None) is None


def test_profiles_come_from_player_core_with_rosters_as_the_fallback():
    core = pd.DataFrame([{
        "athlete_id": 1, "height": 81.0, "weight": 250.0, "date_of_birth": "1984-12-30T08:00Z",
        "jersey": "23", "experience_years": 23.0, "draft_year": 2003.0, "draft_round": 1.0, "draft_selection": 1.0,
    }, {
        "athlete_id": 2, "height": None, "weight": None, "date_of_birth": None, "jersey": None,
        "experience_years": None, "draft_year": None, "draft_round": None, "draft_selection": None,
    }])
    rosters = pd.DataFrame([{
        "athlete_id": 2, "height": "6' 3\"", "weight": "190 lbs", "date_of_birth": "2000-02-01T08:00Z",
        "jersey": "5", "experience_years": "2",
    }])
    drafts = pd.DataFrame([{"athlete_id": 1, "team_id": 13}])
    rows = {r["player_id"]: r for r in enrichment.build_player_profiles(
        2026, {1, 2, 3}, core, rosters, drafts, {13: "LAL"}, NOW,
    )}
    star = rows[1]
    assert (star["height_in"], star["weight_lb"], star["jersey"]) == (81, 250, 23)
    assert star["birth_date"] == "1984-12-30"
    assert (star["draft_year"], star["draft_round"], star["draft_pick"], star["draft_team"]) == (2003, 1, 1, "LAL")
    assert star["years_exp"] == 23 and star["rookie_season"] == 2004      # 2026 - 23 + 1: the 2003-04 season
    fallback = rows[2]
    assert (fallback["height_in"], fallback["weight_lb"], fallback["jersey"]) == (75, 190, 5)
    assert fallback["birth_date"] == "2000-02-01" and fallback["years_exp"] == 2
    unknown = rows[3]
    assert unknown["height_in"] is None and unknown["birth_date"] is None


def test_every_profile_row_has_every_column_and_no_nfl_data():
    [row] = enrichment.build_player_profiles(2026, {9}, pd.DataFrame(), pd.DataFrame(), pd.DataFrame(), {}, NOW)
    for column in enrichment.PROFILE_OPTIONAL_COLUMNS:
        assert column in row and row[column] is None
    assert row["college"] is None
    assert set(row) >= {"player_id", "season", "jersey", "birth_date", "height_in", "weight_lb", "years_exp",
                        "rookie_season", "draft_year", "draft_round", "draft_pick", "draft_team", "updated_at"}


# ---- ratings ----------------------------------------------------------------------------

def games_table(results):
    """results: (home, away, home_points, away_points) tuples, one game per tuple."""
    rows = []
    for n, (home, away, hp, ap) in enumerate(results):
        date = f"2025-11-{(n % 28) + 1:02d}"
        rows.append({"game_id": n, "game_date": date, "team": home, "opp": away, "home": True,
                     "points_for": hp, "points_against": ap, "poss": 100.0, "opp_poss": 100.0})
        rows.append({"game_id": n, "game_date": date, "team": away, "opp": home, "home": False,
                     "points_for": ap, "points_against": hp, "poss": 100.0, "opp_poss": 100.0})
    return pd.DataFrame(rows)


def test_ratings_are_per_100_possessions_and_centred_on_zero():
    table = tr.team_game_rows(games_table([("AAA", "BBB", 110, 100), ("BBB", "AAA", 100, 102), ("AAA", "CCC", 120, 100)]))
    ratings = tr.rate(table, full_schedule_weight=True)
    assert sum(r.rating for r in ratings.values()) == pytest.approx(0, abs=1e-6)
    assert ratings["AAA"].rating > 0 > ratings["CCC"].rating
    a = ratings["AAA"]
    assert a.rating == pytest.approx(a.offense + a.defense)
    assert (a.wins, a.losses, a.games, a.points_for, a.points_against) == (3, 0, 3, 110 + 102 + 120, 100 + 100 + 100)


def test_schedule_adjustment_credits_a_hard_schedule():
    # A and B both go 2-0 by 10; A did it against the league's best team, B against its worst.
    results = [("AAA", "STR", 105, 95), ("STR", "AAA", 95, 105),
               ("BBB", "WEK", 105, 95), ("WEK", "BBB", 95, 105),
               ("STR", "WEK", 130, 80), ("WEK", "STR", 80, 130), ("STR", "WEK", 130, 80), ("WEK", "STR", 80, 130)]
    ratings = tr.rate(tr.team_game_rows(games_table(results)), full_schedule_weight=True)
    assert ratings["AAA"].rating > ratings["BBB"].rating


def test_schedule_weight_phases_in_over_the_first_games():
    assert tr.sos_weight(0) == 0 and tr.sos_weight(10) == 0.5 and tr.sos_weight(20) == 1 and tr.sos_weight(60) == 1


def test_early_ratings_lean_on_last_season():
    prior = {"AAA": tr.TeamRating("AAA", 82, 8.0, 5.0, 3.0, 0, 0, 9000, 8200, 60, 22, 0)}
    table = tr.team_game_rows(games_table([("AAA", "BBB", 100, 100), ("BBB", "AAA", 100, 100)]))
    current = tr.rate(table, prior=prior)["AAA"]
    assert current.prior_weight == pytest.approx(20 / 22)
    assert 3.5 < current.rating < 4.5            # half of last year's +8, almost entirely
    assert tr.prior_weight(0) == 1 and tr.prior_weight(20) == 0.5
    start = tr.preseason(prior)["AAA"]
    assert start.rating == pytest.approx(4.0) and start.games == 0 and start.prior_weight == 1


def test_projection_adds_home_court_and_uses_a_normal_with_sigma_twelve():
    home = tr.TeamRating("H", 10, 5.0, 3.0, 2.0, 0, 0, 0, 0, 0, 0, 0)
    away = tr.TeamRating("A", 10, 1.0, 0.5, 0.5, 0, 0, 0, 0, 0, 0, 0)
    margin, win = tr.project(home, away)
    assert margin == pytest.approx(5.0 - 1.0 + 2.5)
    assert win == pytest.approx(0.7060, abs=0.001)         # Phi(6.5 / 12)
    neutral_margin, neutral_win = tr.project(home, away, neutral=True)
    assert neutral_margin == pytest.approx(4.0) and neutral_win < win
    even = tr.project(away, away, neutral=True)
    assert even == (0.0, 0.5)


def test_team_ratings_and_projections_rows():
    games = games_table([("AAA", "BBB", 110, 100), ("BBB", "AAA", 100, 105)])
    schedule = pd.DataFrame([
        {"game_id": 900, "game_date": pd.Timestamp("2026-01-12").date(), "season_type": 2, "status_type_completed": False,
         "home_abbreviation": "AAA", "away_abbreviation": "BBB", "neutral_site": False},
        {"game_id": 901, "game_date": pd.Timestamp("2025-11-01").date(), "season_type": 2, "status_type_completed": True,
         "home_abbreviation": "AAA", "away_abbreviation": "BBB", "neutral_site": False},
        {"game_id": 902, "game_date": pd.Timestamp("2026-02-13").date(), "season_type": 2, "status_type_completed": False,
         "home_abbreviation": "STARS", "away_abbreviation": "STRIPES", "neutral_site": True},
        {"game_id": 903, "game_date": pd.Timestamp("2026-04-10").date(), "season_type": 5, "status_type_completed": False,
         "home_abbreviation": "AAA", "away_abbreviation": "BBB", "neutral_site": False},
    ])
    team_rows, projections = enrichment.build_team_ratings(2026, games, pd.DataFrame(), schedule, NOW)
    assert [r["team"] for r in team_rows] == ["AAA", "BBB"] and team_rows[0]["rank"] == 1
    assert set(team_rows[0]) == {
        "season", "team", "rank", "games", "through_week", "rating", "offense", "defense", "schedule",
        "prior_weight", "wins", "losses", "ties", "points_for", "points_against", "updated_at",
    }
    # Only the unplayed regular-season game between rated clubs projects: not the
    # completed one, the All-Star squads (no rating) or the play-in game.
    assert [p["game_id"] for p in projections] == ["900"]
    projection = projections[0]
    assert projection["home_team"] == "AAA" and projection["away_team"] == "BBB" and projection["week"] == 16
    assert 0 < projection["home_win_prob"] < 1 and set(projection) == {
        "game_id", "season", "week", "home_team", "away_team", "home_margin", "home_win_prob", "updated_at",
    }


def test_a_season_before_opening_night_starts_from_last_years_ratings():
    prior = games_table([("NYK", "BOS", 120, 100), ("BOS", "NYK", 100, 110)])
    schedule = pd.DataFrame([{
        "game_id": 1, "game_date": pd.Timestamp("2026-10-21").date(), "season_type": 2,
        "status_type_completed": False, "home_abbreviation": "NY", "away_abbreviation": "BOS", "neutral_site": False,
    }])
    assert enrichment.team_game_table(pd.DataFrame()).empty
    team_rows, projections = enrichment.build_team_ratings(2027, pd.DataFrame(), prior, schedule, NOW)
    assert {r["team"] for r in team_rows} == {"NYK", "BOS"}
    assert all(r["games"] == 0 and r["prior_weight"] == 1 and r["through_week"] == 0 for r in team_rows)
    assert [p["game_id"] for p in projections] == ["1"] and projections[0]["home_team"] == "NYK"


def test_unplayed_games_in_the_past_are_not_projected():
    games = games_table([("AAA", "BBB", 110, 100), ("BBB", "AAA", 100, 105)])
    schedule = pd.DataFrame([
        {"game_id": n, "game_date": pd.Timestamp(day).date(), "season_type": 2, "status_type_completed": False,
         "home_abbreviation": "AAA", "away_abbreviation": "BBB", "neutral_site": False}
        for n, day in ((1, "2026-01-09"), (2, "2026-01-10"), (3, "2026-01-11"))
    ])
    _, projections = enrichment.build_team_ratings(2026, games, pd.DataFrame(), schedule, NOW)
    assert [p["game_id"] for p in projections] == ["2", "3"]
