import Metal
import QuartzCore

struct RightPanelRowState {
    var texture: MTLTexture?
    var data: SongCardData?
    var queueIndex: Int

    var currentPosX: Float
    var currentPosY: Float
    var currentOpacity: Float
    var currentScale: Float

    var targetPosX: Float
    var targetPosY: Float
    var targetOpacity: Float
    var targetScale: Float

    var startPosX: Float
    var startPosY: Float
    var startOpacity: Float
    var startScale: Float

    var isAnimating: Bool = false
    var animStartTime: CFTimeInterval = 0
    var animDuration: Float = 0.6

    var shouldRemoveAfterAnimation: Bool = false
    var pendingAnimations: [RightPanelAnimationStep] = []
    var zOrder: Int = 0

    static func atPosition(posX: Float, posY: Float, texture: MTLTexture? = nil, data: SongCardData? = nil, queueIndex: Int = -1) -> RightPanelRowState {
        return RightPanelRowState(
            texture: texture,
            data: data,
            queueIndex: queueIndex,
            currentPosX: posX,
            currentPosY: posY,
            currentOpacity: 1.0,
            currentScale: 1.0,
            targetPosX: posX,
            targetPosY: posY,
            targetOpacity: 1.0,
            targetScale: 1.0,
            startPosX: posX,
            startPosY: posY,
            startOpacity: 1.0,
            startScale: 1.0
        )
    }
}

struct RightPanelAnimationStep {
    let targetPosX: Float
    let targetPosY: Float
    let targetOpacity: Float
    let targetScale: Float
    let duration: Float
    let delay: Float
}

class RightPanelCompositor {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private var uniformsBuffers: [MTLBuffer]

    var enabled: Bool = true

    private var stateLock = os_unfair_lock_s()

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
    private var pendingScrollOffset: Float? = nil

    private var targetScrollOffset: Float = 0
    private var startScrollOffset: Float = 0
    private var scrollAnimStartTime: CFTimeInterval = 0
    private var scrollAnimDuration: Float = 0.45
    private var isScrollAnimating: Bool = false
    private var scrollCompletion: (() -> Void)?
    private var isPreScrolling: Bool = false

    private var isIdleScrolling: Bool = false
    private let idleScrollSpeed: Float = 0.5
    private var idleScrollLastTime: CFTimeInterval = 0
    private var lastOperationTime: CFTimeInterval = 0
    private let idleScrollPauseDuration: Float = 2.0

    private enum IdleScrollPhase {
        case waiting
        case scrolling
        case fadingOut
        case fadingIn
    }
    private var idleScrollPhase: IdleScrollPhase = .waiting

    private var globalOpacity: Float = 1.0
    private var targetGlobalOpacity: Float = 1.0
    private var startGlobalOpacity: Float = 1.0
    private var globalOpacityAnimating: Bool = false
    private var globalOpacityAnimStartTime: CFTimeInterval = 0
    private var globalOpacityAnimDuration: Float = 0.75

    var currentScrollOffset: Float {
        return pendingScrollOffset ?? scrollOffset
    }

    var totalRowCount: Int {
        return rows.count
    }

    init?(device: MTLDevice) {
        self.device = device

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "songCardBlend"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps

        self.uniformsBuffers = []
        for _ in 0..<64 {
            guard let buffer = device.makeBuffer(
                length: MemoryLayout<SongCardUniforms>.stride,
                options: .storageModeShared
            ) else { return nil }
            self.uniformsBuffers.append(buffer)
        }
    }

    func updateTitleTexture(_ texture: MTLTexture?) {
        os_unfair_lock_lock(&stateLock)
        titleTexture = texture
        os_unfair_lock_unlock(&stateLock)
    }

    var hasTitleTexture: Bool {
        return titleTexture != nil
    }

    func setRows(textures: [Int: MTLTexture], data: [SongCardData], startQueueIndex: Int) {
        os_unfair_lock_lock(&stateLock)
        interruptCurrentAnimations()
        rows.removeAll()
        scrollOffset = 0
        lastOperationTime = CACurrentMediaTime()
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
        os_unfair_lock_unlock(&stateLock)
    }

