# Hardwood StatScout Project Guide

Hardwood StatScout: NBA advanced-stats percentiles / player-comparison app (iOS),
forked from the Football (NFL) StatScout repo, which was forked from Baseball.
XcodeGen project/scheme: `StatScout` (names kept to minimize churn), sim lease
owner `basketball`. Bundle id `com.jackwallner.basketball`, product name "Hardwood StatScout".

**App Store name:** **"Basketball Next: StatScout"**, chosen for ASO. In-app it is
`PRODUCT_NAME: "Hardwood StatScout"`, home-screen `StatScout`, paid tier `StatScout+`.
ASO plan: `project-docs/marketing/aso-plan.md`.

**The web reference is Cleaning the Glass**: percentiles within a position group
(G / F / C), points and rates per 100 possessions, shooting split into zone
frequency and accuracy, rebounding and defense as shares of chances, on/off impact.
Labels and formulas are fixed in `handoff/NBA_CONTRACT.md`; the Swift registry and
the backend both mirror it. Change the contract first, then both sides.

**This repo is NOT the fastlane template canonical source.** That lives in the
baseball StatScout repo. Metadata/screenshots here are app-specific.

**App Store release workflow and current state:** `.claude/rules/app-store-release.md`.

**App Store reviews:** `StatScout/Services/ReviewPromptTracker.swift` calls
`requestReview()` directly (no enjoyment funnel, App Review 5.6.1). Feedback
`jackwallner+bb@gmail.com`.

## Backend / data pipeline (NBA)

StatScout is backed by a Supabase NBA dataset fed by an event-aware refresh pipeline
on GitHub Actions.

- **Supabase** project "Basketball" (ref `ftlwpyjymjndadccqrqd`) lives on its own
  Supabase account (org "Basketball"). Creds, the Management token and the DB
  password are in `~/.basketball_credentials`; the same token is in
  `~/.supabase_keepalive_tokens` here and on the MBP keepalive host. Apply schema with
  `psql` using `SUPABASE_DB_PASSWORD` (`host=db.<ref>.supabase.co user=postgres`).
- **Data source**: hoopR-nba-data (sportsdataverse's ESPN mirror on GitHub), no key,
  cloud-IP friendly. A hoopR season is named for the year it ends (2027 = 2026-27).
- The historical plist is the only source of past seasons in the app, and
  `backend/prune_history.py` is a manual tool, never a nightly step.
- Tables, categories, refresh workflows, the Recent Form windows, and regenerating
  the historical bundle are in `.claude/rules/backend-pipeline.md`, which loads when
  you read a matching file; Codex and other agents should open it directly.
- **TestFlight upload** sources the creds first: `source ~/.basketball_credentials && bash scripts/testflight.sh`.

## RevenueCat
Project `projf687e8b0` ("Basketball Next: StatScout"), app `app9636969fcd`,
entitlement `Basketball Pro` (display "StatScout+"), offering `default` with
`$rc_monthly` / `$rc_annual` / `$rc_lifetime`. Products
`com.jackwallner.basketball.pro.monthly` ($1.99, 7-day trial),
`.pro.yearly` ($9.99, 7-day trial), `.pro` lifetime ($19.99).

---
Shared iOS conventions (build, simulator, release scripts, ASC key, review funnel, signing, gotchas):
the global agent rules + the `ios-dev` skill.
