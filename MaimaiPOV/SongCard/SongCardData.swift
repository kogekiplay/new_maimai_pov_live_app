import Foundation

struct SongCardData: Codable, Identifiable {
    let id: UUID
    var songName: String
    var artist: String
    var difficulty: String?
    var level: String?
    var coverURL: String?
    var requester: String?
    var musicId: Int?
    var chartType: String?

    init(id: UUID = UUID(), songName: String, artist: String, difficulty: String? = nil, level: String? = nil, coverURL: String? = nil, requester: String? = nil, musicId: Int? = nil, chartType: String? = nil) {
        self.id = id
        self.songName = songName
        self.artist = artist
        self.difficulty = difficulty
        self.level = level
        self.coverURL = coverURL
        self.requester = requester
        self.musicId = musicId
        self.chartType = chartType
    }

    static func previewData() -> [SongCardData] {
        return [
            SongCardData(songName: "TEST SONG 1", artist: "Artist A", difficulty: "EXPERT", level: "12+", requester: "User1"),
            SongCardData(songName: "TEST SONG 2", artist: "Artist B", difficulty: "MASTER", level: "14", requester: "User2"),
            SongCardData(songName: "TEST SONG 3", artist: "Artist C", difficulty: "ADVANCED", level: "10", requester: "User3")
        ]
    }
}
