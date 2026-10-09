import Foundation

protocol PlayerCaching: Sendable {
    func loadPlayers() throws -> [Player]
    /// Persists a snapshot. `liveSeason` is the season the server is currently
    /// writing: rows from it onward are the expiring server tier, everything
    /// before it is permanent history.
    func savePlayers(_ players: [Player], liveSeason: Int) throws
}

struct DiskPlayerCache: PlayerCaching {
    let fileURL: URL
    private let maxAge: TimeInterval?

    /// Pass `nil` for maxAge to disable expiration (permanent cache).
    init(fileManager: FileManager = .default, maxAge: TimeInterval? = 48 * 60 * 60) {
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.fileURL = directory.appending(path: "players-cache.json")
        self.maxAge = maxAge
    }

    init(fileURL: URL, maxAge: TimeInterval? = 48 * 60 * 60) {
        self.fileURL = fileURL
        self.maxAge = maxAge
    }

    func loadPlayers() throws -> [Player] {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let maxAge = maxAge,
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > maxAge {
            throw URLError(.resourceUnavailable)
        }
        return try loadPlayersIgnoringAge()
    }

    func loadPlayersIgnoringAge() throws -> [Player] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.statScout.decode([Player].self, from: data)
    }

    func savePlayers(_ players: [Player], liveSeason: Int) throws {
        let data = try JSONEncoder.statScout.encode(players)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }
}

extension DiskPlayerCache {
    func savePlayers(_ players: [Player]) throws {
        try savePlayers(players, liveSeason: 0)
    }
}

/// Proof that the current-season snapshot on disk came from the server, written
/// beside it whenever this build saves one.
///
/// Without a marker the only honest reading of a file at that path is "unknown
/// origin": a bundled export and a server response look identical on disk, and
/// the opening-week validator accepts both, by design, so it can never be the
/// thing that separates them.
struct CurrentSnapshotProvenance: Codable {
    /// Bump when what the snapshot file means changes.
    static let currentSchema = 1
    var schema: Int = currentSchema
    var savedAt: Date
}

/// Two-tier cache: a permanent archive of past seasons, and the newest server
/// snapshot for the live one.
///
/// The bundled archive carries every completed season, which includes the
/// live one while the next has not published (2025-26 is both in the bundle and
/// live from the network until 2026-27 tips off). The tiers therefore overlap on
/// purpose, and the rule is precedence rather than exclusion: the server copy
/// wins when present, and the bundled copy is what a cold, offline start shows
/// until it arrives.
struct TwoTierPlayerCache: PlayerCaching {
    private let current: DiskPlayerCache
    private let currentProvenanceURL: URL
    private let bundle: Bundle
    private let historicalBundleResourceName: String

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        bundle: Bundle = .main,
        historicalBundleResourceName: String = "players-historical"
    ) {
        let directory = directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.current = DiskPlayerCache(fileURL: directory.appending(path: "players-current.json"), maxAge: nil)
        self.currentProvenanceURL = directory.appending(path: "players-current-provenance.json")
        self.bundle = bundle
        self.historicalBundleResourceName = historicalBundleResourceName
    }

    func loadPlayers() throws -> [Player] {
        let currentPlayers = (try? loadCurrentPlayers()) ?? []
        let served = Set(currentPlayers.map(\.id))
        // Server rows win a clash with the archive.
        return loadHistoricalPlayers().filter { !served.contains($0.id) } + currentPlayers
    }

    /// The last snapshot this device accepted from the server, whatever its age.
    ///
    /// Only server data is ever returned. An old saved snapshot is still the
    /// user's newest real data, and the freshness caption restored beside it says
    /// how old it is.
    func loadCurrentPlayers() throws -> [Player] {
        // A file with no provenance marker cannot be vouched for as server data,
        // so it is discarded once rather than kept and presented as the live
        // league. The cost is one refresh; the next save writes the marker and
        // this never happens again. See `CurrentSnapshotProvenance`.
        guard hasServerProvenance else {
            discardCurrentSnapshot()
            return []
        }
        guard let cached = try? current.loadPlayersIgnoringAge(),
              PlayerSnapshotValidator.isCompleteCurrent(cached) else {
            return []
        }
        return cached
    }

    private var hasServerProvenance: Bool {
        guard let data = try? Data(contentsOf: currentProvenanceURL),
              let marker = try? JSONDecoder.statScout.decode(CurrentSnapshotProvenance.self, from: data)
        else { return false }
        return marker.schema == CurrentSnapshotProvenance.currentSchema
    }

    private func discardCurrentSnapshot() {
        try? FileManager.default.removeItem(at: current.fileURL)
        try? FileManager.default.removeItem(at: currentProvenanceURL)
    }

    private func writeCurrentProvenance() {
        guard let data = try? JSONEncoder.statScout.encode(CurrentSnapshotProvenance(savedAt: Date())) else { return }
        try? FileManager.default.createDirectory(
            at: currentProvenanceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: currentProvenanceURL, options: [.atomic])
    }

    /// Every season the bundle carries, in the order `bundledSeasons` lists them.
    ///
    /// The archive is one plist per season (see `scripts/export_historical.py`),
    /// because PropertyListDecoder costs about half a millisecond a row: the
    /// old single file took around five seconds to decode in a release build, and
    /// an offline first launch waited on all of it before showing a row. Each
    /// file is independent, so this decodes them on every core at once.
    ///
    /// Callers merge it *under* server rows (see `loadPlayers`), never over
    /// them, so a frozen bundled snapshot can never overwrite the live feed.
    func loadHistoricalPlayers() -> [Player] {
        let seasons = Self.bundledSeasons
        let results = ResultSlots<[Player]>(count: seasons.count)
        DispatchQueue.concurrentPerform(iterations: seasons.count) { index in
            results.set(index, loadHistoricalSeason(seasons[index]))
        }
        return results.values.flatMap { $0 }
    }

    /// One bundled season, or the career rollup for `StatScoutSeason.allTime`.
    /// Empty when the bundle has no file for it.
    func loadHistoricalSeason(_ season: Int) -> [Player] {
        loadBundledPlayers(named: "\(historicalBundleResourceName)-\(season)") ?? []
    }

    /// The newest bundled season that is no later than `season`: what an offline
    /// cold start can show in place of a live feed it cannot reach.
    func loadNewestBundledSeason(atMost season: Int) -> [Player] {
        guard let newest = Self.bundledSeasons.filter({ $0 != StatScoutSeason.allTime && $0 <= season }).max()
        else { return [] }
        return loadHistoricalSeason(newest)
    }

    /// The career rollup first, then each season from the earliest up.
    static var bundledSeasons: [Int] {
        [StatScoutSeason.allTime] + Array(StatScoutSeason.earliest...StatScoutSeason.bundledNewest)
    }

    private func loadBundledPlayers(named name: String) -> [Player]? {
        guard let url = bundle.url(forResource: name, withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListDecoder.statScout.decode([Lenient<Player>].self, from: data).compactMap(\.value)
    }

    /// Saves the live season's rows. Past seasons are never written: the bundle
    /// is the permanent archive, and a second copy in Caches only cost a
    /// multi-second write the first time anything asked for history.
    func savePlayers(_ players: [Player], liveSeason: Int) throws {
        let currentPlayers = players.filter { ($0.season ?? 0) >= liveSeason }
        if !currentPlayers.isEmpty, PlayerSnapshotValidator.isCompleteCurrent(currentPlayers) {
            try current.savePlayers(currentPlayers)
            // Only after the rows are safely down, so a failed write never
            // leaves a marker vouching for a file that isn't there.
            writeCurrentProvenance()
        }
    }
}

