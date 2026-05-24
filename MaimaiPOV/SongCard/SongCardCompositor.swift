import Metal
import QuartzCore

struct CardSlot {
    var posX: Float
    var posY: Float
    var scale: Float
}

struct AnimationStep {
    let targetPosX: Float
    let targetPosY: Float
    let targetScale: Float
    let targetOpacity: Float
    let duration: Float
    let delay: Float
}

class SongCardCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private var uniformsBuffers: [MTLBuffer]

    struct CardState {
        var texture: MTLTexture?
        var data: SongCardData?

        var currentPosX: Float
        var currentPosY: Float
        var currentScale: Float
        var currentOpacity: Float

        var targetPosX: Float
        var targetPosY: Float
        var targetScale: Float
        var targetOpacity: Float

        var startPosX: Float
        var startPosY: Float
        var startScale: Float
        var startOpacity: Float

        var isAnimating: Bool = false
        var animStartTime: CFTimeInterval = 0
        var animDuration: Float = 0.4

        var shouldRemoveAfterAnimation: Bool = false
        var pendingAnimations: [AnimationStep] = []
    }

    static let defaultSlots: [CardSlot] = [
        CardSlot(posX: 0.20, posY: 0.125, scale: 0.40),
        CardSlot(posX: 0.48, posY: 0.14, scale: 0.30),
        CardSlot(posX: 0.76, posY: 0.15, scale: 0.30)
    ]

    static let defaultOffScreenRight = CardSlot(posX: 1.3, posY: 0.14, scale: 0.30)
    static let defaultOffScreenLeft = CardSlot(posX: -0.3, posY: 0.125, scale: 0.40)

    var slots: [CardSlot] = defaultSlots
    var offScreenRight: CardSlot = defaultOffScreenRight
    var offScreenLeft: CardSlot = defaultOffScreenLeft

    var cards: [CardState] = []
    var enabled: Bool = false

    var renderer: SongCardRenderer?

    let outWidth = Config.outputWidth
    let outHeight = Config.outputHeight

    static let maxCards = 5

    init?(device: MTLDevice) {
        self.device = device

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "songCardBlend"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps

        self.uniformsBuffers = []
        for _ in 0..<Self.maxCards {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<SongCardUniforms>.stride,
                options: .storageModeShared
            ) else { return nil }
            self.uniformsBuffers.append(buffer)
        }

        self.renderer = SongCardRenderer(device: device)
    }

    private func easeOutCubic(_ t: Float) -> Float {
        return 1.0 - pow(1.0 - t, 3.0)
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }

    func updateAnimations() {
        let currentTime = CACurrentMediaTime()
        var indicesToRemove: [Int] = []

        for i in 0..<cards.count {
            guard cards[i].isAnimating else { continue }

            let elapsed = Float(currentTime - cards[i].animStartTime)
            if elapsed < 0 { continue }

            let rawProgress = min(elapsed / cards[i].animDuration, 1.0)
            let eased = easeOutCubic(rawProgress)

            cards[i].currentPosX = lerp(cards[i].startPosX, cards[i].targetPosX, eased)
            cards[i].currentPosY = lerp(cards[i].startPosY, cards[i].targetPosY, eased)
            cards[i].currentScale = lerp(cards[i].startScale, cards[i].targetScale, eased)
            cards[i].currentOpacity = lerp(cards[i].startOpacity, cards[i].targetOpacity, eased)

            if rawProgress >= 1.0 {
                cards[i].isAnimating = false

                if !cards[i].pendingAnimations.isEmpty {
                    let next = cards[i].pendingAnimations.removeFirst()
                    cards[i].startPosX = cards[i].currentPosX
                    cards[i].startPosY = cards[i].currentPosY
                    cards[i].startScale = cards[i].currentScale
                    cards[i].startOpacity = cards[i].currentOpacity
                    cards[i].targetPosX = next.targetPosX
                    cards[i].targetPosY = next.targetPosY
                    cards[i].targetScale = next.targetScale
                    cards[i].targetOpacity = next.targetOpacity
                    cards[i].animDuration = next.duration
                    cards[i].animStartTime = CACurrentMediaTime() + Double(next.delay)
                    cards[i].isAnimating = true
                } else if cards[i].shouldRemoveAfterAnimation {
                    indicesToRemove.append(i)
                }
            }
        }

        if !indicesToRemove.isEmpty {
            for i in indicesToRemove.reversed() {
                cards.remove(at: i)
            }
        }
    }

    func repositionCards() {
        for i in 0..<min(cards.count, slots.count) {
            if !cards[i].isAnimating {
                cards[i].currentPosX = slots[i].posX
                cards[i].currentPosY = slots[i].posY
                cards[i].currentScale = slots[i].scale
            }
        }
    }

    func addCard(texture: MTLTexture, data: SongCardData?) {
        let visibleCount = cards.count

        if visibleCount == 0 {
            let card = CardState(
                texture: texture,
                data: data,
                currentPosX: offScreenRight.posX,
                currentPosY: offScreenRight.posY,
                currentScale: offScreenRight.scale,
                currentOpacity: 0.0,
                targetPosX: slots[2].posX,
                targetPosY: slots[2].posY,
                targetScale: slots[2].scale,
                targetOpacity: 1.0,
                startPosX: offScreenRight.posX,
                startPosY: offScreenRight.posY,
                startScale: offScreenRight.scale,
                startOpacity: 0.0,
                isAnimating: true,
                animStartTime: CACurrentMediaTime(),
                animDuration: 0.35
            )
            var newCard = card
            newCard.pendingAnimations = [
                AnimationStep(targetPosX: slots[1].posX, targetPosY: slots[1].posY, targetScale: slots[1].scale, targetOpacity: 1.0, duration: 0.3, delay: 0.1),
                AnimationStep(targetPosX: slots[0].posX, targetPosY: slots[0].posY, targetScale: slots[0].scale, targetOpacity: 1.0, duration: 0.35, delay: 0.1)
            ]
            cards.append(newCard)
        } else if visibleCount < slots.count {
            let slotIndex = visibleCount
            let slot = slots[slotIndex]
            let card = CardState(
                texture: texture,
                data: data,
                currentPosX: offScreenRight.posX,
                currentPosY: offScreenRight.posY,
                currentScale: offScreenRight.scale,
                currentOpacity: 0.0,
                targetPosX: slot.posX,
                targetPosY: slot.posY,
                targetScale: slot.scale,
                targetOpacity: 1.0,
                startPosX: offScreenRight.posX,
                startPosY: offScreenRight.posY,
                startScale: offScreenRight.scale,
                startOpacity: 0.0,
                isAnimating: true,
                animStartTime: CACurrentMediaTime(),
                animDuration: 0.4
            )
            cards.append(card)
        }
    }

    func switchToNext(newCardTexture: MTLTexture? = nil, newCardData: SongCardData? = nil) {
        if !cards.isEmpty {
            animateCardOutLeft(index: 0, duration: 0.4)
        }

        if cards.count > 1 {
            animateCardToSlot(index: 1, slot: slots[0], duration: 0.4, delay: 0.05)
        }

        if cards.count > 2 {
            animateCardToSlot(index: 2, slot: slots[1], duration: 0.4, delay: 0.1)
        }

        if let texture = newCardTexture {
            addCardFromRight(texture: texture, data: newCardData, targetSlot: 2, duration: 0.4)
        }
    }

    func updateAllCards(cardDataList: [(texture: MTLTexture, data: SongCardData)]) {
        let oldCount = cards.count
        for i in 0..<oldCount {
            animateCardOutLeft(index: i, duration: 0.3)
        }

        let delayBase = Double(oldCount) * 0.05 + 0.35

        DispatchQueue.main.asyncAfter(deadline: .now() + delayBase) { [weak self] in
            guard let self = self else { return }
            self.cards.removeAll()

            for (i, item) in cardDataList.enumerated() {
                guard i < self.slots.count else { break }
                let slot = self.slots[i]
                let card = CardState(
                    texture: item.texture,
                    data: item.data,
                    currentPosX: self.offScreenRight.posX,
                    currentPosY: self.offScreenRight.posY,
                    currentScale: self.offScreenRight.scale,
                    currentOpacity: 0.0,
                    targetPosX: slot.posX,
                    targetPosY: slot.posY,
                    targetScale: slot.scale,
                    targetOpacity: 1.0,
                    startPosX: self.offScreenRight.posX,
                    startPosY: self.offScreenRight.posY,
                    startScale: self.offScreenRight.scale,
                    startOpacity: 0.0,
                    isAnimating: true,
                    animStartTime: CACurrentMediaTime() + Double(i) * 0.1,
                    animDuration: 0.4
                )
                self.cards.append(card)
            }
        }
    }

    func clearAll() {
        for i in cards.indices {
            animateCardOutLeft(index: i, duration: 0.3)
        }
    }

    private func animateCardToSlot(index: Int, slot: CardSlot, duration: Float = 0.4, delay: Float = 0.0) {
        guard index >= 0, index < cards.count else { return }

        cards[index].startPosX = cards[index].currentPosX
        cards[index].startPosY = cards[index].currentPosY
        cards[index].startScale = cards[index].currentScale
        cards[index].startOpacity = cards[index].currentOpacity

        cards[index].targetPosX = slot.posX
        cards[index].targetPosY = slot.posY
        cards[index].targetScale = slot.scale
        cards[index].targetOpacity = 1.0

        cards[index].isAnimating = true
        cards[index].animStartTime = CACurrentMediaTime() + Double(delay)
        cards[index].animDuration = duration
        cards[index].shouldRemoveAfterAnimation = false
        cards[index].pendingAnimations.removeAll()
    }

    private func animateCardOutLeft(index: Int, duration: Float = 0.4) {
        guard index >= 0, index < cards.count else { return }

        cards[index].startPosX = cards[index].currentPosX
        cards[index].startPosY = cards[index].currentPosY
        cards[index].startScale = cards[index].currentScale
        cards[index].startOpacity = cards[index].currentOpacity

        cards[index].targetPosX = offScreenLeft.posX
        cards[index].targetPosY = offScreenLeft.posY
        cards[index].targetScale = offScreenLeft.scale
        cards[index].targetOpacity = 0.0

        cards[index].isAnimating = true
        cards[index].animStartTime = CACurrentMediaTime()
        cards[index].animDuration = duration
        cards[index].shouldRemoveAfterAnimation = true
        cards[index].pendingAnimations.removeAll()
    }

    private func addCardFromRight(texture: MTLTexture, data: SongCardData?, targetSlot: Int, duration: Float = 0.4) {
        let slot = targetSlot < slots.count ? slots[targetSlot] : slots[2]

        let card = CardState(
            texture: texture,
            data: data,
            currentPosX: offScreenRight.posX,
            currentPosY: offScreenRight.posY,
            currentScale: offScreenRight.scale,
            currentOpacity: 0.0,
            targetPosX: slot.posX,
            targetPosY: slot.posY,
            targetScale: slot.scale,
            targetOpacity: 1.0,
            startPosX: offScreenRight.posX,
            startPosY: offScreenRight.posY,
            startScale: offScreenRight.scale,
            startOpacity: 0.0,
            isAnimating: true,
            animStartTime: CACurrentMediaTime(),
            animDuration: duration
        )

        cards.append(card)
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled, !cards.isEmpty else { return }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(outputTexture, index: 0)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)

        for i in 0..<min(cards.count, Self.maxCards) {
            guard let cardTex = cards[i].texture else { continue }
            if cards[i].currentOpacity < 0.001 && !cards[i].isAnimating { continue }

            var uniforms = SongCardUniforms()
            uniforms.posX = cards[i].currentPosX
            uniforms.posY = cards[i].currentPosY
            uniforms.scale = cards[i].currentScale
            uniforms.opacity = cards[i].currentOpacity
            uniforms.cardWidth = Float(cardTex.width)
            uniforms.cardHeight = Float(cardTex.height)
            uniforms.outWidth = Float(outWidth)
            uniforms.outHeight = Float(outHeight)

            memcpy(uniformsBuffers[i].contents(), &uniforms, MemoryLayout<SongCardUniforms>.stride)

            encoder.setTexture(cardTex, index: 1)
            encoder.setBuffer(uniformsBuffers[i], offset: 0, index: 0)

            let gridSize = MTLSize(width: outWidth, height: outHeight, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
    }
}
