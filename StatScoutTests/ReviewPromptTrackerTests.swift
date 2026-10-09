import XCTest
@testable import Hardwood_StatScout

/// The rating request fires at passive moments with no question first (an
/// "Enjoying it?" gate that forwards only yes answers is rejected under 5.6.1),
/// so the tracker is the whole policy: how engaged, and how long since the last
/// request.
@MainActor
final class ReviewPromptTrackerTests: XCTestCase {
    private let day: TimeInterval = 86_400

    override func setUp() {
        super.setUp()
        resetTracker()
    }

    override func tearDown() {
        resetTracker()
        super.tearDown()
    }

    nonisolated private func resetTracker() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("reviewPrompt.") {
            defaults.removeObject(forKey: key)
        }
    }

    /// An engaged user: a first open long enough ago, five launches on three
    /// separate days, and three positive moments.
    private func makeEngagedUser(now: Date) {
        ReviewPromptTracker.firstAppOpenDate = now.addingTimeInterval(-10 * day)
        ReviewPromptTracker.appLaunchCount = ReviewPromptTracker.minimumLaunchCount
        UserDefaults.standard.set(ReviewPromptTracker.minimumDistinctUseDays, forKey: "reviewPrompt.distinctUseDays")
        ReviewPromptTracker.positiveMomentCount = ReviewPromptTracker.minimumPositiveMoments
        ReviewPromptTracker.hasPendingPositiveMoment = true
    }

    func testAFreshInstallIsNeverAskedToRate() {
        let now = Date()
        ReviewPromptTracker.recordAppLaunch(now: now)
        ReviewPromptTracker.recordPositiveMoment()
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: now))
    }

    func testAnEngagedUserIsAskedAfterAPositiveMoment() {
        let now = Date()
        makeEngagedUser(now: now)
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: now))
        XCTAssertTrue(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: true, now: now))
    }

    func testNothingIsRequestedBeforeOnboardingCompletes() {
        let now = Date()
        makeEngagedUser(now: now)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: false, now: now))
    }

    func testARequestNeedsAFreshPositiveMoment() {
        let now = Date()
        makeEngagedUser(now: now)
        ReviewPromptTracker.hasPendingPositiveMoment = false
        XCTAssertFalse(ReviewPromptTracker.shouldRequestAfterPositiveMoment(hasCompletedOnboarding: true, now: now))
    }

    func testReturningOnOneDayOnlyIsNotEngagement() {
        let now = Date()
        makeEngagedUser(now: now)
        UserDefaults.standard.set(1, forKey: "reviewPrompt.distinctUseDays")
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: now))
    }

    func testCooldownBlocksAnotherRequestUntilItElapses() {
        let now = Date()
        makeEngagedUser(now: now)
        ReviewPromptTracker.markRequested(now: now)

        XCTAssertFalse(ReviewPromptTracker.hasPendingPositiveMoment, "Asking consumes the moment")
        ReviewPromptTracker.hasPendingPositiveMoment = true
        let soon = now.addingTimeInterval(Double(ReviewPromptTracker.cooldownDays - 1) * day)
        XCTAssertFalse(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: soon))
        let later = now.addingTimeInterval(Double(ReviewPromptTracker.cooldownDays) * day)
        XCTAssertTrue(ReviewPromptTracker.canRequestReview(hasCompletedOnboarding: true, now: later))
    }

    func testRecordingAMomentPostsTheNotification() {
        let posted = expectation(forNotification: .statscoutPositiveMomentForReview, object: nil)
        ReviewPromptTracker.recordPositiveMoment()
        wait(for: [posted], timeout: 1)
        XCTAssertEqual(ReviewPromptTracker.positiveMomentCount, 1)
        XCTAssertTrue(ReviewPromptTracker.hasPendingPositiveMoment)
    }

    func testDistinctUseDaysCountsEachCalendarDayOnce() {
        let now = Date()
        ReviewPromptTracker.recordAppLaunch(now: now)
        ReviewPromptTracker.recordAppLaunch(now: now)
        XCTAssertEqual(ReviewPromptTracker.distinctUseDays, 1)
        ReviewPromptTracker.recordAppLaunch(now: now.addingTimeInterval(2 * day))
        XCTAssertEqual(ReviewPromptTracker.distinctUseDays, 2)
        XCTAssertEqual(ReviewPromptTracker.appLaunchCount, 3)
    }
}
