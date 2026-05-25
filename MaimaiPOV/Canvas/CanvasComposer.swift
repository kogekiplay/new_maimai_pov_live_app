import Metal

class CanvasComposer {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let uniformsBuffer: MTLBuffer

    let canvasWidth = Config.outputWidth
    let canvasHeight = Config.outputHeight
    let gameX = Config.gameAreaX
    let gameY = Config.gameAreaY
    let gameW = Config.gameAreaWidth
    let gameH = Config.gameAreaHeight

    let stabWidth = Float(Config.stabWidth)
    let stabHeight = Float(Config.stabHeight)

    var bgColorR: Float = 0.06
    var bgColorG: Float = 0.06
    var bgColorB: Float = 0.12

    init?(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "cropAndCompose"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps

        self.uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<CanvasUniforms>.stride,
            options: .storageModeShared
        )!
    }

    func encode(into encoder: MTLComputeCommandEncoder,
                stabTexture: MTLTexture,
                cx: Float, cy: Float, cropW: Float, cropH: Float,
                outputTexture: MTLTexture) {
        let halfW = cropW / 2.0
        let halfH = cropH / 2.0

        let cropX1 = cx - halfW
        let cropY1 = cy - halfH

        var uniforms = CanvasUniforms()
        uniforms.cropX1 = cropX1
        uniforms.cropY1 = cropY1
        uniforms.cropW = cropW
        uniforms.cropH = cropH
        uniforms.stabWidth = stabWidth
        uniforms.stabHeight = stabHeight
        uniforms.canvasWidth = Float(canvasWidth)
        uniforms.canvasHeight = Float(canvasHeight)
        uniforms.gameX = Float(gameX)
        uniforms.gameY = Float(gameY)
        uniforms.gameW = Float(gameW)
        uniforms.gameH = Float(gameH)
        uniforms.bgColorR = bgColorR
        uniforms.bgColorG = bgColorG
        uniforms.bgColorB = bgColorB

        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<CanvasUniforms>.stride)

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(stabTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBuffer(uniformsBuffer, offset: 0, index: 0)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: canvasWidth, height: canvasHeight, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
    }

    func makeFallbackTrack() -> (cx: Float, cy: Float, cropW: Float, cropH: Float) {
        let cropRatio = Config.gameAreaRatio
        let maxCropW = min(stabWidth, stabHeight * cropRatio)
        let maxCropH = maxCropW / cropRatio
        return (stabWidth / 2.0, stabHeight / 2.0, maxCropW, maxCropH)
    }
}