/// Fixed-size result slots for `DispatchQueue.concurrentPerform`, which hands
/// out indices rather than collecting return values.
private final class ResultSlots<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [Value?]

    init(count: Int) { slots = Array(repeating: nil, count: count) }

    func set(_ index: Int, _ value: Value) {
        lock.lock()
        slots[index] = value
        lock.unlock()
    }

    var values: [Value] { lock.lock(); defer { lock.unlock() }; return slots.compactMap { $0 } }
}

enum PlayerSnapshotValidator {
    /// 2002-03 and 2003-04 were played by 29 teams; the Bobcats joined in
    /// 2004-05.
    private static let minimumHistoricalTeamCount = 29
    private static let requiredTypes: Set<String> = ["g", "f", "c"]

    /// Every season the bundle promises, each with a full league of teams and
    /// all three position cohorts.
    static func isCompleteHistorical(
        _ players: [Player],
        through lastSeason: Int = StatScoutSeason.bundledNewest
    ) -> Bool {
        let expectedSeasons = Set(StatScoutSeason.earliest...lastSeason)
        let grouped = Dictionary(grouping: players.filter {
            guard let season = $0.season else { return false }
            return expectedSeasons.contains(season)
                && $0.seasonPhase == .regular
        }, by: { $0.season! })

        guard Set(grouped.keys) == expectedSeasons else { return false }
        return grouped.values.allSatisfy { seasonPlayers in
            let teams = Set(seasonPlayers.map { normalizedTeamAbbreviation($0.team) })
            let types = Set(seasonPlayers.compactMap(\.playerType).map { $0.lowercased() })
            return teams.count >= minimumHistoricalTeamCount
                && requiredTypes.isSubset(of: types)
                && seasonPlayers.allSatisfy { !$0.metrics.isEmpty }
        }
    }

    /// A usable live-season snapshot. `season` is the one expected; nil means
    /// the newest regular season present, which is how a saved snapshot is
    /// judged without knowing which season was live when it was written.
    static func isCompleteCurrent(_ players: [Player], season: Int? = nil) -> Bool {
        let regular = players.filter { $0.seasonPhase == .regular }
        guard let target = season ?? regular.compactMap(\.season).max() else { return false }
        let current = regular.filter { $0.season == target }
        let teams = Set(current.map { normalizedTeamAbbreviation($0.team) })
        let types = Set(current.compactMap(\.playerType).map { $0.lowercased() })
        let metricLabels = Set(current.flatMap(\.metrics).map(\.label))
        let requiredMetrics: Set<String> = ["Pts/100", "AST%", "REB%"]
        // The first published game has two teams. A 30-team requirement kept
        // valid opening-night data out of the cache until every team had played.
        // The publisher checks game coverage and regression before promotion.
        return teams.count >= 2
            && current.count >= 20
            && requiredTypes.isSubset(of: types)
            && requiredMetrics.isSubset(of: metricLabels)
    }
}

extension JSONEncoder {
    static var statScout: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension PropertyListEncoder {
    static var statScout: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}

extension PropertyListDecoder {
    /// Conversion script stores dates as native plist Date values, so default decoding works.
    static var statScout: PropertyListDecoder { PropertyListDecoder() }
}
