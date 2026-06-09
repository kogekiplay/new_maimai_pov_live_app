import Foundation

struct QueueDisplayWindow: Sendable {
    let queueCount: Int
    let startIndex: Int
    let followingStartIndex: Int

    init(queueCount: Int, currentIndex: Int) {
        self.queueCount = max(0, queueCount)
        if queueCount <= 0 {
            startIndex = 0
            followingStartIndex = 0
        } else {
            startIndex = min(max(currentIndex, 0), queueCount - 1)
            followingStartIndex = min(max(currentIndex + 1, 0), queueCount)
        }
    }

    var visibleRange: Range<Int> {
        startIndex..<queueCount
    }

    var followingRange: Range<Int> {
        followingStartIndex..<queueCount
    }

    var remaining: Int {
        max(0, queueCount - startIndex - 1)
    }

    func displayIndex(forRealIndex index: Int) -> Int {
        index - startIndex
    }

    func realIndex(forDisplayIndex displayIndex: Int) -> Int? {
        let index = startIndex + displayIndex
        guard visibleRange.contains(index) else { return nil }
        return index
    }
}
