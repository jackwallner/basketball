"""
Shot-zone classification from the hoopR shots parquet.

ESPN logs every shot with court-centred coordinates (``coordinate_x`` along the
length, ``coordinate_y`` across, in feet). From those this module derives the
Cleaning the Glass style zones the Shooting category is built on:

* rim: closer than 4 ft to the basket
* short mid: 4 to 14 ft, not a three
* long mid: 14 ft and out, not a three
* corner 3 (|y| >= 22 and within 9 ft of the rim's depth) / non-corner 3

Three things make this less obvious than it looks, each covered by tests:

1. **The basket is not where the diagram says.** On a court centred at the
   origin the rim sits at x = +/-41.75, but ESPN's frame puts it nearer 39.75 in
   recent seasons and drifts between seasons (41.6 in 2003, 40.9 in 2011, 39.8
   in 2025). Distances measured from 41.75 would push roughly a third of all
   rim finishes into "short mid". The rim is therefore calibrated once per
   season from the centroid of dunks and layups, and the build fails if that
   centroid is implausible.
2. **The shots feed does not say which misses were threes.** Made threes carry
   ``score_value == 3``; a missed three looks like any other miss. The
   play-by-play row for the same shot says ``points_attempted`` (or "three
   point" in its text), so misses are joined to it. Only a shot with no
   play-by-play match falls back to distance from the calibrated rim.
3. **Free throws live in the same table.** Anything whose ``type_text`` starts
   with "Free Throw" is not a field-goal attempt and is dropped.
"""

from __future__ import annotations

import logging
import math
from typing import Optional

import polars as pl

logger = logging.getLogger(__name__)

BASKET_X_NOMINAL = 41.75
# The contract asks for 1.5 ft of agreement with the nominal rim. ESPN's frame
# disagrees by up to 2 ft (the rim reads 39.75 in 2018-2026), so the check is
# widened to 3 ft: wide enough for every season observed, narrow enough to catch
# a feed whose coordinates are scaled, mirrored or shifted by something larger.
CALIBRATION_TOLERANCE = 3.0
CALIBRATION_LATERAL_TOLERANCE = 1.5
CALIBRATION_MIN_SHOTS = 500

RIM_RADIUS = 4.0
SHORT_MID_END = 14.0
CORNER_Y = 22.0
# The straight corner segment of the three-point line ends where the 23.75 ft
# arc crosses |y| = 22, which is sqrt(23.75^2 - 22^2) = 8.96 ft out from the rim.
# The contract wrote this as "inside the last 14 feet of the court length", which
# is the same thing measured from the baseline (the rim is 5.25 ft off it); its
# "41.75 - 14" shorthand measures 14 ft from the RIM instead and sweeps sideline
# wing threes into the corner (31% of all threes, against the ~26% real share).
CORNER_DEPTH = 9.0
# Distance fallback for a shot with no play-by-play match: the corner line is
# 22 ft from the rim and the arc 23.75 ft; ESPN's one-foot coordinate grid puts
# true arc threes as close as 23.0.
CORNER_THREE_MIN_DISTANCE = 22.0
ARC_THREE_MIN_DISTANCE = 23.0

ZONES = ("rim", "smid", "lmid", "c3", "nc3")
THREE_TEXT_PATTERN = r"(?i)three[ -]?point|3[ -]?pt|three[ -]?pointer"


class CalibrationError(RuntimeError):
    """The shots feed's basket location is implausible; do not publish zones."""


def field_goal_shots(shots: pl.DataFrame) -> pl.DataFrame:
    """Field-goal attempts only: no free throws, no placeholder rows."""
    return shots.filter(
        ~pl.col("type_text").fill_null("").str.starts_with("Free Throw")
        & (pl.col("type_text").fill_null("") != "No Shot (Default Shot)")
        & pl.col("athlete_id_1").is_not_null()
        & pl.col("coordinate_x").is_not_null()
        & pl.col("coordinate_y").is_not_null()
    )


# ESPN's frame has held the rim at 39.7-40.1 ft since 2018. The first days of a
# new season have too few close shots to calibrate from, so a recent season may
# borrow this until it has enough (a few game days).
RECENT_RIM_X = 39.8
RECENT_RIM_FIRST_SEASON = 2018


def calibrate_basket(field_goals: pl.DataFrame, fallback: Optional[float] = None) -> float:
    """The season's rim distance from centre court, from dunks and layups.

    Both ends of the court are folded onto one by taking ``abs(x)``. Raises
    ``CalibrationError`` when there are too few close-range shots to trust (and
    no ``fallback`` to borrow), the centroid is off-centre laterally, or it is
    further than ``CALIBRATION_TOLERANCE`` from where a regulation court puts
    the rim.
    """
    close = field_goals.filter(pl.col("type_text").str.contains(r"(?i)dunk|layup"))
    if close.height < CALIBRATION_MIN_SHOTS:
        if fallback is not None:
            logger.warning("Only %d dunks and layups; borrowing the recent rim at %.2f ft", close.height, fallback)
            return fallback
        raise CalibrationError(f"only {close.height} dunks and layups to calibrate the rim")
    rim_x = float(close.select(pl.col("coordinate_x").abs().mean()).item())
    rim_y = float(close.select(pl.col("coordinate_y").mean()).item())
    logger.info("Rim calibration: centroid (%.2f, %.2f) from %d dunks/layups", rim_x, rim_y, close.height)
    if abs(rim_y) > CALIBRATION_LATERAL_TOLERANCE:
        raise CalibrationError(f"rim centroid is {rim_y:.2f} ft off the court's centre line")
    if abs(rim_x - BASKET_X_NOMINAL) > CALIBRATION_TOLERANCE:
        raise CalibrationError(
            f"rim centroid x={rim_x:.2f} is more than {CALIBRATION_TOLERANCE} ft from {BASKET_X_NOMINAL}"
        )
    return rim_x


