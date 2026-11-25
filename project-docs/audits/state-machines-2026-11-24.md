# State machine audit, 2026-11-24

Scope: the Hardwood StatScout iOS app (one app target). There are no widgets, Watch app, App Intents or notification targets, so no scheduled notifications or widget timelines exist to reconcile. Android is out of scope. Audited from `0bb6057` with no app code changed. Method: the fleet's 2026-11-06 audit (`jackwallner/baseball` `project-docs/audits/state-machines-2026-11-06*.md`).

**Summary: 2 bugs proved by failing test, 2 code path only (not proved).** Plus 6 product calls (not counted).

Evidence run: `gh-sim test --scheme StatScout --only StatScoutTests/StateMachineAuditRepro`, run `basketball@20261125-130518-83e6-claude-mbprof849-1125-131109-15497`, GitHub run `45701983727` (Xcode 27.1, iPhone 17, iOS 27.2), no build settings or secrets passed (the simulator build skips the Supabase check). Result: 4 tests, 2 passed (the controls), 2 failed (the claims). The repro suite is `state-machines-2026-11-24-repro.swift` beside this file; copy it into `StatScoutTests/` to run it.

Test seams used: an injected `StatcastProviding` (`ReproFeedProvider`, a feed that changes per call), `makeViewModel` from `DashboardViewModelTests.swift:11` (its own `UserDefaults` suite, no disk cache), `UserDefaults.standard` and `ReviewPromptTracker` accessors (saved and restored per test), `PaywallGate.shared`, and a `UIHostingController` in a `UIWindow` on the app host. Seams that do not exist: a constructible `CustomerInfo` and an injected purchases client in `StoreService` (RevenueCat is never configured on a simulator), so every purchase claim stays code path.

## Bugs ranked by impact

| ID | Bug | What the user sees | Promise | User route | Impact | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | Returning to a profile from a drill-down counts as another profile open | A free user on their first player page taps one metric row, reads the leaders board and goes back: the trial pitch sheet rises over the page they were already reading. After two such round trips on one profile the review moment fires as if a third profile had been opened. | `PlayerProfileView.swift:262-265`: "Defer the first-impression pitch ... Show it from the *second* profile open onward". `:271`: "Third+ profile visit = engaged browsing." | Stats tab, tap any player (free user). Tap any percentile row, a `NavigationLink(value: MetricRoute)` (`PlayerProfileView.swift:911, 936, 949`), handled by `RootTabView.swift:549`. Tap Back. `onAppear` fires again and counts open 2, so `.playerScouting` presents while `PaywallGate` allows it (2 per session). | Every free user, from their first profile, any device or locale. Metric rows are the main thing on a profile, so the common path hits it. Cost: an unwanted sheet the code deliberately delays, and an early review moment. | `testReturningToOneProfileFromADrillDownIsNotANewProfileOpen` failed with `("3") is not equal to ("1") - one profile opened once, but the counter says more`. Preconditions asserted first: free user, counter 1 after the first open, path depth 1 after two round trips. Control `testControlOpeningTheProfileTwiceCountsTwice` passed (1 then 2). | `PlayerProfileView.swift:261-276` |
| B2 | A refresh keeps live-season rows the publisher pruned | A player the publisher dropped (fell out of the built set) stays on the Stats board, Teams rosters and Compare pickers with his last percentiles, for the rest of the session, ranked against players with fresh numbers. | `backend/ingest.py:731-747` deletes every live-season snapshot it no longer builds ("Pruned stale/unqualified rows"). Onboarding copy `StatScoutApp.swift:502`: "Fresh stats soon after every game". | App open in season. The publisher posts a new revision; the 2-minute poll or a foreground (`StatScoutApp.swift:149-163`) sees it (`DashboardViewModel.swift:1520`) and calls `load()`, which merges the feed over the rows on hand (`mergePlayers(replacing:)`, `:2025`). Pull to refresh takes the same path. A cold launch inside the cache's life does the same over the cached rows. | Any user who keeps the app open or resumes it across a publish that prunes a row, in season. Rows leave the built set routinely, so a few per publish. Cost: a stale row and a misstated rank, not data loss. A later relaunch clears it because the cache is rewritten from the feed. | `testRefreshDropsAPlayerThePublisherPruned` failed with `XCTAssertFalse failed - the publisher pruned this player, but the board still ranks him`. Preconditions: first load shows all 90 rows including him, the second feed request was made, no error, `lastFetchFailed` false. Control `testControlRefreshReplacesARowThatIsStillInTheFeed` passed. | `DashboardViewModel.swift:1692, 1783, 2025-2034` |
| C1 | (Code path, not proved) Ask to Buy is shown as a failed purchase | A child account taps the trial button, chooses Ask, and sees "Couldn't complete the purchase. Please try again." in red (or an older unrelated error line), inviting a retry that sends a second request. | `StatScoutApp.swift:482-484`, `PaywallView.swift:500-503`, `Components.swift:985-987`: "Ask-to-Buy / deferred payment: ... explain instead of appearing dead", with a "pending approval" line. | Onboarding last page, the trial pitch sheet, an upsell card or the plan picker, on a Family Sharing child account. | Child accounts with Ask to Buy on; every attempt. | Not run: RevenueCat reports a deferred purchase by throwing `ErrorCode.paymentPendingError` from `purchase(package:)`, so `StoreService.purchase` (`:762`) never returns `.pending` for it and every caller lands in its `catch`. The `.pending` branches the comments describe are reachable only for a result without the entitlement. No seam builds a RevenueCat throw. | `StoreService.swift:762`, `StatScoutApp.swift:488-490`, `PaywallView.swift:507-509`, `StoreService.swift:801-803` |
| C2 | (Code path, not proved) A failed purchase shows whatever `lastError` last held | After a foreground refresh failed offline, a later purchase failure reads "Couldn't refresh your subscription status. Check your connection and try again." | The callers' own fallback, "Couldn't complete the purchase", is what a purchase failure is meant to say; `purchase` never writes `lastError`. | Background the app offline, return (`updateCustomerProductStatus` writes `lastError`, `StoreService.swift:814`), go online, hit any purchase failure. | Rare: needs a refresh failure then a purchase failure in one session. Cost: a misleading line. | Not run, same missing seam. | `StoreService.swift:802, 814`, `StatScoutApp.swift:489`, `PaywallView.swift:508` |

