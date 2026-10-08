from datetime import datetime, timezone

import numpy as np
import pandas as pd
import pytest

import ingest
import rollup_all_time as career
from conftest import player_game

NOW = datetime(2026, 7, 20, tzinfo=timezone.utc)


def season_games(athlete, season_label, n, **overrides):
    return pd.DataFrame([
        player_game(athlete, season_label * 1000 + g, f"{season_label}-12-{(g % 28) + 1:02d}", **overrides)
        for g in range(n)
    ])


def part(frame, phase="REG"):
    return career.season_part(frame, phase)


def test_career_sums_components_across_seasons():
    young = season_games(1, 2004, 40, min=20.0, pts=10, fga=10, fta=2, fgm=4, fg3m=0)
    prime = season_games(1, 2008, 80, min=38.0, pts=30, fga=22, fta=8, fgm=11, fg3m=2)
    agg = career.combine_parts([part(young), part(prime)])
    row = agg.loc[1]
    assert row["g"] == 120 and row["min"] == 40 * 20 + 80 * 38
    assert row["pts"] == 40 * 10 + 80 * 30
    # A ratio of career sums: the 40-game rookie year weighs 40 games, not half the career.
    assert row["ts_pct"] == pytest.approx(100 * (400 + 2400) / (2 * ((400 / 10 * 0 + 40 * (10 + 0.88)) + 80 * (22 + 0.44 * 8))))
    assert row["ppg"] == pytest.approx((400 + 2400) / 120)


def test_career_identity_is_the_newest_season():
    older = season_games(1, 2004, 10, team="SEA", pos="G", player_type="g", name="Old Name")
    newer = season_games(1, 2009, 10, team="OKC", pos="F", player_type="f", name="New Name")
    agg = career.combine_parts([part(older), part(newer)])
    assert agg.loc[1, "team"] == "OKC" and agg.loc[1, "player_type"] == "f" and agg.loc[1, "name"] == "New Name"


def test_seasons_a_player_missed_do_not_drop_him():
    only_early = season_games(2, 2004, 70)
    other = season_games(3, 2010, 70)
    agg = career.combine_parts([part(only_early), part(other)])
    assert set(agg.index) == {2, 3}


def test_career_zone_metrics_pool_only_the_tracked_seasons():
    untracked = season_games(1, 2003, 50)
    tracked = season_games(1, 2012, 50, rim_fga=8, rim_fgm=5, smid_fga=4, smid_fgm=2, lmid_fga=2,
                           lmid_fgm=1, c3_fga=1, c3_fgm=0, nc3_fga=3, nc3_fgm=1, ast_fgm=4, shot_fga=18)
    row = career.combine_parts([part(untracked), part(tracked)]).loc[1]
    assert row["rim_freq"] == pytest.approx(100 * 8 / 18)       # a share of tracked shots only
    assert row["rim_fg"] == pytest.approx(62.5)


def test_career_on_off_is_never_published():
    games = season_games(1, 2020, 70, on_margin=5.0, off_margin=-3.0, off_poss=26.0)
    agg = career.combine_parts([part(games)])
    assert np.isnan(agg.loc[1, "on_off"])


def test_career_on_court_plus_minus_uses_only_games_that_have_it():
    no_pm = season_games(1, 2005, 40, plus_minus=np.nan)
    with_pm = season_games(1, 2012, 40, plus_minus=4.0)
    row = career.combine_parts([part(no_pm), part(with_pm)]).loc[1]
    assert row["plus_minus"] == 160
    assert row["on_net"] == pytest.approx(100 * 160 / (103.68 * 36 / 48 * 40))


def test_career_bars_are_far_above_a_season():
    rows = []
    for season in range(2004, 2008):                    # four full seasons of 82 games, 36 minutes
        rows.append(season_games(1, season, 82))
    for season in range(2004, 2006):                    # a two-season player
        rows.append(season_games(2, season, 82))
    agg = career.combine_parts([part(pd.concat(rows))] if False else [part(f) for f in rows])
    snapshots = {r["id"]: r for r in ingest.build_snapshot_rows(agg, ingest.ALL_TIME_SEASON, NOW, "REG")}
    # 4 * 82 * 36 = 11,808 minutes clears 8,000; 2 * 82 * 36 = 5,904 does not.
    assert set(snapshots) == {1}
    assert snapshots[1]["season"] == 0 and snapshots[1]["season_type"] == "REG"


def test_career_playoffs_have_their_own_low_bar():
    games = pd.concat([
        season_games(1, 2010, 10, season_type="POST", min=40.0),     # 400 minutes
        season_games(1, 2012, 4, season_type="POST", min=40.0),      # 160 more: 560 clears 500
        season_games(2, 2010, 10, season_type="POST", min=40.0),     # 400: does not
    ])
    agg = career.combine_parts([part(games, "POST")])
    snapshots = {r["id"] for r in ingest.build_snapshot_rows(agg, ingest.ALL_TIME_SEASON, NOW, "POST")}
    assert snapshots == {1}


def test_an_empty_phase_has_no_part():
    assert part(season_games(1, 2010, 5), "POST") is None
    assert career.combine_parts([]).empty
