# NBA Conversion Contract (shared between backend + iOS)

App: **Hardwood StatScout** (product name), App Store name **Basketball Next: StatScout**.
NBA analytics/percentiles app forked from the Gridiron (NFL) StatScout codebase, which was
itself forked from the Baseball Savant StatScout app. Same architecture: Python ingest on
GitHub Actions, Supabase (PostgREST), SwiftUI iOS app reading `player_snapshots`,
`player_game_logs`, `player_recent_form`, `games`, `game_details`, `team_ratings`.

The web destination we mimic is **Cleaning the Glass**: percentile-ranked rate stats within
a position cohort, points per 100 possessions, shooting split into frequency and accuracy
by zone, rebounding and defense as shares of opportunities, on/off impact. Vocabulary and
abbreviations follow CTG and Basketball-Reference, never ESPN's.

## Supabase
- Dedicated "Basketball" project (same conventions as Football). Creds in
  `~/.basketball_credentials` (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
  SUPABASE_DB_PASSWORD, plus the Management PAT path). Schema via `supabase/migrations/`.
- Tables keep the Football shapes exactly so the Swift decoders and the publish RPC carry
  over unchanged: `player_snapshots` (PK id, season, season_type), `player_game_logs`
  (PK player_id, season, season_type, game_date, player_type), `player_recent_form`
  (PK player_id, season, season_type, player_type, window_weeks), `games`,
  `game_details`, `player_profiles`, `team_ratings`, `game_projections`,
  `data_refresh_state` / `data_refresh_runs` / `data_refresh_status`.

## Data source: hoopR-nba-data (sportsdataverse, ESPN mirror)
Static parquet on GitHub, no key, cloud-IP friendly, rebuilt nightly (last commit checked
2026-10-08 03:52 UTC). Base URL
`https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/main/nba/`:

| Asset | Path | Use |
| --- | --- | --- |
| Player box scores | `player_box/parquet/player_box_<season>.parquet` | every counting stat, minutes, plus/minus, starter, headshot, position (G/F/C), team colours |
| Team box scores | `team_box/parquet/team_box_<season>.parquet` | team and opponent totals per game (possessions, rebounds, four factors) |
| Shots | `shots/parquet/shots_<season>.parquet` | per-shot coordinates and type, for zone frequency and accuracy |
| Play by play | `pbp/parquet/play_by_play_<season>.parquet` | score series, substitutions (on/off), clutch plays |
| Schedule | `schedules/parquet/nba_schedule_<season>.parquet` | `games` table, status, tip-off times |
| Rosters / player core / draft | `rosters/`, `player_core/`, `draft/` | profiles: height, weight, birth date, draft |
| Standings | `standings/` | team records |

Seasons available: 2002 through 2027. **A hoopR season is named for the year it ends**:
`2026` is the 2025-26 season and `2027` is 2026-27 (tips off 2026-10-20 or so). The
app stores the hoopR integer and renders it as `"2025-26"` via `SeasonLabel`. Season
rule: `season = year + 1 if month >= 10 else year` (October 2026 resolves to 2027).
`STATCAST_SEASON` env var name is kept for workflow compatibility and overrides.

`season_type`: 2 = regular season (`REG`), 3 = postseason (`POST`), 5 = play-in. Play-in
games are **excluded** from both phases (they are neither). 1 = preseason, excluded.
All-Star rows (team abbreviations `STARS`, `STRIPES`, `WORLD`, `GIANNIS`, `LEBRON` etc.,
i.e. any team not in the 30-team table) are dropped.

Row counts for a scale check: 2025-26 regular season is 32,294 player-game rows, 2,460
team-game rows (1,230 games), about 300k shots.

## Player IDs
ESPN `athlete_id` (int) is the DB `id` directly. Headshots are
`https://a.espncdn.com/i/headshots/nba/players/full/<id>.png` (the app does not render
them; `image_url` is still written).

