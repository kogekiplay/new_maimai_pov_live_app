import XCTest
@testable import MaimaiPOV

final class DanmakuParserTests: XCTestCase {
    func testCancelCommandIgnoresTrailingNewline() {
        let parser = DanmakuParser()

        let result = parser.parse("取消\r\n")

        if case .cancelRequest = result.type {
            XCTAssertEqual(result.originalQuery, "取消")
        } else {
            XCTFail("Expected cancel request")
        }
    }

    func testSongRequestIgnoresSurroundingNewlines() {
        let parser = DanmakuParser()

        let result = parser.parse("\n点歌 紫  Our Wrenally  dx\r\n")

        if case let .songRequest(query, diffInput, chartTypePreference) = result.type {
            XCTAssertEqual(query, "Our Wrenally")
            XCTAssertEqual(diffInput, "紫")
            XCTAssertEqual(chartTypePreference, "dx")
            XCTAssertEqual(result.originalQuery, "紫  Our Wrenally  dx")
        } else {
            XCTFail("Expected song request")
        }
    }
}
