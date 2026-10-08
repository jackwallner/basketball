"""
Who was on the floor, rebuilt from hoopR play-by-play, for On-Off.

On-Off is the one headline number the box score cannot give: the team's margin
with a player on the court minus its margin with him off it. The play-by-play
carries every substitution (``athlete_id_1`` enters, ``athlete_id_2`` leaves)
and a running score, so the floor can be replayed:

* Period 1 starts with the box score's starters.
* A later period starts with whoever played in it before being substituted for,
  inferred from the first event each player records ("a player is on the floor
  at the opening tip of the period if his first appearance is as an actor or as
  the man being replaced"). Anyone silent for the whole period carries over from
  the previous period's final five.
* Every score change is credited to the ten players on the court.

The replay is only trusted where it can be checked. The box score's
``plus_minus`` is exactly the margin while a player was on the court, so a
player-game validates when the replay reproduces it (and the game's final score
matches the box). ``validation_rate`` over a season decides whether On-Off is
published at all (97% bar); a player's number is published when at least ``ON_OFF_MIN_VALID_SHARE`` (95%) of his games validate, computed over those games
to appear. A wrong On-Off is worse than a missing one.

Technical fouls, ejections and timeouts are ignored when inferring starters:
a bench player can be hit with a technical at any point, which would otherwise
read as "he started the period".
"""

from __future__ import annotations

import logging
import re
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any, Iterable, Optional

import pandas as pd
import polars as pl

logger = logging.getLogger(__name__)

TEAM_SIZE = 5
VALIDATION_BAR = 0.97
SUBSTITUTION = "Substitution"
IGNORED_FOR_INFERENCE = ("Technical", "Ejection", "Timeout", "End Period", "End Game")

Event = tuple  # (period, type_text, team_id, a1, a2, a3, (home points, away points), clock)
FREE_THROW_PATTERN = re.compile(r"^Free Throw.*?(\d+) of (\d+)$")


@dataclass
class GameReplay:
    """Outcome of replaying one game."""

    on_margin: dict[int, int] = field(default_factory=dict)
    ever_on: set[int] = field(default_factory=set)
    final_home: int = 0
    final_away: int = 0
    glitches: int = 0
    trace: Optional[list] = None  # (period, clock, type_text, swing, home five, away five), debugging only
    notes: list = field(default_factory=list)  # what went wrong, for the validation log


def _is_substitution(event: Event) -> bool:
    return event[1] == SUBSTITUTION


def free_throw_in_progress(type_text: Optional[str]) -> Optional[bool]:
    """True after a free throw with another to come, False after the last one.

    ``None`` for any other event. A free throw with no "k of n" suffix (a
    technical) is a one-shot sequence.
    """
    text = type_text or ""
    if not text.startswith("Free Throw"):
        return None
    match = FREE_THROW_PATTERN.match(text)
    return bool(match) and int(match.group(1)) < int(match.group(2))


# What a substitution logged inside a free-throw stoppage does to the points of
# that trip. Keyed by (whose sub, where): "shoot" = the shooting team's own sub,
# "foul" = the fouling team's; "early" = logged before the foul itself, "pre" =
# logged between the foul and the first free throw, "mid" = logged between free
# throws. "I" applies it where it is logged, "D" holds it until the last free
# throw, "P" applies it before the first one. Tested against the 2025-26 box
# scores, holding every sub in a trip until its last free throw is far better
# than any alternative (a quarter to a third of player-games fail otherwise).
SUB_POLICY: dict[tuple[str, str, str], str] = {}


def _sub_action(role: str, where: str, kind: str, early: str = "I") -> str:
    """What to do with a substitution logged inside a free-throw stoppage.

    Subs logged between the foul and the last free throw always wait for the
    trip to end. Subs logged before the foul are the one thing the feed's eras
    disagree on: since about 2019 they really did happen first ("I"), earlier
    ones are ordered the same way as the rest of the trip ("D"). ``early`` is
    chosen per season by whichever matches more box plus/minus.
    """
    return SUB_POLICY.get((role, where, kind)) or (early if where == "early" else "D")


DEFER_ALL_STOPPAGES = False


