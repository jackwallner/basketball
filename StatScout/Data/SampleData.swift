#if DEBUG
import Foundation

/// Previews and the debug provider read the same real 2025-26 rows the
/// screenshot harness serves, so there is one set of sample players to keep
/// honest rather than two.
struct SampleData {
    /// Twenty-two 2025-26 players across guards, forwards and centers, plus a
    /// 2024-25 row for six of them so year switching has data.
    static let players: [Player] = ScreenshotFixtureAPI.players
}
#endif
