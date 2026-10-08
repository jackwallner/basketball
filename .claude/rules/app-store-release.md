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

## Current state, 2026-10-08

- App Store Connect app `6820647074` ("Basketball Next: StatScout", SKU
  `basketball-statscout`, bundle id `com.jackwallner.basketball`, portal id
  `69QDVP4NJT`), created 2026-10-08.
- Version 1.0 (build 1) is the first build; ASC created the 1.0 version with the app record. Submit with manual release
  (`automatic_release: false`, releaseType MANUAL).
- The first subscription group ships with the version: attach the three IAPs to
  the version before submitting, or review will reject the paywall.
- Only `en-US` metadata exists. Localized metadata is regenerated from en-US
  when the listing is live; do not copy the Football locales.

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
