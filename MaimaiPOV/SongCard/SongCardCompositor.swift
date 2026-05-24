import Metal

class SongCardCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private var uniformsBuffers: [MTLBuffer]

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

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled, !cards.isEmpty else { return }

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(outputTexture, index: 0)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)

        for i in 0..<min(cards.count, Self.maxCards) {
            guard let cardTex = cards[i].texture else { continue }

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
