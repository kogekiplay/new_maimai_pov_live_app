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

        var startPosX: Float = 0
        var startPosY: Float = 0
        var startScale: Float = 0
        var startOpacity: Float = 1.0

        var isAnimating: Bool = false
        var animStartTime: CFTimeInterval = 0
        var animDuration: Float = 0.4

        var shouldRemoveAfterAnimation: Bool = false
        var pendingAnimations: [AnimationStep] = []
    }

    static let slots: [CardSlot] = [
        CardSlot(posX: 0.20, posY: 0.115, scale: 0.30),
        CardSlot(posX: 0.47, posY: 0.13, scale: 0.22),
        CardSlot(posX: 0.72, posY: 0.14, scale: 0.18)
    ]

    static let offScreenRight = CardSlot(posX: 1.3, posY: 0.13, scale: 0.18)
    static let offScreenLeft = CardSlot(posX: -0.3, posY: 0.115, scale: 0.30)

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

    func animateCardToSlot(index: Int, slot: CardSlot, duration: Float = 0.4, delay: Float = 0.0) {
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
    }

    func animateCardOutLeft(index: Int, duration: Float = 0.4) {
        guard index >= 0, index < cards.count else { return }

        cards[index].startPosX = cards[index].currentPosX
        cards[index].startPosY = cards[index].currentPosY
        cards[index].startScale = cards[index].currentScale
        cards[index].startOpacity = cards[index].currentOpacity

        cards[index].targetPosX = Self.offScreenLeft.posX
        cards[index].targetPosY = Self.offScreenLeft.posY
        cards[index].targetScale = Self.offScreenLeft.scale
        cards[index].targetOpacity = 0.0

        cards[index].isAnimating = true
        cards[index].animStartTime = CACurrentMediaTime()
        cards[index].animDuration = duration
        cards[index].shouldRemoveAfterAnimation = true
    }

    func addCardFromRight(texture: MTLTexture, data: SongCardData?, targetSlot: Int, duration: Float = 0.4) {
        let slot = targetSlot < Self.slots.count ? Self.slots[targetSlot] : Self.slots[2]

        let card = CardState(
            texture: texture,
            data: data,
            currentPosX: Self.offScreenRight.posX,
            currentPosY: Self.offScreenRight.posY,
            currentScale: Self.offScreenRight.scale,
            currentOpacity: 1.0,
            targetPosX: slot.posX,
            targetPosY: slot.posY,
            targetScale: slot.scale,
            targetOpacity: 1.0,
            isAnimating: true,
            animStartTime: CACurrentMediaTime(),
            animDuration: duration
        )

        cards.append(card)
    }

    func shiftCardsLeft(newCardTexture: MTLTexture? = nil, newCardData: SongCardData? = nil) {
        if !cards.isEmpty {
            animateCardOutLeft(index: 0, duration: 0.4)
        }

        if cards.count > 1 {
            animateCardToSlot(index: 1, slot: Self.slots[0], duration: 0.4, delay: 0.05)
        }

        if cards.count > 2 {
            animateCardToSlot(index: 2, slot: Self.slots[1], duration: 0.4, delay: 0.1)
        }

        if let texture = newCardTexture {
            addCardFromRight(texture: texture, data: newCardData, targetSlot: 2, duration: 0.4)
        }
    }

    func loadHTMLCards(data: [SongCardData]) {
        guard let renderer = renderer else { return }

        let group = DispatchGroup()
        var textures: [MTLTexture?] = Array(repeating: nil, count: min(data.count, Self.slots.count))

        for i in 0..<min(data.count, Self.slots.count) {
            group.enter()
            renderer.renderCard(data: data[i]) { texture in
                textures[i] = texture
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.cards.removeAll()

            for i in 0..<textures.count {
                guard let texture = textures[i] else { continue }
                let slot = Self.slots[i]
                let card = CardState(
                    texture: texture,
                    data: i < data.count ? data[i] : nil,
                    currentPosX: Self.offScreenRight.posX,
                    currentPosY: slot.posY,
                    currentScale: Self.offScreenRight.scale,
                    currentOpacity: 1.0,
                    targetPosX: slot.posX,
                    targetPosY: slot.posY,
                    targetScale: slot.scale,
                    targetOpacity: 1.0,
                    isAnimating: true,
                    animStartTime: CACurrentMediaTime() + Double(i) * 0.1,
                    animDuration: 0.4
                )
                self.cards.append(card)
            }
        }
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
