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
    let offScreenRightPosX: Float = 1.3

    private var scrollOffset: Float = 0

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

    var hasTitleTexture: Bool {
        return titleTexture != nil
    }

    func setRows(textures: [Int: MTLTexture], data: [SongCardData], startQueueIndex: Int) {
        interruptCurrentAnimations()
        rows.removeAll()
        scrollOffset = 0
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

    func switchToNext(newBottomRowTexture: MTLTexture?, newBottomRowData: SongCardData?, newBottomQueueIndex: Int) {
        interruptCurrentAnimations()

        if !rows.isEmpty {
            animateRowOutRight(index: 0, duration: 0.4)
        }

        for i in 1..<rows.count {
            let targetPosY = rowPosY(rowListIndex: i - 1, scrollOffset: scrollOffset)
            rows[i].queueIndex -= 1
            animateRowTo(index: i, posX: normalPosX, posY: targetPosY, opacity: 1.0, duration: 0.4, delay: 0)
        }

        if let texture = newBottomRowTexture, let data = newBottomRowData {
            let newRowIndex = rows.count
            let targetPosY = rowPosY(rowListIndex: newRowIndex - 1, scrollOffset: scrollOffset)
            let newRow = RightPanelRowState(
                texture: texture,
                data: data,
                queueIndex: newBottomQueueIndex,
                currentPosX: offScreenRightPosX,
                currentPosY: targetPosY,
                currentOpacity: 0.0,
                targetPosX: normalPosX,
                targetPosY: targetPosY,
                targetOpacity: 1.0,
                startPosX: offScreenRightPosX,
                startPosY: targetPosY,
                startOpacity: 0.0,
                isAnimating: true,
                animStartTime: CACurrentMediaTime() + 0.2,
                animDuration: 0.3,
                shouldRemoveAfterAnimation: false,
                pendingAnimations: []
            )
            rows.append(newRow)
        }

        scrollOffset = 0
    }

    func addRowAtBottom(texture: MTLTexture, data: SongCardData, queueIndex: Int) {
        interruptCurrentAnimations()

        let listIndex = rows.count
        let targetPosY = rowPosY(rowListIndex: listIndex, scrollOffset: scrollOffset)

        let newRow = RightPanelRowState(
            texture: texture,
            data: data,
            queueIndex: queueIndex,
            currentPosX: offScreenRightPosX,
            currentPosY: targetPosY,
            currentOpacity: 0.0,
            targetPosX: normalPosX,
            targetPosY: targetPosY,
            targetOpacity: 1.0,
            startPosX: offScreenRightPosX,
            startPosY: targetPosY,
            startOpacity: 0.0,
            isAnimating: true,
            animStartTime: CACurrentMediaTime(),
            animDuration: 0.4,
            shouldRemoveAfterAnimation: false,
            pendingAnimations: []
        )
        rows.append(newRow)
    }

    func reorderRows(newOrder: [(queueIndex: Int, data: SongCardData)], textures: [Int: MTLTexture]) {
        interruptCurrentAnimations()

        var newRows: [RightPanelRowState] = []
        for (listIndex, item) in newOrder.enumerated() {
            let targetPosY = rowPosY(rowListIndex: listIndex, scrollOffset: scrollOffset)
            if let existingIndex = rows.firstIndex(where: { $0.queueIndex == item.queueIndex }) {
                var row = rows[existingIndex]
                row.data = item.data
                if let tex = textures[item.queueIndex] {
                    row.texture = tex
                }
                let fromPosY = row.currentPosY
                let fromPosX = row.currentPosX
                let fromOpacity = row.currentOpacity
                row.startPosX = fromPosX
                row.startPosY = fromPosY
                row.startOpacity = fromOpacity
                row.targetPosX = normalPosX
                row.targetPosY = targetPosY
                row.targetOpacity = 1.0
                row.isAnimating = true
                row.animStartTime = CACurrentMediaTime()
                row.animDuration = 0.4
                row.shouldRemoveAfterAnimation = false
                row.pendingAnimations = []
                newRows.append(row)
            } else {
                let texture = textures[item.queueIndex]
                let row = RightPanelRowState.atPosition(
                    posX: normalPosX,
                    posY: targetPosY,
                    texture: texture,
                    data: item.data,
                    queueIndex: item.queueIndex
                )
                newRows.append(row)
            }
        }
        rows = newRows
    }

    func removeRow(queueIndex: Int) {
        interruptCurrentAnimations()

        guard let removeIndex = rows.firstIndex(where: { $0.queueIndex == queueIndex }) else { return }

        animateRowOutRight(index: removeIndex, duration: 0.4)

        for i in (removeIndex + 1)..<rows.count {
            let targetPosY = rowPosY(rowListIndex: i - 1, scrollOffset: scrollOffset)
            rows[i].queueIndex -= 1
            animateRowTo(index: i, posX: normalPosX, posY: targetPosY, opacity: 1.0, duration: 0.4, delay: 0)
        }
    }

    func scrollToTop(duration: Float = 0.3) {
        scrollOffset = 0
        repositionAllRows()
    }

    func scrollToBottom(totalRows: Int, duration: Float = 0.3) {
        let maxOffset = Float(max(0, totalRows - maxVisibleRows))
        scrollOffset = maxOffset
        repositionAllRows()
    }

    func scrollToRow(rowIndex: Int, duration: Float = 0.3) {
        let targetOffset = Float(max(0, min(rowIndex, max(0, rows.count - maxVisibleRows))))
        scrollOffset = targetOffset
        repositionAllRows()
    }

    func clearAll() {
        rows.removeAll()
        scrollOffset = 0
    }

    var currentRowCount: Int {
        return rows.count
    }

    func getRowDataForQueueIndex(_ queueIndex: Int) -> SongCardData? {
        return rows.first(where: { $0.queueIndex == queueIndex })?.data
    }

    func updateAnimations() {
        let now = CACurrentMediaTime()

        for i in rows.indices {
            guard rows[i].isAnimating else { continue }

            let elapsed = Float(now - rows[i].animStartTime)
            if elapsed < 0 { continue }

            var progress = elapsed / rows[i].animDuration
            progress = min(max(progress, 0), 1)
            let eased = easeOutCubic(progress)

            rows[i].currentPosX = rows[i].startPosX + (rows[i].targetPosX - rows[i].startPosX) * eased
            rows[i].currentPosY = rows[i].startPosY + (rows[i].targetPosY - rows[i].startPosY) * eased
            rows[i].currentOpacity = rows[i].startOpacity + (rows[i].targetOpacity - rows[i].startOpacity) * eased

            if progress >= 1.0 {
                rows[i].currentPosX = rows[i].targetPosX
                rows[i].currentPosY = rows[i].targetPosY
                rows[i].currentOpacity = rows[i].targetOpacity
                rows[i].isAnimating = false

                if rows[i].shouldRemoveAfterAnimation {
                    rows[i].texture = nil
                }

                if !rows[i].pendingAnimations.isEmpty {
                    let nextStep = rows[i].pendingAnimations.removeFirst()
                    startAnimation(index: i, step: nextStep)
                }
            }
        }

        rows.removeAll { $0.texture == nil && !$0.isAnimating }
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

        for i in 0..<rows.count {
            let row = rows[i]
            guard let texture = row.texture, row.currentOpacity > 0.01 else { continue }

            let bufferIndex = (i % (uniformsBuffers.count - 1)) + 1

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

    private func easeOutCubic(_ t: Float) -> Float {
        return 1 - pow(1 - t, 3)
    }

    private func startAnimation(index: Int, step: RightPanelAnimationStep) {
        rows[index].startPosX = rows[index].currentPosX
        rows[index].startPosY = rows[index].currentPosY
        rows[index].startOpacity = rows[index].currentOpacity
        rows[index].targetPosX = step.targetPosX
        rows[index].targetPosY = step.targetPosY
        rows[index].targetOpacity = step.targetOpacity
        rows[index].animDuration = step.duration
        rows[index].animStartTime = CACurrentMediaTime() + CFTimeInterval(step.delay)
        rows[index].isAnimating = true
    }

    private func animateRowTo(index: Int, posX: Float, posY: Float, opacity: Float, duration: Float, delay: Float) {
        guard index < rows.count else { return }
        if delay > 0 {
            let step = RightPanelAnimationStep(targetPosX: posX, targetPosY: posY, targetOpacity: opacity, duration: duration, delay: delay)
            if rows[index].isAnimating {
                rows[index].pendingAnimations.append(step)
            } else {
                startAnimation(index: index, step: step)
            }
        } else {
            rows[index].startPosX = rows[index].currentPosX
            rows[index].startPosY = rows[index].currentPosY
            rows[index].startOpacity = rows[index].currentOpacity
            rows[index].targetPosX = posX
            rows[index].targetPosY = posY
            rows[index].targetOpacity = opacity
            rows[index].animDuration = duration
            rows[index].animStartTime = CACurrentMediaTime()
            rows[index].isAnimating = true
        }
    }

    private func animateRowOutRight(index: Int, duration: Float) {
        guard index < rows.count else { return }
        rows[index].startPosX = rows[index].currentPosX
        rows[index].startPosY = rows[index].currentPosY
        rows[index].startOpacity = rows[index].currentOpacity
        rows[index].targetPosX = offScreenRightPosX
        rows[index].targetPosY = rows[index].currentPosY
        rows[index].targetOpacity = 0.0
        rows[index].animDuration = duration
        rows[index].animStartTime = CACurrentMediaTime()
        rows[index].isAnimating = true
        rows[index].shouldRemoveAfterAnimation = true
        rows[index].pendingAnimations.removeAll()
    }

    private func interruptCurrentAnimations() {
        for i in rows.indices {
            if rows[i].isAnimating {
                rows[i].currentPosX = rows[i].targetPosX
                rows[i].currentPosY = rows[i].targetPosY
                rows[i].currentOpacity = rows[i].targetOpacity
                rows[i].isAnimating = false
                rows[i].pendingAnimations.removeAll()

                if rows[i].shouldRemoveAfterAnimation {
                    rows[i].texture = nil
                    rows[i].shouldRemoveAfterAnimation = false
                }
            }
        }
        rows.removeAll { $0.texture == nil && !$0.isAnimating }
    }

    private func repositionAllRows() {
        for i in 0..<rows.count {
            let targetPosY = rowPosY(rowListIndex: i, scrollOffset: scrollOffset)
            rows[i].currentPosY = targetPosY
            rows[i].targetPosY = targetPosY
            rows[i].startPosY = targetPosY
            rows[i].currentPosX = normalPosX
            rows[i].targetPosX = normalPosX
            rows[i].startPosX = normalPosX
            rows[i].currentOpacity = 1.0
            rows[i].targetOpacity = 1.0
            rows[i].startOpacity = 1.0
            rows[i].isAnimating = false
            rows[i].pendingAnimations.removeAll()
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
