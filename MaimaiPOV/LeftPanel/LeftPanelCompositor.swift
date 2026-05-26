import Metal
import QuartzCore

struct PanelSlot {
    var posX: Float
    var posY: Float
    var scale: Float
}

struct PanelAnimationStep {
    let targetPosX: Float
    let targetPosY: Float
    let targetScale: Float
    let targetOpacity: Float
    let duration: Float
    let delay: Float
}

struct PanelCardState {
    var texture: MTLTexture?
    var data: SongCardData?
    var cardWidth: Int
    var cardHeight: Int

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
    var pendingAnimations: [PanelAnimationStep] = []

    static func atSlot(_ slot: PanelSlot, texture: MTLTexture? = nil, data: SongCardData? = nil, cardWidth: Int = 420, cardHeight: Int = 432) -> PanelCardState {
        return PanelCardState(
            texture: texture,
            data: data,
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            currentPosX: slot.posX,
            currentPosY: slot.posY,
            currentScale: slot.scale,
            currentOpacity: 1.0,
            targetPosX: slot.posX,
            targetPosY: slot.posY,
            targetScale: slot.scale,
            targetOpacity: 1.0,
            startPosX: slot.posX,
            startPosY: slot.posY,
            startScale: slot.scale,
            startOpacity: 1.0
        )
    }
}

class LeftPanelCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private var uniformsBuffers: [MTLBuffer]

    var enabled: Bool = true

    private var currentSongState: PanelCardState
    private var nextSongState: PanelCardState
    private var announcementState: PanelCardState

    let outWidth = Config.outputWidth
    let outHeight = Config.outputHeight

    static let currentSongSlot = PanelSlot(
        posX: Float(420) / Float(1920) / 2,
        posY: Float(432) / Float(1080) / 2,
        scale: Float(420) / Float(1920)
    )

    static let nextSongSlot = PanelSlot(
        posX: Float(420) / Float(1920) / 2,
        posY: (Float(432) + Float(324) / 2) / Float(1080),
        scale: Float(420) / Float(1920) * Float(324) / Float(432)
    )

    static let announcementSlot = PanelSlot(
        posX: Float(420) / Float(1920) / 2,
        posY: (Float(756) + Float(324) / 2) / Float(1080),
        scale: Float(420) / Float(1920)
    )

    static let offScreenLeft = PanelSlot(posX: -0.3, posY: 0.2, scale: Float(420) / Float(1920))

    init?(device: MTLDevice) {
        self.device = device

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "songCardBlend"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps

        self.uniformsBuffers = []
        for _ in 0..<3 {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<SongCardUniforms>.stride,
                options: .storageModeShared
            ) else { return nil }
            self.uniformsBuffers.append(buffer)
        }

        self.currentSongState = .atSlot(Self.currentSongSlot)
        self.nextSongState = .atSlot(Self.nextSongSlot)
        self.announcementState = .atSlot(Self.announcementSlot, cardWidth: LeftPanelTemplate.announcementWidth, cardHeight: LeftPanelTemplate.announcementHeight)
    }

    private func easeOutCubic(_ t: Float) -> Float {
        return 1.0 - pow(1.0 - t, 3.0)
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }

    func updateAnimations() {
        let currentTime = CACurrentMediaTime()
        updateCardState(&currentSongState, currentTime: currentTime)
        updateCardState(&nextSongState, currentTime: currentTime)
    }

    private func updateCardState(_ state: inout PanelCardState, currentTime: CFTimeInterval) {
        guard state.isAnimating else { return }

        let elapsed = Float(currentTime - state.animStartTime)
        if elapsed < 0 { return }

        let rawProgress = min(elapsed / state.animDuration, 1.0)
        let eased = easeOutCubic(rawProgress)

        state.currentPosX = lerp(state.startPosX, state.targetPosX, eased)
        state.currentPosY = lerp(state.startPosY, state.targetPosY, eased)
        state.currentScale = lerp(state.startScale, state.targetScale, eased)
        state.currentOpacity = lerp(state.startOpacity, state.targetOpacity, eased)

        if rawProgress >= 1.0 {
            state.isAnimating = false

            if !state.pendingAnimations.isEmpty {
                let next = state.pendingAnimations.removeFirst()
                state.startPosX = state.currentPosX
                state.startPosY = state.currentPosY
                state.startScale = state.currentScale
                state.startOpacity = state.currentOpacity
                state.targetPosX = next.targetPosX
                state.targetPosY = next.targetPosY
                state.targetScale = next.targetScale
                state.targetOpacity = next.targetOpacity
                state.animDuration = next.duration
                state.animStartTime = CACurrentMediaTime() + Double(next.delay)
                state.isAnimating = true
            } else if state.shouldRemoveAfterAnimation {
                state.texture = nil
                state.data = nil
                state.shouldRemoveAfterAnimation = false
            }
        }
    }

    func setCurrentSong(texture: MTLTexture?, data: SongCardData?, animate: Bool = true) {
        let hadTexture = currentSongState.texture != nil
        currentSongState.texture = texture
        currentSongState.data = data

        if animate && !hadTexture && texture != nil {
            currentSongState.currentPosX = Self.offScreenLeft.posX
            currentSongState.currentPosY = Self.currentSongSlot.posY
            currentSongState.currentScale = Self.currentSongSlot.scale
            currentSongState.currentOpacity = 0.0

            currentSongState.startPosX = Self.offScreenLeft.posX
            currentSongState.startPosY = Self.currentSongSlot.posY
            currentSongState.startScale = Self.currentSongSlot.scale
            currentSongState.startOpacity = 0.0

            currentSongState.targetPosX = Self.currentSongSlot.posX
            currentSongState.targetPosY = Self.currentSongSlot.posY
            currentSongState.targetScale = Self.currentSongSlot.scale
            currentSongState.targetOpacity = 1.0

            currentSongState.isAnimating = true
            currentSongState.animStartTime = CACurrentMediaTime()
            currentSongState.animDuration = 0.4
            currentSongState.shouldRemoveAfterAnimation = false
            currentSongState.pendingAnimations.removeAll()
        } else if !currentSongState.isAnimating {
             currentSongState.currentPosX = Self.currentSongSlot.posX
             currentSongState.currentPosY = Self.currentSongSlot.posY
             currentSongState.currentScale = Self.currentSongSlot.scale
             currentSongState.currentOpacity = 1.0
         }
     }

    func setNextSong(texture: MTLTexture?, data: SongCardData?, animate: Bool = true) {
         let hadTexture = nextSongState.texture != nil
         nextSongState.texture = texture
         nextSongState.data = data

         if animate && !hadTexture && texture != nil {
             nextSongState.currentPosX = Self.offScreenLeft.posX
             nextSongState.currentPosY = Self.nextSongSlot.posY
             nextSongState.currentScale = Self.nextSongSlot.scale
             nextSongState.currentOpacity = 0.0

             nextSongState.startPosX = Self.offScreenLeft.posX
             nextSongState.startPosY = Self.nextSongSlot.posY
             nextSongState.startScale = Self.nextSongSlot.scale
             nextSongState.startOpacity = 0.0

             nextSongState.targetPosX = Self.nextSongSlot.posX
             nextSongState.targetPosY = Self.nextSongSlot.posY
             nextSongState.targetScale = Self.nextSongSlot.scale
             nextSongState.targetOpacity = 1.0

             nextSongState.isAnimating = true
             nextSongState.animStartTime = CACurrentMediaTime() + 0.1
             nextSongState.animDuration = 0.4
             nextSongState.shouldRemoveAfterAnimation = false
             nextSongState.pendingAnimations.removeAll()
         } else if !nextSongState.isAnimating {
             nextSongState.currentPosX = Self.nextSongSlot.posX
             nextSongState.currentPosY = Self.nextSongSlot.posY
             nextSongState.currentScale = Self.nextSongSlot.scale
             nextSongState.currentOpacity = 1.0
         }
     }

    func setAnnouncement(texture: MTLTexture?) {
        announcementState.texture = texture
        if !announcementState.isAnimating {
            announcementState.currentPosX = Self.announcementSlot.posX
            announcementState.currentPosY = Self.announcementSlot.posY
            announcementState.currentScale = Self.announcementSlot.scale
            announcementState.currentOpacity = 1.0
        }
    }

    func switchToNext(newNextTexture: MTLTexture?, newNextData: SongCardData?) {
        animateStateOutLeft(&currentSongState)

        animateStateToSlot(&nextSongState, slot: Self.currentSongSlot, duration: 0.4, delay: 0.05)

        let oldNextState = nextSongState
        currentSongState = oldNextState
        currentSongState.shouldRemoveAfterAnimation = false
        currentSongState.pendingAnimations.removeAll()

        var newState = PanelCardState.atSlot(Self.nextSongSlot, texture: newNextTexture, data: newNextData)
        newState.currentPosX = Self.offScreenLeft.posX
        newState.currentPosY = Self.nextSongSlot.posY
        newState.currentScale = Self.nextSongSlot.scale
        newState.currentOpacity = 0.0
        newState.startPosX = Self.offScreenLeft.posX
        newState.startPosY = Self.nextSongSlot.posY
        newState.startScale = Self.nextSongSlot.scale
        newState.startOpacity = 0.0
        newState.targetPosX = Self.nextSongSlot.posX
        newState.targetPosY = Self.nextSongSlot.posY
        newState.targetScale = Self.nextSongSlot.scale
        newState.targetOpacity = 1.0
        newState.isAnimating = true
        newState.animStartTime = CACurrentMediaTime() + 0.1
        newState.animDuration = 0.4
        nextSongState = newState
    }

    func clearAll() {
        animateStateOutLeft(&currentSongState)
        animateStateOutLeft(&nextSongState)
    }

    func resetToEmpty() {
        currentSongState.texture = nil
        currentSongState.data = nil
        currentSongState.currentPosX = Self.currentSongSlot.posX
        currentSongState.currentPosY = Self.currentSongSlot.posY
        currentSongState.currentScale = Self.currentSongSlot.scale
        currentSongState.currentOpacity = 0.0
        currentSongState.isAnimating = false
        currentSongState.pendingAnimations.removeAll()

        nextSongState.texture = nil
        nextSongState.data = nil
        nextSongState.currentPosX = Self.nextSongSlot.posX
        nextSongState.currentPosY = Self.nextSongSlot.posY
        nextSongState.currentScale = Self.nextSongSlot.scale
        nextSongState.currentOpacity = 0.0
        nextSongState.isAnimating = false
        nextSongState.pendingAnimations.removeAll()
    }

    private func animateStateToSlot(_ state: inout PanelCardState, slot: PanelSlot, duration: Float = 0.4, delay: Float = 0.0) {
        state.startPosX = state.currentPosX
        state.startPosY = state.currentPosY
        state.startScale = state.currentScale
        state.startOpacity = state.currentOpacity

        state.targetPosX = slot.posX
        state.targetPosY = slot.posY
        state.targetScale = slot.scale
        state.targetOpacity = 1.0

        state.isAnimating = true
        state.animStartTime = CACurrentMediaTime() + Double(delay)
        state.animDuration = duration
        state.shouldRemoveAfterAnimation = false
        state.pendingAnimations.removeAll()
    }

    private func animateStateOutLeft(_ state: inout PanelCardState, duration: Float = 0.4) {
        state.startPosX = state.currentPosX
        state.startPosY = state.currentPosY
        state.startScale = state.currentScale
        state.startOpacity = state.currentOpacity

        state.targetPosX = Self.offScreenLeft.posX
        state.targetPosY = Self.offScreenLeft.posY
        state.targetScale = Self.offScreenLeft.scale
        state.targetOpacity = 0.0

        state.isAnimating = true
        state.animStartTime = CACurrentMediaTime()
        state.animDuration = duration
        state.shouldRemoveAfterAnimation = true
        state.pendingAnimations.removeAll()
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled else { return }

        encoder.setComputePipelineState(pipelineState)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)

        if let texture = currentSongState.texture, currentSongState.currentOpacity > 0.01 {
            encodeCard(encoder, state: currentSongState, texture: texture, bufferIndex: 0, outputTexture: outputTexture, tgSize: tgSize)
        }

        if let texture = nextSongState.texture, nextSongState.currentOpacity > 0.01 {
            encodeCard(encoder, state: nextSongState, texture: texture, bufferIndex: 1, outputTexture: outputTexture, tgSize: tgSize)
        }

        if let texture = announcementState.texture, announcementState.currentOpacity > 0.01 {
            encodeCard(encoder, state: announcementState, texture: texture, bufferIndex: 2, outputTexture: outputTexture, tgSize: tgSize)
        }
    }

    private func encodeCard(_ encoder: MTLComputeCommandEncoder, state: PanelCardState, texture: MTLTexture, bufferIndex: Int, outputTexture: MTLTexture, tgSize: MTLSize) {
        var uniforms = SongCardUniforms()
        uniforms.posX = state.currentPosX
        uniforms.posY = state.currentPosY
        uniforms.scale = state.currentScale
        uniforms.opacity = state.currentOpacity
        uniforms.cardWidth = Float(state.cardWidth)
        uniforms.cardHeight = Float(state.cardHeight)
        uniforms.outWidth = Float(outWidth)
        uniforms.outHeight = Float(outHeight)

        memcpy(uniformsBuffers[bufferIndex].contents(), &uniforms, MemoryLayout<SongCardUniforms>.stride)

        encoder.setTexture(outputTexture, index: 0)
        encoder.setTexture(texture, index: 1)
        encoder.setBuffer(uniformsBuffers[bufferIndex], offset: 0, index: 0)

        let gridSize = MTLSize(width: outWidth, height: outHeight, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
    }
}
