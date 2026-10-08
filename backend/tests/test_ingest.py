import math
import os
from datetime import datetime, timezone
from unittest.mock import patch

import numpy as np
import pandas as pd
import pytest

import ingest

NOW = datetime(2026, 7, 20, tzinfo=timezone.utc)


# --------------------------------------------------------------------------- #
# Season resolution
# --------------------------------------------------------------------------- #
def test_resolve_season_cli_wins():
    assert ingest.resolve_season(2022) == 2022


def test_resolve_season_env():
    with patch.dict(os.environ, {"STATCAST_SEASON": "2021"}, clear=False):
        assert ingest.resolve_season(None) == 2021


def test_resolve_season_out_of_range_falls_back():
    assert ingest.resolve_season(1990) == ingest.DEFAULT_SEASON
    assert ingest.resolve_season(ingest.DEFAULT_SEASON + 5) == ingest.DEFAULT_SEASON
    with patch.dict(os.environ, {"STATCAST_SEASON": "abc"}, clear=False):
        assert ingest.resolve_season(None) == ingest.DEFAULT_SEASON


def test_default_season_follows_the_year_it_ends():
    from datetime import date
    import hoopr
    assert ingest.DEFAULT_SEASON == hoopr.season_for_date(date.today())
    assert ingest.OLDEST_SUPPORTED_SEASON == 2003


# --------------------------------------------------------------------------- #
# Contract: ids, labels, categories, standard_stats
# --------------------------------------------------------------------------- #
def test_categories_and_metric_counts_match_the_contract():
    assert list(ingest.METRIC_DEFS) == ["Scoring", "Shooting", "Playmaking", "Rebounding", "Defense", "Impact"]
    assert [len(v) for v in ingest.METRIC_DEFS.values()] == [11, 9, 8, 6, 8, 6]


def test_labels_and_ids_are_the_contract_strings():
    labels = {m.id: m.label for m in ingest.ALL_METRICS}
    assert labels["pts_per_100"] == "Pts/100"
    assert labels["usg_pct"] == "USG%"
    assert labels["three_par"] == "3PT Rate"
    assert labels["ftr"] == "FT Rate"
    assert labels["short_mid_freq"] == "Short Mid Freq"
    assert labels["nc3_fg"] == "Non-Corner 3%"
    assert labels["ast_fg_pct"] == "Assisted FG%"
    assert labels["on_net"] == "On-Court +/-"
    assert labels["on_off"] == "On-Off"
    assert labels["plus_minus"] == "+/-"
    assert len({m.id for m in ingest.ALL_METRICS}) == len(ingest.ALL_METRICS)


def test_inverted_metrics_are_exactly_the_lower_is_better_ones():
    assert {m.id for m in ingest.ALL_METRICS if m.inverted} == {"tov_pct", "tov_pg", "foul_per_100"}


def test_attempt_gates_match_the_contract():
    gates = {m.id: m.gate for m in ingest.ALL_METRICS if m.gate}
    assert gates == {
        "three_pct": ("fg3a", 50), "ft_pct": ("fta", 50), "rim_fg": ("rim_fga", 40),
        "short_mid_fg": ("smid_fga", 40), "long_mid_fg": ("lmid_fga", 40),
        "corner3_fg": ("c3_fga", 30), "nc3_fg": ("nc3_fga", 50),
    }


# --------------------------------------------------------------------------- #
# Value formatting
# --------------------------------------------------------------------------- #
def test_format_value():
    assert ingest.format_value(1502, "comma") == "1,502"
    assert ingest.format_value(27, "int") == "27"
    assert ingest.format_value(61.24, "pct1") == "61.2%"
    assert ingest.format_value(28.44, "dec1") == "28.4"
    assert ingest.format_value(0.176, "dec2") == "0.18"
    assert ingest.format_value(6.3, "signed1") == "+6.3"
    assert ingest.format_value(-1.2, "signed1") == "-1.2"
    assert ingest.format_value(142, "signed_comma") == "+142"
    assert ingest.format_value(-1035, "signed_comma") == "-1,035"
    assert ingest.format_value(None, "int") == ""
    assert ingest.format_value(float("nan"), "comma") == ""


