import XCTest
@testable import MaimaiPOV

final class QueueDisplayWindowTests: XCTestCase {
    func testVisibleRangeClampsOutOfBoundsCurrentIndexToLastQueueItem() {
        let window = QueueDisplayWindow(queueCount: 3, currentIndex: 99)

        XCTAssertEqual(Array(window.visibleRange), [2])
        XCTAssertEqual(window.remaining, 0)
        XCTAssertEqual(window.displayIndex(forRealIndex: 2), 0)
        XCTAssertEqual(window.realIndex(forDisplayIndex: 0), 2)
    }

    func testVisibleRangeStartsAtFirstItemForNegativeCurrentIndex() {
        let window = QueueDisplayWindow(queueCount: 3, currentIndex: -1)

        XCTAssertEqual(Array(window.visibleRange), [0, 1, 2])
        XCTAssertEqual(window.remaining, 2)
        XCTAssertEqual(window.displayIndex(forRealIndex: 1), 1)
        XCTAssertEqual(window.realIndex(forDisplayIndex: 1), 1)
    }

    func testVisibleRangeIsEmptyForEmptyQueue() {
        let window = QueueDisplayWindow(queueCount: 0, currentIndex: 7)

        XCTAssertTrue(window.visibleRange.isEmpty)
        XCTAssertEqual(window.remaining, 0)
        XCTAssertNil(window.realIndex(forDisplayIndex: 0))
    }

    func testRealIndexRejectsDisplayIndexesOutsideVisibleWindow() {
        let window = QueueDisplayWindow(queueCount: 4, currentIndex: 2)

        XCTAssertEqual(Array(window.visibleRange), [2, 3])
        XCTAssertNil(window.realIndex(forDisplayIndex: -1))
        XCTAssertNil(window.realIndex(forDisplayIndex: 2))
        XCTAssertEqual(window.realIndex(forDisplayIndex: 0), 2)
        XCTAssertEqual(window.realIndex(forDisplayIndex: 1), 3)
    }

    func testFollowingRangeClampsCurrentIndexBelowIdleToQueueStart() {
        let window = QueueDisplayWindow(queueCount: 3, currentIndex: -2)

        XCTAssertEqual(Array(window.followingRange), [0, 1, 2])
    }

    func testFollowingRangeIsEmptyForCurrentIndexPastQueueEnd() {
        let window = QueueDisplayWindow(queueCount: 3, currentIndex: 99)

        XCTAssertTrue(window.followingRange.isEmpty)
    }
}
