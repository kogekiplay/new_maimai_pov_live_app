import Metal

class MarqueeCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let uniformsBuffer: MTLBuffer
    let manager: MarqueeManager
    private let renderer: MarqueeRenderer

    private let maxConcurrentItems = 16

    var enabled: Bool = true

    init?(device: MTLDevice, manager: MarqueeManager, renderer: MarqueeRenderer) {
        self.device = device
        self.manager = manager
        self.renderer = renderer

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "marqueeBlend"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps
        self.uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<MarqueeUniforms>.stride * maxConcurrentItems,
            options: .storageModeShared
        )!
    }

    func updateAnimations() {
        let toRender = manager.itemsToRender
        for item in toRender {
            let (texture, contentWidth) = renderer.render(text: item.text, type: item.type)
            if let texture = texture {
                manager.setCurrentTexture(texture, contentWidth: contentWidth, for: item.id)
            }
        }
        manager.updateAnimations()
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled else { return }

        let items = manager.visibleItems
        guard !items.isEmpty else { return }

        for (index, entry) in items.enumerated() {
            guard index < maxConcurrentItems else { break }
            guard let textTexture = entry.item.texture else { continue }

            var uniforms = MarqueeUniforms()
            uniforms.scrollX = entry.scrollX
            uniforms.textY = Float(manager.barY)
            uniforms.textWidth = Float(entry.item.contentWidth)
            uniforms.textHeight = Float(manager.barHeight)
            uniforms.opacity = 1.0
            uniforms.outWidth = Float(Config.outputWidth)
            uniforms.outHeight = Float(Config.outputHeight)

            let offset = index * MemoryLayout<MarqueeUniforms>.stride
            memcpy(uniformsBuffer.contents() + offset, &uniforms, MemoryLayout<MarqueeUniforms>.stride)

            encoder.setComputePipelineState(pipelineState)
            encoder.setTexture(outputTexture, index: 0)
            encoder.setTexture(textTexture, index: 1)
            encoder.setBuffer(uniformsBuffer, offset: offset, index: 0)

            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let gridSize = MTLSize(width: Config.outputWidth, height: Config.outputHeight, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
    }
}