## Teams
30 teams. ESPN abbreviations are normalised to the fan-standard codes:
`GS->GSW`, `NO->NOP`, `NY->NYK`, `SA->SAS`, `UTAH->UTA`, `WSH->WAS`. Everything else is
already standard: ATL BKN BOS CHA CHI CLE DAL DEN DET HOU IND LAC LAL MEM MIA MIL MIN OKC
ORL PHI PHX POR SAC TOR. Older seasons carry relocated or renamed teams (SEA, NJN, NOH,
NOK, CHA Bobcats, VAN); keep the historical code the row carried, but map ESPN's current
short forms as above.

## player_type (snapshot + game log rows)
ESPN box scores carry only `G`, `F`, `C` (2025-26: 281 guards, 221 forwards, 86 centers;
a handful of rows say PG/SF/PF, fold those into G/F/F). `player_type` is lowercase
`"g"`, `"f"`, `"c"`, `"unknown"` for a null position. **Percentiles are ranked within
(season, season_type, player_type, category)**, the Cleaning the Glass convention, so a
center's rebounding is judged against centers. One snapshot row per player, season and
season type. A traded player gets one row for the season with `team` = the last team he
played for, and the standard line notes `"3 TM"` style is NOT used; the team column is
just the latest.

## Possessions and playing time
- Team possessions per game: `poss = FGA - OREB + TOV + 0.44 * FTA` (team box).
- Team minutes per game: `240 + 25 * overtimes` (from max period in pbp, or infer from
  the sum of player minutes / 5).
- Player on-court possessions per game: `player_poss = team_poss * MP / (team_minutes / 5)`.
- Season `player_poss` is the sum over games. Every per-100 rate is `stat / player_poss * 100`.

## Metric categories (jsonb `metrics[].category`, exact strings)
Every player qualifies for every category; there is no position-to-category split. The
Swift registry (`BasketballMetricRegistry`) mirrors this table exactly: labels are
identical strings, `kind` is `advanced` or `traditional`, lower-is-better metrics are
marked (inverted).

### `"Scoring"`
| id | label | kind | formula | notes |
| --- | --- | --- | --- | --- |
| pts_per_100 | Pts/100 | advanced | PTS / player_poss × 100 | |
| usg_pct | USG% | advanced | 100 × (FGA + 0.44 FTA + TOV) × (TmMP/5) / (MP × (TmFGA + 0.44 TmFTA + TmTOV)) | summed per game numerators and denominators |
| ts_pct | TS% | advanced | PTS / (2 × (FGA + 0.44 FTA)) | |
| efg_pct | eFG% | advanced | (FGM + 0.5 × 3PM) / FGA | |
| ftr | FT Rate | advanced | FTA / FGA | CTG "FTA/FGA" |
| three_par | 3PT Rate | advanced | 3PA / FGA | CTG "3PA/FGA" |
| ppg | PPG | traditional | PTS / G | |
| fg_pct | FG% | traditional | FGM / FGA | |
| three_pct | 3P% | traditional | 3PM / 3PA | needs ≥ 50 3PA (prorated) else unranked |
| ft_pct | FT% | traditional | FTM / FTA | needs ≥ 50 FTA (prorated) else unranked |
| three_pm | 3PM | traditional | season total | |

### `"Shooting"` (all advanced; from the shots parquet)
Zones from court-centred coordinates (`coordinate_x` in [-47, 47] feet along the length,
`coordinate_y` in [-25, 25] across; baskets at x = ±41.75, y = 0; distance = distance to
the nearer basket). Free throws (`type_text` starts with "Free Throw") are not shots.
Three-pointers are shots whose `type_text`, `text` or `score_value` say three (made
threes have `score_value == 3`; missed threes carry "three point" / "3PT" in the text,
otherwise fall back to distance ≥ 22 ft in the corners / 23.75 ft elsewhere). Corner
three: three with |x| ≥ 41.75 − 14 (i.e. inside the last 14 feet of the court length) and
|y| ≥ 22. Calibrate the basket location once by taking the centroid of dunks and layups
and assert it lands within 1.5 ft of (±41.75, 0); log and fail the build otherwise.