def _stoppage_plan(
    events: list[Event], team_of: dict[int, int], early: str = "I",
) -> dict[int, tuple[str, int, int]]:
    """For each substitution inside a free-throw stoppage: (action, first FT, last FT).

    A stoppage is a run of events sharing one clock reading; timeouts and
    delay-of-game calls can sit between a substitution and the free throws.
    Substitutions in stoppages without free throws are absent (applied as logged).
    """
    plan: dict[int, tuple[str, int, int]] = {}
    n = len(events)
    start = 0
    while start < n:
        end = start
        while end < n and events[end][7] == events[start][7]:
            end += 1
        throws = [i for i in range(start, end) if free_throw_in_progress(events[i][1]) is not None]
        if not throws and DEFER_ALL_STOPPAGES:
            throws = [end - 1]
        if throws:
            first, last = throws[0], throws[-1]
            shooter_team = team_of.get(events[first][3]) or events[first][2]
            for i in range(start, end):
                if not _is_substitution(events[i]) or i > last:
                    continue
                sub_team = team_of.get(events[i][3]) or team_of.get(events[i][4]) or events[i][2]
                role = "shoot" if sub_team == shooter_team else "foul"
                fouls = [t for t in range(start, first) if "Foul" in (events[t][1] or "")]
                where = "mid" if i > first else "early" if (not fouls or i < fouls[0]) else "pre"
                kind = "tech" if any("Technical" in (events[t][1] or "") for t in throws) else str(min(len(throws), 3))
                plan[i] = (_sub_action(role, where, kind, early), first, last)
        start = end
    return plan


def _counts_as_appearance(event: Event) -> bool:
    type_text = event[1] or ""
    return not any(marker in type_text for marker in IGNORED_FOR_INFERENCE)


def infer_period_starters(
    events: Iterable[Event],
    team_of: dict[int, int],
    carry: dict[int, set[int]],
) -> dict[int, set[int]]:
    """Each team's five on the floor when the period began.

    ``carry`` is the previous period's closing lineup, used only to fill a
    spot when a player never recorded an event or a substitution all period.
    """
    status: dict[int, str] = {}
    starters: dict[int, list[int]] = defaultdict(list)
    for event in events:
        _, _, team_id, a1, a2, a3, _, _ = event
        if _is_substitution(event):
            if a2 is not None and a2 not in status and a2 in team_of:
                starters[team_of[a2]].append(a2)
            if a2 is not None:
                status[a2] = "off"
            if a1 is not None:
                status[a1] = "on"
        elif _counts_as_appearance(event):
            for athlete in (a1, a2, a3):
                if athlete is not None and athlete not in status and athlete in team_of:
                    starters[team_of[athlete]].append(athlete)
                    status[athlete] = "on"

    result: dict[int, set[int]] = {}
    for team, previous in carry.items():
        chosen = list(dict.fromkeys(starters.get(team, [])))
        if len(chosen) > TEAM_SIZE:
            chosen = [p for p in chosen if p in previous] + [p for p in chosen if p not in previous]
            chosen = chosen[:TEAM_SIZE]
        for athlete in previous:
            if len(chosen) >= TEAM_SIZE:
                break
            if athlete not in status and athlete not in chosen:
                chosen.append(athlete)
        result[team] = set(chosen)
    return result


def _apply_substitution(
    lineup: dict[int, set[int]],
    event: Event,
    team_of: dict[int, int],
    replay: GameReplay,
) -> None:
    _, _, team_id, a1, a2, _, _, _ = event
    side = team_of.get(a1) or team_of.get(a2) or team_id
    if side not in lineup:
        replay.glitches += 1
        return
    if a2 is not None:
        if a2 in lineup[side]:
            lineup[side].discard(a2)
        else:
            replay.glitches += 1
            replay.notes.append(("leaver not on floor", event[0], event[7], a2))
    if a1 is not None:
        if a1 in lineup[side]:
            replay.notes.append(("entrant already on floor", event[0], event[7], a1))
        lineup[side].add(a1)
        replay.ever_on.add(a1)


