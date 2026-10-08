import numpy as np
import pandas as pd
import polars as pl

import lineups

HOME, AWAY = 1, 2
HOME_FIVE = {11, 12, 13, 14, 15}
AWAY_FIVE = {21, 22, 23, 24, 25}
TEAM_OF = {**{p: HOME for p in HOME_FIVE | {16, 17, 18}}, **{p: AWAY for p in AWAY_FIVE | {26}}}


def event(period, kind, team, a1=None, a2=None, home=0, away=0, clock="10:00", a3=None):
    return (period, kind, team, a1, a2, a3, (home, away), clock)


def replay(events):
    return lineups.replay_game(events, TEAM_OF, {HOME: set(HOME_FIVE), AWAY: set(AWAY_FIVE)})


def small_game():
    return [
        event(1, "Jump Shot", HOME, 11, home=2, clock="11:00"),
        event(1, "Jump Shot", AWAY, 21, away=3, clock="10:00"),
        event(1, "Substitution", HOME, 16, 15, clock="9:00"),
        event(1, "Shooting Foul", AWAY, 22, clock="8:00"),
        event(1, "Free Throw - 1 of 2", HOME, 16, home=1, clock="8:00"),
        event(1, "Substitution", HOME, 17, 11, clock="8:00"),     # logged mid trip
        event(1, "Free Throw - 2 of 2", HOME, 16, home=1, clock="8:00"),
        event(1, "Jump Shot", HOME, 12, home=2, clock="7:00"),
    ]


def test_on_court_margin_by_hand():
    result = replay(small_game())
    margin = result.on_margin
    # Starters were on for +2 (11), -3 (21), +1, +1 and +2 (12). 11 leaves only
    # after the second free throw (the substitution waits for the trip to end).
    assert margin[11] == 2 - 3 + 1 + 1
    assert margin[12] == 2 - 3 + 1 + 1 + 2
    assert margin[13] == margin[14] == 3
    assert margin[15] == 2 - 3                      # replaced before the free throws
    assert margin[16] == 1 + 1 + 2                  # entered before them, both free throws count
    assert margin[17] == 2                          # entered after the trip, only the last basket
    for away in AWAY_FIVE:
        assert margin[away] == -2 + 3 - 1 - 1 - 2
    assert (result.final_home, result.final_away) == (6, 3)
    assert result.glitches == 0


def test_substitution_before_the_foul_happens_first():
    events = [
        event(1, "Substitution", HOME, 16, 15, clock="8:00"),     # before the foul: really first
        event(1, "Shooting Foul", AWAY, 22, clock="8:00"),
        event(1, "Free Throw - 1 of 2", HOME, 16, home=1, clock="8:00"),
        event(1, "Free Throw - 2 of 2", HOME, 16, home=1, clock="8:00"),
    ]
    margin = replay(events).on_margin
    assert margin[16] == 2 and margin.get(15, 0) == 0


def test_score_shown_on_a_substitution_row_belongs_to_the_old_lineup():
    events = [
        event(1, "Substitution", HOME, 16, 15, clock="5:00"),
        event(1, "Substitution", HOME, 17, 14, home=3, clock="5:00"),   # the three-pointer's points land here
    ]
    margin = replay(events).on_margin
    assert margin[15] == 3 and margin[14] == 3        # on the floor when it was scored
    assert margin.get(16, 0) == 0 and margin.get(17, 0) == 0


def test_a_substitution_for_a_player_not_on_the_floor_is_a_glitch():
    result = replay([event(1, "Substitution", HOME, 16, 18)])
    assert result.glitches == 1


def test_second_period_starters_are_inferred_from_first_events():
    events = [
        event(1, "Substitution", HOME, 16, 15, clock="1:00"),
        event(2, "Jump Shot", HOME, 11, home=2, clock="11:30"),
        event(2, "Jump Shot", AWAY, 21, away=2, clock="11:00"),
        event(2, "Substitution", HOME, 17, 12, clock="10:00"),   # 12 never acted but is replaced: a starter
        event(2, "Jump Shot", HOME, 17, home=2, clock="9:00"),
    ]
    starters = lineups.infer_period_starters(events[1:], TEAM_OF, {HOME: {11, 12, 13, 14, 16}, AWAY: set(AWAY_FIVE)})
    assert starters[HOME] == {11, 12, 13, 14, 16}
    assert starters[AWAY] == AWAY_FIVE


def test_silent_players_carry_over_from_the_previous_period():
    # Only three home players do anything in the period; the carried five fill in.
    events = [
        event(2, "Jump Shot", HOME, 11, home=2),
        event(2, "Defensive Rebound", HOME, 12),
        event(2, "Turnover", HOME, 13),
    ]
    starters = lineups.infer_period_starters(events, TEAM_OF, {HOME: {11, 12, 13, 14, 15}, AWAY: set(AWAY_FIVE)})
    assert starters[HOME] == {11, 12, 13, 14, 15}


