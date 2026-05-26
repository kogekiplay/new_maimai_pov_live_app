import Foundation
import Metal

class MarqueeManager {
    private var queue: [MarqueeItem] = []
    private var activeItems: [ActiveMarquee] = []

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
        if canStartNext() {
            let startX = Float(Config.outputWidth)
            let active = ActiveMarquee(item: item, scrollX: startX, isFullyVisible: false)
            activeItems.append(active)
        } else {
            queue.append(item)
        }
    }

    func setCurrentTexture(_ texture: MTLTexture, contentWidth: Int, for itemId: UUID) {
        if let index = activeItems.firstIndex(where: { $0.item.id == itemId }) {
            activeItems[index].item.texture = texture
            activeItems[index].item.contentWidth = contentWidth
        }
    }

    func updateAnimations() {
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

        tryDequeueNext()
    }

    private func canStartNext() -> Bool {
        if activeItems.isEmpty { return true }
        return activeItems[activeItems.count - 1].isFullyVisible
    }

    private func tryDequeueNext() {
        guard !queue.isEmpty else { return }
        guard canStartNext() else { return }

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
        return activeItems.filter { $0.item.texture == nil }.map { $0.item }
    }

    var visibleItems: [(item: MarqueeItem, scrollX: Float)] {
        return activeItems.filter { $0.item.texture != nil }.map { (item: $0.item, scrollX: $0.scrollX) }
    }
}
