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
}
