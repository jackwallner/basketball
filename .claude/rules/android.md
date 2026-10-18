---
paths:
  - "android/**"
  - "docs/android-*.html"
  - "scripts/play_screenshot_compositor.py"
  - "scripts/play-products.py"
  - "scripts/play-upload.sh"
  - "scripts/sync-android-historical.py"
  - "scripts/make_android_icon.py"
---

# Hardwood StatScout Android rules

## Identity and products

- Native Android code is in `android/`, a screen-for-screen port of the iOS app
  (same copy, tokens, flows, product IDs). It started as a copy of
  `~/hockey/android`; everything NHL was replaced with this repo's iOS app as
  the spec. When iOS changes, port the change.
- Package `com.jackwallner.basketball`, Play name "Hoops Edge: Hardwood
  StatScout", launcher label "StatScout", paid tier "StatScout+". Feedback and
  Play contact email `jackwallner+bb@gmail.com`.
- Products (same IDs as iOS): subscriptions
  `com.jackwallner.basketball.pro.monthly` and
  `com.jackwallner.basketball.pro.yearly` (base plans `monthly` / `yearly`,
  7-day `trial-7d` new-customer offer), lifetime one-time product
  `com.jackwallner.basketball.pro`. Android US ladder $1.49 / $7.99 / $15.99,
  about 20% under iOS ($1.99 / $9.99 / $19.99); local prices are Play's
  conversion plus the fleet PPP curve. Never put prices in listing copy or app
  literals.
- RevenueCat project `projf687e8b0`: Test Store app `appba36335343` (Debug key,
  `apikeyf6fcdf78f1`), Play app `appa1887192a1` (`goog_` key
  `apikey1fe08d6c51`, release only), entitlement `Basketball Pro`
  (`entl5dc505a312`, fallback `pro`). The app reads offering `android`
  (`ofrng5a68aa37d7`, not current; iOS keeps `default`) with `$rc_monthly`,
  `$rc_annual`, `$rc_lifetime`, each holding the Play product
  (`...monthly:monthly`, `...yearly:yearly`, `...pro`) and the Test Store twin
  (`monthly`, `annual`, `lifetime`).
- Season model matches iOS: the live season is free and default; older seasons
  (back to 2002-03) and All Time are StatScout+.
- Play reviewers unlock StatScout+ with a code (long-press Settings > App
  Version). Only its SHA-256 is in the build (`PLAY_REVIEW_CODE_SHA256` in
  `local.properties`); the code is `BASKETBALL_PLAY_REVIEW_CODE` in
  `~/.basketball_credentials` and goes in Play Console App access. Never
  commit it.
- No deep link and no URL scheme: iOS has none.

## Deliberate differences from iOS

- Leaderboards use competition ranks (`competitionRanks`): tied values share a
  rank (1, 2, 2, 4). iOS numbers rows by position.
- Live and history loads merge at ingest time on the main thread
  (`DashboardViewModel.ingestPlayers(mergePlayers(...))`), so whichever lands
  second never drops the other's seasons.
- Recent form, games and box-score ids are fetched with `paged { offset }`
  because PostgREST caps a response at 1,000 rows.
- `selectSeason` starts the historical load when a past season is picked,
  instead of waiting for the screen to ask.
- Recent controls are hidden for seasons without per-game history
  (`supportsRecentForm`, 2025-26 on), rather than showing an empty window.
- Purchase copy names Google Play and has no "24 hours before the end of the
  period" clause (Play has no such rule). `PriceDisclosureTest` pins it.
- Settings says "Rate on Google Play"; the review prompt keeps the iOS gates
  (second launch on, onboarding done, 30-day cooldown) and goes through
  `launchReviewFlow` only when the window has focus.

## Build