| id | label | formula | notes |
| --- | --- | --- | --- |
| rim_freq | Rim Freq | rim FGA / FGA | rim = distance < 4 ft |
| rim_fg | Rim FG% | rim FGM / rim FGA | ≥ 40 rim FGA |
| short_mid_freq | Short Mid Freq | 4-14 ft, non-three FGA / FGA | |
| short_mid_fg | Short Mid FG% | | ≥ 40 FGA in zone |
| long_mid_freq | Long Mid Freq | ≥ 14 ft, non-three FGA / FGA | |
| long_mid_fg | Long Mid FG% | | ≥ 40 FGA in zone |
| corner3_fg | Corner 3% | corner 3PM / corner 3PA | ≥ 30 attempts |
| nc3_fg | Non-Corner 3% | | ≥ 50 attempts |
| ast_fg_pct | Assisted FG% | share of made FGs that were assisted (`athlete_id_2` set on the made shot) | lower = more self-created; NOT inverted, just descriptive, ranked higher-is-better |

Frequencies are ranked higher-is-better (a high rim frequency is the CTG framing: "gets to
the rim"); accuracy likewise. Zone accuracy below its attempt gate is omitted (not
written as 0) for seasons before the live one, and written with `qualified: false` for
the live season, same rule as every other metric.

### `"Playmaking"`
| id | label | kind | formula |
| --- | --- | --- | --- |
| ast_pct | AST% | advanced | 100 × AST / (((MP / (TmMP/5)) × TmFGM) − FGM), summed per game |
| ast_per_100 | AST/100 | advanced | AST / player_poss × 100 |
| tov_pct | TOV% | advanced (inverted) | 100 × TOV / (FGA + 0.44 FTA + TOV) |
| ast_to | AST:TO | advanced | AST / TOV |
| ast_usg | AST:USG | advanced | AST% / USG% (CTG) |
| apg | APG | traditional | AST / G |
| ast | AST | traditional | total |
| tov_pg | TOV/G | traditional (inverted) | TOV / G |

### `"Rebounding"`
| id | label | kind | formula |
| --- | --- | --- | --- |
| oreb_pct | OREB% | advanced | 100 × OREB × (TmMP/5) / (MP × (TmOREB + OppDREB)) |
| dreb_pct | DREB% | advanced | 100 × DREB × (TmMP/5) / (MP × (TmDREB + OppOREB)) |
| reb_pct | REB% | advanced | 100 × REB × (TmMP/5) / (MP × (TmREB + OppREB)) |
| rpg | RPG | traditional | REB / G |
| oreb | OREB | traditional | total |
| dreb | DREB | traditional | total |

### `"Defense"`
| id | label | kind | formula |
| --- | --- | --- | --- |
| stl_pct | STL% | advanced | 100 × STL × (TmMP/5) / (MP × OppPoss) |
| blk_pct | BLK% | advanced | 100 × BLK × (TmMP/5) / (MP × (OppFGA − Opp3PA)) |
| stocks_per_100 | Stocks/100 | advanced | (STL + BLK) / player_poss × 100 |
| foul_per_100 | Fouls/100 | advanced (inverted) | PF / player_poss × 100 |
| spg | SPG | traditional | STL / G |
| bpg | BPG | traditional | BLK / G |
| stl | STL | traditional | total |
| blk | BLK | traditional | total |

### `"Impact"`
| id | label | kind | formula | notes |
| --- | --- | --- | --- | --- |
| on_net | On-Court +/- | advanced | box plus_minus summed / player_poss × 100 | exact from box scores; the CTG "On" net rating |
| on_off | On-Off | advanced | on-court net rating − off-court net rating, per 100 | needs the pbp lineup reconstruction, see below |
| min_pct | Min% | advanced | MP / (TmMP/5) summed share | share of available minutes |
| mpg | MPG | traditional | MP / G | |
| gs | GS | traditional | games started | |
| plus_minus | +/- | traditional | total | |

