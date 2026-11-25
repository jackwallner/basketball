# Fixes for the 2026-11-24 state machine audit

Fixes for every claim in `state-machines-2026-11-24.md` that survived the Phase 2 review, in ranked order.

**Summary: 4 claims. 4 fixed, 0 held, 0 skipped.** B1 and B2 were proved by failing tests on `0bb6057` (GitHub run `45701983727`); C1 and C2 are code path only and were fixed with Rollout A, whose mapping is unit tested.

## Claims

| ID | Outcome | Commit | Regression test | What changed |
|---|---|---|---|---|
| B1 | Fixed | `fix: count a player page once per visit, not on every pop back` | `ProfileOpenRegressionTests.testReturningToOneProfileFromADrillDownIsNotANewProfileOpen` (the repro, failed on `0bb6057` with `("3") is not equal to ("1")`), upgrade `testExistingOpenCountCarriesOverAndCountsOncePerProfile`, control `testControlOpeningTheProfileTwiceCountsTwice` | `PlayerProfileView` counts an open once per pushed profile: a `@State hasCountedOpen` guard in `onAppear`. The stored `profileOpenCount` key and its meaning are unchanged, so an existing install keeps its count. The pitch deferral and the review moment both read that count, so both now follow the documented rule. |
| B2 | Fixed | `fix: drop players the publisher pruned when the board refreshes` | `PrunedFeedRegressionTests.testRefreshDropsAPlayerThePublisherPruned` (the repro, failed on `0bb6057`), upgrade `testColdLaunchFromAnExistingCacheDropsThePrunedRow` (a 1.0.1 cache still holding the row), controls `testRefreshStillReplacesARowThatIsInTheFeed`, `testRefreshKeepsPastSeasonRows` | `DashboardViewModel.mergePlayers(replacing:authoritative:)`: an accepted live feed replaces every row of each season and phase it carries; other seasons and phases are kept. Partial or regressed feeds are still rejected before the merge, so the complete cache is kept as before (`testPartialRefreshPreservesCompleteCache`). |
| C1 | Fixed | `fix: show a pending Ask to Buy as waiting for approval, not a failure` | `PurchaseFailureTests.testAskToBuyIsWaitingForApproval`, `testPendingCopyIsCalm` | `StoreService.purchase` maps RevenueCat's `paymentPendingError` throw to the existing `.pending` outcome, which every surface already renders as a calm line. Not proved headless (RevenueCat is never configured on a simulator). |
| C2 | Fixed | same commit as C1 | `PurchaseFailureTests.testLostConnectionSaysSo`, `testOtherErrorsKeepTheExistingLine` | Purchase errors are mapped by `PurchaseFailure` instead of reading the shared `lastError`. |

The regression tests for B1 and B2 are the audit's repro tests moved into `StatScoutTests/StateMachineRegressionTests.swift`; their failure on the starting commit is the audit's evidence run.

## Held for Jack

None from the claims. The audit's product calls 1 and 2 (the review ask's strict gates, and trial wording when intro eligibility is unknown) are decisions, listed in the audit and in `rollout-2026-11-24.md`.

## Skipped

None.