def replay_game(
    events: list[Event],
    team_of: dict[int, int],
    box_starters: dict[int, set[int]],
    trace: bool = False,
    early: str = "I",
) -> GameReplay:
    """Replay one game's events into per-player on-court point margins."""
    replay = GameReplay(trace=[] if trace else None)
    teams = list(box_starters)
    if len(teams) != 2:
        replay.glitches += 1
        return replay
    home, away = teams[0], teams[1]  # caller orders (home, away)
    lineup = {team: set(players) for team, players in box_starters.items()}
    margin: dict[int, int] = defaultdict(int)

    periods: dict[int, list[Event]] = defaultdict(list)
    for event in events:
        periods[event[0]].append(event)

    for period in sorted(periods):
        evs = periods[period]
        if period == 1 and all(len(lineup[t]) == TEAM_SIZE for t in teams):
            replay.ever_on.update(lineup[home] | lineup[away])
        else:
            lineup = infer_period_starters(evs, team_of, lineup)
            for team in teams:
                lineup.setdefault(team, set())
            replay.ever_on.update(lineup[home] | lineup[away])
            if any(len(lineup[t]) != TEAM_SIZE for t in teams):
                replay.glitches += 1
                replay.notes.append(("period start lineup size", period, "", [len(lineup[t]) for t in teams]))

        plan = _stoppage_plan(evs, team_of, early)
        retro = {index: [i for i, (action, first, _) in plan.items() if action == "P" and first == index] for index in {v[1] for v in plan.values()}}
        release: dict[int, list[int]] = defaultdict(list)
        for i, (action, _, last) in plan.items():
            if action == "D":
                release[last].append(i)
        before_subs: Optional[dict[int, set[int]]] = None
        for index, event in enumerate(evs):
            _, type_text, team_id, a1, _, _, points, _ = event
            is_sub = _is_substitution(event)
            for i in retro.get(index, []):
                _apply_substitution(lineup, evs[i], team_of, replay)
            if is_sub and before_subs is None:
                before_subs = {team: set(players) for team, players in lineup.items()}
            if points[0] or points[1]:
                on_floor = before_subs if is_sub and before_subs is not None else lineup
                swing = points[0] - points[1]
                if replay.trace is not None:
                    replay.trace.append((period, event[7], type_text, swing, frozenset(on_floor[home]), frozenset(on_floor[away])))
                for athlete in on_floor[home]:
                    margin[athlete] += swing
                for athlete in on_floor[away]:
                    margin[athlete] -= swing
                replay.final_home += points[0]
                replay.final_away += points[1]
            if is_sub:
                action = plan.get(index, ("I", 0, 0))[0]
                if action == "I":
                    _apply_substitution(lineup, event, team_of, replay)
                continue
            before_subs = None
            for i in release.get(index, []):
                _apply_substitution(lineup, evs[i], team_of, replay)

    replay.on_margin = dict(margin)
    return replay


EVENT_COLUMNS = [
    "game_id", "game_play_number", "period_number", "type_text", "team_id",
    "athlete_id_1", "athlete_id_2", "athlete_id_3", "scoring_play", "score_value",
    "clock_display_value", "text", "home_score", "away_score", "home_team_id", "away_team_id",
]


def event_points(type_text: Optional[str], scoring: Any, score_value: Any, text: Optional[str]) -> int:
    """Points an event put on the board.

    The feed's running score columns are unreliable before 2020 (they run
    backwards between rows), and in some seasons ``score_value`` is 0 for made
    free throws, so points come from the event itself: a made free throw is 1,
    a made field goal is its ``score_value`` when that is 2 or 3, otherwise 3
    if the description says three-pointer, otherwise 2.
    """
    if not scoring:
        return 0
    if (type_text or "").startswith("Free Throw"):
        return 1
    if score_value in (2, 3):
        return int(score_value)
    return 3 if re.search(r"(?i)three", text or "") else 2


def row_points(frame: pl.DataFrame, home_id: int, away_id: int) -> list[tuple[int, int]]:
    """(home points, away points) per row.

    Points come from the scoring events themselves (the running score columns
    run backwards between rows before 2020, and ``score_value`` is 0 for made
    free throws in some seasons). Some seasons also drop made field goals from
    the event list while the score columns still carry them, so a shortfall
    between the events and the score columns that never closes is added back at
    the row where it opened.
    """
    n = frame.height
    home = [0] * n
    away = [0] * n
    for i, (team, scoring, value, kind, text) in enumerate(zip(
        frame["team_id"], frame["scoring_play"], frame["score_value"], frame["type_text"], frame["text"],
    )):
        made = event_points(kind, scoring, value, text)
        if team == home_id:
            home[i] = made
        elif team == away_id:
            away[i] = made

    for points, column in ((home, frame["home_score"]), (away, frame["away_score"])):
        cumulative = high_water = 0
        shortfall = [0] * n
        for i, shown in enumerate(column):
            cumulative += points[i]
            high_water = max(high_water, shown or 0)
            shortfall[i] = max(0, high_water - cumulative)
        # A shortfall that later closes was the score column running ahead of
        # its event; only the part that never closes is a missing event.
        floor = 0
        for i in range(n - 1, -1, -1):
            floor = shortfall[i] if i == n - 1 else min(floor, shortfall[i])
            shortfall[i] = floor
        previous = 0
        for i in range(n):
            if shortfall[i] > previous:
                points[i] += shortfall[i] - previous
                previous = shortfall[i]
    return list(zip(home, away))


def _opt(value: Any) -> Optional[int]:
    return None if value is None else int(value)