C1 and C2 are fixed by Rollout A (`rollout-2026-11-24.md`): every purchase error is now mapped by `PurchaseFailure`, which is unit tested.

## Product calls (not counted: documented, or no cited promise)

1. The review ask's gates (`ReviewPromptTracker.swift:29-35`: 5 launches, 7 days since first open, 3 positive moments, 3 distinct days, 120-day cooldown) are far stricter than the fleet's (2nd launch, 30-day cooldown). Documented on purpose; changing them is the star-prompt rollout, out of scope for this run.
2. Unknown intro-offer eligibility: the doc comment on `isEligibleForIntroOffer` (`StoreService.swift:610-612`) says unknown shows the trial, but `refreshIntroEligibility` (`:843`) stores RevenueCat's `.unknown` as ineligible. Which wording a failed lookup should show is a trial-offer decision (same as baseball's PC1).
3. `isPro` starts false and is not persisted (`StoreService.swift:407-410`). A subscriber cold-launching offline depends on RevenueCat delivering cached customer info to the delegate. The Best & Worst board already waits for known entitlement (`StatsBoardControls.swift`, `launchBoard`).
4. `ConversionDiagnostics.recordConversion` runs only on a direct purchase result (`StoreService.swift:767`). A restore, or an Ask to Buy approved later through the delegate, never writes `converted_*` attributes. Attribution only.
5. `PlayerComparisonView.swift:201-205` records a review moment on every `onAppear` for a subscriber, including a return from a pushed screen. The moment is only a pending flag and the 120-day cooldown paces it.
6. `loadHistoricalIfNeeded` fills live-season rows from the bundled archive when they are absent (`DashboardViewModel.swift:1949-1955`). That only matters while the live season is also the newest bundled one (the off-season), when the publisher prunes nothing.

## State machines

### SM1. Entitlement and purchase (`StoreService`)

State: `isConfigured`, `customerInfo`, `isPro`, `purchaseInFlight`, `isLoadingProducts`, `products`, `currentOffering`, `introEligibility`, `lastError`.

States: Unconfigured (simulator) / Configured, customer unknown / Free / Lapsed (`isLapsed`) / Pro.

Invariants: E1 `isPro == customerInfo.hasProEntitlement` after every `apply` (`:846-856`). E2 a purchase message describes that purchase (C1, C2). E3 a CTA naming a trial is for an eligible account. E4 an approval made later unlocks without a relaunch.

| From | Event | To | Invariant |
|---|---|---|---|
| Unconfigured | `start()` on device | Configured, unknown | none |
| Configured, unknown | `customerInfo(.fetchCurrent)` ok | Free or Pro | E1 |
| Configured, unknown | fetch fails offline | unknown, `isPro` false, `lastError` set | product call 3, feeds C2 |
| Free | purchase ok with entitlement | Pro, conversion recorded | E1 |
| Free | user cancels Apple's sheet | Free, "Purchase cancelled" | none |
| Free | Ask to Buy (`paymentPendingError` thrown) | Free, shown as a failure | E2 broken (C1) |
| Free (Ask to Buy) | parent approves, delegate `receivedUpdated` | Pro in place; onboarding finishes via `onChange(isPro)`, the plan picker dismisses | E4 holds |
| Free | other purchase error | Free, stale `lastError` or generic line | E2 broken (C2) |
| Free | restore finds entitlement | Pro | E1 |
| Pro | foreground refresh finds expiry | Lapsed, win-back trigger | E1 |

No stored pending flag exists, so nothing can fire a stale unlock later (the baseball C1 pattern does not apply here).

### SM2. First run (`hasCompletedOnboarding`, `OnboardingCards`)

