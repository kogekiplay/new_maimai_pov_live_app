import SwiftUI
import Combine
import AVFoundation
import CoreMedia
import Metal
import simd
import QuartzCore
import UIKit
import CoreImage

class LivePipelineManager: ObservableObject, SongCardDataProvider {
    @Published var focusValue: Double = Config.focusValue
    @Published var autoFocusEnabled: Bool = Config.autoFocusEnabled
    @Published var shutterTimescale: Double = Config.shutterTimescale
    @Published var isoValue: Double = Config.isoValue
    @Published var minISO: Double = 50.0
    @Published var maxISO: Double = 3200.0
    @Published var selectedLens: LensType = Config.selectedLens

    @Published var syncOffsetMs: Double = Config.syncOffsetMs
    @Published var readoutTimeMs: Double = Config.readoutTimeMs

    @Published var fov: Float = Config.fov
    @Published var distRatio: Float = Config.distRatio
    @Published var yaw: Float = Config.yaw
    @Published var pitch: Float = Config.pitch
    @Published var roll: Float = Config.roll
    @Published var stabEnabled: Bool = Config.stabEnabled
    @Published var lagMs: Double = 0

    @Published var yoloEnabled: Bool = Config.yoloEnabled
    @Published var previewEnabled: Bool = Config.previewEnabled
    @Published var yoloPadding: Double = Double(Config.yoloPadding)
    @Published var yoloPreviewEnabled: Bool = Config.yoloPreviewEnabled
    @Published var yoloOverlayEnabled: Bool = Config.yoloOverlayEnabled
    @Published var yoloTargetFPS: Double = Config.yoloTargetFPS

    @Published var trackTargetRatio: Double = Config.trackTargetRatio
    @Published var trackRecenterSpeed: Double = Config.trackRecenterSpeed
    @Published var recenterGraceMs: Double = Config.recenterGraceMs
    @Published var acquireSpeed: Double = Config.acquireSpeed

    @Published var smoothingEnabled: Bool = Config.smoothingEnabled
    @Published var smoothingBaseAlpha: Double = Config.smoothingBaseAlpha
    @Published var smoothingMinDeviation: Double = Config.smoothingMinDeviation
    @Published var smoothingMaxDeviation: Double = Config.smoothingMaxDeviation
    @Published var smoothingCenterFloor: Double = Config.smoothingCenterFloor

    @Published var currentFPS: Double = 0

    @Published var overlayEnabled: Bool = Config.overlayEnabled
    @Published var overlayPosX: Float = Config.overlayPosX
    @Published var overlayPosY: Float = Config.overlayPosY
    @Published var overlayScale: Float = Config.overlayScale
    @Published var overlayOpacity: Float = Config.overlayOpacity
    @Published var overlayRotation: Float = Config.overlayRotation

    @Published var songCardEnabled: Bool = Config.songCardEnabled
    @Published var songRequestTestMode: Bool = false
    @Published var songRequestTestPriorityMode: Bool = false

    @Published var slot0PosX: Float = 0.20
    @Published var slot0PosY: Float = 0.13
    @Published var slot0Scale: Float = 0.25
    @Published var slot1PosX: Float = 0.51
    @Published var slot1PosY: Float = 0.135
    @Published var slot1Scale: Float = 0.23
    @Published var slot2PosX: Float = 0.81
    @Published var slot2PosY: Float = 0.135
    @Published var slot2Scale: Float = 0.23

    @Published var cropHorizontalOffset: Float = Config.cropHorizontalOffset

    @Published var blivechatConnectionState: ConnectionState = .disconnected
    @Published var blivechatServer: BlivechatServer = BlivechatServer(rawValue: Config.blivechatServer) ?? .cn
    @Published var blivechatIdentityCode: String = Config.blivechatIdentityCode
    @Published var latestDanmaku: String = ""
    @Published var danmakuCount: Int = 0
    @Published var webServerURL: String = ""

    let camera = CameraCaptureManager()
    let debug = DebugInfoManager.shared
    let device: MTLDevice = MTLCreateSystemDefaultDevice()!
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    let sharedCommandQueue: MTLCommandQueue
    let streamManager = RTMPStreamManager()

    var stabilizer: MetalStabilizer?
    var yoloDetector: YOLODetector?
    var cropRenderer: CropRenderer?
    var overlayCompositor: OverlayCompositor?
    var songCardCompositor: SongCardCompositor?
    var canvasComposer: CanvasComposer?
    let songCardManager = SongCardManager()
    let blivechatClient = BlivechatClient()
    let giftPermissionManager = GiftPermissionManager()
    let songDatabase = SongDatabase()
    let danmakuParser = DanmakuParser()
    let webServerManager = WebServerManager()
    var bboxTracker = BBoxTracker()
    var latestTrackOutput: BBoxTracker.TrackOutput?

    var onStreamBufferAvailable: ((CVPixelBuffer, CMTime) -> Void)?
    var onAudioSampleAvailable: ((CMSampleBuffer, Double) -> Void)?

    var previewTexture: MTLTexture? {
        if previewEnabled {
            if let pool = ioSurfacePool, let buf = pool.lastCompletedBuffer {
                return buf.texture
            }
            if let cc = canvasComposer {
                return nil
            }
            if let cr = cropRenderer {
                return cr.outputTexture
            }
            return stabilizer?.outputTexture
        }
        return nil
    }
    
    var stabTexture: MTLTexture? {
        stabilizer?.outputTexture
    }

    var isCropActive: Bool { canvasComposer != nil || cropRenderer != nil }

    let pipelineQueue = DispatchQueue(label: "com.maimai.pipeline", qos: .userInteractive)

    private var ioSurfacePool: IOSurfaceOutputPool?
    private var frameCount: Int = 0
    private var streamFrameCount: Int = 0
    private var fpsTimer: Timer?
    private var temperatureTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var yoloPreviewFrameCount: Int = 0
    private var lastStabOnlyMs: Double = 0

