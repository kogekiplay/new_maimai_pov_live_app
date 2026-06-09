import Foundation
import OSLog

struct Song: Codable, Sendable {
    let id: Int
    let title: String
    let titleSort: String?
    let artist: String?
    let genre: String?
    let genreId: Int?
    let bpm: Int?
    let chartType: String?
    let addVersion: String?
    let addVersionId: Int?
    let releaseTag: String?
    let versionCode: Int?
    let longMusic: Bool?
    let utageKanji: String?
    let utagePlayStyle: Int?
    let notes: [SongNote]

    enum CodingKeys: String, CodingKey {
        case id, title, artist, genre, bpm, notes
        case titleSort = "title_sort"
        case genreId = "genre_id"
        case chartType = "chart_type"
        case addVersion = "add_version"
        case addVersionId = "add_version_id"
        case releaseTag = "release_tag"
        case versionCode = "version_code"
        case longMusic = "long_music"
        case utageKanji = "utage_kanji"
        case utagePlayStyle = "utage_play_style"
    }
}

enum DifficultyValue: Codable, Equatable, Sendable {
    case intValue(Int)
    case stringValue(String)

    var isUtage: Bool {
        if case .stringValue(let v) = self { return v == "utage" }
        return false
    }

    var intVal: Int? {
        if case .intValue(let v) = self { return v }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .intValue(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .stringValue(stringValue)
        } else {
            self = .intValue(0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .intValue(let v): try container.encode(v)
        case .stringValue(let v): try container.encode(v)
        }
    }
}

struct SongNote: Codable, Sendable {
    let difficulty: DifficultyValue
    let level: String
    let levelValue: Double
    let noteDesigner: String?
    let maxNotes: Int?
    let isEnable: Bool

    enum CodingKeys: String, CodingKey {
        case difficulty, level
        case levelValue = "level_value"
        case noteDesigner = "note_designer"
        case maxNotes = "max_notes"
        case isEnable = "is_enable"
    }
}

struct SongListData: Codable, Sendable {
    let schemaVersion: Int?
    let generatedAt: String?
    let songCount: Int?
    let countsByChartType: [String: Int]?
    let songs: [Song]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case songCount = "song_count"
        case countsByChartType = "counts_by_chart_type"
        case songs
    }
}

struct AliasEntry: Codable, Sendable {
    let songId: String
    let aliases: [String]

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case aliases
    }
}

struct AliasListData: Codable, Sendable {
    let aliases: [AliasEntry]
}

struct NoteResult: Sendable {
    let diffName: String
    let level: Double
    let levelValue: Double
    let noteIndex: Int
}

enum MatchKind: String, Sendable {
    case id
    case title
    case alias
    case fuzzyTitle = "fuzzy_title"
    case fuzzyAlias = "fuzzy_alias"
}

enum ResolvedDifficulty: Equatable, Sendable {
    case level(Int)
    case utage
}

struct FindCandidatesResult: Sendable {
    let candidates: [Song]
    let matchKind: MatchKind?
}

class SongDatabase {
    private static let logger = Logger(subsystem: "com.maimai.MaimaiPOV", category: "SongDatabase")

    struct LoadSummary: Sendable {
        let loadedCount: Int
        let standardCount: Int
        let dxCount: Int
        let utageCount: Int
        let titleIndexCount: Int
        let aliasIndexCount: Int
    }

    struct BundleSnapshot: Sendable {
        let songList: [Song]
        let aliasMap: [String: [String]]
        let byId: [Int: Song]
        let byTitle: [String: [Song]]
        let byAlias: [String: [Song]]
        let summary: LoadSummary
    }

    enum BundleLoadResult: Sendable {
        case success(BundleSnapshot)
        case failure(String)
    }

    private var songList: [Song] = []
    private var aliasMap: [String: [String]] = [:]

    private var byId: [Int: Song] = [:]
    private var byTitle: [String: [Song]] = [:]
    private var byAlias: [String: [Song]] = [:]

