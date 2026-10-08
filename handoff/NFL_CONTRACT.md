# NFL Conversion Contract (shared between backend + iOS)

App: **Gridiron StatScout** (working name), NFL analytics/percentiles app cloned from the
Baseball Savvy StatScout codebase. Same architecture: nightly Python ingest → Supabase →
SwiftUI iOS app reading `player_snapshots` + `player_game_logs` via PostgREST.

## Supabase
- URL: `https://qwkmpwnhrejsuplcwxrb.supabase.co` (dedicated "Football" project, separate
  Supabase account — apply schema via `psql` with `SUPABASE_DB_PASSWORD`, not the CLI token).
- Creds file: `~/.football_credentials` (SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_DB_PASSWORD).
- Tables (already created):
  - `player_snapshots` — same shape as baseball (id bigint, season int,
    season_type `REG`/`POST`, PK (id, season, season_type); name, team, position,
    handedness, image_url, player_type, source, metrics jsonb, standard_stats jsonb,
    games jsonb).
  - `player_game_logs` — PK (player_id, season, season_type, game_date, player_type); columns
    `plays` (was plate_appearances) and `touches` (was batted_ball_events), metrics jsonb.
  - `player_recent_form` — league-anchored 3/5/8-week aggregates. PK
    (player_id, season, season_type, player_type, window_weeks).

## Data source
- `nflreadpy` (nflverse). Verified working in `backend/.venv` (Python 3.14):
  - `load_player_stats([season])` — weekly rows, 145 cols (passing_*, rushing_*, receiving_*, def_*, fg_*, ...).
  - `load_nextgen_stats(stat_type='passing'|'rushing'|'receiving')` — NGS advanced metrics; week 0 rows = season aggregate.
  - `load_schedules([season])` — `game_id` → `gameday` date mapping.
  - `load_players()` — headshots, positions.
- No API key needed. Data is a static parquet mirror, cloud-IP friendly (works in GitHub Actions).

## Season
- NFL season label = starting year. Season 2025 ran Sep 2025 – Feb 2026 and is the most
  recent complete season. Rule: `season = year if month >= 9 else year - 1` (today, July 2026 → 2025).
- `STATCAST_SEASON` env var name is kept (workflow compatibility) and overrides.

## Player IDs
- nflverse `player_id` is GSIS, e.g. `"00-0034796"`. DB id is bigint:
  `id = int(gsis_id.split('-')[-1])` (e.g. 34796). Collision-free in practice.

## player_type (snapshot + game log rows)
Position-group based, lowercase: `"qb"`, `"rb"`, `"wr"`, `"te"`, `"def"`, `"k"`.
Derived from `position_group`. One snapshot row per player, season, and season type.
`REG` and `POST` are ranked separately.

## Metric categories (jsonb `metrics[].category`, exact strings)
- `"Passing"` — QBs. Metrics (id → label): pass_yards→"Pass Yds", pass_tds→"Pass TD",
  cmp_pct→"Cmp%", ypa→"Y/A", int_rate→"INT%" (inverted), passer_rating→"Rating",
  passing_epa/dropbacks→"EPA/Play", cpoe→"CPOE", avg_time_to_throw→"Time to Throw",
  aggressiveness→"Aggressiveness", avg_intended_air_yards→"Intended Air Yds", sack_rate→"Sack%" (inverted).
- `"Rushing"` — RBs + rushing QBs. rush_yards→"Rush Yds", rush_tds→"Rush TD", ypc→"Y/C",
  rushing_epa/carries→"EPA/Rush", rushing_epa→"Rush EPA", rush_first_downs→"Rush 1D", explosive_rush_rate→"Explosive%",
  fumble_rate→"Fumble%" (inverted), rush_yoe (NGS rush_yards_over_expected)→"RYOE" if available.
- `"Receiving"` — WR/TE/RB with targets. receptions→"Rec", rec_yards→"Rec Yds",
  rec_tds→"Rec TD", yac→"YAC", target_share→"Target Share", wopr→"WOPR", racr→"RACR",
  receiving_epa/targets→"EPA/Tgt", receiving_epa→"Rec EPA", catch_pct→"Catch%", avg_separation→"Separation" (NGS),
  avg_yac_above_expectation→"YAC+" (NGS).
- `"Defense"` — DEF players. Advanced (PFR `advstats_season_def`, 2018+):
  def_pressures→"Pressures", def_hurries→"Hurries", def_qb_knockdowns→"QB KD",
  def_cmp_pct_allowed→"Cmp% Allowed" (inverted), def_yds_per_tgt_allowed→"Yds/Tgt Allowed" (inverted),
  def_rating_allowed→"Rating Allowed" (inverted), def_missed_tkl_pct→"Missed Tkl%" (inverted).
  Traditional: tackles→"Tackles", sacks→"Sacks", def_ints→"INT",
  passes_defended→"PD", forced_fumbles→"FF", tfl→"TFL", qb_hits→"QB Hits".
  PFR is keyed by `pfr_id`, joined to GSIS via `load_players()`. The season table has no
  `season_type`, so **advanced defence is regular season only**. Coverage rates need
  ≥ 20 targets and Missed Tkl% needs ≥ 20 combined tackles, else they are nulled rather
  than ranked on a two-target sample. `standard_stats` carries "Tgt Allowed" as the
  weighting denominator.

## Metric coverage by season

