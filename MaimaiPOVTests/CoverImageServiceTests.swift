import XCTest
@testable import MaimaiPOV

final class CoverImageServiceTests: XCTestCase {
    func testResolverNormalizesCoverIdsAndBuildsCandidatesInFormatOrder() throws {
        let resolver = CoverResourceResolver(cdnBase: URL(string: "https://example.test/gameRes/mai2")!)

        let candidates = resolver.remoteCandidates(for: 110834)

        XCTAssertEqual(candidates.map(\.url.absoluteString), [
            "https://example.test/gameRes/mai2/010834.webp",
            "https://example.test/gameRes/mai2/010834.png",
            "https://example.test/gameRes/mai2/010834.avif"
        ])
        XCTAssertEqual(candidates.map(\.fallbackContentType), [
            "image/webp",
            "image/png",
            "image/avif"
        ])
        XCTAssertEqual(resolver.cacheKey(for: 110834), "010834")
        XCTAssertEqual(resolver.cacheKey(for: 20834), "010834")
        XCTAssertEqual(resolver.cacheKey(for: 10834), "000834")
        XCTAssertEqual(resolver.cacheKey(for: 834), "000834")
    }

    func testResolverRejectsNonPositiveMusicIdsBeforeNetworkFetch() {
        let resolver = CoverResourceResolver(cdnBase: URL(string: "https://example.test/gameRes/mai2")!)

        XCTAssertNil(resolver.cacheKey(for: 0))
        XCTAssertNil(resolver.cacheKey(for: -1))
        XCTAssertTrue(resolver.remoteCandidates(for: 0).isEmpty)
        XCTAssertTrue(resolver.remoteCandidates(for: -1).isEmpty)
    }

    func testCoverCacheReturnsItemsUntilExpiration() {
        let cache = CoverImageCache(ttl: 10)
        let now = Date(timeIntervalSince1970: 100)
        let data = Data([1, 2, 3])

        cache.store(CoverFetchResult(data: data, contentType: "image/webp"), forKey: "000834", now: now)

        XCTAssertEqual(cache.value(forKey: "000834", now: now.addingTimeInterval(9))?.data, data)
        XCTAssertNil(cache.value(forKey: "000834", now: now.addingTimeInterval(11)))
        XCTAssertNil(cache.value(forKey: "000834", now: now.addingTimeInterval(12)))
    }
}