def reconstruct_season(
    pbp: pl.DataFrame,
    player_games: pd.DataFrame,
    early_actions: tuple[str, ...] = ("I", "D"),
) -> pd.DataFrame:
    """Replay every game and validate it against the box score.

    ``player_games`` needs ``game_id``, ``athlete_id``, ``team_id``,
    ``starter``, ``plus_minus`` (NaN when the box score has none), ``tm_score``
    and ``opp_score`` (the team's final score and its opponent's). Returns one
    row per player-game: ``on_margin`` (NaN when the player was never found on
    the floor), ``valid`` and ``team_margin``.

    The season is replayed once per ``early_actions`` convention (see
    ``_sub_action``) and the one that reproduces more of the box plus/minus is
    kept: one convention per season, never per game or per player.
    """
    events_by_game = {
        key[0] if isinstance(key, tuple) else key: frame
        for key, frame in pbp.select(EVENT_COLUMNS).sort("game_id", "game_play_number")
        .partition_by("game_id", as_dict=True)
        .items()
    }
    prepared = []
    for game_id, game_players in player_games.groupby("game_id", sort=False):
        frame = events_by_game.get(int(game_id))
        if frame is None or frame.is_empty():
            prepared.append((int(game_id), game_players, None))
            continue
        home_id = int(frame["home_team_id"][0])
        away_id = int(frame["away_team_id"][0])
        team_of = {int(a): int(t) for a, t in zip(game_players["athlete_id"], game_players["team_id"])}
        starters = {
            home_id: {int(a) for a in game_players.loc[(game_players["team_id"] == home_id) & game_players["starter"], "athlete_id"]},
            away_id: {int(a) for a in game_players.loc[(game_players["team_id"] == away_id) & game_players["starter"], "athlete_id"]},
        }
        events = [
            (int(p), t, _opt(tid), _opt(a1), _opt(a2), _opt(a3), pts, clock)
            for p, t, tid, a1, a2, a3, pts, clock in zip(
                frame["period_number"], frame["type_text"], frame["team_id"],
                frame["athlete_id_1"], frame["athlete_id_2"], frame["athlete_id_3"],
                row_points(frame, home_id, away_id), frame["clock_display_value"],
            )
        ]
        prepared.append((int(game_id), game_players, (events, team_of, starters, home_id)))

    best: Optional[pd.DataFrame] = None
    for early in early_actions:
        result = _replay_rows(prepared, early)
        if best is None or result["valid"].sum() > best["valid"].sum():
            best = result
    return best


def _replay_rows(prepared: list, early: str) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    for game_id, game_players, game in prepared:
        if game is None:
            rows.extend(_missing_rows(game_players))
            continue
        events, team_of, starters, home_id = game
        replay = replay_game(events, team_of, starters, early=early)
        scores_agree = _scores_agree(game_players, home_id, replay)
        for row in game_players.itertuples(index=False):
            on = replay.on_margin.get(int(row.athlete_id), 0) if int(row.athlete_id) in replay.ever_on else None
            plus_minus = row.plus_minus
            valid = (
                scores_agree
                and on is not None
                and not pd.isna(plus_minus)
                and int(on) == int(plus_minus)
            )
            rows.append({
                "game_id": game_id,
                "athlete_id": int(row.athlete_id),
                "on_margin": float(on) if on is not None else float("nan"),
                "valid": bool(valid),
                "team_margin": float(row.tm_score - row.opp_score),
                "glitches": replay.glitches,
                "scores_agree": scores_agree,
            })
    return pd.DataFrame(
        rows, columns=["game_id", "athlete_id", "on_margin", "valid", "team_margin", "glitches", "scores_agree"],
    )


def _scores_agree(game_players: pd.DataFrame, home_id: int, replay: GameReplay) -> bool:
    for team_id, tm_score in zip(game_players["team_id"], game_players["tm_score"]):
        expected = replay.final_home if int(team_id) == home_id else replay.final_away
        if int(tm_score) != expected:
            return False
    return True


def _missing_rows(game_players: pd.DataFrame) -> list[dict[str, Any]]:
    return [
        {
            "game_id": int(row.game_id),
            "athlete_id": int(row.athlete_id),
            "on_margin": float("nan"),
            "valid": False,
            "team_margin": float(row.tm_score - row.opp_score),
            "glitches": -1,
            "scores_agree": False,
        }
        for row in game_players.itertuples(index=False)
    ]


def validation_rate(replayed: pd.DataFrame) -> float:
    """Share of player-games whose replay matched the box plus/minus."""
    return float(replayed["valid"].mean()) if len(replayed) else 0.0


def fully_validated_players(replayed: pd.DataFrame) -> set[int]:
    """Players none of whose games failed validation."""
    bad = replayed.loc[~replayed["valid"], "athlete_id"]
    return set(replayed["athlete_id"]) - set(bad)