def distance_to_rim(x: float, y: float, rim_x: float) -> float:
    """Feet to the nearer basket (the court is folded with ``abs(x)``)."""
    return math.hypot(abs(x) - rim_x, y)


def is_three_by_distance(x: float, y: float, rim_x: float) -> bool:
    """Distance fallback for a shot whose play-by-play row is missing."""
    distance = distance_to_rim(x, y, rim_x)
    if abs(y) >= CORNER_Y:
        return distance >= CORNER_THREE_MIN_DISTANCE
    return distance >= ARC_THREE_MIN_DISTANCE


def classify_zone(x: float, y: float, is_three: bool, rim_x: float) -> str:
    """One of ``ZONES`` for a field-goal attempt (scalar twin of ``with_zones``)."""
    if is_three:
        in_corner_depth = rim_x - abs(x) <= CORNER_DEPTH
        return "c3" if abs(y) >= CORNER_Y and in_corner_depth else "nc3"
    distance = distance_to_rim(x, y, rim_x)
    if distance < RIM_RADIUS:
        return "rim"
    return "smid" if distance < SHORT_MID_END else "lmid"


def three_lookup(pbp: pl.DataFrame) -> pl.DataFrame:
    """Per-shot three-point flag read from play-by-play rows.

    Keyed on (game, period, clock, shooter, shot type), which the shots feed and
    the play-by-play share. Uses ``points_attempted`` when the season's file has
    it and the row text ("three point jumper", "3PT") when it does not.
    """
    shooting = pbp.filter(pl.col("shooting_play").fill_null(False))
    if "points_attempted" in shooting.columns:
        flag = pl.col("points_attempted") == 3
    else:
        flag = pl.col("text").fill_null("").str.contains(THREE_TEXT_PATTERN)
    return (
        shooting.select(
            "game_id", "period_number", "clock_display_value", "athlete_id_1", "type_id",
            flag.alias("pbp_three"),
        )
        .group_by("game_id", "period_number", "clock_display_value", "athlete_id_1", "type_id")
        .agg(pl.col("pbp_three").max())
    )


def with_zones(field_goals: pl.DataFrame, rim_x: float, pbp: Optional[pl.DataFrame] = None) -> pl.DataFrame:
    """Add ``dist``, ``is_three`` and ``zone`` columns to the field-goal frame."""
    frame = field_goals
    if pbp is not None and not pbp.is_empty():
        frame = frame.join(
            three_lookup(pbp),
            on=["game_id", "period_number", "clock_display_value", "athlete_id_1", "type_id"],
            how="left",
        )
    else:
        frame = frame.with_columns(pl.lit(None, dtype=pl.Boolean).alias("pbp_three"))

    abs_x = pl.col("coordinate_x").abs()
    abs_y = pl.col("coordinate_y").abs()
    dist = ((abs_x - rim_x) ** 2 + abs_y ** 2).sqrt()
    by_distance = (
        pl.when(abs_y >= CORNER_Y)
        .then(dist >= CORNER_THREE_MIN_DISTANCE)
        .otherwise(dist >= ARC_THREE_MIN_DISTANCE)
    )
    made = pl.col("scoring_play").fill_null(False)
    is_three = (
        pl.when(made).then(pl.col("score_value") == 3)
        .when(pl.col("pbp_three").is_not_null()).then(pl.col("pbp_three"))
        .otherwise(by_distance)
    )
    framed = frame.with_columns(dist.alias("dist"), is_three.alias("is_three"))
    zone = (
        pl.when(pl.col("is_three") & (abs_y >= CORNER_Y) & ((rim_x - abs_x) <= CORNER_DEPTH)).then(pl.lit("c3"))
        .when(pl.col("is_three")).then(pl.lit("nc3"))
        .when(pl.col("dist") < RIM_RADIUS).then(pl.lit("rim"))
        .when(pl.col("dist") < SHORT_MID_END).then(pl.lit("smid"))
        .otherwise(pl.lit("lmid"))
    )
    return framed.with_columns(zone.alias("zone"))


def zone_counts(zoned: pl.DataFrame) -> pl.DataFrame:
    """Per player-game made/attempted counts by zone, plus assisted makes.

    ``shot_fga`` is the tracked total (sum of the five zones); frequencies are
    taken against it so a player's zone shares always sum to 100%, even in the
    rare game where the shots feed and the box score disagree by a shot.
    """
    made = pl.col("scoring_play").fill_null(False)
    aggs: list[pl.Expr] = []
    for zone in ZONES:
        in_zone = pl.col("zone") == zone
        aggs.append(in_zone.sum().cast(pl.Int64).alias(f"{zone}_fga"))
        aggs.append((in_zone & made).sum().cast(pl.Int64).alias(f"{zone}_fgm"))
    aggs.append((made & pl.col("athlete_id_2").is_not_null()).sum().cast(pl.Int64).alias("ast_fgm"))
    aggs.append(pl.len().cast(pl.Int64).alias("shot_fga"))
    return (
        zoned.group_by("game_id", "athlete_id_1")
        .agg(aggs)
        .rename({"athlete_id_1": "athlete_id"})
    )