# --------------------------------------------------------------------------- #
# Percentiles: midpoint rank, inversion, ties
# --------------------------------------------------------------------------- #
def test_rank_percentiles_higher_is_better():
    pct = ingest.rank_percentiles(pd.Series({1: 10.0, 2: 20.0, 3: 30.0, 4: 40.0}), inverted=False)
    assert pct[4] > pct[3] > pct[2] > pct[1]
    assert pct[4] == 88 and pct[1] == 13        # (below + 0.5) / 4 of the pool


def test_rank_percentiles_inverted_flips_the_order():
    # Fewer turnovers rank higher.
    pct = ingest.rank_percentiles(pd.Series({1: 1.0, 2: 2.0, 3: 3.0, 4: 4.0}), inverted=True)
    assert pct[1] > pct[2] > pct[3] > pct[4]
    assert pct[1] == 88 and pct[4] == 13


def test_inversion_mirrors_the_plain_ranking():
    values = pd.Series({1: 3.0, 2: 9.0, 3: 5.0, 4: 7.0, 5: 1.0})
    up = ingest.rank_percentiles(values, inverted=False)
    down = ingest.rank_percentiles(values, inverted=True)
    for player in values.index:
        assert up[player] + down[player] == pytest.approx(100, abs=1)


def test_ties_share_the_midpoint_and_extremes_stay_on_the_scale():
    pct = ingest.rank_percentiles(pd.Series({1: 5.0, 2: 5.0, 3: 5.0, 4: 9.0}), inverted=False)
    assert pct[1] == pct[2] == pct[3] == 38     # (0 + 1.5) / 4
    values = pd.Series({i: float(i) for i in range(1, 301)})
    scale = ingest.rank_percentiles(values, inverted=False)
    assert scale[300] == 100 and scale[1] == 1  # clamped to 1..100


def test_rank_percentiles_ignores_nan():
    pct = ingest.rank_percentiles(pd.Series({1: 5.0, 2: float("nan"), 3: 15.0}), inverted=False)
    assert 2 not in pct and pct[3] > pct[1]


def test_unqualified_player_is_placed_against_the_pool_without_joining_it():
    pool = np.array([10.0, 20.0, 30.0, 40.0])
    assert ingest.midpoint_percentile(pool, 25.0, inverted=False) == 50
    assert ingest.midpoint_percentile(pool, 5.0, inverted=False) == 1
    assert ingest.midpoint_percentile(pool, 99.0, inverted=False) == 100
    assert ingest.midpoint_percentile(np.array([]), 1.0, inverted=False) == 50


# --------------------------------------------------------------------------- #
# Qualification and proration
# --------------------------------------------------------------------------- #
def test_full_season_bar_is_870_minutes_and_20_games():
    assert ingest.qualifies({"min": 870, "g": 20}, "REG")
    assert not ingest.qualifies({"min": 869, "g": 40}, "REG")
    assert not ingest.qualifies({"min": 2000, "g": 19}, "REG")


def test_postseason_and_career_bars():
    assert ingest.qualifies({"min": 60, "g": 3}, "POST")
    assert not ingest.qualifies({"min": 59, "g": 3}, "POST")
    assert not ingest.qualifies({"min": 100, "g": 2}, "POST")
    assert ingest.qualifies({"min": 8000, "g": 300}, "REG", career=True)
    assert not ingest.qualifies({"min": 7999, "g": 300}, "REG", career=True)
    assert ingest.qualifies({"min": 500, "g": 20}, "POST", career=True)
    assert not ingest.qualifies({"min": 499, "g": 20}, "POST", career=True)


def test_scale_is_median_team_games_over_82_floored_at_a_tenth():
    assert ingest.qualification_scale([20] * 30) == pytest.approx(20 / 82)
    assert ingest.qualification_scale([21, 20, 20, 20, 19]) == pytest.approx(20 / 82)   # median club, not the busiest
    assert ingest.qualification_scale([2] * 30) == 0.1                                 # floor
    assert ingest.qualification_scale([82] * 30) == 1.0
    assert ingest.qualification_scale([90] * 30) == 1.0                                # capped
    assert ingest.qualification_scale([]) == 1.0


def test_live_bar_is_prorated_by_how_much_of_the_season_is_played():
    scale = ingest.qualification_scale([20] * 30)
    # 870 * 20/82 = 212.2 -> 213 minutes; 20 * 20/82 = 4.9 -> 5 games.
    assert ingest.qualifies({"min": 213, "g": 5}, "REG", scale=scale)
    assert not ingest.qualifies({"min": 212, "g": 5}, "REG", scale=scale)
    assert not ingest.qualifies({"min": 213, "g": 4}, "REG", scale=scale)
    # The postseason bar ignores the season's proration.
    assert ingest.qualifies({"min": 60, "g": 3}, "POST", scale=0.1)


