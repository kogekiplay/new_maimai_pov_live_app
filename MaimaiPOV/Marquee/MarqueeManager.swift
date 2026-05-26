import Foundation
import Metal

class MarqueeManager {
    private var queue: [MarqueeItem] = []

    private var slots: [MarqueeSlot] = []
    let maxSlots: Int = 3
    let slotGap: Int = 8

    let scrollSpeed: Float = Config.marqueeSpeed
    let barHeight: Int = 64
    let barBottomPadding: Int = 16

    var barY: Int { Config.outputHeight - barHeight - barBottomPadding }

    struct MarqueeSlot {
        var item: MarqueeItem
        var scrollX: Float
        var yPosition: Int
        var state: MarqueeState

        enum MarqueeState {
            case rendering
            case scrolling
        }
    }

    init() {
        slots = []
    }

    func slotY(for index: Int) -> Int {
        return barY - index * (barHeight + slotGap)
    }

    func enqueue(_ item: MarqueeItem) {
        if slots.count < maxSlots {
            let slotIndex = slots.count
            let slot = MarqueeSlot(
                item: item,
                scrollX: 0,
                yPosition: slotY(for: slotIndex),
                state: .rendering
            )
            slots.append(slot)
        } else {
            queue.append(item)
        }
    }

    func setCurrentTexture(_ texture: MTLTexture, contentWidth: Int, for itemId: UUID) {
        guard let slotIndex = slots.firstIndex(where: { $0.item.id == itemId }) else { return }
        slots[slotIndex].item.texture = texture
        slots[slotIndex].item.contentWidth = contentWidth
        if slots[slotIndex].state == .rendering {
            slots[slotIndex].scrollX = Float(Config.outputWidth)
            slots[slotIndex].state = .scrolling
        }
    }

    func updateAnimations() {
        var completedIndices: [Int] = []

        for i in 0..<slots.count {
            let slot = slots[i]
            if slot.state == .scrolling {
                slots[i].scrollX -= scrollSpeed
                if slots[i].scrollX < -Float(slots[i].item.contentWidth) {
                    completedIndices.append(i)
                }
            }
        }

        for i in completedIndices.reversed() {
            slots.remove(at: i)
            if let next = queue.first {
                queue.removeFirst()
                let newSlotIndex = i
                let slot = MarqueeSlot(
                    item: next,
                    scrollX: 0,
                    yPosition: slotY(for: newSlotIndex),
                    state: .rendering
                )
                if newSlotIndex < slots.count {
                    slots.insert(slot, at: newSlotIndex)
                } else {
                    slots.append(slot)
                }
            }
        }

        for i in 0..<slots.count {
            slots[i].yPosition = slotY(for: i)
        }
    }

    var slotsToRender: [(item: MarqueeItem, yPosition: Int)] {
        return slots.filter { $0.state == .rendering && $0.item.texture == nil }
            .map { (item: $0.item, yPosition: $0.yPosition) }
    }

    var activeSlots: [(item: MarqueeItem, scrollX: Float, yPosition: Int)] {
        return slots.filter { $0.state == .scrolling }
            .map { (item: $0.item, scrollX: $0.scrollX, yPosition: $0.yPosition) }
    }
}
