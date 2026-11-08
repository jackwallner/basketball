# Pre-submit deep review, 2026-11-08

Scope: every user-reachable path on `origin/main` (92cd3b3), not just the diff
since the live version. The live version is 1.0; the last commit at
`MARKETING_VERSION: "1.0"` is `30ef703^` (7f4246e), and HEAD is 1.0.1 (12).
Reviewed:

- purchase, restore, trial eligibility and the paywall (`StoreService`,
  `PaywallView`, `TrialPitchSheet`, `PlusDirectCTA`)
- onboarding and Pro gating
- persistence (`PlayerCache`, `FavoritesStore`, `ReviewPromptTracker`,
  `@AppStorage` keys)
- network decoding, Info.plist and entitlements
- a crash sweep of every model, view and the view model

The app has no notifications, widgets, app intents, SwiftData or Core Data. It
ships English only. No simulator or local xcodebuild was used.

| Severity | Location | What happens | Status |
|---|---|---|---|
| P1 | `StatScout/Views/StatsView.swift:74` | The launch reset meant for free users ("must not relaunch onto the Best & Worst gate") ran on the first frame, while `isPro` still reads false until RevenueCat answers. A subscriber's saved Best & Worst board went back to Advanced on every cold launch. | Fixed: the reset waits for customer info (`StatsBoard.launchBoard`). Test `StandardStatsTests.testBestWorstBoardWaitsForEntitlementBeforeResetting`. |
| P1 | `StatScout/Models/GameDetail.swift:165` | The game page's margin chart is keyed by `elapsed` seconds. The backend writes one point per play, so free-throw trips and quarter boundaries (720 s ends Q1 and starts Q2) give duplicate ids inside the chart's `ForEach`. Marks can be dropped or merged. This is the same defect class as 92cd3b3. | Fixed: points are keyed by their position in the series. Test `GamesTests.testMarginPointsAtTheSameSecondKeepDistinctIdentities`. |
| P2 | `StatScout/Services/StoreService.swift:843` | `.unknown` intro eligibility maps to `false`, though `isEligibleForIntroOffer` documents unknown as `true`. When StoreKit cannot answer, the copy omits a trial that Apple may still grant. | Not fixed: this errs toward understating the offer, which is the safe direction for 3.1.2(c), so it is not worth changing purchase copy on the last check. |
| P2 | `StatScout/Views/PlayerComparisonView.swift:117`, `StatScout/Views/YearComparisonView.swift:396` | `Dictionary(uniqueKeysWithValues:)` over `standard_stats` labels would trap on a repeated label. | Not fixed: unreachable today. The backend builds the labels from a fixed unique list, and the 25 bundled plists have no duplicates. |
| P2 | `StatScout/Views/PlayerProfileView.swift:266` | `onAppear` counts every return to a profile (popping back from a metric page) as a new open, so the scouting pitch can reappear sooner than "second open" suggests. | Not fixed: `PaywallGate` caps it at two per session, and the sheet is dismissible. |
| P2 | `StatScout/StatScoutApp.swift:393` | On the last onboarding page, Restore Purchases is hidden while league data is still loading. | Not fixed: Restore is still on the paywall and in Settings, and the slot appears once data loads. |
| P2 | `support.html` on the published site | The support FAQ says the data is "public pitch-tracking data", text left over from the baseball app. | Not fixed: website copy, outside app code. |

No P0 found. Checked and clean:

- the paywall close button is always reachable
- Terms and Privacy links are on all three purchase surfaces, and both URLs return 200
- the price lead sits above every transacting button
- the restore and pending (Ask to Buy) paths report an outcome
- `isPro` cannot unlock free users (the DEBUG overrides are compiled out of Release)
- RevenueCat is never configured on a simulator
- the offering falls back to direct product lookup
- cache decoding is lenient or `try?` everywhere
- no debug UI is reachable in Release
- there are no health claims and no links to other platforms