    func switchToNext(newBottomRowTexture: MTLTexture?, newBottomRowData: SongCardData?, newBottomQueueIndex: Int) {
        os_unfair_lock_lock(&stateLock)
        interruptCurrentAnimations()
        lastOperationTime = CACurrentMediaTime()

        if !rows.isEmpty {
            animateRowOutRight(index: 0, duration: 0.6)
        }

        for i in 1..<rows.count {
            let targetPosY = rowPosY(rowListIndex: i - 1, scrollOffset: scrollOffset)
            rows[i].queueIndex -= 1
            animateRowTo(index: i, posX: normalPosX, posY: targetPosY, opacity: 1.0, duration: 0.6, delay: 0)
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
                currentScale: 1.0,
                targetPosX: normalPosX,
                targetPosY: targetPosY,
                targetOpacity: 1.0,
                targetScale: 1.0,
                startPosX: offScreenRightPosX,
                startPosY: targetPosY,
                startOpacity: 0.0,
                startScale: 1.0,
                isAnimating: true,
                animStartTime: CACurrentMediaTime() + 0.3,
                animDuration: 0.45,
                shouldRemoveAfterAnimation: false,
                pendingAnimations: []
            )
            rows.append(newRow)
        }
        os_unfair_lock_unlock(&stateLock)
    }

    func addRowAtBottom(texture: MTLTexture, data: SongCardData, queueIndex: Int) {
        os_unfair_lock_lock(&stateLock)
        if isScrollAnimating {
            scrollOffset = targetScrollOffset
            isScrollAnimating = false
            scrollCompletion = nil
            updateRowPositionsForScroll()
        }
        _stopIdleScrollLocked()
        lastOperationTime = CACurrentMediaTime()

        let listIndex = rows.count
        let targetPosY = rowPosY(rowListIndex: listIndex, scrollOffset: scrollOffset)

        let newRow = RightPanelRowState(
            texture: texture,
            data: data,
            queueIndex: queueIndex,
            currentPosX: offScreenRightPosX,
            currentPosY: targetPosY,
            currentOpacity: 0.0,
            currentScale: 1.0,
            targetPosX: normalPosX,
            targetPosY: targetPosY,
            targetOpacity: 1.0,
            targetScale: 1.0,
            startPosX: offScreenRightPosX,
            startPosY: targetPosY,
            startOpacity: 0.0,
            startScale: 1.0,
            isAnimating: true,
            animStartTime: CACurrentMediaTime(),
            animDuration: 0.6,
            shouldRemoveAfterAnimation: false,
            pendingAnimations: []
        )
        rows.append(newRow)
        os_unfair_lock_unlock(&stateLock)
    }

    func reorderRows(newOrder: [(queueIndex: Int, data: SongCardData)], textures: [Int: MTLTexture], targetScrollOffset: Float? = nil) {
        os_unfair_lock_lock(&stateLock)
        interruptCurrentAnimations(preservePosition: true)
        lastOperationTime = CACurrentMediaTime()

        let effectiveTargetScrollOffset = targetScrollOffset ?? scrollOffset

        if targetScrollOffset != nil {
            pendingScrollOffset = targetScrollOffset
        }

        print("[RightPanel] reorderRows called, newOrder.count=\(newOrder.count), existing rows=\(rows.count), targetScrollOffset=\(effectiveTargetScrollOffset)")

        var moveDistances: [UUID: Float] = [:]
        for (listIndex, item) in newOrder.enumerated() {
            let targetPosY = rowPosY(rowListIndex: listIndex, scrollOffset: effectiveTargetScrollOffset)
            if let existingIndex = rows.firstIndex(where: { $0.data?.id == item.data.id }) {
                let fromPosY = rows[existingIndex].currentPosY
                let distance = max(0, fromPosY - targetPosY)
                moveDistances[item.data.id] = distance
            }
        }

        var newRows: [RightPanelRowState] = []
        for (listIndex, item) in newOrder.enumerated() {
            let targetPosY = rowPosY(rowListIndex: listIndex, scrollOffset: effectiveTargetScrollOffset)
            if let existingIndex = rows.firstIndex(where: { $0.data?.id == item.data.id }) {
                var row = rows[existingIndex]
                let fromPosY = row.currentPosY
                row.data = item.data
                row.queueIndex = item.queueIndex
                if let tex = textures[item.queueIndex] {
                    row.texture = tex
                }
                row.startPosX = row.currentPosX
                row.startPosY = row.currentPosY
                row.startOpacity = row.currentOpacity
                row.startScale = row.currentScale
                row.targetPosX = normalPosX
                row.targetPosY = targetPosY
                row.targetOpacity = 1.0
                row.targetScale = 1.0
                row.isAnimating = true
                row.animStartTime = CACurrentMediaTime()
                row.animDuration = targetScrollOffset != nil ? 1.0 : 0.6
                row.shouldRemoveAfterAnimation = false
                row.pendingAnimations = []

                let distance = moveDistances[item.data.id] ?? 0
                let isMovingUp = targetPosY < row.startPosY - 0.001
                let isMovingDown = targetPosY > row.startPosY + 0.001

                if isMovingUp && distance > 0.001 {
                    row.zOrder = 100
                    let scaleStep = RightPanelAnimationStep(
                        targetPosX: normalPosX,
                        targetPosY: targetPosY,
                        targetOpacity: 1.0,
                        targetScale: 1.20,
                        duration: 0.45,
                        delay: 0
                    )
                    let scaleBackStep = RightPanelAnimationStep(
                        targetPosX: normalPosX,
                        targetPosY: targetPosY,
                        targetOpacity: 1.0,
                        targetScale: 1.0,
                        duration: 0.55,
                        delay: 0
                    )
                    row.targetScale = 1.20
                    row.animDuration = 0.45
                    row.pendingAnimations = [scaleBackStep]
                } else if isMovingDown {
                    row.zOrder = 50
                } else {
                    row.zOrder = 0
                }

                newRows.append(row)
                let dy = abs(targetPosY - fromPosY)
                print("[RightPanel]   row[\(listIndex)] '\(item.data.songName)' qi=\(item.queueIndex) fromY=\(String(format:"%.4f",fromPosY)) toY=\(String(format:"%.4f",targetPosY)) dy=\(String(format:"%.4f",dy)) zOrder=\(row.zOrder) animating=true")
            } else {
                let texture = textures[item.queueIndex]
                let row = RightPanelRowState(
                    texture: texture,
                    data: item.data,
                    queueIndex: item.queueIndex,
                    currentPosX: offScreenRightPosX,
                    currentPosY: targetPosY,
                    currentOpacity: 0.0,
                    currentScale: 1.0,
                    targetPosX: normalPosX,
                    targetPosY: targetPosY,
                    targetOpacity: 1.0,
                    targetScale: 1.0,
                    startPosX: offScreenRightPosX,
                    startPosY: targetPosY,
                    startOpacity: 0.0,
                    startScale: 1.0,
                    isAnimating: true,
                    animStartTime: CACurrentMediaTime() + 0.225,
                    animDuration: 0.525,
                    shouldRemoveAfterAnimation: false,
                    pendingAnimations: []
                )
                newRows.append(row)
                print("[RightPanel]   row[\(listIndex)] '\(item.data.songName)' qi=\(item.queueIndex) NEW slideIn atY=\(String(format:"%.4f",targetPosY)) hasTexture=\(texture != nil)")
            }
        }
        rows = newRows
        os_unfair_lock_unlock(&stateLock)
    }

    func removeRow(queueIndex: Int) {
        os_unfair_lock_lock(&stateLock)
        interruptCurrentAnimations()
        lastOperationTime = CACurrentMediaTime()

        guard let removeIndex = rows.firstIndex(where: { $0.queueIndex == queueIndex }) else { os_unfair_lock_unlock(&stateLock); return }

        animateRowOutRight(index: removeIndex, duration: 0.6)

        for i in (removeIndex + 1)..<rows.count {
            let targetPosY = rowPosY(rowListIndex: i - 1, scrollOffset: scrollOffset)
            rows[i].queueIndex -= 1
            animateRowTo(index: i, posX: normalPosX, posY: targetPosY, opacity: 1.0, duration: 0.6, delay: 0)
        }
        os_unfair_lock_unlock(&stateLock)
    }

    func animateScrollTo(targetOffset: Float, duration: Float = 0.45, extraRows: Int = 0, isPreScroll: Bool = false, completion: (() -> Void)? = nil) {
        os_unfair_lock_lock(&stateLock)
        _stopIdleScrollLocked()
        lastOperationTime = CACurrentMediaTime()

        if let pending = pendingScrollOffset {
            scrollOffset = pending
            pendingScrollOffset = nil
            updateRowPositionsForScroll()
        }

        if isScrollAnimating {
            scrollOffset = targetScrollOffset
            isScrollAnimating = false
            isPreScrolling = false
            updateRowPositionsForScroll()
            scrollCompletion = nil
        }

        let maxOffset = Float(max(0, rows.count + extraRows - maxVisibleRows))
        let clampedTarget = max(0, min(targetOffset, maxOffset))

        if abs(scrollOffset - clampedTarget) < 0.01 {
            scrollOffset = clampedTarget
            updateRowPositionsForScroll()
            os_unfair_lock_unlock(&stateLock)
            completion?()
            return
        }

        startScrollOffset = scrollOffset
        targetScrollOffset = clampedTarget
        scrollAnimStartTime = CACurrentMediaTime()
        scrollAnimDuration = duration
        isScrollAnimating = true
        isPreScrolling = isPreScroll
        scrollCompletion = completion
        os_unfair_lock_unlock(&stateLock)
    }

    func cancelPreScroll() {
        os_unfair_lock_lock(&stateLock)
        guard isPreScrolling else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        scrollOffset = targetScrollOffset
        isScrollAnimating = false
        isPreScrolling = false
        updateRowPositionsForScroll()
        scrollCompletion = nil
        os_unfair_lock_unlock(&stateLock)
    }

    func startIdleScroll() {
        os_unfair_lock_lock(&stateLock)
        guard rows.count > maxVisibleRows else { os_unfair_lock_unlock(&stateLock); return }
        isIdleScrolling = true
        idleScrollPhase = .waiting
        lastOperationTime = CACurrentMediaTime()
        idleScrollLastTime = CACurrentMediaTime()
        os_unfair_lock_unlock(&stateLock)
    }

    func stopIdleScroll() {
        os_unfair_lock_lock(&stateLock)
        _stopIdleScrollLocked()
        os_unfair_lock_unlock(&stateLock)
    }

    private func _stopIdleScrollLocked() {
        isIdleScrolling = false
        idleScrollPhase = .waiting
        if globalOpacityAnimating {
            globalOpacity = 1.0
            targetGlobalOpacity = 1.0
            globalOpacityAnimating = false
        }
    }

    func clearAll() {
        os_unfair_lock_lock(&stateLock)
        rows.removeAll()
        scrollOffset = 0
        pendingScrollOffset = nil
        isScrollAnimating = false
        scrollCompletion = nil
        _stopIdleScrollLocked()
        os_unfair_lock_unlock(&stateLock)
    }

    func currentRowCount() -> Int {
        os_unfair_lock_lock(&stateLock)
        let count = rows.filter { $0.texture != nil }.count
        os_unfair_lock_unlock(&stateLock)
        return count
    }

    func getRowDataForId(_ id: UUID) -> SongCardData? {
        os_unfair_lock_lock(&stateLock)
        let result = rows.first(where: { $0.data?.id == id })?.data
        os_unfair_lock_unlock(&stateLock)
        return result
    }

    func listIndexForSong(id: UUID) -> Int? {
        os_unfair_lock_lock(&stateLock)
        let result = rows.firstIndex(where: { $0.data?.id == id })
        os_unfair_lock_unlock(&stateLock)
        return result
    }

    func isRowVisible(listIndex: Int) -> Bool {
        os_unfair_lock_lock(&stateLock)
        let result = listIndex >= Int(scrollOffset) && listIndex < Int(scrollOffset) + maxVisibleRows
        os_unfair_lock_unlock(&stateLock)
        return result
    }

    func scrollOffsetNeededForRow(listIndex: Int) -> Float {
        os_unfair_lock_lock(&stateLock)
        let current = scrollOffset
        os_unfair_lock_unlock(&stateLock)
        if listIndex < Int(current) {
            return Float(listIndex)
        } else if listIndex >= Int(current) + maxVisibleRows {
            return Float(listIndex - maxVisibleRows + 1)
        }
        return current
    }

    func updateRowTexture(queueIndex: Int, texture: MTLTexture) {
        os_unfair_lock_lock(&stateLock)
        if let index = rows.firstIndex(where: { $0.queueIndex == queueIndex }) {
            rows[index].texture = texture
        }
        os_unfair_lock_unlock(&stateLock)
    }

    func updateRowTexture(bySongId songId: UUID, texture: MTLTexture) {
        os_unfair_lock_lock(&stateLock)
        if let index = rows.firstIndex(where: { $0.data?.id == songId }) {
            rows[index].texture = texture
        }
        os_unfair_lock_unlock(&stateLock)
    }

    func updateAnimations() {
        let now = CACurrentMediaTime()
        var pendingCompletion: (() -> Void)?

        os_unfair_lock_lock(&stateLock)

        if isScrollAnimating {
            let elapsed = Float(now - scrollAnimStartTime)
            var progress = min(max(elapsed / scrollAnimDuration, 0), 1)
            let eased = easeOutCubic(progress)
            scrollOffset = startScrollOffset + (targetScrollOffset - startScrollOffset) * eased
            updateRowPositionsForScroll()

            if progress >= 1.0 {
                scrollOffset = targetScrollOffset
                isScrollAnimating = false
                isPreScrolling = false
                updateRowPositionsForScroll()
                pendingCompletion = scrollCompletion
                scrollCompletion = nil
            }
        }

        if isIdleScrolling && !isScrollAnimating {
            handleIdleScroll(now: now)
        }

        if !isIdleScrolling && !isScrollAnimating && rows.count > maxVisibleRows && pendingScrollOffset == nil {
            let timeSinceOp = Float(now - lastOperationTime)
            if timeSinceOp >= idleScrollPauseDuration {
                isIdleScrolling = true
                idleScrollPhase = .scrolling
                idleScrollLastTime = now
            }
        }

        if globalOpacityAnimating {
            let elapsed = Float(now - globalOpacityAnimStartTime)
            var progress = min(max(elapsed / globalOpacityAnimDuration, 0), 1)
            let eased = easeOutCubic(progress)
            globalOpacity = startGlobalOpacity + (targetGlobalOpacity - startGlobalOpacity) * eased

            if progress >= 1.0 {
                globalOpacity = targetGlobalOpacity
                globalOpacityAnimating = false
                handleGlobalOpacityComplete()
            }
        }

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
            rows[i].currentScale = rows[i].startScale + (rows[i].targetScale - rows[i].startScale) * eased

            if progress >= 1.0 {
                rows[i].currentPosX = rows[i].targetPosX
                rows[i].currentPosY = rows[i].targetPosY
                rows[i].currentOpacity = rows[i].targetOpacity
                rows[i].currentScale = rows[i].targetScale
                rows[i].isAnimating = false

                if rows[i].pendingAnimations.isEmpty {
                    rows[i].zOrder = 0
                }

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

        if pendingScrollOffset != nil && rows.allSatisfy({ !$0.isAnimating }) {
            scrollOffset = pendingScrollOffset!
            pendingScrollOffset = nil
            updateRowPositionsForScroll()
        }

        os_unfair_lock_unlock(&stateLock)

        pendingCompletion?()
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        guard enabled else { return }

        os_unfair_lock_lock(&stateLock)
        let localTitleTexture = titleTexture
        let localRows = rows
        let localGlobalOpacity = globalOpacity
        os_unfair_lock_unlock(&stateLock)

        encoder.setComputePipelineState(pipelineState)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)

        if let titleTex = localTitleTexture {
            var uniforms = SongCardUniforms()
            uniforms.posX = normalPosX
            uniforms.posY = titlePosY()
            uniforms.scale = rowScale
            uniforms.opacity = 1.0
            uniforms.cardWidth = Float(RightPanelTemplate.titleWidth)
            uniforms.cardHeight = Float(titleHeight)
            uniforms.outWidth = Float(outWidth)
            uniforms.outHeight = Float(outHeight)

            let cardPixelW = Float(outWidth) * rowScale
            let cardPixelH = cardPixelW * (Float(titleHeight) / Float(RightPanelTemplate.titleWidth))
            let centerX = uniforms.posX * Float(outWidth)
            let centerY = uniforms.posY * Float(outHeight)
            let originX = max(0, Int(centerX - cardPixelW / 2.0))
            let originY = max(0, Int(centerY - cardPixelH / 2.0))
            let gridW = min(outWidth, Int(centerX + cardPixelW / 2.0)) - originX
            let gridH = min(outHeight, Int(centerY + cardPixelH / 2.0)) - originY

            if gridW > 0 && gridH > 0 && uniformsBuffers.count > 0 {
                uniforms.originX = Float(originX)
                uniforms.originY = Float(originY)
                memcpy(uniformsBuffers[0].contents(), &uniforms, MemoryLayout<SongCardUniforms>.stride)
                encoder.setTexture(outputTexture, index: 0)
                encoder.setTexture(titleTex, index: 1)
                encoder.setBuffer(uniformsBuffers[0], offset: 0, index: 0)

                let gridSize = MTLSize(width: gridW, height: gridH, depth: 1)
                encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
            }
        }

        let visibleMinY: Float = Float(titleHeight) / Float(outHeight) - 0.1
        let visibleMaxY: Float = 1.1
        let rowHeightNorm = Float(rowHeight) / Float(outHeight)

        let sortedIndices = localRows.indices.sorted { localRows[$0].zOrder < localRows[$1].zOrder }

        for i in sortedIndices {
            let row = localRows[i]
            guard let texture = row.texture, row.currentOpacity > 0.01 else { continue }

            let rowTop = row.currentPosY - rowHeightNorm / 2.0
            let rowBottom = row.currentPosY + rowHeightNorm / 2.0
            if rowBottom < visibleMinY || rowTop > visibleMaxY { continue }

            let bufferIndex = (i % (uniformsBuffers.count - 1)) + 1

            let effectiveScale = rowScale * row.currentScale
            var uniforms = SongCardUniforms()
            uniforms.posX = row.currentPosX
            uniforms.posY = row.currentPosY
            uniforms.scale = effectiveScale
            uniforms.opacity = row.currentOpacity * localGlobalOpacity
            uniforms.cardWidth = Float(RightPanelTemplate.rowWidth)
            uniforms.cardHeight = Float(rowHeight)
            uniforms.outWidth = Float(outWidth)
            uniforms.outHeight = Float(outHeight)

            let cardPixelW = Float(outWidth) * effectiveScale
            let cardPixelH = cardPixelW * (Float(rowHeight) / Float(RightPanelTemplate.rowWidth))
            let centerX = uniforms.posX * Float(outWidth)
            let centerY = uniforms.posY * Float(outHeight)
            let originX = max(0, Int(centerX - cardPixelW / 2.0))
            let originY = max(0, Int(centerY - cardPixelH / 2.0))
            let gridW = min(outWidth, Int(centerX + cardPixelW / 2.0)) - originX
            let gridH = min(outHeight, Int(centerY + cardPixelH / 2.0)) - originY

            if gridW > 0 && gridH > 0 {
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
    }

    private func easeOutCubic(_ t: Float) -> Float {
        return 1 - pow(1 - t, 3)
    }

    private func startAnimation(index: Int, step: RightPanelAnimationStep) {
        rows[index].startPosX = rows[index].currentPosX
        rows[index].startPosY = rows[index].currentPosY
        rows[index].startOpacity = rows[index].currentOpacity
        rows[index].startScale = rows[index].currentScale
        rows[index].targetPosX = step.targetPosX
        rows[index].targetPosY = step.targetPosY
        rows[index].targetOpacity = step.targetOpacity
        rows[index].targetScale = step.targetScale
        rows[index].animDuration = step.duration
        rows[index].animStartTime = CACurrentMediaTime() + CFTimeInterval(step.delay)
        rows[index].isAnimating = true
    }

    private func animateRowTo(index: Int, posX: Float, posY: Float, opacity: Float, duration: Float, delay: Float) {
        guard index < rows.count else { return }
        if delay > 0 {
            let step = RightPanelAnimationStep(targetPosX: posX, targetPosY: posY, targetOpacity: opacity, targetScale: 1.0, duration: duration, delay: delay)
            if rows[index].isAnimating {
                rows[index].pendingAnimations.append(step)
            } else {
                startAnimation(index: index, step: step)
            }
        } else {
            rows[index].startPosX = rows[index].currentPosX
            rows[index].startPosY = rows[index].currentPosY
            rows[index].startOpacity = rows[index].currentOpacity
            rows[index].startScale = rows[index].currentScale
            rows[index].targetPosX = posX
            rows[index].targetPosY = posY
            rows[index].targetOpacity = opacity
            rows[index].targetScale = 1.0
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

    private func interruptCurrentAnimations(preservePosition: Bool = false) {
        if let pending = pendingScrollOffset {
            scrollOffset = pending
            pendingScrollOffset = nil
            updateRowPositionsForScroll()
        }

        if isScrollAnimating {
            if preservePosition {
                let elapsed = Float(CACurrentMediaTime() - scrollAnimStartTime)
                var progress = min(max(elapsed / scrollAnimDuration, 0), 1)
                let eased = easeOutCubic(progress)
                scrollOffset = startScrollOffset + (targetScrollOffset - startScrollOffset) * eased
            } else {
                scrollOffset = targetScrollOffset
            }
            isScrollAnimating = false
            scrollCompletion = nil
            updateRowPositionsForScroll()
        }

        _stopIdleScrollLocked()

        for i in rows.indices {
            if rows[i].isAnimating {
                if preservePosition {
                    let elapsed = Float(CACurrentMediaTime() - rows[i].animStartTime)
                    if elapsed >= 0 {
                        var progress = min(max(elapsed / rows[i].animDuration, 0), 1)
                        let eased = easeOutCubic(progress)
                        rows[i].currentPosX = rows[i].startPosX + (rows[i].targetPosX - rows[i].startPosX) * eased
                        rows[i].currentPosY = rows[i].startPosY + (rows[i].targetPosY - rows[i].startPosY) * eased
                        rows[i].currentOpacity = rows[i].startOpacity + (rows[i].targetOpacity - rows[i].startOpacity) * eased
                        rows[i].currentScale = rows[i].startScale + (rows[i].targetScale - rows[i].startScale) * eased
                    }
                } else {
                    rows[i].currentPosX = rows[i].targetPosX
                    rows[i].currentPosY = rows[i].targetPosY
                    rows[i].currentOpacity = rows[i].targetOpacity
                    rows[i].currentScale = rows[i].targetScale
                }
                rows[i].isAnimating = false
                rows[i].pendingAnimations.removeAll()
                rows[i].zOrder = 0

                if rows[i].shouldRemoveAfterAnimation {
                    rows[i].texture = nil
                    rows[i].shouldRemoveAfterAnimation = false
                }
            }
        }
        rows.removeAll { $0.texture == nil && !$0.isAnimating }
    }

    private func updateRowPositionsForScroll() {
        for i in rows.indices {
            guard !rows[i].isAnimating else { continue }
            let targetY = rowPosY(rowListIndex: i, scrollOffset: scrollOffset)
            rows[i].currentPosY = targetY
            rows[i].targetPosY = targetY
            rows[i].startPosY = targetY
            rows[i].currentPosX = normalPosX
            rows[i].targetPosX = normalPosX
            rows[i].startPosX = normalPosX
            rows[i].currentOpacity = 1.0
            rows[i].targetOpacity = 1.0
            rows[i].startOpacity = 1.0
            rows[i].currentScale = 1.0
            rows[i].targetScale = 1.0
            rows[i].startScale = 1.0
            rows[i].zOrder = 0
        }
    }

    private func handleIdleScroll(now: CFTimeInterval) {
        switch idleScrollPhase {
        case .waiting:
            let timeSinceOp = Float(now - lastOperationTime)
            if timeSinceOp >= idleScrollPauseDuration {
                idleScrollPhase = .scrolling
                idleScrollLastTime = now
            }

        case .scrolling:
            let dt = Float(now - idleScrollLastTime)
            idleScrollLastTime = now
            scrollOffset += idleScrollSpeed * dt

            let maxOffset = Float(max(0, rows.count - maxVisibleRows))
            if scrollOffset >= maxOffset {
                scrollOffset = maxOffset
                updateRowPositionsForScroll()
                idleScrollPhase = .fadingOut
                startGlobalOpacityAnimation(target: 0.0, duration: globalOpacityAnimDuration)
            } else {
                updateRowPositionsForScroll()
            }

        case .fadingOut:
            break

        case .fadingIn:
            break
        }
    }

    private func startGlobalOpacityAnimation(target: Float, duration: Float) {
        startGlobalOpacity = globalOpacity
        targetGlobalOpacity = target
        globalOpacityAnimStartTime = CACurrentMediaTime()
        globalOpacityAnimDuration = duration
        globalOpacityAnimating = true
    }

    private func handleGlobalOpacityComplete() {
        if idleScrollPhase == .fadingOut && globalOpacity <= 0.01 {
            scrollOffset = 0
            updateRowPositionsForScroll()
            idleScrollPhase = .fadingIn
            startGlobalOpacityAnimation(target: 1.0, duration: globalOpacityAnimDuration)
        } else if idleScrollPhase == .fadingIn && globalOpacity >= 0.99 {
            idleScrollPhase = .scrolling
            idleScrollLastTime = CACurrentMediaTime()
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