**On-Off** is the Cleaning the Glass headline number and the one metric that needs play by
play. Reconstruct who is on the floor from the box score starters plus `Substitution`
events (`athlete_id_1` enters, `athlete_id_2` leaves); period starters are inferred from
the first event each player records in the period before any substitution involving him.
Validation: for every player-game, the reconstructed on-court margin must equal the box
`plus_minus`. Publish `on_off` for a season only when ≥ 97% of player-games validate, and
only for players with at least 95% of their games validated (`ON_OFF_MIN_VALID_SHARE`;
the number is computed over the validated games, which are exact); otherwise omit `on_off`
(never write a wrong number). Box plus_minus is `"--"` for every player through 2008, so
On-Court +/- is simply absent there (see coverage).

## Qualification
Minutes based, prorated through the live season (`qualification_scale` = team games
played / 82, floored at 0.1), the same mechanism as Football's.
- Regular season: `MP >= 15 * 58 = 870` minutes at a full season (≈ 15 MPG over the
  NBA's 58-game award threshold) **and** `G >= 20`. Historical seasons use the full bar.
- Postseason: `MP >= 60` and `G >= 3`.
- Career (All Time, season `0`): regular `MP >= 8,000` (≈ four starting seasons);
  playoffs `MP >= 500`.
- Zone and percentage gates above are attempt counts, also prorated.
Unqualified live-season players are still written with `qualified: false` on every metric
so the leaderboard can show them greyed, exactly as Football does.

Percentile: int 1-100, midpoint rank within (season, season_type, player_type, category)
among qualified players; inverted metrics flip. `value` is the formatted string
(`"28.4"`, `"61.2%"`, `"+6.3"`, `"1,502"`). Percent metrics carry `%`; per-100 and
ratio metrics one decimal; counts grouped.

## metrics jsonb element shape (unchanged)
`{"id": "...", "label": "...", "value": "...", "percentile": 87, "category": "Scoring", "qualified": true}`

## standard_stats jsonb
`[{"id","label","value"}]`, in this order: `G`, `GS`, `MPG`, `PPG`, `RPG`, `APG`, `SPG`,
`BPG`, `FG` (as `"FGM/FGA"` pair, e.g. `"612/1,250"`), `3P` (pair), `FT` (pair), `TOV`,
`PF`, `+/-`, `MIN` (total minutes, the weighting denominator for every rate).
The Swift `StandardStatSemantics` treats `FG`, `3P`, `FT` as made/attempted pairs
(ranked by percentage) and `TOV`, `PF` as lower-is-better.

## games jsonb (snapshot)
`[{"id","date","opponent","summary","percentile_delta","key_metric"}]`, may be `[]`.

## player_game_logs
One row per player per game and season type. `game_date` from the box score. `plays` =
possessions used (`FGA + 0.44 FTA + TOV`, rounded), `touches` = minutes (rounded).
`metrics` jsonb is a flat dict of per-game raw counts plus the team context needed to
recompute every rate across a window: `min, pts, fgm, fga, fg3m, fg3a, ftm, fta, oreb,
dreb, reb, ast, stl, blk, tov, pf, plus_minus, starter, team_poss, player_poss, tm_min,
tm_fgm, tm_fga, tm_fta, tm_tov, tm_oreb, tm_dreb, tm_reb, opp_poss, opp_fga, opp_fg3a,
opp_oreb, opp_dreb, opp_reb, rim_fga, rim_fgm, smid_fga, smid_fgm, lmid_fga, lmid_fgm,
c3_fga, c3_fgm, nc3_fga, nc3_fgm, ast_fgm, on_margin (nullable), off_margin (nullable),
off_poss (nullable)`.

## player_recent_form
`WINDOW_WEEKS = (1, 2, 4)` (roughly the last 3-4, 7 and 14 games), league-anchored on the
latest game date, same table and semantics as Football. Rates are recomputed from summed
numerators and denominators, never averaged.

## games / game_details
`games` from the schedule parquet (id, season, season_type, date, tip-off time in UTC,
home/away codes, scores, status). `game_details` per final game: team four factors
(eFG%, TOV%, OREB%, FT Rate), ORtg, pace, points in the paint, fast-break points, bench
points, biggest lead; player lines (pts, reb, ast, TS%, USG%, +/-) with percentiles
against the season's team games and qualifying player games (≥ 10 minutes); the score
margin series from pbp (in place of the NFL win probability line); and the biggest
plays, defined as scoring plays in the last five minutes of the fourth quarter or
overtime with the margin within five, plus the play that produced the largest lead change.

## Enrichment (player_profiles, team_ratings, game_projections)
- `player_profiles`: height, weight, birth date, jersey, years of experience, draft year,
  round, pick and team (hoopR `player_core`, `rosters`, `draft`). Contract, snap and
  injury columns stay null (no public source in hoopR); the Swift screens already hide
  null lines. The salary / contract-value views are removed from the app.
- `team_ratings`: net rating adjusted for schedule (SRS) with an offense and defense
  split from ORtg and DRtg, shrunk toward last season early (same blend as Football).
- `game_projections`: projected home margin = rating diff + 2.5 home court, win
  probability from a normal with σ = 12.

## Metric coverage by season
Verified 2026-10-08 by running the pipeline over every hoopR season (2003-2026). The
constants in `backend/ingest.py` mirror this table and `MetricCoverage` (Swift) should too.

| Metric group | Seasons | Bound by |
| --- | --- | --- |
| Every box-score metric (Scoring, Playmaking, Rebounding, Defense, Min%, MPG, GS) | 2003 onward (2002-03) | hoopR player box starts 2002; 2003 is the first full season |
| On-Court +/- and the `+/-` standard stat | 2009 onward | ESPN `plus_minus` is the placeholder `"--"` for every player through 2008 (not "partial 2002-04" as first assumed) |
| Shooting zones (`ZONES_FIRST_SEASON = 2004`) | 2004 onward | shots feed tracks 98-100% of box attempts from 2004; 2003 has 80% of attempts in 82% of games, 2002 has 37%, so both ship without zones |
| On-Off, regular season (`lineups.VALIDATION_BAR = 0.97`) | 2014, 2015, 2021-2026 | play-by-play replay reproduces the box plus/minus for >= 97% of player-games |
| On-Off, postseason | 2009, 2010, 2012-2015, 2021-2026 | same bar, per phase |

`ON_OFF_FIRST_SEASON = 2009` is where the replay is attempted (the first season with a box
plus/minus to check it against); whether it is published is decided per season and phase by
the 97% bar, so the table below is the evidence, not a hardcoded list.

Replay validation rate (share of player-games whose replayed on-court margin equals the box
plus/minus exactly, in games whose replayed final score matches the box), regular season / postseason:

| Season | REG | POST | | Season | REG | POST |
| --- | --- | --- | --- | --- | --- | --- |
| 2009 | 93.3% | 97.7% | | 2018 | 93.8% | 96.7% |
| 2010 | 95.7% | 97.6% | | 2019 | 96.0% | 95.5% |
| 2011 | 96.7% | 93.8% | | 2020 | 95.7% | 96.7% |
| 2012 | 96.5% | 98.5% | | 2021 | 98.4% | 99.8% |
| 2013 | 91.3% | 97.1% | | 2022 | 98.1% | 99.1% |
| 2014 | 97.5% | 97.7% | | 2023 | 97.3% | 99.2% |
| 2015 | 97.7% | 98.6% | | 2024 | 98.5% | 98.8% |
| 2016 | 92.6% | 96.7% | | 2025 | 98.5% | 98.8% |
| 2017 | 95.3% | 97.3% | | 2026 | 98.2% | 98.3% |

First season clearing the bar in the regular season: **2014** (both phases); the first season
from which it clears in every season and phase: **2021**. Seasons that miss ship without
On-Off, never with a lower-quality number.

### How many players get an On-Off number
`ON_OFF_MIN_VALID_SHARE = 0.95`: a player's On-Off is published when at least 95% of his games
validated, computed over those games (each is exact, so the figure is a slightly smaller sample,
not a wrong one). The first draft required every game; that gave only 73 of 310 qualified players
(24%) a number in 2025-26, because 98.2% per game compounds over ~65 games. At 0.95 it is 291 of
310 (94%). Postseason, with its short runs, reaches nearly everyone.

### Source quirks the pipeline absorbs
- ESPN's rim sits at |x| = 41.6 (2004-2010), 40.9-41.2 (2011-2017) and 39.7-40.1 (2018 onward),
  not the textbook 41.75: rim, short-mid and corner zones are measured from a per-season
  calibrated rim (see Shooting). The 1.5 ft assertion in the first draft of this contract fails
  from 2018 on, so the check is 3 ft and the lateral centre line 1.5 ft.
- Corner three: "|x| >= 41.75 - 14" measures 14 ft from the rim, not the baseline, and sweeps
  sideline wing threes into the corner (31% of all threes vs the real ~26%). The line's straight
  segment ends where the 23.75 ft arc crosses |y| = 22, 9 ft out from the rim, so a corner three
  is a three with |y| >= 22 within 9 ft of the rim's depth.
- The shots parquet has no `text`; a missed three is read from the play-by-play row for the same
  shot (`points_attempted` where the season has it, else "three point"/"3PT" in the text), joined on
  (game, period, clock, shooter, shot type). Misses with no match fall back to distance
  (>= 23.0 ft, or >= 22.0 ft in the corner); against the play-by-play truth that fallback is 99.4% right.
- Tracked shots can exceed box attempts by ~0.4%, so zone frequencies divide by the tracked
  total and always sum to 100% with the three-point share.
- Team `turnovers` in team box is the official team total in old files and the players' sum in
  recent ones (`total_turnovers` adds team turnovers, or doubles it in old files); the pipeline
  takes the team total either way, so USG%'s denominator is one definition across seasons.
- Play-by-play score columns run backwards before 2020 and `score_value` is 0 for made free
  throws in some seasons; the replay takes points from the scoring events and recovers events the
  feed dropped from the score columns. ESPN holds a substitution logged inside a free-throw trip
  until the trip ends (a quarter to a third of player-games fail otherwise); a sub logged before
  the foul is "immediate" from about 2019 and "deferred" before, chosen per season by whichever
  matches more box plus/minus.
`MetricCoverage` (Swift) and the constants in `ingest.py` mirror this table.

## Implementation notes (backend, verified against 2003-2026)
Where the pipeline had to choose or deviate from the text above:
- **Rim calibration.** Zones are measured from a per-season rim calibrated as the centroid of dunks and
  layups (|x| folded), asserted within 3 ft of 41.75 and within 1.5 ft of the centre line; a new season
  with under 500 close shots borrows 39.8 ft (2018 onward only) until it has enough. The 1.5 ft check in
  the first draft fails for every season from 2018.
- **Corner three.** A three with |y| >= 22 within 9 ft of the rim's depth (where the 23.75 ft arc crosses
  the corner line), not `|x| >= 41.75 - 14`, which classified 31% of threes as corner threes.
