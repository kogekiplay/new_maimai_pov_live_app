import Foundation
import Metal

class MarqueeManager {
    private var queue: [MarqueeItem] = []
    private(set) var currentItem: MarqueeItem?
    private(set) var scrollX: Float = 0
    private(set) var state: MarqueeState = .idle

    enum MarqueeState {
        case idle
        case rendering
        case scrolling
    }

    let scrollSpeed: Float = Config.marqueeSpeed
    let barHeight: Int = 64
    let barBottomPadding: Int = 16
    var barY: Int { Config.outputHeight - barHeight - barBottomPadding }

    func enqueue(_ item: MarqueeItem) {
        if state == .idle {
            currentItem = item
            state = .rendering
        } else {
            queue.append(item)
        }
    }

    func setCurrentTexture(_ texture: MTLTexture, contentWidth: Int) {
        currentItem?.texture = texture
        currentItem?.contentWidth = contentWidth
        if state == .rendering {
            scrollX = Float(Config.outputWidth)
            state = .scrolling
        }
    }

    func updateAnimations() {
        guard state == .scrolling, let item = currentItem else { return }
        scrollX -= scrollSpeed
        if scrollX < -Float(item.contentWidth) {
            dequeueNext()
        }
    }

    private func dequeueNext() {
        if let next = queue.first {
            queue.removeFirst()
            currentItem = next
            state = .rendering
            scrollX = 0
        } else {
            currentItem = nil
            state = .idle
            scrollX = 0
        }
    }

    var needsRendering: Bool { state == .rendering && currentItem?.texture == nil }
}
