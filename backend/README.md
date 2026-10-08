# Backend ingestion (NBA)

The backend is serverless and free-tier friendly. GitHub Actions checks the
[hoopR-nba-data](https://github.com/sportsdataverse/hoopR-nba-data) file
metadata on a schedule planned from the NBA calendar (every 30 minutes in the
hours after a game, every 6 hours otherwise in season, daily in the offseason).
When a source file changes, it reads the season's box scores, shots and
play-by-play, computes within-cohort percentiles among qualified players, and
publishes snapshots, per-game logs and Recent Form as one Supabase revision. No
API key is required for the data source.

Metric ids, labels, categories, formulas and qualification are specified in
[`handoff/NBA_CONTRACT.md`](../handoff/NBA_CONTRACT.md); this file covers how the
pipeline runs.

## Local setup

```bash
python3 -m venv backend/.venv
source backend/.venv/bin/activate
pip install -r backend/requirements.txt
export HOOPR_CACHE_DIR=~/.cache/hoopr      # optional: keep downloads on disk
```

Every writer has a dry-run mode that reads hoopR and writes JSON, with no
database involved:

```bash
python backend/ingest.py --season 2026 --season-type all --dry-run --out /tmp/out
python backend/ingest_game_logs.py --season 2026 --dry-run --out /tmp/out
python backend/rollup_recent_form.py --season 2026 --dry-run --out /tmp/out
python backend/ingest_game_details.py --season 2026 --dry-run --out /tmp/out
python backend/ingest_enrichment.py --season 2026 --dry-run --out /tmp/out
python backend/rollup_all_time.py --dry-run --out /tmp/out
python backend/refresh.py --dry-run --season 2026 --out /tmp/out   # the whole publish candidate
```

`--live yes|no` on `ingest.py` forces the live-season shape (every player who has
played, each metric carrying `qualified`) or the past-season shape (qualified
players only). The default is live for the resolved current season.

With Supabase credentials in the environment (`SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, from `~/.basketball_credentials`), the same commands
without `--dry-run` write. Every writer refuses a Supabase host that is not the
Basketball project (`BASKETBALL_SUPABASE_HOST` pins it exactly; the Football
project is refused by name). `backend/.env` is loaded by `python-dotenv`; make
sure it holds Basketball credentials, not the ones copied from the football repo.

Backfill and validate every supported snapshot season (2003 through current):

```bash
python scripts/backfill_historical.py
```

Use `--validate-only` to audit existing Supabase rows without re-ingesting.

Per-game logs and Recent Form for one season:

```bash
python backend/ingest_game_logs.py --season 2026          # incremental
python backend/ingest_game_logs.py --season 2026 --full   # full re-ingest
python backend/rollup_recent_form.py --season 2026
```

## Pipeline

```
hoopR parquet --> boxscore.py   clean player rows, team/opponent totals, possessions
              --> shots.py      rim calibration, three detection, zone counts
              --> lineups.py    play-by-play lineup replay, validated against box +/-
              --> playergames.py  one row per player-game with all of the above
              --> ingest.py     season sums -> metrics -> percentiles -> snapshots
                  ingest_game_logs.py / rollup_recent_form.py / rollup_all_time.py
                  ingest_game_details.py / ingest_enrichment.py + team_ratings.py
```

`nbacodes.py` (stdlib only) holds the season rule, team codes, week numbering and
the Supabase project guard, so the schedule planner and the builders cannot
disagree about them. `hoopr.py` downloads and caches the parquet files.

### Things that are easy to get wrong

* **Season rule.** hoopR names a season for the year it ends: `2026` is 2025-26,
  and October 2026 already resolves to `2027`. `season = year + 1 if month >= 10
  else year`.
* **Team codes.** ESPN's `GS NO NY SA UTAH WSH` become `GSW NOP NYK SAS UTA WAS`
  (`NJ` becomes `NJN`). Any game with a team outside the franchise table (All-Star
  squads) is dropped. Preseason and play-in games belong to neither phase.
* **The rim is not at 41.75 ft in ESPN's frame.** It is calibrated per season from
  dunks and layups (41.6 in 2004, 40.9 in 2011, 39.8 in 2025) and the build fails
  if the centroid is implausible. Misses are classified as threes from the
  play-by-play row (`points_attempted` or the text), not from distance.
* **Box plus/minus is `"--"` before 2009**, parsed to null, never 0.
* **On-Off is only published where the replay reproduces the box.** Each
  player-game must match its box plus/minus exactly and the replayed final score
  must match the box score; a phase is published only when at least 97% of its
  player-games validate, and a player's On-Off only when at least 95% of his games
  validate (computed over the validated games).
* **Free-throw stoppages.** ESPN logs substitutions between free throws, but its
  plus/minus holds them until the trip ends. The replay does the same.

## Event-aware refresh

The production path is `backend/refresh_schedule.py` (planner), then
`backend/source_probe.py`, then `backend/refresh.py`:

1. The planner (stdlib plus pyarrow) reads tip-off times from `public.games` and
   decides whether a probe is worth running: every 30 minutes from 3 to 8 hours
   after any tip-off, hourly to +30 hours, every 30 minutes to 3 hours while a
   posted final has no `player_game_logs` rows (up to five days), otherwise every
   6 hours in season (October through June) and daily July through September. It
   re-syncs `games` from the hoopR schedule every 15 minutes while a game is in
   progress, else daily.
2. The probe makes one `HEAD` request per asset the builders read: player box,
   team box, shots, play-by-play and the season schedule. `raw.githubusercontent.com`
   answers with a strong `ETag` (a content hash) and `Content-Length`; the
   SHA-256 fingerprint combines them, so a rebuild that changes no file changes no
   fingerprint. The last successful fingerprint is stored in `data_refresh_state`.
3. A changed source creates a `data_refresh_runs` row. The builder reads the
   season in full, stages all three outputs under its `refresh_id`, probes again,
   and calls `publish_data_refresh` only if the source stayed stable.
4. The RPC validates row keys, same-season coverage and existing game identities,
   then swaps the requested phases in one transaction. A failure leaves the prior
   rows in place.
5. Before staging, the builder hashes its output without timestamps. If the hash
   matches the live revision, `mark_data_refresh_unchanged` records the new source
   generation as handled, so `published_at` means "the stats last changed".

The workflow is serialized with `cancel-in-progress: false`. A manual force run:

```bash
gh workflow run nightly-statcast.yml -f force=true
```

For a credential-free local probe, leave the Supabase variables unset:

```bash
python backend/source_probe.py --season 2026 --json
```

## Freshness status contract

After applying `supabase/migrations/20260912000000_event_aware_refresh.sql`, the
app reads one curated row from the normal Supabase REST endpoint:

```text
GET /rest/v1/data_refresh_status?select=*&limit=1
```

The stable fields:

- `status`: `unknown`, `source_pending`, `building`, `published`, `degraded`, or
  `failed`.
- `refresh_id`: the last successfully published revision. It stays unchanged
  while a newer attempt is pending or failed. `latest_refresh_id` is the in-flight
  or latest failed attempt.
- `source_fingerprint`, `source_published_at`, `published_at`, `last_checked_at`.
  hoopR files carry no publication timestamp, so `source_published_at` is null
  unless a mirror sends `Last-Modified`; `published_at` is the user-facing time.
- `season`, `season_type`, `max_week`, `max_game_date`: coverage metadata.
  `max_week` is the week number since the season epoch (see below).
- `expected_games`, `observed_games`, `coverage_status`: completed games on the
  schedule versus games present in the box scores.
- `ngs_status`, `pfr_status`: the football column names, kept so the view and the
  publisher RPC need no migration. Here **`ngs_status` is the shots feed** (zone
  metrics) and **`pfr_status` is the play-by-play feed** (On-Off, game pages), each
  `ready`, `pending` (not published yet), `degraded` (failed, built without it) or
  `not_applicable` (the season predates the source). A `pending` or `degraded` feed
  publishes the revision as `degraded`.
- `last_error_code`: a short retry-safe code. `season_pending` means the new
  season's schedule is out but its box scores are not (October 1 to opening night):
  the status is `source_pending`, `season` already names the new season, and the
  published revision fields keep describing the old one.
- `published_season`: the season the live revision covers (derived from
  `max_game_date`; added by `20261008000000_status_published_season.sql`).

## Season, phases and weeks

`season` is the hoopR integer; the app renders it as `"2025-26"`.
`season_type` is `REG` or `POST`; each phase is aggregated and ranked separately.
`STATCAST_SEASON` (kept for workflow compatibility) overrides the season rule.

The NBA has no league weeks, so `week` on `player_game_logs`, `games`,
`game_details` and `player_recent_form` counts calendar weeks from a fixed epoch:
the Monday on or before October 1 of the season's first calendar year (Monday
2025-09-29 for season 2026), starting at 1 and continuing through the playoffs.
Recent Form windows are 1, 2 and 4 weeks, anchored on the phase's latest week.

## Data contract

`player_snapshots` rows are keyed `(id, season, season_type)`:

- `id`: the ESPN athlete id. `player_type`: `g` / `f` / `c` / `unknown` (ESPN's
  `PG`/`SG` fold into `g`, `SF`/`PF` into `f`).
- `metrics`: `{id, label, value, percentile, category}` (plus `qualified` in the
  live season), categories `Scoring`, `Shooting`, `Playmaking`, `Rebounding`,
  `Defense`, `Impact`. A missing `qualified` means qualified.
- `standard_stats`: `G GS MPG PPG RPG APG SPG BPG FG 3P FT TOV PF +/- MIN`
  (`+/-` is omitted before 2009).
- `games`: `[]`.

Percentiles are midpoint ranks within `(season, season_type, player_type,
category)` among qualified players. Regular-season qualification is 870 minutes
and 20 games (prorated by team games played / 82 while the season is live);
postseason 60 minutes and 3 games; career 8,000 and 500.

## Coverage by season

See the table in `handoff/NBA_CONTRACT.md`. In short: box-score metrics 2003
onward, On-Court +/- from 2009, shot zones from 2004, On-Off wherever a phase's
replay validates at 97% (the replay is attempted from 2014 and published per
season and phase).

## Tests

```bash
PYTHONPATH=backend python -m pytest backend/tests
python -m unittest discover -s scripts/tests -v
```