def test_a_technical_foul_on_the_bench_does_not_make_him_a_starter():
    events = [
        event(2, "Technical Foul", HOME, 18, clock="12:00"),
        event(2, "Jump Shot", HOME, 11, home=2, clock="11:00"),
    ]
    starters = lineups.infer_period_starters(events, TEAM_OF, {HOME: set(HOME_FIVE), AWAY: set(AWAY_FIVE)})
    assert 18 not in starters[HOME]


def test_event_points_do_not_trust_missing_score_values():
    assert lineups.event_points("Free Throw - 1 of 2", True, 0, "A makes free throw 1 of 2") == 1
    assert lineups.event_points("Jump Shot", True, 3, "A makes 25-foot three point jumper") == 3
    assert lineups.event_points("Jump Shot", True, 0, "A makes 25-foot three point jumper") == 3
    assert lineups.event_points("Layup Shot", True, 0, "A makes layup") == 2
    assert lineups.event_points("Jump Shot", False, 0, "A misses jumper") == 0


# ---- whole-season reconstruction against a box score -----------------------------------

def _pbp(events, game_id=1):
    rows = []
    for number, (period, kind, team, a1, a2, a3, pts, clock) in enumerate(events, start=1):
        rows.append({
            "game_id": game_id, "game_play_number": number, "period_number": period,
            "type_text": kind, "team_id": team, "athlete_id_1": a1, "athlete_id_2": a2, "athlete_id_3": a3,
            "scoring_play": bool(pts[0] or pts[1]), "score_value": max(pts),
            "clock_display_value": clock, "text": kind, "home_score": 0, "away_score": 0,
            "home_team_id": HOME, "away_team_id": AWAY,
        })
    # Make the running score columns agree with the events.
    home = away = 0
    for row, ev in zip(rows, events):
        home += ev[6][0]
        away += ev[6][1]
        row["home_score"], row["away_score"] = home, away
    return pl.DataFrame(rows, schema_overrides={
        "athlete_id_1": pl.Int64, "athlete_id_2": pl.Int64, "athlete_id_3": pl.Int64,
    })


def _box(plus_minus):
    rows = []
    for athlete, team in TEAM_OF.items():
        if athlete in (18, 26):
            continue
        home = team == HOME
        rows.append({
            "game_id": 1, "athlete_id": athlete, "team_id": team,
            "starter": athlete in HOME_FIVE | AWAY_FIVE, "plus_minus": plus_minus.get(athlete, np.nan),
            "tm_score": 6 if home else 3, "opp_score": 3 if home else 6,
        })
    return pd.DataFrame(rows)


def _expected_box():
    margin = replay(small_game()).on_margin
    return {athlete: float(value) for athlete, value in margin.items()}


def test_reconstruction_validates_against_box_plus_minus():
    expected = _expected_box()
    result = lineups.reconstruct_season(_pbp(small_game()), _box(expected))
    assert result["valid"].all()
    assert lineups.validation_rate(result) == 1.0
    row = result[result["athlete_id"] == 16].iloc[0]
    assert row["on_margin"] == 4 and row["team_margin"] == 3


def test_one_wrong_plus_minus_fails_that_player_only():
    expected = _expected_box()
    expected[12] += 1
    result = lineups.reconstruct_season(_pbp(small_game()), _box(expected)).set_index("athlete_id")
    assert not result.loc[12, "valid"]
    assert result.drop(index=12)["valid"].all()
    assert 12 not in lineups.fully_validated_players(result.reset_index())


def test_a_final_score_that_disagrees_invalidates_the_whole_game():
    box = _box(_expected_box())
    box["tm_score"] = box["tm_score"] + 1
    result = lineups.reconstruct_season(_pbp(small_game()), box)
    assert not result["valid"].any()


def test_missing_box_plus_minus_is_never_validated():
    result = lineups.reconstruct_season(_pbp(small_game()), _box({}))
    assert not result["valid"].any()


def test_a_game_without_play_by_play_is_not_validated():
    result = lineups.reconstruct_season(_pbp(small_game(), game_id=999), _box(_expected_box()))
    assert not result["valid"].any()


def test_events_missing_from_the_feed_are_recovered_from_the_score_columns():
    frame = _pbp(small_game())
    # Drop the last basket's event but leave its score on the running columns.
    broken = frame.with_columns(
        pl.when(pl.col("game_play_number") == 8).then(False).otherwise(pl.col("scoring_play")).alias("scoring_play")
    )
    points = lineups.row_points(broken.sort("game_play_number"), HOME, AWAY)
    assert sum(p[0] for p in points) == 6      # the missing 2 points are added back