def test_attempt_gates_prorate_like_the_minutes_bar():
    three = ingest.METRIC_BY_ID["three_pct"]
    assert ingest.gate_threshold(50) == 50
    assert ingest.gate_threshold(50, scale=0.5) == 25
    assert ingest.gate_threshold(50, scale=0.01) == 1
    assert ingest.gate_threshold(50, season_type="POST") == 10
    assert ingest.gate_threshold(50, career=True) == 200
    assert ingest.gate_met({"fg3a": 50}, three, "REG", False, 1.0)
    assert not ingest.gate_met({"fg3a": 49}, three, "REG", False, 1.0)
    assert ingest.gate_met({"fg3a": 25}, three, "REG", False, 0.5)


# --------------------------------------------------------------------------- #
# Aggregation from per-game rows
# --------------------------------------------------------------------------- #
def test_aggregate_sums_games_and_derives_rates_from_sums(games_df):
    agg = ingest.aggregate_player_games(games_df, "REG")
    guard = agg.loc[1]
    assert guard["g"] == 30 and guard["gs"] == 30 and guard["min"] == 30 * 36
    assert guard["pts"] == 30 * 22
    assert guard["ppg"] == pytest.approx(22.0)
    assert guard["ts_pct"] == pytest.approx(100 * 22 / (2 * (18 + 0.44 * 6)))
    assert guard["efg_pct"] == pytest.approx(100 * (8 + 1) / 18)
    assert guard["usg_pct"] == pytest.approx(27.72695, abs=1e-4)
    assert guard["ast_pct"] == pytest.approx(31.81818, abs=1e-4)
    assert guard["dreb_pct"] == pytest.approx(18.60465, abs=1e-4)
    assert guard["stl_pct"] == pytest.approx(2.77778, abs=1e-4)
    assert guard["blk_pct"] == pytest.approx(2.29885, abs=1e-4)
    assert guard["pts_per_100"] == pytest.approx(100 * 22 / (103.68 * 36 / 48))
    assert guard["tov_pct"] == pytest.approx(100 * 3 / (18 + 0.44 * 6 + 3))
    assert guard["three_par"] == pytest.approx(100 * 6 / 18)
    assert guard["on_net"] == pytest.approx(100 * 5 / (103.68 * 36 / 48))


def test_traits_come_from_the_latest_game(games_df):
    agg = ingest.aggregate_player_games(games_df, "REG")
    assert agg.loc[1, "player_type"] == "g" and agg.loc[2, "player_type"] == "f" and agg.loc[3, "player_type"] == "c"
    assert agg.loc[3, "gs"] == 15
    assert agg.loc[1, "position"] == "G" and agg.loc[3, "position"] == "C"
    assert agg.loc[1, "team"] == "NYK"


def test_a_traded_player_is_one_row_with_the_latest_team(games_df):
    traded = games_df.copy()
    late = traded["athlete_id"].eq(1) & (traded["game_date"] >= "2025-11-20")
    traded.loc[late, ["team", "opp"]] = ["BOS", "NYK"]
    agg = ingest.aggregate_player_games(traded, "REG")
    assert len(agg) == 3 and agg.loc[1, "team"] == "BOS" and agg.loc[1, "g"] == 30


def test_phases_are_aggregated_separately(games_df):
    playoffs = games_df.copy()
    playoffs["season_type"] = "POST"
    both = pd.concat([games_df, playoffs.head(6)])
    assert ingest.aggregate_player_games(both, "POST")["g"].sum() == 6
    assert ingest.aggregate_player_games(both, "REG")["g"].sum() == 90


def test_unavailable_sources_leave_metrics_empty_not_zero(games_df):
    agg = ingest.aggregate_player_games(games_df, "REG")
    for metric_id in ("rim_freq", "rim_fg", "ast_fg_pct", "on_off"):
        assert agg[metric_id].isna().all()
    no_pm = games_df.assign(plus_minus=np.nan)
    agg = ingest.aggregate_player_games(no_pm, "REG")
    assert agg["on_net"].isna().all() and agg["plus_minus"].isna().all()