    private let diffMap: [String: ResolvedDifficulty] = [
        "绿": .level(0), "basic": .level(0),
        "黄": .level(1), "advanced": .level(1),
        "红": .level(2), "expert": .level(2),
        "紫": .level(3), "master": .level(3),
        "白": .level(4), "remaster": .level(4), "re:master": .level(4),
        "宴": .utage, "utage": .utage
    ]

    private let diffNumToName: [Int: String] = [
        0: "easy", 1: "advanced", 2: "expert", 3: "master", 4: "remaster"
    ]

    var songCount: Int { songList.count }
    var lastError: String?

    static func makeBundleSnapshot() -> BundleLoadResult {
        var songURL: URL?
        var aliasURL: URL?

        let searchPaths: [String?] = [nil, "SongRequest", "MaimaiPOV/SongRequest", "MaimaiPOV"]
        for subDir in searchPaths {
            if songURL == nil {
                songURL = Bundle.main.url(forResource: "song_list", withExtension: "json", subdirectory: subDir)
            }
            if aliasURL == nil {
                aliasURL = Bundle.main.url(forResource: "alias_list", withExtension: "json", subdirectory: subDir)
            }
            if songURL != nil && aliasURL != nil { break }
        }

        if songURL == nil || aliasURL == nil {
            var allJsonFiles: [String] = []
            if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
                allJsonFiles.append(contentsOf: urls.map { "root/\($0.lastPathComponent)" })
            }
            for subDir in ["SongRequest", "MaimaiPOV", "MaimaiPOV/SongRequest"] {
                if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: subDir) {
                    allJsonFiles.append(contentsOf: urls.map { "\(subDir)/\($0.lastPathComponent)" })
                }
            }
            let bundlePath = Bundle.main.bundlePath
            let errorMessage = "JSON not found (song=\(songURL != nil), alias=\(aliasURL != nil)) jsons=[\(allJsonFiles.joined(separator: ","))] bundle=\(bundlePath)"
            return .failure(errorMessage)
        }

        guard let songURL = songURL, let aliasURL = aliasURL else {
            return .failure("JSON URL resolution failed")
        }

        do {
            let songData = try Data(contentsOf: songURL)
            let songListData = try JSONDecoder().decode(SongListData.self, from: songData)
            let songList = songListData.songs

            let aliasData = try Data(contentsOf: aliasURL)
            let aliasListData = try JSONDecoder().decode(AliasListData.self, from: aliasData)
            var aliasMap: [String: [String]] = [:]
            for entry in aliasListData.aliases {
                aliasMap[entry.songId] = entry.aliases
            }

            let indexes = makeIndexes(songList: songList, aliasMap: aliasMap)

            let stdCount = songList.filter { $0.chartType == "standard" }.count
            let dxCount = songList.filter { $0.chartType == "dx" }.count
            let utageCount = songList.filter { $0.chartType == "utage" }.count
            let summary = LoadSummary(
                loadedCount: songList.count,
                standardCount: stdCount,
                dxCount: dxCount,
                utageCount: utageCount,
                titleIndexCount: indexes.byTitle.count,
                aliasIndexCount: indexes.byAlias.count
            )
            return .success(BundleSnapshot(
                songList: songList,
                aliasMap: aliasMap,
                byId: indexes.byId,
                byTitle: indexes.byTitle,
                byAlias: indexes.byAlias,
                summary: summary
            ))
        } catch {
            return .failure("JSON decode error: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func install(_ result: BundleLoadResult) -> Bool {
        switch result {
        case .success(let snapshot):
            songList = snapshot.songList
            aliasMap = snapshot.aliasMap
            byId = snapshot.byId
            byTitle = snapshot.byTitle
            byAlias = snapshot.byAlias
            lastError = nil
            logLoaded(summary: snapshot.summary)
            return true
        case .failure(let message):
            lastError = message
            Self.logger.error("\(message, privacy: .public)")
            return false
        }
    }

    func loadFromBundle() {
        install(Self.makeBundleSnapshot())
    }

    private static func makeIndexes(
        songList: [Song],
        aliasMap: [String: [String]]
    ) -> (byId: [Int: Song], byTitle: [String: [Song]], byAlias: [String: [Song]]) {
        var byId: [Int: Song] = [:]
        var byTitle: [String: [Song]] = [:]
        var byAlias: [String: [Song]] = [:]

        for song in songList {
            byId[song.id] = song
        }

        for song in songList {
            let key = song.title.lowercased()
            if !key.isEmpty {
                if !byTitle[key, default: []].contains(where: { $0.id == song.id }) {
                    byTitle[key, default: []].append(song)
                }
            }
        }

        for (songIdKey, aliases) in aliasMap {
            guard let baseId = Int(songIdKey) else { continue }

            var candidates: [Song] = []
            if let s = byId[baseId], !candidates.contains(where: { $0.id == s.id }) { candidates.append(s) }
            if baseId < 10000, let s = byId[baseId + 10000], !candidates.contains(where: { $0.id == s.id }) { candidates.append(s) }
            if baseId >= 10000 && baseId < 20000, let s = byId[baseId - 10000], !candidates.contains(where: { $0.id == s.id }) { candidates.append(s) }
            if baseId < 10000, let s = byId[baseId + 100000], !candidates.contains(where: { $0.id == s.id }) { candidates.append(s) }

            if candidates.isEmpty { continue }

            for alias in aliases {
                let key = alias.lowercased()
                if !key.isEmpty {
                    for c in candidates {
                        if !byAlias[key, default: []].contains(where: { $0.id == c.id }) {
                            byAlias[key, default: []].append(c)
                        }
                    }
                }
            }
        }

        return (byId, byTitle, byAlias)
    }

    private func buildIndexes() {
        let indexes = Self.makeIndexes(songList: songList, aliasMap: aliasMap)
        byId = indexes.byId
        byTitle = indexes.byTitle
        byAlias = indexes.byAlias
    }

    private func logLoaded(summary: LoadSummary) {
        Self.logger.info("Loaded \(summary.loadedCount) songs (std=\(summary.standardCount) dx=\(summary.dxCount) utage=\(summary.utageCount)) byTitle=\(summary.titleIndexCount) byAlias=\(summary.aliasIndexCount)")
    }

    func findCandidates(query: String) -> FindCandidatesResult {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return FindCandidatesResult(candidates: [], matchKind: nil) }

        if let id = Int(q), id > 0 {
            if let direct = byId[id] {
                return FindCandidatesResult(candidates: [direct], matchKind: .id)
            }
            var variants: [Int] = []
            if id < 10000 { variants.append(id + 10000) }
            if id >= 10000 && id < 20000 { variants.append(id - 10000) }
            if id < 10000 { variants.append(id + 100000) }
            var found: [Song] = []
            for v in variants {
                if let s = byId[v], !found.contains(where: { $0.id == s.id }) {
                    found.append(s)
                }
            }
            return FindCandidatesResult(candidates: found, matchKind: found.isEmpty ? nil : .id)
        }

        if let titleHit = byTitle[q], !titleHit.isEmpty {
            return FindCandidatesResult(candidates: titleHit, matchKind: .title)
        }

        if let aliasHit = byAlias[q], !aliasHit.isEmpty {
            return FindCandidatesResult(candidates: aliasHit, matchKind: .alias)
        }

        var fuzzyTitle: [Song] = []
        for song in songList {
            if song.title.lowercased().contains(q), !fuzzyTitle.contains(where: { $0.id == song.id }) {
                fuzzyTitle.append(song)
            }
        }
        if !fuzzyTitle.isEmpty {
            return FindCandidatesResult(candidates: fuzzyTitle, matchKind: .fuzzyTitle)
        }

        var fuzzyAlias: [Song] = []
        for (aliasKey, songs) in byAlias {
            if aliasKey.contains(q) {
                for s in songs {
                    if !fuzzyAlias.contains(where: { $0.id == s.id }) {
                        fuzzyAlias.append(s)
                    }
                }
            }
        }
        if !fuzzyAlias.isEmpty {
            return FindCandidatesResult(candidates: fuzzyAlias, matchKind: .fuzzyAlias)
        }

        return FindCandidatesResult(candidates: [], matchKind: nil)
    }

    func pickByChartType(candidates: [Song], chartTypePreference: String?, diffInput: String?) -> Song? {
        guard !candidates.isEmpty else { return nil }

        if resolveDiffInput(diffInput) == .utage {
            if let u = candidates.first(where: { $0.chartType == "utage" }) { return u }
        }

        let chartTypePreference = normalizedChartTypePreference(chartTypePreference)

        if chartTypePreference == "dx" {
            return candidates.first(where: { $0.chartType == "dx" })
                ?? candidates.first(where: { $0.chartType == "standard" })
                ?? candidates.first(where: { $0.chartType == "utage" })
                ?? candidates.first
        }
        if chartTypePreference == "standard" {
            return candidates.first(where: { $0.chartType == "standard" })
                ?? candidates.first(where: { $0.chartType == "dx" })
                ?? candidates.first(where: { $0.chartType == "utage" })
                ?? candidates.first
        }

        return candidates.first(where: { $0.chartType == "dx" })
            ?? candidates.first(where: { $0.chartType == "standard" })
            ?? candidates.first(where: { $0.chartType == "utage" })
            ?? candidates.first
    }

    func findNote(song: Song, targetDiffNum: ResolvedDifficulty?) -> NoteResult? {
        guard !song.notes.isEmpty else { return nil }

        if song.chartType == "utage" || targetDiffNum == .utage {
            guard let idx = song.notes.firstIndex(where: { $0.isEnable && $0.difficulty.isUtage }) else {
                guard let idx = song.notes.firstIndex(where: { $0.isEnable }) else { return nil }
                let n = song.notes[idx]
                return NoteResult(diffName: "utage", level: n.levelValue, levelValue: n.levelValue, noteIndex: idx)
            }
            let n = song.notes[idx]
            return NoteResult(diffName: "utage", level: n.levelValue, levelValue: n.levelValue, noteIndex: idx)
        }

        if targetDiffNum == nil {
            for i in stride(from: 4, through: 0, by: -1) {
                if let n = song.notes.first(where: { $0.difficulty.intVal == i && $0.isEnable }) {
                    guard let idx = song.notes.firstIndex(where: { $0.difficulty.intVal == i && $0.isEnable }) else { continue }
                    return NoteResult(
                        diffName: diffNumToName[i] ?? "master",
                        level: n.levelValue,
                        levelValue: n.levelValue,
                        noteIndex: idx
                    )
                }
            }
            return nil
        }

        guard case .level(let diffNum) = targetDiffNum, diffNum >= 0, diffNum <= 4 else { return nil }

        for i in stride(from: diffNum, through: 0, by: -1) {
            if let n = song.notes.first(where: { $0.difficulty.intVal == i && $0.isEnable }) {
                guard let idx = song.notes.firstIndex(where: { $0.difficulty.intVal == i && $0.isEnable }) else { continue }
                return NoteResult(
                    diffName: diffNumToName[i] ?? "master",
                    level: n.levelValue,
                    levelValue: n.levelValue,
                    noteIndex: idx
                )
            }
        }
        return nil
    }

    func resolveDiffInput(_ input: String?) -> ResolvedDifficulty? {
        guard let key = normalizedDifficultyInput(input) else { return nil }
        return diffMap[key]
    }

    func difficultyDisplayName(_ diffName: String) -> String {
        switch diffName {
        case "easy": return "BASIC"
        case "advanced": return "ADVANCED"
        case "expert": return "EXPERT"
        case "master": return "MASTER"
        case "remaster": return "Re:MASTER"
        case "utage": return "UTAGE"
        default: return diffName.uppercased()
        }
    }

    func chartTypeDisplayName(_ chartType: String?) -> String {
        switch chartType {
        case "standard": return "STD"
        case "dx": return "DX"
        case "utage": return "UTAGE"
        default: return chartType?.uppercased() ?? ""
        }
    }

    private func normalizedDifficultyInput(_ input: String?) -> String? {
        guard let input else { return nil }
        let key = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "：", with: ":")
        return key.isEmpty ? nil : key
    }

    private func normalizedChartTypePreference(_ input: String?) -> String? {
        guard let input else { return nil }
        let key = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch key {
        case "dx":
            return "dx"
        case "std", "standard", "标", "标准":
            return "standard"
        case "utage", "宴":
            return "utage"
        default:
            return nil
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
