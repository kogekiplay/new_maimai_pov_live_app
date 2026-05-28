import Metal

class DeviceStatusCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let uniformsBuffer: MTLBuffer
    private let manager: DeviceStatusManager
    private let renderer: DeviceStatusRenderer
    private var currentTexture: MTLTexture?
    private var currentContentWidth: Int = 0
    private var lastRenderedLevel: Int = -2
    var enabled: Bool = true

    private let padding: Int = 16
    private let barHeight: Int = 44

    init?(device: MTLDevice, manager: DeviceStatusManager, renderer: DeviceStatusRenderer) {
        self.device = device
        self.manager = manager
        self.renderer = renderer

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "deviceStatusBlend"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps
        self.uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<DeviceStatusUniforms>.stride,
            options: .storageModeShared
        )!
    }

    func updateIfNeeded() {
        let level = manager.batteryLevel
        guard level != lastRenderedLevel else { return }
        lastRenderedLevel = level

        let displayLevel = level < 0 ? 0 : level
        let text = "🔋 \(displayLevel)%"
        let (texture, width) = renderer.render(text: text)
        currentTexture = texture
        currentContentWidth = width
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled, let texture = currentTexture, currentContentWidth > 0 else { return }

        let posX = Float(Config.gameAreaX + Config.gameAreaWidth - padding - currentContentWidth)
        let posY = Float(padding)
        let texWidth = Float(currentContentWidth)
        let texHeight = Float(barHeight)

        let originX = max(0, Int(posX))
        let originY = max(0, Int(posY))
        let gridW = min(Config.outputWidth, Int(posX + texWidth)) - originX
        let gridH = min(Config.outputHeight, Int(posY + texHeight)) - originY

        guard gridW > 0 && gridH > 0 else { return }

        var uniforms = DeviceStatusUniforms()
        uniforms.posX = posX
        uniforms.posY = posY
        uniforms.texWidth = texWidth
        uniforms.texHeight = texHeight
        uniforms.opacity = 1.0
        uniforms.outWidth = Float(Config.outputWidth)
        uniforms.outHeight = Float(Config.outputHeight)
        uniforms.originX = Float(originX)
        uniforms.originY = Float(originY)

        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<DeviceStatusUniforms>.stride)

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(outputTexture, index: 0)
        encoder.setTexture(texture, index: 1)
        encoder.setBuffer(uniformsBuffer, offset: 0, index: 0)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: gridW, height: gridH, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
    }
}
