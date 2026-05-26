import Foundation
import Metal

class MarqueeManager {
    private var queue: [MarqueeItem] = []
    private var activeItems: [ActiveMarquee] = []

    struct ActiveMarquee {
        let item: MarqueeItem
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
            if !activeItems[i].isFullyVisible,
               let cw = activeItems[i].item.texture != nil ? activeItems[i].item.contentWidth : 0,
               cw > 0,
               activeItems[i].scrollX + Float(cw) <= Float(Config.outputWidth) {
                activeItems[i].isFullyVisible = true
            }
        }

        while let first = activeItems.first,
              let cw = first.item.texture != nil ? first.item.contentWidth : 0,
              cw > 0,
              first.scrollX < -Float(cw) {
            activeItems.removeFirst()
        }

        tryDequeueNext()
    }

    private func canStartNext() -> Bool {
        if activeItems.isEmpty { return true }
        guard let last = activeItems.last else { return true }
        return last.isFullyVisible
    }

    private func tryDequeueNext() {
        guard !queue.isEmpty else { return }
        guard canStartNext() else { return }

        let next = queue.removeFirst()
        let startX: Float
        if let last = activeItems.last, let lastCW = last.item.texture != nil ? last.item.contentWidth : 0, lastCW > 0 {
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
