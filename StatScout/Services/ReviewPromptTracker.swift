import Foundation

extension Notification.Name {
    /// Posted after a passive positive moment. The host may ask Apple for the
    /// rating prompt after a short delay.
    static let statscoutPositiveMomentForReview = Notification.Name("com.jackwallner.basketball.positiveMomentForReview")
}

/// Persists launch counts, positive moments and the cooldown for asking Apple
/// to show its rating prompt.
///
/// The prompt is requested directly at a passive moment, with no question
/// first. An earlier version asked "Enjoying it?" and forwarded only the yes
/// answers to the store, which App Review rejects as review manipulation
/// (guideline 5.6.1). Apple rate-limits `requestReview()` itself, so the
/// cooldown here only keeps us from asking more often than we need to.
@MainActor
enum ReviewPromptTracker {
    private static let defaults = UserDefaults.standard

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastRequestedKey = "reviewPrompt.lastRequestedDate"
    private static let positiveMomentCountKey = "reviewPrompt.positiveMomentCount"
    private static let pendingPositiveMomentKey = "reviewPrompt.pendingPositiveMoment"
    private static let distinctDaysKey = "reviewPrompt.distinctUseDays"
    private static let lastUseDayKey = "reviewPrompt.lastUseDay"

    static let minimumLaunchCount = 5
    static let minimumDaysSinceFirstOpen = 7
    static let minimumPositiveMoments = 3
    static let cooldownDays = 120
    /// Separate calendar days of use before a request is allowed. Three taps in
    /// one sitting isn't a habit; three days is.
    static let minimumDistinctUseDays = 3

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: firstOpenKey)
            } else {
                defaults.removeObject(forKey: firstOpenKey)
            }
        }
    }

    static var lastRequestedDate: Date? {
        get { defaults.object(forKey: lastRequestedKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastRequestedKey)
            } else {
                defaults.removeObject(forKey: lastRequestedKey)
            }
        }
    }

    static var positiveMomentCount: Int {
        get { max(defaults.integer(forKey: positiveMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: positiveMomentCountKey) }
    }

    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: pendingPositiveMomentKey) }
        set { defaults.set(newValue, forKey: pendingPositiveMomentKey) }
    }

    /// Skip passive requests during UI tests / Fastlane snapshot runs.
    static var isAutomationRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
            || ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
    }

    /// Distinct calendar days the app has been opened.
    static var distinctUseDays: Int {
        max(defaults.integer(forKey: distinctDaysKey), 0)
    }

    /// Bump the distinct-day counter once per calendar day. Returning on
    /// separate days is the retention signal the request leans on.
    private static func recordUseDay(now: Date) {
        // Local calendar on purpose: "a different day" should mean the user's
        // day, not UTC's. Built from components rather than a cached formatter,
        // which isn't Sendable under Swift 6 strict concurrency.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let key = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        guard defaults.string(forKey: lastUseDayKey) != key else { return }
        defaults.set(key, forKey: lastUseDayKey)
        defaults.set(distinctUseDays + 1, forKey: distinctDaysKey)
    }

    static func recordAppLaunch(now: Date = .now) {
        recordUseDay(now: now)
        if firstAppOpenDate == nil {
            firstAppOpenDate = now
        }
        appLaunchCount += 1
    }

    static func recordPositiveMoment() {
        positiveMomentCount += 1
        hasPendingPositiveMoment = true
        NotificationCenter.default.post(name: .statscoutPositiveMomentForReview, object: nil)
    }

    static func consumePendingPositiveMoment() {
        hasPendingPositiveMoment = false
    }

    static func cooldownElapsed(now: Date = .now) -> Bool {
        guard let last = lastRequestedDate else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(cooldownDays) * 86_400
    }

    static func canRequestReview(
        hasCompletedOnboarding: Bool,
        now: Date = .now
    ) -> Bool {
        guard !isAutomationRun else { return false }
        guard hasCompletedOnboarding else { return false }
        guard cooldownElapsed(now: now) else { return false }
        guard appLaunchCount >= minimumLaunchCount else { return false }
        guard positiveMomentCount >= minimumPositiveMoments else { return false }
        guard distinctUseDays >= minimumDistinctUseDays else { return false }
        guard let first = firstAppOpenDate else { return false }
        let minInterval = TimeInterval(minimumDaysSinceFirstOpen) * 86_400
        guard now.timeIntervalSince(first) >= minInterval else { return false }
        return true
    }

    static func shouldRequestAfterPositiveMoment(
        hasCompletedOnboarding: Bool,
        now: Date = .now
    ) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canRequestReview(hasCompletedOnboarding: hasCompletedOnboarding, now: now)
    }

    /// Call right after asking Apple for the prompt, whether or not it shows.
    static func markRequested(now: Date = .now) {
        lastRequestedDate = now
        consumePendingPositiveMoment()
    }
}