- JDK 17, checked-in Gradle wrapper, AGP 9.4.1, minSdk 26, target/compile 36.
- `android/local.properties` (ignored, mode 600) holds `REVENUECAT_TEST_KEY`,
  `REVENUECAT_PLAY_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (same Supabase
  project as iOS), `PLAY_REVIEW_CODE_SHA256` and `PLAY_UPLOAD_*` (upload
  keystore `~/.android/keystores/basketball-upload.p12`, alias `upload`,
  password `BASKETBALL_PLAY_UPLOAD_PASSWORD` in `~/.basketball_credentials`).
  Release builds fail without them. Upload cert SHA-256
  `65:5E:42:D1:09:4E:C9:41:AB:94:15:48:B6:6F:B6:B5:4C:91:A9:39:18:AE:20:6B:75:9D:BA:13:A7:68:DE:60`.
- `qa` build type: R8 release config, debug signing, no RevenueCat key; use it
  for emulator speed checks.
- `scripts/sync-android-historical.py` writes one gzip JSON asset per season,
  `app/src/main/assets/players-historical-<season>.bin` (0 is All Time), from
  the iOS `StatScout/Data/players-historical-<season>.plist` files. Rerun it
  after every `export_historical.py` run. Never name an asset `.gz`: the
  packager inflates it and drops the extension, so past seasons vanish.
- `scripts/make_android_icon.py` derives the adaptive icon layers and
  `play-assets/icon-512.png` from the iOS AppIcon.
- Increment `versionCode` on every Play upload. 1.0 is versionCode 1.
- `scripts/play-upload.sh [validate|internal|internal-draft|production-draft]`
  and `scripts/play-products.py [--dry-run]` need `PLAY_SERVICE_ACCOUNT_JSON`.
  Neither has been run yet.

## Emulator (remote MacBook Pro only)

Follow the `android-dev` skill's Remote MacBook Pro section. Host
`jackwallner@192.168.4.25` (strict host keys), SDK
`/Users/jackwallner/Library/Android/sdk`. The Pro has no cmdline-tools and no
JDK 17: sync `android/` (minus `build/`, `.gradle/`, `local.properties`,
`play-assets/`) to `~/basketball-agent-test/android`, write a debug-only
`local.properties` (sdk.dir, Supabase URL and anon key, Test Store key, review
digest), and unpack a temporary Temurin 17 into `~/basketball-agent-test/jdk`.
Create the temporary AVD `basketball_agent_test` by hand (`.ini` plus a
`config.ini` cloned from another agent AVD with `hw.lcd.height = 2400`,
`android-36` `google_apis_playstore` x86_64, 1080x2400), boot it headless on
port 5564 (`emulator-5564`), and delete only it (and
`~/basketball-agent-test`) afterwards with `adb -s emulator-5564 emu kill`.
Never touch `small_phone` or other agents' AVDs. The Pro is a 2-core 2015
i7: a cold boot takes about 5 minutes and Play services churn can trip System
UI ANRs for the first ~30 minutes, so let it settle before trusting a
connected run (the live-feed test needs about 75 s once warm).

Debug launch extras (`DebugLaunchOptions`, debug builds only): `resetAll`,
`onboarded`, `forcePro`, `previewStore`, `previewTrialUsed`, `tab`,
`onboardingPage`, `uiTest`, `statsBoard`, and `screenshotData` (the 2025-26
fixture feed, `ScreenshotFixtureApi`), with `fixtureFresh` and
`fixtureStatus published` as on iOS.

## Store assets

`StoreScreenshotTest` (excluded from the connected suite; run it with
`am instrument -e class com.jackwallner.basketball.StoreScreenshotTest`) writes
the seven raw 1080x2400 captures to
`/sdcard/Android/data/com.jackwallner.basketball/files/screens/` with System UI
demo mode on. Pull them into `android/play-assets/raw/` and run
`python3 scripts/play_screenshot_compositor.py` for the 1080x1920 frames (App
Store headlines) and the 1024x500 feature graphic. Shot 01 sorts the board by
Pts/100 like iOS; shot 05 frames the Shooting section (the fixture holds only
part of each roster, so the scaled team Pts/100 reads high); shot 07 is the
all-teams grid. The compositor sets font axes by name: SF Rounded has only
GRAD and Weight. Listing text and the
changelog are in `android/play-assets/metadata/android/en-US/` (English only).
Privacy and terms pages are `docs/android-privacy.html` and
`docs/android-terms.html` on GitHub Pages.

## Play state (2026-10-17)

Ready to send (verified 2026-10-17): review code saved in App access, RevenueCat
Play credentials set. Only Send for review remains, in this app's pacing slot.

Staged, not sent for review. Play app id `4974676872954034270` (E3 Apps).
versionCode 1 (1.0) uploaded with `~/docs/android/tools/play_stage.py`;
listing, icon, feature graphic and 7 screenshots committed by API; draft
releases on internal and production, production targets all 178 countries.
Products from `scripts/play-products.py` are active (two subscriptions with
`trial-7d`, one lifetime). App content is complete: privacy policy, no ads, no
ad ID, not a government app, no financial features, App access (instructions
only), 18 and over, data safety (RevenueCat: purchase history, app
interactions, device IDs), IARC (not educational; Brazil ClassInd shows 14+),
category Sports. Publishing overview shows "Submit 11 changes for review".

Left for Jack: paste `BASKETBALL_PLAY_REVIEW_CODE` from
`~/.basketball_credentials` into App access > StatScout+ review unlock >
Password, then press Send for review when this app's pacing slot comes. Review codes:
`~/docs/android/tools/play_handoff.py review-codes`. RevenueCat Play credentials
were uploaded with `play_handoff.py rc-credentials --apply` on
 2026-10-17. The RevenueCat service account already has account-wide
Play permissions, so no per-app grant is needed.