- **Decimals.** FT Rate (FTA/FGA, near 0.25) and AST:USG (near 0.8) are written with two decimals;
  one decimal would show every player as 0.2 or 0.3. Every other ratio and per-100 metric has one.
  `+/-` is a signed grouped integer (`"+142"`); counts are grouped (`"1,502"`).
- **Percentiles** are midpoint ranks rounded half up, clamped to 1-100, against the qualified pool
  that also clears the metric's attempt gate. In the live season an unqualified player is placed
  against that pool without joining it, so a hot newcomer cannot move anyone else's rank.
- **`qualified` appears only in the live season.** Past-season metrics omit the key (the app reads
  a missing key as qualified); a past-season metric under its attempt gate is omitted instead.
- **Attempt gates** prorate like the minutes bar in the live season (`ceil(gate * scale)`); the
  postseason uses 0.2 of the full gate (3PA >= 10, FTA >= 10, rim >= 8, zone >= 8, corner >= 6,
  non-corner >= 10) and a career uses 4x (3PA >= 200 ...), neither of which the text specified.
- **Positions.** `player_type` is `g`/`f`/`c`/`unknown`; `position` is the folded `G`/`F`/`C` ("" when unknown).
- **Weeks.** `week` / `start_week` / `end_week` / `max_week` / `through_week` count calendar weeks from
  the Monday on or before October 1 of the season's first calendar year (2025-09-29 for season 2026),
  starting at 1 and continuing through the playoffs. Windows are 1, 2 and 4 weeks, anchored per phase on
  the latest week with a game. Recent Form metric keys are the season metric ids above.
