import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

TEAM_CONTEXT = {
    "tm_min": 240, "tm_fgm": 40, "tm_fga": 90, "tm_fta": 22, "tm_tov": 14,
    "tm_oreb": 10, "tm_dreb": 34, "tm_reb": 44, "team_poss": 103.68,
    "opp_poss": 96, "opp_fga": 88, "opp_fg3a": 30, "opp_oreb": 9, "opp_dreb": 33, "opp_reb": 42,
}


def player_game(athlete_id: int, game_id: int, date: str, **overrides) -> dict:
    """One player-game row shaped like ``playergames.build_player_games`` output."""
    row = {
        "game_id": game_id, "season_type": "REG", "game_date": date, "athlete_id": athlete_id,
        "name": f"Player {athlete_id}", "team_id": 1, "team": "NYK", "opp_team_id": 2, "opp": "BOS",
        "min": 36.0, "pts": 22, "fgm": 8, "fga": 18, "fg3m": 2, "fg3a": 6, "ftm": 4, "fta": 6,
        "oreb": 2, "dreb": 6, "reb": 8, "ast": 7, "stl": 2, "blk": 1, "tov": 3, "pf": 2,
        "plus_minus": 5.0, "starter": True, "pos": "G", "player_type": "g", "home": True,
        "tm_score": 110, "opp_score": 100,
        "rim_fga": np.nan, "rim_fgm": np.nan, "smid_fga": np.nan, "smid_fgm": np.nan,
        "lmid_fga": np.nan, "lmid_fgm": np.nan, "c3_fga": np.nan, "c3_fgm": np.nan,
        "nc3_fga": np.nan, "nc3_fgm": np.nan, "ast_fgm": np.nan, "shot_fga": np.nan,
        "on_margin": np.nan, "off_margin": np.nan, "off_poss": np.nan,
        **TEAM_CONTEXT,
    }
    row["player_poss"] = row["team_poss"] * row["min"] / (row["tm_min"] / 5)
    row.update(overrides)
    return row


@pytest.fixture(autouse=True)
def _isolate_environment(monkeypatch):
    """A stale backend/.env (load_dotenv runs at import) must not steer the tests."""
    monkeypatch.delenv("STATCAST_SEASON", raising=False)
    monkeypatch.delenv("BASKETBALL_SUPABASE_HOST", raising=False)


@pytest.fixture
def games_df() -> pd.DataFrame:
    """Three players over a season-shaped sample: a guard, a forward and a center."""
    rows = []
    for n in range(30):
        date = f"2025-11-{(n % 28) + 1:02d}"
        rows.append(player_game(1, 1000 + n, date, name="Guard One", pos="G", player_type="g"))
        rows.append(player_game(2, 1000 + n, date, name="Forward Two", pos="F", player_type="f",
                                pts=14, fgm=6, fga=12, fg3m=0, fg3a=1, ftm=2, fta=3, oreb=3, dreb=7,
                                reb=10, ast=2, stl=1, blk=2, min=32.0, plus_minus=-2.0))
        rows.append(player_game(3, 1000 + n, date, name="Center Three", pos="C", player_type="c",
                                pts=10, fgm=5, fga=7, fg3m=0, fg3a=0, ftm=0, fta=2, oreb=4, dreb=8,
                                reb=12, ast=1, stl=0, blk=3, min=30.0, starter=n % 2 == 0,
                                plus_minus=1.0))
    return pd.DataFrame(rows)
