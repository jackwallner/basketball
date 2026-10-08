# Hardwood StatScout

Hardwood StatScout ("Basketball Next: StatScout" on the App Store) is a native SwiftUI iOS app for NBA fans who want the numbers analysts use: percentile rankings within a position group for scoring, shooting by zone, playmaking, rebounding, defense and on-court impact, refreshed soon after every game. Unaffiliated with the NBA.

## Stack

- **iOS app:** SwiftUI, iOS 17+, XcodeGen project
- **Database/API:** Supabase Postgres + PostgREST
- **Refresh:** GitHub Actions, event-aware (probes the source and publishes one atomic revision)
- **Ingestion:** Python + polars reading hoopR-nba-data parquet (ESPN box scores, play by play, shots)

## Project layout

```text
StatScout/                  SwiftUI source
StatScoutTests/             Unit tests (run with the StatScout scheme)
backend/                    Ingest, rollups, refresh planner and publisher
supabase/migrations/        Schema, applied with psql
.github/workflows/          Refresh, timer, enrichment and CI workflows
handoff/NBA_CONTRACT.md     The metric and schema contract shared by backend and app
project.yml                 XcodeGen project definition
```

## Run the iOS app

```bash
brew install xcodegen
xcodegen generate
source ~/.basketball_credentials   # SUPABASE_URL + SUPABASE_ANON_KEY
```

Then build the `StatScout` scheme. The shared headless simulator pool and release scripts are described in `AGENTS.md`.

## Backend

See `backend/README.md` for local setup, dry runs and the refresh workflow.
