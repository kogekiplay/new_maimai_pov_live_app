import Metal

class MarqueeCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let uniformsBuffer: MTLBuffer
    let manager: MarqueeManager
    private let renderer: MarqueeRenderer

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
            length: MemoryLayout<MarqueeUniforms>.stride,
            options: .storageModeShared
        )!
    }

    func updateAnimations() {
        let toRender = manager.slotsToRender
        for entry in toRender {
            let (texture, contentWidth) = renderer.render(text: entry.item.text, type: entry.item.type)
            if let texture = texture {
                manager.setCurrentTexture(texture, contentWidth: contentWidth, for: entry.item.id)
            }
        }
        manager.updateAnimations()
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled else { return }

        let activeSlots = manager.activeSlots
        guard !activeSlots.isEmpty else { return }

        for slot in activeSlots {
            guard let textTexture = slot.item.texture else { continue }

            var uniforms = MarqueeUniforms()
            uniforms.scrollX = slot.scrollX
            uniforms.textY = Float(slot.yPosition)
            uniforms.textWidth = Float(slot.item.contentWidth)
            uniforms.textHeight = Float(manager.barHeight)
            uniforms.opacity = 1.0
            uniforms.outWidth = Float(Config.outputWidth)
            uniforms.outHeight = Float(Config.outputHeight)

            memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<MarqueeUniforms>.stride)

            encoder.setComputePipelineState(pipelineState)
            encoder.setTexture(outputTexture, index: 0)
            encoder.setTexture(textTexture, index: 1)
            encoder.setBuffer(uniformsBuffer, offset: 0, index: 0)

            let tgSize = MTLSize(width: 16, height: 16, depth: 1)
            let gridSize = MTLSize(width: Config.outputWidth, height: Config.outputHeight, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
    }
}