States: page 0, 1, 2 / Main. Invariants: O1 the tabs are disabled and not hit-testable until done (`StatScoutApp.swift:131-132`); O2 a subscriber skips the upsell.

| From | Event | To | Invariant |
|---|---|---|---|
| page 0-1 | Skip | Main | O1 |
| page 2 | Get Started | Main | O1 |
| page 2 | monthly purchase ok, or `isPro` flips | Main via `onChange(isPro)` | O2 |
| page 2 | Ask to Buy | stays, red failure line | C1 |
| any | killed mid-onboarding | page 0 next launch (intended) | none |

### SM3. Profile opens and the first-open pitch (`profileOpenCount`, `PaywallGate`)

State: `profileOpenCount` in `UserDefaults`, `PaywallGate.presentedCount` per trigger (session), the profile's `trialPitchTrigger`.

Invariants: P1 one pushed profile is one open; P2 the pitch waits for the second open; P3 at most two `.playerScouting` pitches a session; P4 the review moment needs a third open and never fires on a visit that showed the pitch.

| From | Event | To | Invariant |
|---|---|---|---|
| none | push a profile | count + 1 | P1 |
| profile | push a metric board or Compare, then Back | count + 1 again | P1 broken (B1), then P2 and P4 |
| count 1 | open a second profile (free) | pitch sheet | P2, P3 |
| count >= 3 | open a profile, pitch not shown | review moment pending | P4 |

### SM4. Review ask (`ReviewPromptTracker`, `RootTabView`)

State: `appLaunchCount`, `firstAppOpenDate`, `lastRequestedDate`, `positiveMomentCount`, `hasPendingPositiveMoment`, `distinctUseDays`, `lastUseDay`, `reviewRequestedThisSession`.

Invariants: R1 never in onboarding; R2 cooldown in elapsed seconds (immune to time zone and DST); R3 at most one ask a session; R4 a moment that finds the gates shut stays pending.

| From | Event | To | Invariant |
|---|---|---|---|
| idle | positive moment (3rd+ profile, subscriber Compare) | pending, notification posted | R1 checked at ask time |
| pending | 3.5 s later, gates open | asked, `markRequested` | R2, R3 |
| pending | gates shut | pending | R4 |
| any | new calendar day at launch | distinct days + 1 (local calendar) | none; a time zone change can at most count one extra day |

Moments are inflated by B1. Otherwise the tracker holds up (`ReviewPromptTrackerTests`).

### SM5. Live season and data load (`DashboardViewModel`)

State: `live` (season, upcoming) persisted as `statscout.liveSeason` / `statscout.upcomingSeason`, `selectedSeason`, `selectedPhase`, `playerHistories`, `players`, `isLoading`, `lastFetchFailed`, `displayedDataRevision`, `dataFreshness` (cached), the disk cache.

Invariants: D1 a free user is never left on a locked season (`clampSelectedSeason`, `:251`); D2 the board shows the publisher's live-season rows; D3 a partial or regressed feed never replaces a complete one (`:1676-1691`); D4 a revision that moves mid-load is not adopted (`:1765-1776`).

| From | Event | To | Invariant |
|---|---|---|---|
| launch | cache hydrates, feed ok and complete | feed merged over cache | D2 broken for rows the feed dropped (B2) |
| shown | new revision seen by poll or foreground, `load()` | feed merged over rows on hand | D2 broken (B2) |
| shown | partial feed with a complete cache | cache kept, "Showing complete saved data" | D3 |
| shown | revision moves mid-load | nothing adopted, next check reloads | D4 |
| Pro | lapse (`applyProState(false)`) | season clamped to free | D1 |
| status row | season pending to published | `live` advances, remembered | none |

### SM6. Saved board choices (`stats.board`, `stats.board.beforeBestWorst`, `teams.view`, qualifier)

The Best & Worst board waits for known entitlement before resetting a free user (fixed 2026-11-08, `3a78ed5`). `teams.view` falls back to Teams off the live season without rewriting the stored choice. No invalid transition found.

## Phase 2, skeptical self-review

Re-read as an independent reviewer:

- **B1 survives.** The route is the shipping one: `PlayerProfileView` pushes `MetricRoute` through `NavigationLink(value:)` inside the tab's `NavigationStack`, and SwiftUI calls `onAppear` again on the pop. The test drives a real `NavigationStack` with a real `PlayerProfileView`; the control proves the harness sees genuine opens, so the failure is not a broken setup. The pitch itself was kept off screen in the test (gate used up), so the claim rests on the counter, which is what both the pitch and the review moment read.
- **B2 survives.** `load()` is reached by the 2-minute poll and by foreground when the status row's revision changes, and the test's second feed passes the same completeness and regression checks a real publish does (90 rows, 30 teams, 1 missing, under the 20% regression bar). A reviewer could ask whether the publisher really drops live rows: `_prune_orphans` deletes every id it did not build for that season and phase whenever it built at least 150 rows. Survives.
- **C1 and C2 stay code path.** The RevenueCat throw cannot be produced on a simulator without a seam. Not counted as proved; fixed anyway under Rollout A, whose mapping is unit tested.
