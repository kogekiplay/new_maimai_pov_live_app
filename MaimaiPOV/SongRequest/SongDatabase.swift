import Foundation

struct Song: Codable {
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

struct SongNote: Codable {
    let difficulty: Int
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

struct SongListData: Codable {
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

struct AliasEntry: Codable {
    let songId: String
    let aliases: [String]

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case aliases
    }
}

struct AliasListData: Codable {
    let aliases: [AliasEntry]
}

struct NoteResult {
    let diffName: String
    let level: Double
    let levelValue: Double
    let noteIndex: Int
}

enum MatchKind: String {
    case id
    case title
    case alias
    case fuzzyTitle = "fuzzy_title"
    case fuzzyAlias = "fuzzy_alias"
}

struct FindCandidatesResult {
    let candidates: [Song]
    let matchKind: MatchKind?
}

class SongDatabase {
    private var songList: [Song] = []
    private var aliasMap: [String: [String]] = [:]

    private var byId: [Int: Song] = [:]
    private var byTitle: [String: [Song]] = [:]
    private var byAlias: [String: [Song]] = [:]

    private let diffMap: [String: Any] = [
        "绿": 0, "basic": 0,
        "黄": 1, "advanced": 1,
        "红": 2, "expert": 2,
        "紫": 3, "master": 3,
        "白": 4, "remaster": 4,
        "宴": "utage", "utage": "utage"
    ]

    private let diffNumToName: [Int: String] = [
        0: "easy", 1: "advanced", 2: "expert", 3: "master", 4: "remaster"
    ]

    var songCount: Int { songList.count }

    func loadFromBundle() {
        guard let songURL = Bundle.main.url(forResource: "song_list", withExtension: "json"),
              let aliasURL = Bundle.main.url(forResource: "alias_list", withExtension: "json") else {
            print("[SongDatabase] ERROR: song_list.json or alias_list.json not found in bundle")
            return
        }

        do {
            let songData = try Data(contentsOf: songURL)
            let songListData = try JSONDecoder().decode(SongListData.self, from: songData)
            songList = songListData.songs

            let aliasData = try Data(contentsOf: aliasURL)
            let aliasListData = try JSONDecoder().decode(AliasListData.self, from: aliasData)
            for entry in aliasListData.aliases {
                aliasMap[entry.songId] = entry.aliases
            }

            buildIndexes()

            let stdCount = songList.filter { $0.chartType == "standard" }.count
            let dxCount = songList.filter { $0.chartType == "dx" }.count
            let utageCount = songList.filter { $0.chartType == "utage" }.count
            print("[SongDatabase] Loaded \(songList.count) songs (std=\(stdCount) dx=\(dxCount) utage=\(utageCount)) byTitle=\(byTitle.count) byAlias=\(byAlias.count)")
        } catch {
            print("[SongDatabase] ERROR loading data: \(error)")
        }
    }

    private func buildIndexes() {
        byId.removeAll()
        byTitle.removeAll()
        byAlias.removeAll()

        for song in songList {
            byId[song.id] = song
        }

        for song in songList {
            let key = song.title.lowercased()
            if !key.isEmpty {
                if byTitle[key] == nil { byTitle[key] = [] }
                if !byTitle[key]!.contains(where: { $0.id == song.id }) {
                    byTitle[key]!.append(song)
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
                    if byAlias[key] == nil { byAlias[key] = [] }
                    for c in candidates {
                        if !byAlias[key]!.contains(where: { $0.id == c.id }) {
                            byAlias[key]!.append(c)
                        }
                    }
                }
            }
        }
    }

    func findCandidates(query: String) -> FindCandidatesResult {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
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

        if diffInput == "utage" || diffInput == "宴" {
            if let u = candidates.first(where: { $0.chartType == "utage" }) { return u }
        }

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

    func findNote(song: Song, targetDiffNum: Any?) -> NoteResult? {
        guard !song.notes.isEmpty else { return nil }

        if song.chartType == "utage" || (targetDiffNum as? String) == "utage" {
            guard let idx = song.notes.firstIndex(where: { $0.isEnable }) else { return nil }
            let n = song.notes[idx]
            return NoteResult(diffName: "utage", level: n.levelValue, levelValue: n.levelValue, noteIndex: idx)
        }

        if targetDiffNum == nil {
            for i in stride(from: 4, through: 0, by: -1) {
                if let n = song.notes[safe: i], n.isEnable {
                    return NoteResult(
                        diffName: diffNumToName[i] ?? "master",
                        level: n.levelValue,
                        levelValue: n.levelValue,
                        noteIndex: i
                    )
                }
            }
            return nil
        }

        guard let diffNum = targetDiffNum as? Int, diffNum >= 0, diffNum <= 4 else { return nil }

        for i in stride(from: diffNum, through: 0, by: -1) {
            if let n = song.notes[safe: i], n.isEnable {
                return NoteResult(
                    diffName: diffNumToName[i] ?? "master",
                    level: n.levelValue,
                    levelValue: n.levelValue,
                    noteIndex: i
                )
            }
        }
        return nil
    }

    func resolveDiffInput(_ input: String?) -> Any? {
        guard let input = input?.lowercased(), !input.isEmpty else { return nil }
        if let val = diffMap[input] { return val }
        return nil
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
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
