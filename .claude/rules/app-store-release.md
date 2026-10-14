---
paths:
  - "project.yml"
  - "fastlane/**/*"
  - "scripts/asc-*.py"
  - "scripts/asc-*.sh"
  - "scripts/asc_lib.py"
  - "scripts/testflight.sh"
---

# App Store release workflow

## Current state, 2026-10-14

- App Store Connect app `6820647074` ("Basketball: Hardwood StatScout", SKU
  `basketball-statscout`, bundle id `com.jackwallner.basketball`).
- Version 1.0, build 5, submitted for review 2026-10-14 (review submission
  `ce070079-e7c4-4456-a168-7a7246118225`, five items: the version, the
  subscription group, monthly, yearly and the lifetime IAP). Release type
  MANUAL: release it by hand once approved.
- 39 locales of metadata (see Localized listing below), 6 iPhone 6.9" and
  3 iPad 13" screenshots (en-US only), age rating, privacy (Data Not
  Collected), free price, all territories.
- Products: `.pro.monthly` ($1.99) and `.pro.yearly` ($9.99), both with a
  1-week trial in 175 territories, lifetime `.pro` ($19.99). Subscription
  review notes set 2026-10-14.
- A version in a draft review submission is frozen ("could not find an
  editable version"). To edit it, delete its reviewSubmissionItem (the
  products stay queued), edit, then `scripts/asc-submit-for-review.py`
  re-adds it and submits.
- 1.0 carries no What's New (Apple rejects it on a first version).

## Submission scripts

`scripts/asc-readiness.py` reports what the record still needs,
`scripts/asc-attach-build.py` attaches the newest processed build, and
`scripts/asc-submit-for-review.py` adds the version to the open review
submission and submits it (`--dry-run` first). Products cannot be added over
this API key; the first IAPs are queued by hand in the ASC web UI.

## Localized listing

`scripts/aso/localized_listing.py` writes name, subtitle, keywords, promo
text and description for 35 translated locales (plus en-AU/CA/GB copies of
en-US). Edit the dict there, rerun it, then upload. Keywords carry no league
or team trademarks.

## QA tour

`scripts/tour.sh <udid> [testT..]` runs `StatScoutTourUITests` one section at
a time on live data and exports numbered frames to `build/tour/`. Source the
credentials first. Run it before every submission and look at every frame.

## Screenshots

`scripts/screenshots/capture.py` drives the DEBUG fixture build with
`-ScreenshotRoute profile|compare|yearCompare` (the UI-test runner times out
walking the leaderboard on the shared pool). The iPhone set renders through
`~/ios/appstore-screenshots/configs/basketball.json`; the iPad 13" frames come
from `scripts/screenshots/ipad_compose.py`. Run captures inside one shell that
holds the `agent-sim` lease, or the lease goes stale between tool calls.

The `submit_review` lane uses `automatic_release: false`. `Deliverfile` lists
the locales currently accepted by Fastlane. The 11 retired App Store locales
are handled by the `fill_deprecated_locales` lane.

## Review contact

`fastlane/metadata/review_information/` is gitignored (it holds the review
phone). Keep a local copy; the Fastfile reads `notes.txt` from there.

## Draft version helper

`ASC_DRAFT_VERSION` is the version to bump from, not the target version. For
example, with 1.0 live, setting `ASC_DRAFT_VERSION=1.0` creates 1.0.1 when
there is no editable draft. `scripts/asc_lib.py` reuses an editable draft and
bumps an existing live version instead of returning it.

If an editable draft's `versionString` is wrong, it can be patched with
`PATCH /appStoreVersions/{id}`. A draft cannot be deleted once a build exists
for its platform (409 `STATE_ERROR`).

## TestFlight build number

`scripts/testflight.sh` increments `CURRENT_PROJECT_VERSION`, regenerates the
XcodeGen project, archives, then uploads. After a successful upload, commit the
updated build number in both `project.yml` and `StatScout.xcodeproj` in a
separate `chore:` commit. That build-number-only push does not need another
TestFlight build.

Before editing `fastlane/metadata/`, run
`./scripts/pull-appstore-metadata.sh` and compare the pull with its timestamped
backup. Do not run the full metadata uploader when changing only one version's
What's New text.
