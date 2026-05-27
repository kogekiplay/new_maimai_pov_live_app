import Foundation
import Metal

class MarqueeManager {
    private var queue: [MarqueeItem] = []
    private var activeItems: [ActiveMarquee] = []
    private var lock = os_unfair_lock_s()

    private let maxQueueSize = 50

    struct ActiveMarquee {
        var item: MarqueeItem
        var scrollX: Float
        var isFullyVisible: Bool
    }

    let scrollSpeed: Float = Config.marqueeSpeed
    let barHeight: Int = 64
    let barBottomPadding: Int = 16
    let itemGap: Float = 40

    var barY: Int { Config.outputHeight - barHeight - barBottomPadding }

    func enqueue(_ item: MarqueeItem) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        if let mergeKey = item.mergeKey {
            if let index = queue.lastIndex(where: { $0.mergeKey == mergeKey }) {
                queue[index].mergeCount += item.mergeCount
                if let prefix = queue[index].textPrefix {
                    queue[index].text = "\(prefix) ×\(queue[index].mergeCount)"
                }
                return
            }
        }

        if canStartNextUnsafe() {
            let startX = Float(Config.outputWidth)
            let active = ActiveMarquee(item: item, scrollX: startX, isFullyVisible: false)
            activeItems.append(active)
        } else {
            if queue.count >= maxQueueSize {
                queue.removeFirst()
            }
            queue.append(item)
        }
    }

    func setCurrentTexture(_ texture: MTLTexture, contentWidth: Int, for itemId: UUID) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        if let index = activeItems.firstIndex(where: { $0.item.id == itemId }) {
            activeItems[index].item.texture = texture
            activeItems[index].item.contentWidth = contentWidth
        }
    }

    func updateAnimations() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for i in 0..<activeItems.count {
            activeItems[i].scrollX -= scrollSpeed
            let cw = activeItems[i].item.contentWidth
            if !activeItems[i].isFullyVisible && cw > 0 && activeItems[i].scrollX + Float(cw) <= Float(Config.outputWidth) {
                activeItems[i].isFullyVisible = true
            }
        }

        while !activeItems.isEmpty {
            let first = activeItems[0]
            let cw = first.item.contentWidth
            if cw > 0 && first.scrollX < -Float(cw) {
                activeItems.removeFirst()
            } else {
                break
            }
        }

        tryDequeueNextUnsafe()
    }

    private func canStartNextUnsafe() -> Bool {
        if activeItems.isEmpty { return true }
        return activeItems[activeItems.count - 1].isFullyVisible
    }

    private func tryDequeueNextUnsafe() {
        guard !queue.isEmpty else { return }
        guard canStartNextUnsafe() else { return }

        let next = queue.removeFirst()
        let startX: Float
        let last = activeItems[activeItems.count - 1]
        let lastCW = last.item.contentWidth
        if lastCW > 0 {
            startX = last.scrollX + Float(lastCW) + itemGap
        } else {
            startX = Float(Config.outputWidth)
        }
        let active = ActiveMarquee(item: next, scrollX: startX, isFullyVisible: false)
        activeItems.append(active)
    }

    var itemsToRender: [MarqueeItem] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return activeItems.filter { $0.item.texture == nil }.map { $0.item }
    }

    var visibleItems: [(item: MarqueeItem, scrollX: Float)] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return activeItems.filter { $0.item.texture != nil }.map { (item: $0.item, scrollX: $0.scrollX) }
    }
}