def test_zone_metrics_when_the_shots_feed_covers_the_games(games_df):
    zoned = games_df.copy()
    zoned.loc[:, ["rim_fga", "rim_fgm", "smid_fga", "smid_fgm", "lmid_fga", "lmid_fgm",
                  "c3_fga", "c3_fgm", "nc3_fga", "nc3_fgm", "ast_fgm"]] = [8, 5, 4, 2, 2, 1, 1, 0, 3, 1, 4]
    zoned["shot_fga"] = 18
    row = ingest.aggregate_player_games(zoned, "REG").loc[1]
    assert row["rim_freq"] == pytest.approx(100 * 8 / 18)
    assert row["rim_fg"] == pytest.approx(100 * 5 / 8)
    assert row["corner3_fg"] == pytest.approx(0.0)
    assert row["nc3_fg"] == pytest.approx(100 / 3)
    assert row["ast_fg_pct"] == pytest.approx(100 * 4 / 9)          # 4 assisted of 9 tracked makes
    freq = row["rim_freq"] + row["short_mid_freq"] + row["long_mid_freq"] + 100 * (1 + 3) / 18
    assert freq == pytest.approx(100)


def test_on_off_needs_95_percent_of_games_validated(games_df):
    assert ingest.ON_OFF_MIN_VALID_SHARE == 0.95
    replayed = games_df.copy()
    replayed["on_margin"] = 5.0
    replayed["off_margin"] = -5.0
    replayed["off_poss"] = 103.68 * 4 / 5
    full = ingest.aggregate_player_games(replayed, "REG")
    on = 100 * 5 / (103.68 * 36 / 48)
    off = 100 * -5 / (103.68 * 4 / 5)
    assert full.loc[1, "on_off"] == pytest.approx(on - off)
    # One failed game of 30 (96.7% validated): still published, over the 29 that validated.
    replayed.loc[replayed.index[0], "on_margin"] = np.nan
    one_miss = ingest.aggregate_player_games(replayed, "REG")
    assert one_miss.loc[1, "on_off"] == pytest.approx(on - off)
    # Two failed games (93.3%): omitted for that player only.
    first_two = replayed.index[replayed["athlete_id"] == 1][:2]
    replayed.loc[first_two, "on_margin"] = np.nan
    two_miss = ingest.aggregate_player_games(replayed, "REG")
    assert math.isnan(two_miss.loc[1, "on_off"])
    assert not math.isnan(two_miss.loc[2, "on_off"])


# --------------------------------------------------------------------------- #
# Snapshot rows
# --------------------------------------------------------------------------- #
def snapshot_rows(games, live=False, scale=1.0, season_type="REG"):
    agg = ingest.aggregate_player_games(games, season_type)
    return ingest.build_snapshot_rows(agg, 2026, NOW, season_type, qual_scale=scale, live=live)


def test_snapshot_shape_and_ordering(games_df):
    rows = snapshot_rows(games_df)
    assert [r["id"] for r in rows] == [1, 2, 3]
    guard = rows[0]
    assert guard["player_type"] == "g" and guard["season"] == 2026 and guard["season_type"] == "REG"
    assert guard["source"] == "hoopR" and guard["games"] == [] and guard["handedness"] == ""
    assert guard["image_url"].endswith("/players/full/1.png")
    categories = list(dict.fromkeys(m["category"] for m in guard["metrics"]))
    assert categories == ["Scoring", "Playmaking", "Rebounding", "Defense", "Impact"]   # no zones in this sample
    first = guard["metrics"][0]
    assert set(first) == {"id", "label", "value", "percentile", "category"}      # past seasons carry no qualified flag
    assert first["id"] == "scoring-1-pts_per_100"


def test_standard_stats_labels_and_order(games_df):
    stats = snapshot_rows(games_df)[0]["standard_stats"]
    assert [s["label"] for s in stats] == ingest.STANDARD_STAT_LABELS
    assert [s["label"] for s in stats] == [
        "G", "GS", "MPG", "PPG", "RPG", "APG", "SPG", "BPG", "FG", "3P", "FT", "TOV", "PF", "+/-", "MIN",
    ]
    by_label = {s["label"]: s["value"] for s in stats}
    assert by_label["G"] == "30" and by_label["MPG"] == "36.0" and by_label["PPG"] == "22.0"
    assert by_label["FG"] == "240/540" and by_label["3P"] == "60/180" and by_label["FT"] == "120/180"
    assert by_label["TOV"] == "90" and by_label["+/-"] == "+150" and by_label["MIN"] == "1,080"
    assert stats[0]["id"] == "std-G"