- **Game logs.** `metrics` holds exactly the keys listed above; zone keys are omitted for a game the
  shots feed does not cover, and `plus_minus`, `on_margin`, `off_margin`, `off_poss` are `null` where
  unavailable. `week` is on the row. `game_id` is the ESPN game id as text.
- **All Time.** Zone metrics pool seasons from 2004 (shares of tracked attempts); career On-Off is not
  published; On-Court +/- uses the games that have a box plus/minus.
- **game_details.** `team_stats.{away,home}` carries `pts, ortg, drtg, pace, efg_pct, tov_pct, oreb_pct,
  ft_rate, points_in_paint, fast_break_points, bench_points, largest_lead` as `{value, pct}` ranked
  across the season's team games. `players` has one `{role: "player", player_id, name, team, starter, min,
  pts, reb, ast, ts_pct, usg_pct, plus_minus}` per player, each stat `{value, pct}` (pct null under 10
  minutes). `win_probability` holds the margin series `[[elapsed_seconds, home_margin], ...]`.
  `big_plays` is `{qtr, clock, team, description, points, home_margin, kind}` with `kind` of `late_score`
  (last five minutes of the fourth quarter or any overtime, margin within five after the play) or
  `lead_change` (the lead-changing play worth the most points, anywhere in the game).
- **team_ratings** are per 100 possessions (within a percent of points per game at today's pace):
  `rating = offense + defense`, `offense`/`defense` positive is good, `schedule` is the SRS adjustment
  already included. `through_week` uses the week numbering above, `ties` is 0.
- **player_profiles.** `rookie_season = season - years_exp + 1`, `draft_pick` is the overall pick,
  `college` and `draft_team` are null (hoopR has a college id but no name, and its draft files are
  sparse with ids that do not match ESPN's).
- **Source probe.** `raw.githubusercontent.com` sends a strong `ETag` and `Content-Length` but no
  `Last-Modified`, so `source_published_at` is null and `published_at` is the user-facing time. The
  five assets (player_box, team_box, shots, pbp, schedule) are all in the fingerprint.
- **Empty live season.** From the October 1 rollover to opening night (about Oct 20) the new season has
  a schedule (loaded into `games`) but no box scores. `source_probe.py` then reports `season_pending`
  instead of a generic 404, `data_refresh_status` reads `status = source_pending`, `season = 2027`,
  `last_error_code = season_pending`, and the last published revision (`refresh_id`, `published_at`,
  `max_game_date`, coverage) plus the new `published_season = 2026` keep describing 2025-26. No run is
  created and nothing errors; the planner re-checks every 6 hours.
- **Status view.** `ngs_status` = the shots feed, `pfr_status` = the play-by-play feed; values `ready`,
  `pending`, `degraded`, `not_applicable`. Column names are unchanged; no migration was needed.

## All Time (career rollup)
Season `0` sentinel, same as Football: one career row per player, aggregated from the box
feed (not from stored snapshots), ranked within the career cohort, with the career
qualification bars above. Trends excludes it.

## Free vs Pro season gating (iOS)
- `StatScoutSeason.current` resolves by the October rule above (2027 today); `free =
  current`; `oldest = 2003` (2002-03, the first full hoopR season); historical seasons
  (Pro) = 2003-2026.
- Recent Form covers the newest two seasons (2026 and 2027 today).
- The historical plist bundles every season 2003-2026 plus the career rollup; no live
  season in the bundle.
