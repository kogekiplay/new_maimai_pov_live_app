import XCTest
@testable import MaimaiPOV

final class SongCardDataTests: XCTestCase {
    func testDecodingLegacySongCardWithoutPriorityDefaultsToNormalQueueItem() throws {
        let data = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "songName": "Legacy Song",
          "artist": "Legacy Artist"
        }
        """.data(using: .utf8)!

        let song = try JSONDecoder().decode(SongCardData.self, from: data)

        XCTAssertFalse(song.isPriority)
        XCTAssertEqual(song.giftValue, 0)
        XCTAssertEqual(song.songName, "Legacy Song")
        XCTAssertEqual(song.artist, "Legacy Artist")
    }

    func testRenderCacheKeyChangesWhenVisibleFieldsChange() {
        let base = SongCardData(
            songName: "Song",
            artist: "Artist",
            difficulty: "MASTER",
            level: "13",
            requester: "Alice",
            requesterName: "Ignored",
            chartType: "dx",
            giftValue: 100
        )

        let variants = [
            SongCardData(songName: "Other", artist: "Artist", difficulty: "MASTER", level: "13", requester: "Alice", requesterName: "Ignored", chartType: "dx", giftValue: 100),
            SongCardData(songName: "Song", artist: "Other", difficulty: "MASTER", level: "13", requester: "Alice", requesterName: "Ignored", chartType: "dx", giftValue: 100),
            SongCardData(songName: "Song", artist: "Artist", difficulty: "EXPERT", level: "13", requester: "Alice", requesterName: "Ignored", chartType: "dx", giftValue: 100),
            SongCardData(songName: "Song", artist: "Artist", difficulty: "MASTER", level: "14", requester: "Alice", requesterName: "Ignored", chartType: "dx", giftValue: 100),
            SongCardData(songName: "Song", artist: "Artist", difficulty: "MASTER", level: "13", requester: "Bob", requesterName: "Ignored", chartType: "dx", giftValue: 100),
            SongCardData(songName: "Song", artist: "Artist", difficulty: "MASTER", level: "13", requester: "Alice", requesterName: "Ignored", chartType: "standard", giftValue: 100),
            SongCardData(songName: "Song", artist: "Artist", difficulty: "MASTER", level: "13", requester: "Alice", requesterName: "Ignored", chartType: "dx", giftValue: 200)
        ]

        let baseKey = base.renderCacheKey(coverBase64: "cover-a")

        for variant in variants {
            XCTAssertNotEqual(baseKey, variant.renderCacheKey(coverBase64: "cover-a"))
        }
        XCTAssertNotEqual(baseKey, base.renderCacheKey(coverBase64: "cover-b"))
    }
}