def test_plus_minus_is_omitted_from_standard_stats_before_it_existed(games_df):
    stats = snapshot_rows(games_df.assign(plus_minus=np.nan))[0]["standard_stats"]
    assert "+/-" not in [s["label"] for s in stats]


def test_percentiles_are_within_the_player_type_cohort():
    rows = []
    from conftest import player_game
    for n in range(25):
        rows.append(player_game(1, 2000 + n, "2025-12-01", pos="C", player_type="c", reb=14))
        rows.append(player_game(2, 2000 + n, "2025-12-01", pos="G", player_type="g", reb=3))
    snapshots = {r["id"]: r for r in snapshot_rows(pd.DataFrame(rows))}
    center = next(m for m in snapshots[1]["metrics"] if m["id"].endswith("-rpg"))
    guard = next(m for m in snapshots[2]["metrics"] if m["id"].endswith("-rpg"))
    # Each is the only player in his cohort, so each sits at the middle of it, not 100 vs 1.
    assert center["value"] == "14.0" and guard["value"] == "3.0"
    assert center["percentile"] == guard["percentile"] == 50


def test_inverted_metric_ranks_fewer_turnovers_higher():
    from conftest import player_game
    rows = []
    for pid, tov in ((1, 1), (2, 3), (3, 5)):
        for n in range(25):
            rows.append(player_game(pid, 3000 + n, "2025-12-01", tov=tov))
    snapshots = {r["id"]: r for r in snapshot_rows(pd.DataFrame(rows))}
    pct = {pid: next(m for m in s["metrics"] if m["id"].endswith("-tov_pg"))["percentile"] for pid, s in snapshots.items()}
    assert pct[1] > pct[2] > pct[3]
    plain = {pid: next(m for m in s["metrics"] if m["id"].endswith("-ppg"))["percentile"] for pid, s in snapshots.items()}
    assert plain[1] == plain[2] == plain[3]


def test_past_seasons_only_ship_qualified_players_and_gated_metrics():
    from conftest import player_game
    rows = []
    for n in range(25):                                                                 # clears 870 min / 20 G
        rows.append(player_game(1, 4000 + n, "2025-12-01", min=36.0, fg3a=1, fta=1))   # 25 3PA, 25 FTA: under the gates
    for n in range(10):                                                                 # 360 minutes
        rows.append(player_game(2, 4000 + n, "2025-12-02", min=36.0))
    snapshots = {r["id"]: r for r in snapshot_rows(pd.DataFrame(rows))}
    assert set(snapshots) == {1}
    labels = {m["label"] for m in snapshots[1]["metrics"]}
    assert "3P%" not in labels and "FT%" not in labels and "FG%" in labels


def test_live_season_ships_everyone_with_qualified_flags_against_the_qualified_pool():
    from conftest import player_game
    rows = []
    for n in range(25):
        rows.append(player_game(1, 5000 + n, "2025-12-01", pts=20, min=36.0))
    for n in range(2):
        rows.append(player_game(2, 5000 + n, "2025-12-01", pts=50, min=36.0))          # hot, but 2 games
    scale = ingest.qualification_scale([22] * 30)
    snapshots = {r["id"]: r for r in snapshot_rows(pd.DataFrame(rows), live=True, scale=scale)}
    assert set(snapshots) == {1, 2}
    ppg = {pid: next(m for m in s["metrics"] if m["id"].endswith("-ppg")) for pid, s in snapshots.items()}
    assert ppg[1]["qualified"] is True and ppg[2]["qualified"] is False
    assert ppg[2]["percentile"] == 100          # placed against the qualified pool
    assert ppg[1]["percentile"] == 50           # the lone qualifier is not pushed down by the hot newcomer
    # 150 three-point attempts clear the prorated gate (ceil(50 * 0.268) = 14); a
    # newcomer's 12 do not, and he is unqualified anyway.
    assert [m for m in snapshots[1]["metrics"] if m["label"] == "3P%"][0]["qualified"] is True
    assert all(m["qualified"] is False for m in snapshots[2]["metrics"])
