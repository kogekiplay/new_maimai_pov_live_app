import Foundation

struct SongCardData: Codable, Identifiable, Sendable {
    let id: UUID
    var songName: String
    var artist: String
    var difficulty: String?
    var level: String?
    var coverURL: String?
    var requester: String?
    var requesterName: String?
    var musicId: Int?
    var chartType: String?
    var isPriority: Bool
    var bpm: Int?
    var giftValue: Int
    var addedAt: Date
    var lastOwnerActivityAt: Date

    init(id: UUID = UUID(), songName: String, artist: String, difficulty: String? = nil, level: String? = nil, coverURL: String? = nil, requester: String? = nil, requesterName: String? = nil, musicId: Int? = nil, chartType: String? = nil, isPriority: Bool = false, bpm: Int? = nil, giftValue: Int = 0, addedAt: Date = Date(), lastOwnerActivityAt: Date = Date()) {
        self.id = id
        self.songName = songName
        self.artist = artist
        self.difficulty = difficulty
        self.level = level
        self.coverURL = coverURL
        self.requester = requester
        self.requesterName = requesterName
        self.musicId = musicId
        self.chartType = chartType
        self.isPriority = isPriority
        self.bpm = bpm
        self.giftValue = giftValue
        self.addedAt = addedAt
        self.lastOwnerActivityAt = lastOwnerActivityAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        songName = try container.decode(String.self, forKey: .songName)
        artist = try container.decode(String.self, forKey: .artist)
        difficulty = try container.decodeIfPresent(String.self, forKey: .difficulty)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        requester = try container.decodeIfPresent(String.self, forKey: .requester)
        requesterName = try container.decodeIfPresent(String.self, forKey: .requesterName)
        musicId = try container.decodeIfPresent(Int.self, forKey: .musicId)
        chartType = try container.decodeIfPresent(String.self, forKey: .chartType)
        isPriority = try container.decode(Bool.self, forKey: .isPriority)
        bpm = try container.decodeIfPresent(Int.self, forKey: .bpm)
        giftValue = try container.decodeIfPresent(Int.self, forKey: .giftValue) ?? 0
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastOwnerActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastOwnerActivityAt) ?? Date()
    }

    static func previewData() -> [SongCardData] {
        return [
            SongCardData(songName: "TEST SONG 1", artist: "Artist A", difficulty: "EXPERT", level: "12+", requester: "User1"),
            SongCardData(songName: "TEST SONG 2", artist: "Artist B", difficulty: "MASTER", level: "14", requester: "User2"),
            SongCardData(songName: "TEST SONG 3", artist: "Artist C", difficulty: "ADVANCED", level: "10", requester: "User3")
        ]
    }
}