Every season 2000–2025 is present with ~1,100–1,300 players. What varies is which
*advanced* metrics exist, and it varies because of the sources, not by choice. This
table is the reference; `MetricCoverage` (Swift) and the constants in `ingest.py`
mirror it, and the app shows a short note in-app for any season with a gap.

| Metric group | Seasons | Bound by |
| --- | --- | --- |
| All traditional counting stats, EPA/Play, EPA/Rush, Rush EPA, Rec EPA, Sack%, INT%, Explosive%, Fumble%, Y/A, Y/C, Rating | 2000–2025 | none; pbp runs from 1999 |
| CPOE | 2006–2025 | pbp air-yards tracking starts 2006 |
| Target-derived receiving: Target Share, WOPR, RACR, Catch%, EPA/Tgt | 2000–2002, 2009–2025 | nflverse `targets` blank 2003–2008 |
| RACR (partial) | 2000–2002 | receiving air yards incomplete pre-2006 |
| NGS passing/receiving: Time to Throw, Aggressiveness, Intended Air Yds, Separation, YAC+ | 2016–2025 | Next Gen Stats era starts 2016 |
| RYOE | 2018–2025 | NGS rushing-over-expected starts 2018 |
| Advanced defence (Pressures, Hurries, QB KD, Cmp%/Yds/Rating Allowed, Missed Tkl%) | 2018–2025 | PFR advanced defence starts 2018 |

CPOE is derived from the weekly feed's `passing_cpoe`, attempt-weighted to a season
figure, **not** from NGS `completion_percentage_above_expectation`. The two are
different expectation models (r ≈ 0.86, ~1.6 points apart over a season), so using the
weekly one throughout avoids a definitional seam at 2016 that would corrupt every
year-over-year CPOE comparison. NGS remains a fallback where weekly is absent.

## All Time (career rollup)

`backend/rollup_all_time.py` writes one extra snapshot per player under the sentinel
season **`0`**, aggregating 2000→current into a career line, with percentiles ranked
inside the career cohort. Stored as a season rather than an app-side mode so the
leaderboards, Teams, Compare and the player page all get it with no special-casing.

- Rendered as "All Time" via `SeasonLabel`; never as `"0"`.
- Career qualification is far higher than a single season (≈ 3 starting years):
  1500 attempts / 500 carries / 300 targets (200 receptions fallback) / 48 games.
- Career **playoffs** get their own, much lower bar (150 attempts / 60 carries /
  40 targets / 25 receptions / 6 games), because a playoff career is measured in
  games, not seasons. Reusing the regular-season career numbers left the
  career-playoff board with exactly one qualifying passer in league history.
- Re-reads the weekly feed rather than summing stored snapshots, which would compound
  rounding and drop every season a player missed the single-season cut.
- Trends excludes it: rolling 3/5/8-week windows are a within-season question.
- The API's historical fetch is an `or=(season.eq.0, and(season.gte.2000, season.lt.current))` —
  a plain `gte.2000` range silently excluded the sentinel.

Percentiles: computed within (season, category) among **qualified** players
(thresholds: Passing ≥ 150 attempts, Rushing ≥ 80 carries, Receiving ≥ 40 targets,
Defense ≥ 300 defensive snaps or ≥ 8 games). Inverted metrics: lower raw value = higher
percentile. Percentile int 1–100. `value` is the formatted raw stat string (e.g. "4,918", "68.3%").
A player appears in every category they qualify for (rushing QB gets Passing + Rushing metrics).
The nflverse target field is effectively blank for 2003–2008. Those seasons use
≥ 25 receptions (≥ 3 postseason) as the receiving qualification and omit
target-derived metrics instead of presenting fabricated zeroes.

## metrics jsonb element shape (same as baseball)
`{"id": "...", "label": "...", "value": "...", "percentile": 87, "category": "Passing"}`

## standard_stats jsonb
`[{"id": "...", "label": "...", "value": "..."}]` — games, totals per relevant categories
(G, Cmp/Att, Yds, TD, INT for QB; Car, Yds, TD for RB; Rec/Tgt, Yds, TD; etc.)

## games jsonb (snapshot) — keep same shape as baseball
`[{"id","date","opponent","summary","percentile_delta","key_metric"}]` — may be empty [].

## player_game_logs
One row per player per game and season type (per side: player_type as above). `game_date` from schedule
`gameday`. `plays` = pass attempts + carries + targets (offensive involvement),
`touches` = completions + carries + receptions. `metrics` jsonb: flat dict of per-game raw
stats (passing_yards, passing_tds, interceptions, rushing_yards, carries, receptions,
targets, receiving_yards, epa_total, ...). `player_recent_form` powers Trends using
league-anchored 3/5/8-week windows, so an inactive player does not retain a stale
player-relative "last N games" result.

## Teams
32 NFL abbreviations (nflverse): ARI ATL BAL BUF CAR CHI CIN CLE DAL DEN DET GB HOU IND
JAX KC LA LAC LV MIA MIN NE NO NYG NYJ PHI PIT SEA SF TB TEN WAS.

## Free vs Pro season gating (iOS)
- `StatScoutSeason.current = 2025`, `free = 2025`, `oldest = 2000`; historical seasons (Pro) = 2000–2024.
- Backend backfills regular-season and postseason snapshots for seasons 2000–2025.
  Earlier seasons omit unavailable NGS-only metrics instead of emitting zero values.
- Historical game logs are not bulk-backfilled; Recent Form remains an active-season feed.
