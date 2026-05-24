import Metal
import QuartzCore

class SongCardCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private var uniformsBuffers: [MTLBuffer]

    enum AnimationState: Int32 {
        case idle = 0
        case fadeIn = 1
        case fadeOut = 2
        case slideInLeft = 3
        case slideOutLeft = 4
        case slideInRight = 5
        case slideOutRight = 6
    }

    struct CardState {
        var texture: MTLTexture?
        var posX: Float
        var posY: Float
        var scale: Float
        var opacity: Float
        var slideOffsetX: Float = 0.0
        var slideOffsetY: Float = 0.0
        var animProgress: Float = 1.0
        var animType: Int32 = 0

        var animState: AnimationState = .idle
        var animStartTime: CFTimeInterval = 0
        var animDuration: Float = 0.5
    }

    var cards: [CardState] = []
    var enabled: Bool = false

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

        createTestCards()
    }

    private func createTestCards() {
        guard let tex1 = createTestTexture(width: 300, height: 120, b: 200, g: 80, r: 50, a: 200),
              let tex2 = createTestTexture(width: 280, height: 100, b: 50, g: 180, r: 60, a: 180),
              let tex3 = createTestTexture(width: 240, height: 80, b: 30, g: 130, r: 220, a: 180) else {
            return
        }

        cards = [
            CardState(texture: tex1, posX: 0.22, posY: 0.12, scale: 0.42, opacity: 1.0),
            CardState(texture: tex2, posX: 0.22, posY: 0.22, scale: 0.38, opacity: 1.0),
            CardState(texture: tex3, posX: 0.18, posY: 0.88, scale: 0.32, opacity: 1.0)
        ]
    }

    private func createTestTexture(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8, a: UInt8) -> MTLTexture? {
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        let border = max(4, min(width, height) / 15)

        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let isBorder = x < border || x >= width - border || y < border || y >= height - border

                if isBorder {
                    pixelData[idx] = 255
                    pixelData[idx + 1] = 255
                    pixelData[idx + 2] = 255
                    pixelData[idx + 3] = 220
                } else {
                    pixelData[idx] = b
                    pixelData[idx + 1] = g
                    pixelData[idx + 2] = r
                    pixelData[idx + 3] = a
                }
            }
        }

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = .shaderRead
        texDesc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: texDesc) else { return nil }

        texture.replace(
            region: MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                              size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4
        )

        return texture
    }

    func triggerFadeIn(index: Int, duration: Float = 0.5) {
        guard index >= 0, index < cards.count else { return }
        cards[index].animState = .fadeIn
        cards[index].animStartTime = CACurrentMediaTime()
        cards[index].animDuration = duration
        cards[index].animProgress = 0.0
        cards[index].animType = AnimationState.fadeIn.rawValue
    }

    func triggerFadeOut(index: Int, duration: Float = 0.5) {
        guard index >= 0, index < cards.count else { return }
        cards[index].animState = .fadeOut
        cards[index].animStartTime = CACurrentMediaTime()
        cards[index].animDuration = duration
        cards[index].animProgress = 1.0
        cards[index].animType = AnimationState.fadeOut.rawValue
    }

    func triggerSlideIn(index: Int, fromLeft: Bool = true, duration: Float = 0.5) {
        guard index >= 0, index < cards.count else { return }
        cards[index].animState = fromLeft ? .slideInLeft : .slideInRight
        cards[index].animStartTime = CACurrentMediaTime()
        cards[index].animDuration = duration
        cards[index].animProgress = 0.0
        cards[index].slideOffsetX = fromLeft ? -1.0 : 1.0
        cards[index].animType = (fromLeft ? AnimationState.slideInLeft : AnimationState.slideInRight).rawValue
    }

    func triggerSlideOut(index: Int, toLeft: Bool = true, duration: Float = 0.5) {
        guard index >= 0, index < cards.count else { return }
        cards[index].animState = toLeft ? .slideOutLeft : .slideOutRight
        cards[index].animStartTime = CACurrentMediaTime()
        cards[index].animDuration = duration
        cards[index].animProgress = 1.0
        cards[index].slideOffsetX = 0.0
        cards[index].animType = (toLeft ? AnimationState.slideOutLeft : AnimationState.slideOutRight).rawValue
    }

    func triggerAllFadeIn(duration: Float = 0.5) {
        for i in 0..<cards.count {
            triggerFadeIn(index: i, duration: duration + Float(i) * 0.15)
        }
    }

    func triggerAllSlideIn(duration: Float = 0.5) {
        for i in 0..<cards.count {
            triggerSlideIn(index: i, fromLeft: true, duration: duration + Float(i) * 0.1)
        }
    }

    private func easeOutCubic(_ t: Float) -> Float {
        return 1.0 - pow(1.0 - t, 3.0)
    }

    func updateAnimations() {
        let currentTime = CACurrentMediaTime()

        for i in 0..<cards.count {
            guard cards[i].animState != .idle else { continue }

            let elapsed = Float(currentTime - cards[i].animStartTime)
            let rawProgress = min(elapsed / cards[i].animDuration, 1.0)
            let eased = easeOutCubic(rawProgress)

            switch cards[i].animState {
            case .fadeIn:
                cards[i].animProgress = eased
                if rawProgress >= 1.0 {
                    cards[i].animState = .idle
                    cards[i].animType = 0
                }

            case .fadeOut:
                cards[i].animProgress = 1.0 - eased
                if rawProgress >= 1.0 {
                    cards[i].animState = .idle
                    cards[i].animType = 0
                    cards[i].animProgress = 0.0
                }

            case .slideInLeft:
                cards[i].animProgress = eased
                cards[i].slideOffsetX = (1.0 - eased) * -1.0
                if rawProgress >= 1.0 {
                    cards[i].animState = .idle
                    cards[i].animType = 0
                    cards[i].slideOffsetX = 0.0
                }

            case .slideInRight:
                cards[i].animProgress = eased
                cards[i].slideOffsetX = (1.0 - eased) * 1.0
                if rawProgress >= 1.0 {
                    cards[i].animState = .idle
                    cards[i].animType = 0
                    cards[i].slideOffsetX = 0.0
                }

            case .slideOutLeft:
                cards[i].animProgress = 1.0 - eased
                cards[i].slideOffsetX = eased * -1.0
                if rawProgress >= 1.0 {
                    cards[i].animState = .idle
                    cards[i].animType = 0
                    cards[i].animProgress = 0.0
                    cards[i].slideOffsetX = -1.0
                }

            case .slideOutRight:
                cards[i].animProgress = 1.0 - eased
                cards[i].slideOffsetX = eased * 1.0
                if rawProgress >= 1.0 {
                    cards[i].animState = .idle
                    cards[i].animType = 0
                    cards[i].animProgress = 0.0
                    cards[i].slideOffsetX = 1.0
                }

            default:
                break
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
            if cards[i].animProgress < 0.001 && cards[i].animState == .idle { continue }

            var uniforms = SongCardUniforms()
            uniforms.posX = cards[i].posX
            uniforms.posY = cards[i].posY
            uniforms.scale = cards[i].scale
            uniforms.opacity = cards[i].opacity
            uniforms.slideOffsetX = cards[i].slideOffsetX
            uniforms.slideOffsetY = cards[i].slideOffsetY
            uniforms.cardWidth = Float(cardTex.width)
            uniforms.cardHeight = Float(cardTex.height)
            uniforms.outWidth = Float(outWidth)
            uniforms.outHeight = Float(outHeight)
            uniforms.animProgress = cards[i].animProgress
            uniforms.animType = cards[i].animType

            memcpy(uniformsBuffers[i].contents(), &uniforms, MemoryLayout<SongCardUniforms>.stride)

            encoder.setTexture(cardTex, index: 1)
            encoder.setBuffer(uniformsBuffers[i], offset: 0, index: 0)

            let gridSize = MTLSize(width: outWidth, height: outHeight, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
    }
}
