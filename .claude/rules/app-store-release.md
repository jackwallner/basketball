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

## Current state, 2026-10-09

- App Store Connect app `6820647074` ("Basketball Next: StatScout", SKU
  `basketball-statscout`, bundle id `com.jackwallner.basketball`, portal id
  `69QDVP4NJT`), created 2026-10-08.
- Version 1.0 is `PREPARE_FOR_SUBMISSION` with build 2 attached and release
  type MANUAL. Metadata, 6 iPhone 6.9" and 3 iPad 13" screenshots, age rating,
  content rights, privacy (Data Not Collected), free price and all-territory
  availability are set.
- Subscriptions `.pro.monthly` ($1.99) and `.pro.yearly` ($9.99), both with a
  1-week trial, and lifetime `.pro` ($19.99) are `READY_TO_SUBMIT` with paywall
  review screenshots. The first group must ride with the version: in the ASC
  web UI press Add for Review on 1.0, add the three products to the draft
  submission, then Submit.
- Only `en-US` metadata exists. 1.0 carries no What's New (Apple rejects it on
  a first version); the drafted note is in the session scratchpad only.

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
