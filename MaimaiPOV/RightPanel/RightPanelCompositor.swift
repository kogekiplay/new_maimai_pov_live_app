import Metal
import QuartzCore

struct RightPanelRowState {
    var texture: MTLTexture?
    var data: SongCardData?
    var queueIndex: Int

    var currentPosX: Float
    var currentPosY: Float
    var currentOpacity: Float

    var targetPosX: Float
    var targetPosY: Float
    var targetOpacity: Float

    var startPosX: Float
    var startPosY: Float
    var startOpacity: Float

    var isAnimating: Bool = false
    var animStartTime: CFTimeInterval = 0
    var animDuration: Float = 0.4

    var shouldRemoveAfterAnimation: Bool = false
    var pendingAnimations: [RightPanelAnimationStep] = []

    static func atPosition(posX: Float, posY: Float, texture: MTLTexture? = nil, data: SongCardData? = nil, queueIndex: Int = -1) -> RightPanelRowState {
        return RightPanelRowState(
            texture: texture,
            data: data,
            queueIndex: queueIndex,
            currentPosX: posX,
            currentPosY: posY,
            currentOpacity: 1.0,
            targetPosX: posX,
            targetPosY: posY,
            targetOpacity: 1.0,
            startPosX: posX,
            startPosY: posY,
            startOpacity: 1.0
        )
    }
}

struct RightPanelAnimationStep {
    let targetPosX: Float
    let targetPosY: Float
    let targetOpacity: Float
    let duration: Float
    let delay: Float
}

class RightPanelCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private var uniformsBuffers: [MTLBuffer]

    var enabled: Bool = true

    let panelX: Int = Config.outputWidth - 420
    let panelWidth: Int = 420
    let panelHeight: Int = Config.outputHeight
    let titleHeight: Int = RightPanelTemplate.titleHeight
    let rowHeight: Int = RightPanelTemplate.rowHeight
    let maxVisibleRows: Int = 8

    let outWidth = Config.outputWidth
    let outHeight = Config.outputHeight

    private var rows: [RightPanelRowState] = []
    private var titleTexture: MTLTexture?

    let rowScale: Float = Float(420) / Float(Config.outputWidth)
    let normalPosX: Float = Float(Config.outputWidth - 420) / Float(Config.outputWidth) / 2 + 0.5

    init?(device: MTLDevice) {
        self.device = device

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "songCardBlend"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps

        self.uniformsBuffers = []
        for _ in 0..<12 {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<SongCardUniforms>.stride,
                options: .storageModeShared
            ) else { return nil }
            self.uniformsBuffers.append(buffer)
        }
    }

    func updateTitleTexture(_ texture: MTLTexture?) {
        titleTexture = texture
    }

    func setRows(textures: [Int: MTLTexture], data: [SongCardData], startQueueIndex: Int) {
        rows.removeAll()
        for (i, songData) in data.enumerated() {
            let queueIndex = startQueueIndex + i
            let texture = textures[queueIndex]
            let posY = rowPosY(rowListIndex: i, scrollOffset: 0)
            let rowState = RightPanelRowState.atPosition(
                posX: normalPosX,
                posY: posY,
                texture: texture,
                data: songData,
                queueIndex: queueIndex
            )
            rows.append(rowState)
        }
    }

    func clearAll() {
        rows.removeAll()
    }

    func updateAnimations() {
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled else { return }

        encoder.setComputePipelineState(pipelineState)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)

        if let titleTex = titleTexture {
            var uniforms = SongCardUniforms()
            uniforms.posX = normalPosX
            uniforms.posY = titlePosY()
            uniforms.scale = rowScale
            uniforms.opacity = 1.0
            uniforms.cardWidth = Float(RightPanelTemplate.titleWidth)
            uniforms.cardHeight = Float(titleHeight)
            uniforms.outWidth = Float(outWidth)
            uniforms.outHeight = Float(outHeight)

            if uniformsBuffers.count > 0 {
                memcpy(uniformsBuffers[0].contents(), &uniforms, MemoryLayout<SongCardUniforms>.stride)
                encoder.setTexture(outputTexture, index: 0)
                encoder.setTexture(titleTex, index: 1)
                encoder.setBuffer(uniformsBuffers[0], offset: 0, index: 0)

                let gridSize = MTLSize(width: outWidth, height: outHeight, depth: 1)
                encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
            }
        }

        for i in 0..<min(rows.count, maxVisibleRows) {
            let row = rows[i]
            guard let texture = row.texture, row.currentOpacity > 0.01 else { continue }

            let bufferIndex = i + 1
            guard bufferIndex < uniformsBuffers.count else { break }

            var uniforms = SongCardUniforms()
            uniforms.posX = row.currentPosX
            uniforms.posY = row.currentPosY
            uniforms.scale = rowScale
            uniforms.opacity = row.currentOpacity
            uniforms.cardWidth = Float(RightPanelTemplate.rowWidth)
            uniforms.cardHeight = Float(rowHeight)
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

    private func titlePosY() -> Float {
        return Float(titleHeight) / Float(outHeight) / 2.0
    }

    private func rowPosY(rowListIndex: Int, scrollOffset: Float) -> Float {
        let y = Float(titleHeight) + Float(rowListIndex) * Float(rowHeight) + Float(rowHeight) / 2.0
        let scrolledY = y - scrollOffset * Float(rowHeight)
        return scrolledY / Float(outHeight)
    }
}
