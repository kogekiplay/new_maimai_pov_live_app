import Foundation

struct QueueDisplayWindow: Sendable {
    let queueCount: Int
    let startIndex: Int

    init(queueCount: Int, currentIndex: Int) {
        self.queueCount = max(0, queueCount)
        if queueCount <= 0 {
            startIndex = 0
        } else {
            startIndex = min(max(currentIndex, 0), queueCount - 1)
        }
    }

    var visibleRange: Range<Int> {
        startIndex..<queueCount
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
