import Foundation

struct SongCardData: Codable {
    var songName: String
    var artist: String
    var coverURL: String?
    var requester: String?

    static func previewData() -> [SongCardData] {
        return [
            SongCardData(songName: "TEST SONG 1", artist: "Artist A", requester: "User1"),
            SongCardData(songName: "TEST SONG 2", artist: "Artist B", requester: "User2"),
            SongCardData(songName: "NEXT UP", artist: "Artist C", requester: "User3")
        ]
    }
}