    init() {
        sharedCommandQueue = device.makeCommandQueue()!

        camera.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        streamManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        streamManager.$isStreaming.sink { [weak self] streaming in
            DispatchQueue.main.async {
                self?.debug.isStreaming = streaming
            }
        }.store(in: &cancellables)

        setupBlivechatCallbacks()
        webServerManager.pipeline = self
    }

    private func setupBlivechatCallbacks() {
        blivechatClient.onDanmaku = { [weak self] msg in
            guard let self = self else { return }
            self.latestDanmaku = "\(msg.authorName): \(msg.content)"
            self.danmakuCount += 1
            DispatchQueue.main.async {
                self.debug.log("[弹幕] \(msg.authorName): \(msg.content)")
            }
            self.handleDanmakuForSongRequest(msg)
        }

        blivechatClient.onGift = { [weak self] msg in
            guard let self = self else { return }
            self.giftPermissionManager.handleGift(msg)
            let coinType = msg.isPaidGift ? "付费" : "免费"
            DispatchQueue.main.async {
                self.debug.log("[礼物] \(msg.authorName) 送 \(msg.giftName) x\(msg.num) (\(coinType))")
            }
            if msg.isPaidGift {
                let name = msg.authorName
                self.songCardManager.userGiftPool[name, default: 0] += msg.totalCoin
                if let index = self.songCardManager.findSongIndex(byName: name) {
                    self.songCardManager.updateGiftValue(name: name, delta: msg.totalCoin)
                    let lockedEnd = self.songCardManager.lockedEndIndex
                    DispatchQueue.main.async {
                        if index >= lockedEnd {
                            self.songCardManager.reorderQueueByGiftValue()
                            self.refreshDisplayedCardsIfNeeded()
                        }
                        self.debug.log("[礼物追踪] \(name) 累积 \(self.songCardManager.userGiftPool[name] ?? 0) 金瓜子")
                    }
                }
            }
        }

        blivechatClient.onSuperChat = { [weak self] msg in
            guard let self = self else { return }
            self.giftPermissionManager.handleSuperChat(msg)
            let name = msg.authorName
            let coinValue = msg.price * 1000
            self.songCardManager.userGiftPool[name, default: 0] += coinValue
            if let index = self.songCardManager.findSongIndex(byName: name) {
                self.songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = self.songCardManager.lockedEndIndex
                DispatchQueue.main.async {
                    if index >= lockedEnd {
                        self.songCardManager.reorderQueueByGiftValue()
                        self.refreshDisplayedCardsIfNeeded()
                    }
                }
            }
            DispatchQueue.main.async {
                self.debug.log("[SC] \(msg.authorName): ¥\(msg.price) \(msg.content)")
            }
            self.handleSuperChatForSongRequest(msg)
        }

        blivechatClient.onMember = { [weak self] msg in
            guard let self = self else { return }
            self.giftPermissionManager.handleMember(msg)
            let name = msg.authorName
            let coinValue = 198 * 1000
            self.songCardManager.userGiftPool[name, default: 0] += coinValue
            if let index = self.songCardManager.findSongIndex(byName: name) {
                self.songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = self.songCardManager.lockedEndIndex
                DispatchQueue.main.async {
                    if index >= lockedEnd {
                        self.songCardManager.reorderQueueByGiftValue()
                        self.refreshDisplayedCardsIfNeeded()
                    }
                }
            }
            DispatchQueue.main.async {
                self.debug.log("[上舰] \(msg.authorName)")
            }
        }

        blivechatClient.onError = { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.debug.log("[blivechat错误] code=\(error.code) \(error.message)")
            }
        }
    }

    func handleDanmakuForSongRequest(_ msg: DanmakuMessage) {
        let result = danmakuParser.parse(msg.content)

        switch result.type {
        case .songRequest(let query, let diffInput, let chartTypePreference):
            let name = msg.authorName

            DispatchQueue.main.async {
                self.debug.log("[点歌] 解析: query=\"\(query)\" diff=\(diffInput ?? "nil") chart=\(chartTypePreference ?? "nil") db=\(self.songDatabase.songCount)")
            }

            guard songRequestTestMode || !songCardManager.hasSongInQueue(name: name) else {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] \(msg.authorName) 已有歌曲在队列中")
                }
                return
            }

            let candidates = songDatabase.findCandidates(query: query)
            if candidates.candidates.isEmpty {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] 未找到歌曲: \"\(query)\"")
                }
                return
            }

            guard let song = songDatabase.pickByChartType(
                candidates: candidates.candidates,
                chartTypePreference: chartTypePreference,
                diffInput: diffInput
            ) else {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] 候选\(candidates.candidates.count)首但无法选择")
                }
                return
            }

            let targetDiffNum = songDatabase.resolveDiffInput(diffInput)
            guard let noteResult = songDatabase.findNote(song: song, targetDiffNum: targetDiffNum) else {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] \(song.title) 没有可用难度")
                }
                return
            }

            let diffName = songDatabase.difficultyDisplayName(noteResult.diffName)
            let ctDisplay = songDatabase.chartTypeDisplayName(song.chartType)
            let levelStr = noteResult.levelValue.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(noteResult.levelValue))"
                : "\(noteResult.levelValue)"

            let giftVal = songCardManager.userGiftPool[name] ?? 0

            let cardData = SongCardData(
                songName: song.title,
                artist: song.artist ?? "",
                difficulty: diffName,
                level: levelStr,
                coverURL: nil,
                requester: msg.authorName,
                requesterName: name,
                musicId: song.id,
                chartType: song.chartType,
                isPriority: false,
                bpm: song.bpm,
                giftValue: giftVal
            )

            DispatchQueue.main.async {
                self.addSongToQueue(cardData)
                if giftVal > 0 {
                    self.songCardManager.reorderQueueByGiftValue()
                    self.refreshDisplayedCardsIfNeeded()
                }
                let giftTag = giftVal > 0 ? " [🎁\(giftVal)]" : ""
                self.debug.log("[点歌] ✅ \(msg.authorName) → \(song.title) (\(ctDisplay) \(diffName) \(levelStr)) [\(candidates.matchKind?.rawValue ?? "?")]\(giftTag)")
            }

        case .notACommand:
            break
        }
    }

    func handleSuperChatForSongRequest(_ sc: SuperChatMessage) {
        let result = danmakuParser.parse(sc.content)

        switch result.type {
        case .songRequest(let query, let diffInput, let chartTypePreference):
            let name = sc.authorName

            DispatchQueue.main.async {
                self.debug.log("[SC点歌] 解析: query=\"\(query)\" diff=\(diffInput ?? "nil") chart=\(chartTypePreference ?? "nil") price=\(sc.price)")
            }

            if songCardManager.hasSongInQueue(name: name) {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] \(sc.authorName) 已有歌曲在队列中，SC金额累积到送礼池")
                }
                return
            }

            let candidates = songDatabase.findCandidates(query: query)
            if candidates.candidates.isEmpty {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] 未找到歌曲: \"\(query)\"，SC金额累积到送礼池")
                }
                return
            }

            guard let song = songDatabase.pickByChartType(
                candidates: candidates.candidates,
                chartTypePreference: chartTypePreference,
                diffInput: diffInput
            ) else {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] 候选\(candidates.candidates.count)首但无法选择，SC金额累积到送礼池")
                }
                return
            }

            let targetDiffNum = songDatabase.resolveDiffInput(diffInput)
            guard let noteResult = songDatabase.findNote(song: song, targetDiffNum: targetDiffNum) else {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] \(song.title) 没有可用难度，SC金额累积到送礼池")
                }
                return
            }

            songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
            let giftVal = songCardManager.userGiftPool[name] ?? 0

            let diffName = songDatabase.difficultyDisplayName(noteResult.diffName)
            let ctDisplay = songDatabase.chartTypeDisplayName(song.chartType)
            let levelStr = noteResult.levelValue.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(noteResult.levelValue))"
                : "\(noteResult.levelValue)"

            let cardData = SongCardData(
                songName: song.title,
                artist: song.artist ?? "",
                difficulty: diffName,
                level: levelStr,
                coverURL: nil,
                requester: sc.authorName,
                requesterName: name,
                musicId: song.id,
                chartType: song.chartType,
                isPriority: false,
                bpm: song.bpm,
                giftValue: giftVal
            )

            DispatchQueue.main.async {
                self.addSongToQueue(cardData)
                if giftVal > 0 {
                    self.songCardManager.reorderQueueByGiftValue()
                    self.refreshDisplayedCardsIfNeeded()
                }
                self.debug.log("[SC点歌] ✅ \(sc.authorName) → \(song.title) (\(ctDisplay) \(diffName) \(levelStr)) [🎁\(giftVal)]")
            }

        case .notACommand:
            break
        }
    }

    @MainActor func connectBlivechat() {
        Config.blivechatServer = blivechatServer.rawValue
        Config.blivechatIdentityCode = blivechatIdentityCode

        if songDatabase.songCount == 0 {
            songDatabase.loadFromBundle()
            if songDatabase.songCount == 0 {
                debug.log("[曲库] ❌ 加载失败: \(songDatabase.lastError ?? "unknown")")
            } else {
                debug.log("[曲库] 加载完成: \(songDatabase.songCount) 首歌曲")
            }
        } else {
            debug.log("[曲库] 已加载: \(songDatabase.songCount) 首歌曲")
        }

        blivechatClient.connect(
            server: blivechatServer,
            roomKeyType: .authCode,
            roomKeyValue: blivechatIdentityCode
        )

        webServerManager.start()

        observeBlivechatState()
    }

    @MainActor func disconnectBlivechat() {
        blivechatClient.disconnect()
        blivechatConnectionState = .disconnected
        webServerManager.stop()
    }

    private func observeBlivechatState() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let state = self.blivechatClient.connectionState
            if state != self.blivechatConnectionState {
                self.blivechatConnectionState = state
            }
            if case .disconnected = state {
                timer.invalidate()
            }
        }
    }

    @MainActor func start() {
        let lensCfg = LensCalibration.config(for: selectedLens, inputWidth: Config.inputWidth)
        let stab = MetalStabilizer(device: device, commandQueue: sharedCommandQueue, lensConfig: lensCfg)
        stab?.stabilizerEnabled = stabEnabled
        stab?.fov = fov
        stab?.distRatio = distRatio
        stab?.yawDeg = yaw
        stab?.pitchDeg = pitch
        stab?.rollDeg = roll
        stab?.useRollingShutter = readoutTimeMs > 0
        self.stabilizer = stab

        debug.fov = fov
        debug.distRatio = distRatio
        debug.stabEnabled = stabEnabled
        debug.lensType = selectedLens.rawValue
        debug.log("Pipeline initialized: \(selectedLens.rawValue)")

        let cropR = CropRenderer(device: device, commandQueue: sharedCommandQueue)
        self.cropRenderer = cropR

        self.canvasComposer = CanvasComposer(device: device, commandQueue: sharedCommandQueue)

        self.overlayCompositor = OverlayCompositor(device: device)
        self.overlayCompositor?.enabled = overlayEnabled
        self.overlayCompositor?.posX = overlayPosX
        self.overlayCompositor?.posY = overlayPosY
        self.overlayCompositor?.scale = overlayScale
        self.overlayCompositor?.opacity = overlayOpacity
        self.overlayCompositor?.rotation = overlayRotation * .pi / 180.0

        self.songCardCompositor = SongCardCompositor(device: device)
        self.songCardCompositor?.enabled = songCardEnabled
        songCardManager.delegate = self

        ioSurfacePool = IOSurfaceOutputPool(
            device: device,
            width: Config.outputWidth,
            height: Config.outputHeight
        )

        bboxTracker.targetRatio = Float(trackTargetRatio)
        bboxTracker.recenterSpeed = Float(trackRecenterSpeed)
        bboxTracker.recenterGraceMs = Float(recenterGraceMs)
        bboxTracker.acquireSpeed = Float(acquireSpeed)
        bboxTracker.smoothingEnabled = smoothingEnabled
        bboxTracker.smoothingBaseAlpha = Float(smoothingBaseAlpha)
        bboxTracker.smoothingMinDeviation = Float(smoothingMinDeviation)
        bboxTracker.smoothingMaxDeviation = Float(smoothingMaxDeviation)
        bboxTracker.smoothingCenterFloor = Float(smoothingCenterFloor)
        debug.trackTargetRatio = Float(trackTargetRatio)
        debug.trackRecenterSpeed = Float(trackRecenterSpeed)

        let detector = YOLODetector(device: device, commandQueue: sharedCommandQueue)
        self.yoloDetector = detector
        detector?.targetFPS = yoloTargetFPS
        if detector != nil {
            debug.log("YOLO detector initialized (sync mode)")
        }

        let u = YOLOPreprocessUniforms(padding: Config.yoloPadding)
        debug.yoloUniforms = String(format: "s%.3f pH%.0f pV%.0f pL%.0f pT%.0f",
            u.scale, u.padH, u.padV, u.padLeft, u.padTop)
        debug.yoloOverlayEnabled = Config.yoloOverlayEnabled
        debug.yoloOverlayScale = Config.yoloOverlayScale

        camera.checkPermissionAndStart()
        camera.switchLens(to: selectedLens)
        camera.onDeviceReady = { [weak self] in
            guard let self else { return }
            self.camera.setFocus(Float(self.focusValue))
            self.applyExposure()
        }
        MotionManager.shared.startUpdates()

        camera.onVideoFrame = { [weak self] pixelBuffer, alignedTime in
            let pipelineEnterTime = CACurrentMediaTime()
            self?.pipelineQueue.async {
                guard let self = self else { return }
                self.frameCount += 1
                guard let stab = self.stabilizer, stab.stabilizerEnabled else { return }

                let centerTime = alignedTime + (Config.syncOffsetMs / 1000.0)
                let topTime    = centerTime - (Config.readoutTimeMs / 2000.0)
                let bottomTime = centerTime + (Config.readoutTimeMs / 2000.0)

                guard let qCenter = MotionManager.shared.getQuaternion(at: centerTime),
                      let qTop    = MotionManager.shared.getQuaternion(at: topTime),
                      let qBottom = MotionManager.shared.getQuaternion(at: bottomTime) else { return }

                var detectionResult: YOLODetector.DetectionResult?

                if self.yoloEnabled, let detector = self.yoloDetector {
                    let shouldRunYOLO = detector.advanceSkipCounter()

                    if shouldRunYOLO {
                        let combinedStart = CACurrentMediaTime()

                        guard let cmdBuf = self.sharedCommandQueue.makeCommandBuffer(),
                              let encoder = cmdBuf.makeComputeCommandEncoder() else {
                            stab.process(pixelBuffer: pixelBuffer, qCenter: qCenter, qTop: qTop, qBottom: qBottom)
                            stab.waitForCompletion()
                            return
                        }

                        stab.encode(into: encoder, pixelBuffer: pixelBuffer, qCenter: qCenter, qTop: qTop, qBottom: qBottom)

                        if let yoloPixelBuffer = detector.preprocessor.encode(into: encoder, stabOutputTexture: stab.outputTexture) {
                            encoder.endEncoding()

                            let sem = DispatchSemaphore(value: 0)
                            cmdBuf.addCompletedHandler { _ in
                                sem.signal()
                            }
                            cmdBuf.commit()
                            sem.wait()

                            let combinedMs = (CACurrentMediaTime() - combinedStart) * 1000.0
                            let yoloPrepMs = max(combinedMs - self.lastStabOnlyMs, 0)
                            detectionResult = detector.detectWithPreprocessedPixelBuffer(yoloPixelBuffer, preprocessMs: yoloPrepMs)
                        } else {
                            encoder.endEncoding()

                            let sem = DispatchSemaphore(value: 0)
                            cmdBuf.addCompletedHandler { _ in
                                sem.signal()
                            }
                            cmdBuf.commit()
                            sem.wait()
                        }
                    } else {
                        let stabStart = CACurrentMediaTime()
                        stab.process(pixelBuffer: pixelBuffer, qCenter: qCenter, qTop: qTop, qBottom: qBottom)
                        stab.waitForCompletion()
                        self.lastStabOnlyMs = (CACurrentMediaTime() - stabStart) * 1000.0
                    }
                } else {
                    stab.process(pixelBuffer: pixelBuffer, qCenter: qCenter, qTop: qTop, qBottom: qBottom)
                    stab.waitForCompletion()
                }

                var yoloPreviewImage: UIImage?
                let track: BBoxTracker.TrackOutput
                if let result = detectionResult {
                    track = self.bboxTracker.update(
                        detected: result.detected,
                        stabCx: result.stabCx,
                        stabCy: result.stabCy,
                        stabW: result.stabW,
                        stabH: result.stabH
                    )
                    self.latestTrackOutput = track

                    if self.yoloPreviewEnabled {
                        self.yoloPreviewFrameCount += 1
                        if self.yoloPreviewFrameCount % 30 == 0,
                           let pb = self.yoloDetector?.previewPixelBuffer {
                            let ciImage = CIImage(cvPixelBuffer: pb)
                            if let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                                yoloPreviewImage = UIImage(cgImage: cgImage)
                            }
                        }
                    }
                } else if self.latestTrackOutput != nil {
                    track = self.bboxTracker.freeze()
                } else if let cc = self.canvasComposer {
                    let fb = cc.makeFallbackTrack()
                    track = BBoxTracker.TrackOutput(
                        cx: fb.cx, cy: fb.cy, cropW: fb.cropW, cropH: fb.cropH,
                        detected: false, state: "fallback"
                    )
                } else if let cr = self.cropRenderer {
                    let fb = cr.makeFallbackTrack()
                    track = BBoxTracker.TrackOutput(
                        cx: fb.cx, cy: fb.cy, cropW: fb.cropW, cropH: fb.cropH,
                        detected: false, state: "fallback"
                    )
                } else {
                    let stabW = Float(Config.stabWidth)
                    let stabH = Float(Config.stabHeight)
                    let cropRatio = Config.gameAreaRatio
                    let fallbackCropW = min(stabW, stabH * cropRatio)
                    let fallbackCropH = fallbackCropW / cropRatio
                    track = BBoxTracker.TrackOutput(
                        cx: stabW / 2.0, cy: stabH / 2.0,
                        cropW: fallbackCropW, cropH: fallbackCropH,
                        detected: false, state: "nofallback"
                    )
                }

                let resultCopy = detectionResult
                let previewEnabled = self.yoloPreviewEnabled
                DispatchQueue.main.async {
                    var snapshot = DebugInfoManager.FrameDebugData()
                    if let result = resultCopy {
                        snapshot.hasYoloResult = true
                        snapshot.yoloDetected = result.detected
                        snapshot.yoloConfidence = result.confidence
                        snapshot.yoloInferenceMs = result.inferenceMs
                        snapshot.yoloPreprocessMs = result.preprocessMs
                        snapshot.rawYoloCx = result.rawYoloCx
                        snapshot.rawYoloCy = result.rawYoloCy
                        snapshot.rawYoloW = result.rawYoloW
                        snapshot.rawYoloH = result.rawYoloH
                        snapshot.stabCx = result.stabCx
                        snapshot.stabCy = result.stabCy
                        snapshot.stabW = result.stabW
                        snapshot.stabH = result.stabH
                        snapshot.innerScreenBoxesCount = result.innerScreenBoxesCount
                        snapshot.allBoxesCount = result.allBoxesCount
                        snapshot.topBoxes = result.topBoxes
                        snapshot.bestBoxRank = result.bestBoxRank
                        snapshot.yoloPreviewImage = previewEnabled ? yoloPreviewImage : nil
                    }
                    snapshot.trackCx = track.cx
                    snapshot.trackCy = track.cy
                    snapshot.trackCropW = track.cropW
                    snapshot.trackCropH = track.cropH
                    snapshot.trackState = track.state
                    snapshot.trackRawW = track.rawW
                    snapshot.trackRawH = track.rawH
                    snapshot.trackSmoothSize = track.smoothSize
                    snapshot.trackTrust = track.trust
                    snapshot.trackAspectRatio = track.aspectRatio
                    self.debug.stageFrameData(snapshot)
                }

                let offsetCx = track.cx + self.cropHorizontalOffset

                if let pool = self.ioSurfacePool,
                   let cc = self.canvasComposer,
                   let writeBuffer = pool.nextWriteBuffer() {
                    let timestamp = CMTime(seconds: alignedTime, preferredTimescale: 1000000000)

                    guard let cmdBuf = self.sharedCommandQueue.makeCommandBuffer(),
                          let encoder = cmdBuf.makeComputeCommandEncoder() else {
                        return
                    }

                    cc.encode(into: encoder,
                              stabTexture: stab.outputTexture,
                              cx: offsetCx, cy: track.cy,
                              cropW: track.cropW, cropH: track.cropH,
                              outputTexture: writeBuffer.texture)

                    encoder.endEncoding()

                    cmdBuf.addCompletedHandler { [weak self] _ in
                        self?.pipelineQueue.async {
                            guard let self = self else { return }
                            self.streamFrameCount += 1
                            let pipelineLatencyMs = (CACurrentMediaTime() - pipelineEnterTime) * 1000.0
                            self.onStreamBufferAvailable?(writeBuffer.pixelBuffer, timestamp)
                            self.streamManager.appendVideo(pixelBuffer: writeBuffer.pixelBuffer, timestamp: timestamp)
                            DispatchQueue.main.async {
                                self.lagMs = pipelineLatencyMs
                                self.debug.stageLagData(ms: pipelineLatencyMs, audioDepth: self.streamManager.audioSyncQueueDepth)
                            }
                        }
                    }
                    cmdBuf.commit()
                } else if let pool = self.ioSurfacePool,
                          let cr = self.cropRenderer,
                          let writeBuffer = pool.nextWriteBuffer() {
                    let timestamp = CMTime(seconds: alignedTime, preferredTimescale: 1000000000)

                    guard let cmdBuf = self.sharedCommandQueue.makeCommandBuffer(),
                          let encoder = cmdBuf.makeComputeCommandEncoder() else {
                        cr.process(
                            stabTexture: stab.outputTexture,
                            cx: offsetCx, cy: track.cy,
                            cropW: track.cropW, cropH: track.cropH,
                            outputTexture: writeBuffer.texture
                        ) { [weak self] in
                            self?.pipelineQueue.async {
                                guard let self = self else { return }
                                self.streamFrameCount += 1
                                let pipelineLatencyMs = (CACurrentMediaTime() - pipelineEnterTime) * 1000.0
                                self.onStreamBufferAvailable?(writeBuffer.pixelBuffer, timestamp)
                                self.streamManager.appendVideo(pixelBuffer: writeBuffer.pixelBuffer, timestamp: timestamp)
                                DispatchQueue.main.async {
                                    self.lagMs = pipelineLatencyMs
                                    self.debug.stageLagData(ms: pipelineLatencyMs, audioDepth: self.streamManager.audioSyncQueueDepth)
                                }
                            }
                        }
                        return
                    }

                    cr.encode(into: encoder,
                              stabTexture: stab.outputTexture,
                              cx: offsetCx, cy: track.cy,
                              cropW: track.cropW, cropH: track.cropH,
                              outputTexture: writeBuffer.texture)

                    if let overlay = self.overlayCompositor,
                       overlay.enabled, overlay.overlayTexture != nil {
                        overlay.encode(into: encoder, outputTexture: writeBuffer.texture)
                    }

                    if let songCard = self.songCardCompositor, songCard.enabled {
                        songCard.updateAnimations()
                        songCard.encode(into: encoder, outputTexture: writeBuffer.texture)
                    }

                    encoder.endEncoding()

                    cmdBuf.addCompletedHandler { [weak self] _ in
                        self?.pipelineQueue.async {
                            guard let self = self else { return }
                            self.streamFrameCount += 1
                            let pipelineLatencyMs = (CACurrentMediaTime() - pipelineEnterTime) * 1000.0
                            self.onStreamBufferAvailable?(writeBuffer.pixelBuffer, timestamp)
                            self.streamManager.appendVideo(pixelBuffer: writeBuffer.pixelBuffer, timestamp: timestamp)
                            DispatchQueue.main.async {
                                self.lagMs = pipelineLatencyMs
                                self.debug.stageLagData(ms: pipelineLatencyMs, audioDepth: self.streamManager.audioSyncQueueDepth)
                            }
                        }
                    }
                    cmdBuf.commit()
                } else if let cr = self.cropRenderer {
                    if let track = self.latestTrackOutput {
                        let offsetCx = track.cx + self.cropHorizontalOffset
                        cr.process(stabTexture: stab.outputTexture,
                                   cx: offsetCx, cy: track.cy,
                                   cropW: track.cropW, cropH: track.cropH)
                    } else {
                        let fb = cr.makeFallbackTrack()
                        let offsetCx = fb.cx + self.cropHorizontalOffset
                        cr.process(stabTexture: stab.outputTexture,
                                   cx: offsetCx, cy: fb.cy,
                                   cropW: fb.cropW, cropH: fb.cropH)
                    }
                    let pipelineLatencyMs = (CACurrentMediaTime() - pipelineEnterTime) * 1000.0
                    DispatchQueue.main.async {
                        self.lagMs = pipelineLatencyMs
                        self.debug.stageLagData(ms: pipelineLatencyMs, audioDepth: 0)
                    }
                }
            }
        }

        camera.onAudioSample = { [weak self] sample, alignedTime in
            self?.onAudioSampleAvailable?(sample, alignedTime)
            self?.streamManager.appendAudio(sampleBuffer: sample, alignedTime: alignedTime)
        }

        startFPSTimer()
        startTemperatureTimer()
        debug.startFlushTimer()
    }

    func stop() {
        camera.onVideoFrame = nil
        camera.stopRunning()
        MotionManager.shared.stopUpdates()
        stopFPSTimer()
        stopTemperatureTimer()
        DispatchQueue.main.async {
            self.debug.stopFlushTimer()
        }
    }

    private func startFPSTimer() {
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pipelineQueue.async {
                guard let self = self else { return }
                let count = self.frameCount
                let streamCount = self.streamFrameCount
                self.frameCount = 0
                self.streamFrameCount = 0
                DispatchQueue.main.async {
                    self.currentFPS = Double(count)
                    self.debug.fps = Double(count)
                    self.debug.frameCount = count
                    self.debug.streamInfo = "\(streamCount) bufs/s \(Config.outputWidth)x\(Config.outputHeight)"
                    self.debug.yoloActualFPS = self.yoloDetector?.actualFPS ?? 0
                }
            }
        }
    }

    private func stopFPSTimer() {
        fpsTimer?.invalidate()
        fpsTimer = nil
    }

    @MainActor func handleLensChange(_ newLens: LensType) {
        Config.selectedLens = newLens
        camera.switchLens(to: newLens)
        reconfigureLens()
        debug.lensType = newLens.rawValue
        camera.onDeviceReady = { [weak self] in
            guard let self else { return }
            self.camera.setFocus(Float(self.focusValue))
            self.applyExposure()
        }
    }

    func reconfigureLens() {
        let cfg = LensCalibration.config(for: selectedLens, inputWidth: Config.inputWidth)
        stabilizer?.loadLensConfig(cfg)
        fov = cfg.defaultFov
        Config.fov = cfg.defaultFov
        stabilizer?.fov = cfg.defaultFov
    }

    func applyExposure() {
        Config.focusValue = focusValue
        Config.shutterTimescale = shutterTimescale
        Config.isoValue = isoValue
        camera.setFocus(Float(focusValue))
        guard camera.exposureMode == .custom else { return }
        camera.setExposure(duration: CMTime(value: 1, timescale: Int32(shutterTimescale)), iso: Float(isoValue))
    }

    func updateISORange() {
        let actualMin = Double(camera.getMinISO()), actualMax = Double(camera.getMaxISO())
        guard actualMin > 0, actualMax > actualMin else { return }
        minISO = actualMin; maxISO = actualMax
        if isoValue < actualMin || isoValue > actualMax { 
            isoValue = actualMin
            Config.isoValue = actualMin
        }
    }

    @MainActor func updateStabilizerEnabled() {
        Config.stabEnabled = stabEnabled
        stabilizer?.stabilizerEnabled = stabEnabled
        debug.stabEnabled = stabEnabled
    }

    @MainActor func updateFov() {
        Config.fov = fov
        stabilizer?.fov = fov
        debug.fov = fov
    }

    @MainActor func updateDistRatio() {
        Config.distRatio = distRatio
        stabilizer?.distRatio = distRatio
        debug.distRatio = distRatio
    }

    func updateYaw() {
        Config.yaw = yaw
        stabilizer?.yawDeg = yaw
    }

    func updatePitch() {
        Config.pitch = pitch
        stabilizer?.pitchDeg = pitch
    }

    func updateRoll() {
        Config.roll = roll
        stabilizer?.rollDeg = roll
    }

    @MainActor func updateYoloPadding() {
        let pad = Int(yoloPadding)
        Config.yoloPadding = pad
        yoloDetector?.updatePadding(pad)
        debug.yoloPadding = pad
        let u = YOLOPreprocessUniforms(padding: pad)
        debug.yoloUniforms = String(format: "s%.3f pH%.0f pV%.0f pL%.0f pT%.0f",
            u.scale, u.padH, u.padV, u.padLeft, u.padTop)
    }

    @MainActor func updateYoloPreviewEnabled() {
        Config.yoloPreviewEnabled = yoloPreviewEnabled
    }
    
    @MainActor func updateYoloOverlayEnabled() {
        Config.yoloOverlayEnabled = yoloOverlayEnabled
        debug.yoloOverlayEnabled = yoloOverlayEnabled
    }

    @MainActor func updateTrackTargetRatio() {
        Config.trackTargetRatio = trackTargetRatio
        bboxTracker.targetRatio = Float(trackTargetRatio)
        debug.trackTargetRatio = Float(trackTargetRatio)
    }

    @MainActor func updateTrackRecenterSpeed() {
        Config.trackRecenterSpeed = trackRecenterSpeed
        bboxTracker.recenterSpeed = Float(trackRecenterSpeed)
        debug.trackRecenterSpeed = Float(trackRecenterSpeed)
    }

    @MainActor func updateRecenterGraceMs() {
        Config.recenterGraceMs = recenterGraceMs
        bboxTracker.recenterGraceMs = Float(recenterGraceMs)
    }

    @MainActor func updateAcquireSpeed() {
        Config.acquireSpeed = acquireSpeed
        bboxTracker.acquireSpeed = Float(acquireSpeed)
    }

    @MainActor func updateSmoothingEnabled() {
        Config.smoothingEnabled = smoothingEnabled
        bboxTracker.smoothingEnabled = smoothingEnabled
    }

    @MainActor func updateSmoothingBaseAlpha() {
        Config.smoothingBaseAlpha = smoothingBaseAlpha
        bboxTracker.smoothingBaseAlpha = Float(smoothingBaseAlpha)
    }

    @MainActor func updateSmoothingMinDeviation() {
        Config.smoothingMinDeviation = smoothingMinDeviation
        bboxTracker.smoothingMinDeviation = Float(smoothingMinDeviation)
    }

    @MainActor func updateSmoothingMaxDeviation() {
        Config.smoothingMaxDeviation = smoothingMaxDeviation
        bboxTracker.smoothingMaxDeviation = Float(smoothingMaxDeviation)
    }

    @MainActor func updateSmoothingCenterFloor() {
        Config.smoothingCenterFloor = smoothingCenterFloor
        bboxTracker.smoothingCenterFloor = Float(smoothingCenterFloor)
    }

    @MainActor func updateReadoutTime() {
        Config.readoutTimeMs = readoutTimeMs
        stabilizer?.useRollingShutter = readoutTimeMs > 0
    }

    @MainActor func updateOverlayEnabled() {
        Config.overlayEnabled = overlayEnabled
        overlayCompositor?.enabled = overlayEnabled
    }

    @MainActor func updateOverlayPosition() {
        Config.overlayPosX = overlayPosX
        Config.overlayPosY = overlayPosY
        overlayCompositor?.posX = overlayPosX
        overlayCompositor?.posY = overlayPosY
    }

    @MainActor func updateOverlayScale() {
        Config.overlayScale = overlayScale
        overlayCompositor?.scale = overlayScale
    }

    @MainActor func updateOverlayOpacity() {
        Config.overlayOpacity = overlayOpacity
        overlayCompositor?.opacity = overlayOpacity
    }

    @MainActor func updateOverlayRotation() {
        Config.overlayRotation = overlayRotation
        overlayCompositor?.rotation = overlayRotation * .pi / 180.0
    }

    @MainActor func updateSongCardEnabled() {
        Config.songCardEnabled = songCardEnabled
        songCardCompositor?.enabled = songCardEnabled
    }

    @MainActor func updateSongCardSlots() {
        songCardCompositor?.slots = [
            CardSlot(posX: slot0PosX, posY: slot0PosY, scale: slot0Scale),
            CardSlot(posX: slot1PosX, posY: slot1PosY, scale: slot1Scale),
            CardSlot(posX: slot2PosX, posY: slot2PosY, scale: slot2Scale)
        ]
        songCardCompositor?.offScreenRight = CardSlot(posX: 1.3, posY: slot1PosY, scale: slot1Scale)
        songCardCompositor?.offScreenLeft = CardSlot(posX: -0.3, posY: slot0PosY, scale: slot0Scale)
        songCardCompositor?.repositionCards()
    }

    @MainActor func updateCropHorizontalOffset() {
        Config.cropHorizontalOffset = cropHorizontalOffset
        debug.cropHorizontalOffset = cropHorizontalOffset
    }

    func loadOverlayImage(_ image: UIImage) {
        overlayCompositor?.loadImage(image)
    }

    private func startTemperatureTimer() {
        temperatureTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateDeviceTemperature()
        }
        updateDeviceTemperature()
    }

    private func stopTemperatureTimer() {
        temperatureTimer?.invalidate()
        temperatureTimer = nil
    }

    private func updateDeviceTemperature() {
        DispatchQueue.main.async { [weak self] in
            self?.debug.deviceTemperature = 0.0
        }
    }

    func onCurrentSongChanged(_ song: SongCardData) {
    }

    func onQueueUpdated(_ songs: [SongCardData]) {
    }

    func triggerSongCardSwitch() {
        guard let compositor = songCardCompositor else { return }

        let hasMoreSongs = songCardManager.currentIndex + 1 < songCardManager.queue.count

        if !hasMoreSongs {
            if !compositor.cards.isEmpty {
                compositor.switchToNext()
            }
            songCardManager.clearQueue()
            return
        }

        let nextIndex = songCardManager.currentIndex + 1
        var newData: SongCardData?

        if nextIndex + 2 < songCardManager.queue.count {
            newData = songCardManager.queue[nextIndex + 2]
        }

        if let data = newData, let renderer = compositor.renderer {
            if let musicId = data.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { [weak self] base64 in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        renderer.renderCard(data: data, coverBase64: base64) { [weak self] texture in
                            guard let self = self, let texture = texture else { return }
                            self.songCardCompositor?.switchToNext(newCardTexture: texture, newCardData: data)
                            self.songCardManager.switchToNext()
                        }
                    }
                }
            } else {
                renderer.renderCard(data: data, coverBase64: nil) { [weak self] texture in
                    guard let self = self, let texture = texture else { return }
                    self.songCardCompositor?.switchToNext(newCardTexture: texture, newCardData: data)
                    self.songCardManager.switchToNext()
                }
            }
        } else {
            songCardCompositor?.switchToNext()
            songCardManager.switchToNext()
        }
    }

    func addSongToQueue(_ song: SongCardData) {
        guard let compositor = songCardCompositor else { return }

        songCardManager.addSong(song)

        if compositor.cards.count < compositor.slots.count {
            if let musicId = song.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { [weak self] base64 in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        if base64 != nil {
                            self.debug.log("[封面] musicId=\(musicId) 加载成功")
                        } else {
                            self.debug.log("[封面] musicId=\(musicId) 加载失败，使用占位图")
                        }
                        self.renderAndAddCard(data: song, coverBase64: base64)
                    }
                }
            } else {
                renderAndAddCard(data: song, coverBase64: nil)
            }
        }
    }

    func addSongAtNextToQueue(_ song: SongCardData) {
        songCardManager.addSongAtNext(song)
        refreshDisplayedCards()
    }

    private func refreshDisplayedCards() {
        guard let compositor = songCardCompositor else { return }

        let ci = songCardManager.currentIndex
        let queue = songCardManager.queue
        guard ci >= 0, ci < queue.count else { return }

        let displayData = Array(queue[ci...].prefix(3))
        var textures: [MTLTexture?] = Array(repeating: nil, count: displayData.count)

        func renderNext(index: Int) {
            guard index < displayData.count else {
                let cardDataList: [(texture: MTLTexture, data: SongCardData)] = zip(textures, displayData).compactMap { t, d in
                    guard let t = t else { return nil }
                    return (texture: t, data: d)
                }
                self.songCardCompositor?.updateAllCards(cardDataList: cardDataList)
                DispatchQueue.main.async {
                    self.debug.log("[插队] 卡片已刷新，显示\(cardDataList.count)张")
                }
                return
            }

            let songData = displayData[index]
            let onRendered: (MTLTexture?) -> Void = { texture in
                textures[index] = texture
                renderNext(index: index + 1)
            }

            if let musicId = songData.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { base64 in
                    DispatchQueue.main.async {
                        compositor.renderer?.renderCard(data: songData, coverBase64: base64, completion: onRendered)
                    }
                }
            } else {
                compositor.renderer?.renderCard(data: songData, coverBase64: nil, completion: onRendered)
            }
        }

        renderNext(index: 0)
    }

    private func renderAndAddCard(data: SongCardData, coverBase64: String?) {
        guard let compositor = songCardCompositor else { return }
        compositor.renderer?.renderCard(data: data, coverBase64: coverBase64) { [weak self] texture in
            guard let self = self, let texture = texture else { return }
            if self.songCardCompositor?.cards.count ?? 0 < self.songCardCompositor?.slots.count ?? 0 {
                self.songCardCompositor?.addCard(texture: texture, data: data)
            }
        }
    }

    func updateSongQueue(_ songs: [SongCardData]) {
        songCardManager.updateQueue(songs)

        guard let compositor = songCardCompositor else { return }

        if songs.isEmpty {
            compositor.clearAll()
            return
        }

        let displayData = Array(songs.prefix(3))
        let group = DispatchGroup()
        var textures: [MTLTexture?] = Array(repeating: nil, count: displayData.count)

        for i in 0..<displayData.count {
            group.enter()
            let songData = displayData[i]
            if let musicId = songData.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { base64 in
                    DispatchQueue.main.async {
                        compositor.renderer?.renderCard(data: songData, coverBase64: base64) { texture in
                            textures[i] = texture
                            group.leave()
                        }
                    }
                }
            } else {
                compositor.renderer?.renderCard(data: songData, coverBase64: nil) { texture in
                    textures[i] = texture
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            let cardDataList: [(texture: MTLTexture, data: SongCardData)] = zip(textures, displayData).compactMap { t, d in
                guard let t = t else { return nil }
                return (texture: t, data: d)
            }
            self.songCardCompositor?.updateAllCards(cardDataList: cardDataList)
        }
    }

    func clearSongQueue() {
        songCardCompositor?.clearAll()
        songCardManager.clearQueue()
    }

    func refreshDisplayedCardsIfNeeded() {
        refreshDisplayedCards()
    }
}
