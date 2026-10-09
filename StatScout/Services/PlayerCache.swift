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

/// Binary-plist-backed cache for the heavyweight historical dataset.
/// Plist decode is ~2-3× faster than JSON on the same payload, and the file is ~30% smaller.
struct PlistPlayerCache: PlayerCaching {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadPlayers() throws -> [Player] {
        let data = try Data(contentsOf: fileURL)
        // Lossy per row, like the network path: one malformed row must not take
        // every past season down with it.
        return try PropertyListDecoder.statScout.decode([Lenient<Player>].self, from: data).compactMap(\.value)
    }

    func savePlayers(_ players: [Player], liveSeason: Int) throws {
        let data = try PropertyListEncoder.statScout.encode(players)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }
}

extension PlistPlayerCache {
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
    private let historical: PlistPlayerCache
    private let legacyHistorical: DiskPlayerCache
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
        self.historical = PlistPlayerCache(fileURL: directory.appending(path: "players-historical.plist"))
        self.legacyHistorical = DiskPlayerCache(fileURL: directory.appending(path: "players-historical.json"), maxAge: nil)
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

    /// The permanent archive: every completed season the bundle carries, plus
    /// the season-0 career rollup. This includes the season that is still live
    /// while the next has not published, so a cold offline start has a board to
    /// draw. Callers merge it *under* server rows (see `loadPlayers`), never
    /// over them, so a frozen bundled snapshot can never overwrite the live feed.
    func loadHistoricalPlayers() -> [Player] {
        let bundled = loadBundledPlayers(named: historicalBundleResourceName)
        let bundledIsComplete = bundled.map { PlayerSnapshotValidator.isCompleteHistorical($0) } ?? false

        // 1. Permanent disk cache, unless the bundled archive has broader coverage.
        if let cached = try? historical.loadPlayers(), !cached.isEmpty {
            if PlayerSnapshotValidator.isCompleteHistorical(cached) || !bundledIsComplete {
                return cached
            }
        }
        // 2. Bundled binary plist (shipped with the app).
        if let bundled, bundledIsComplete {
            try? historical.savePlayers(bundled)
            try? FileManager.default.removeItem(at: legacyHistorical.fileURL)
            return bundled
        }
        // 3. Legacy on-disk JSON cache from older builds - migrate forward.
        if let players = try? legacyHistorical.loadPlayers(), !players.isEmpty {
            try? historical.savePlayers(players)
            try? FileManager.default.removeItem(at: legacyHistorical.fileURL)
            return players
        }
        // 4. Bundled JSON fallback (in case the plist asset is ever missing).
        if let players = loadBundledPlayers(named: historicalBundleResourceName, extension: "json"), !players.isEmpty {
            try? historical.savePlayers(players)
            return players
        }
        return []
    }

    private func loadBundledPlayers(named name: String, extension fileExtension: String = "plist") -> [Player]? {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        if fileExtension == "plist" {
            return try? PropertyListDecoder.statScout.decode([Lenient<Player>].self, from: data).compactMap(\.value)
        }
        return try? JSONDecoder.statScout.decode([Lenient<Player>].self, from: data).compactMap(\.value)
    }

    func savePlayers(_ players: [Player], liveSeason: Int) throws {
        let historicalPlayers = players.filter { ($0.season ?? 0) < liveSeason }
        let currentPlayers = players.filter { ($0.season ?? 0) >= liveSeason }
        if !historicalPlayers.isEmpty {
            try historical.savePlayers(historicalPlayers)
        }
        if !currentPlayers.isEmpty, PlayerSnapshotValidator.isCompleteCurrent(currentPlayers) {
            try current.savePlayers(currentPlayers)
            // Only after the rows are safely down, so a failed write never
            // leaves a marker vouching for a file that isn't there.
            writeCurrentProvenance()
        }
    }
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
