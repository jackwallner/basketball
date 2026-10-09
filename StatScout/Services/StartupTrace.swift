import Foundation
import os

/// Timestamps for the launch path, logged to the unified log so a cold start
/// can be measured on a simulator or a device without Instruments:
/// `log stream --predicate 'subsystem == "com.jackwallner.basketball" && category == "startup"'`.
///
/// Each line carries the milliseconds since the first mark (taken in the app's
/// init) and whether the work ran on the main thread, which is the question
/// that matters when the first screen is slow.
enum StartupTrace {
    private static let logger = Logger(subsystem: "com.jackwallner.basketball", category: "startup")
    private static let origin = ProcessInfo.processInfo.systemUptime

    /// Call once, first thing in `App.init`, to pin the origin.
    static func begin() { _ = origin; mark("app init") }

    static func mark(_ event: String) {
        let ms = Int((ProcessInfo.processInfo.systemUptime - origin) * 1000)
        let thread = Thread.isMainThread ? "main" : "bg"
        logger.info("+\(ms, privacy: .public)ms [\(thread, privacy: .public)] \(event, privacy: .public)")
    }
}
