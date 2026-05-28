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
    var animDuration: Float = 0.6

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

    private var stateLock = os_unfair_lock_s()

    private var currentSongState: PanelCardState
    private var announcementState: PanelCardState
    private var outgoingStates: [PanelCardState] = []

    let outWidth = Config.outputWidth
    let outHeight = Config.outputHeight

    static let currentSongSlot = PanelSlot(
        posX: Float(420) / Float(1920) / 2,
        posY: Float(432) / Float(1080) / 2,
        scale: Float(420) / Float(1920)
    )

    static let announcementSlot = PanelSlot(
        posX: Float(420) / Float(1920) / 2,
        posY: (Float(432) + Float(756) / 2) / Float(1080),
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
        for _ in 0..<5 {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<SongCardUniforms>.stride,
                options: .storageModeShared
            ) else { return nil }
            self.uniformsBuffers.append(buffer)
        }

        self.currentSongState = .atSlot(Self.currentSongSlot)
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
        os_unfair_lock_lock(&stateLock)
        updateCardState(&currentSongState, currentTime: currentTime)
        for i in outgoingStates.indices {
            updateCardState(&outgoingStates[i], currentTime: currentTime)
        }
        outgoingStates.removeAll { $0.texture == nil && !$0.isAnimating }
        os_unfair_lock_unlock(&stateLock)
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
        os_unfair_lock_lock(&stateLock)
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
            currentSongState.animDuration = 0.6
            currentSongState.shouldRemoveAfterAnimation = false
            currentSongState.pendingAnimations.removeAll()
        } else if !currentSongState.isAnimating {
             currentSongState.currentPosX = Self.currentSongSlot.posX
             currentSongState.currentPosY = Self.currentSongSlot.posY
             currentSongState.currentScale = Self.currentSongSlot.scale
             currentSongState.currentOpacity = 1.0
         }
         os_unfair_lock_unlock(&stateLock)
     }

    func setAnnouncement(texture: MTLTexture?) {
        os_unfair_lock_lock(&stateLock)
        announcementState.texture = texture
        if !announcementState.isAnimating {
            announcementState.currentPosX = Self.announcementSlot.posX
            announcementState.currentPosY = Self.announcementSlot.posY
            announcementState.currentScale = Self.announcementSlot.scale
            announcementState.currentOpacity = 1.0
        }
        os_unfair_lock_unlock(&stateLock)
    }

    func switchToNext(newCurrentTexture: MTLTexture?, newCurrentData: SongCardData?) {
        os_unfair_lock_lock(&stateLock)
        var outgoingCurrent = currentSongState
        animateStateOutLeft(&outgoingCurrent)
        outgoingStates.append(outgoingCurrent)

        currentSongState = PanelCardState.atSlot(Self.currentSongSlot, texture: newCurrentTexture, data: newCurrentData)
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
        currentSongState.animStartTime = CACurrentMediaTime() + 0.15
        currentSongState.animDuration = 0.6
        currentSongState.shouldRemoveAfterAnimation = false
        currentSongState.pendingAnimations.removeAll()
        os_unfair_lock_unlock(&stateLock)
    }

    func clearAll() {
        os_unfair_lock_lock(&stateLock)
        if currentSongState.texture != nil {
            var outgoing = currentSongState
            animateStateOutLeft(&outgoing)
            outgoingStates.append(outgoing)
        }
        os_unfair_lock_unlock(&stateLock)
    }

    func resetToEmpty() {
        os_unfair_lock_lock(&stateLock)
        currentSongState.texture = nil
        currentSongState.data = nil
        currentSongState.currentPosX = Self.currentSongSlot.posX
        currentSongState.currentPosY = Self.currentSongSlot.posY
        currentSongState.currentScale = Self.currentSongSlot.scale
        currentSongState.currentOpacity = 0.0
        currentSongState.isAnimating = false
        currentSongState.pendingAnimations.removeAll()
        os_unfair_lock_unlock(&stateLock)
    }

    private func animateStateToSlot(_ state: inout PanelCardState, slot: PanelSlot, duration: Float = 0.6, delay: Float = 0.0) {
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

    private func animateStateOutLeft(_ state: inout PanelCardState, duration: Float = 0.6) {
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

        os_unfair_lock_lock(&stateLock)
        let currentSnap = currentSongState
        let announcementSnap = announcementState
        let outgoingSnap = outgoingStates
        os_unfair_lock_unlock(&stateLock)

        encoder.setComputePipelineState(pipelineState)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)

        if let texture = currentSnap.texture, currentSnap.currentOpacity > 0.01 {
            encodeCard(encoder, state: currentSnap, texture: texture, bufferIndex: 0, outputTexture: outputTexture, tgSize: tgSize)
        }

        if let texture = announcementSnap.texture, announcementSnap.currentOpacity > 0.01 {
            encodeCard(encoder, state: announcementSnap, texture: texture, bufferIndex: 1, outputTexture: outputTexture, tgSize: tgSize)
        }

        for i in outgoingSnap.indices {
            let state = outgoingSnap[i]
            if let texture = state.texture, state.currentOpacity > 0.01 {
                let bufferIndex = 2 + i
                if bufferIndex < uniformsBuffers.count {
                    encodeCard(encoder, state: state, texture: texture, bufferIndex: bufferIndex, outputTexture: outputTexture, tgSize: tgSize)
                }
            }
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

        let cardPixelW = Float(outWidth) * state.currentScale
        let cardPixelH = cardPixelW * (Float(state.cardHeight) / Float(state.cardWidth))
        let centerX = uniforms.posX * Float(outWidth)
        let centerY = uniforms.posY * Float(outHeight)
        let originX = max(0, Int(centerX - cardPixelW / 2.0))
        let originY = max(0, Int(centerY - cardPixelH / 2.0))
        let gridW = min(outWidth, Int(centerX + cardPixelW / 2.0)) - originX
        let gridH = min(outHeight, Int(centerY + cardPixelH / 2.0)) - originY

        guard gridW > 0 && gridH > 0 else { return }

        uniforms.originX = Float(originX)
        uniforms.originY = Float(originY)
        memcpy(uniformsBuffers[bufferIndex].contents(), &uniforms, MemoryLayout<SongCardUniforms>.stride)

        encoder.setTexture(outputTexture, index: 0)
        encoder.setTexture(texture, index: 1)
        encoder.setBuffer(uniformsBuffers[bufferIndex], offset: 0, index: 0)

        let gridSize = MTLSize(width: gridW, height: gridH, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
    }
}
