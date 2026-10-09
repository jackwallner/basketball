#if DEBUG
import Foundation

/// Launch with `-ScreenshotRoute profile|compare|yearCompare` (plus
/// `-ScreenshotPlayer` and `-ScreenshotPeer` names) to open the Stats tab
/// already pushed onto that screen.
///
/// The UI-test runner times out walking the leaderboard's accessibility tree
/// on the shared simulator pool, so the App Store captures cannot depend on
/// synthesised taps. Same idea as `-StartTab`. Compiled out of Release.
enum ScreenshotRoute: String {
    case profile
    case compare
    case yearCompare

    static var current: ScreenshotRoute? {
        value(after: "-ScreenshotRoute").flatMap(ScreenshotRoute.init(rawValue:))
    }

    static var playerName: String {
        value(after: "-ScreenshotPlayer") ?? "Shai Gilgeous-Alexander"
    }

    static var peerName: String {
        value(after: "-ScreenshotPeer") ?? "Jalen Brunson"
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
