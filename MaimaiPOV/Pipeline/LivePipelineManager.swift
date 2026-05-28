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
    var overlayCompositor: OverlayCompositor?
    var canvasComposer: CanvasComposer?
    var leftPanelRenderer: LeftPanelRenderer?
    var leftPanelCompositor: LeftPanelCompositor?
    var rightPanelRenderer: RightPanelRenderer?
    var rightPanelCompositor: RightPanelCompositor?
    var marqueeManager: MarqueeManager?
    var marqueeRenderer: MarqueeRenderer?
    var marqueeCompositor: MarqueeCompositor?
    var deviceStatusManager: DeviceStatusManager?
    var deviceStatusRenderer: DeviceStatusRenderer?
    var deviceStatusCompositor: DeviceStatusCompositor?
    private var rightPanelGeneration: Int = 0
    private var refreshLeftPanelWorkItem: DispatchWorkItem?
    private var reorderRightPanelWorkItem: DispatchWorkItem?
    private var isSwitchingSong: Bool = false
    let songCardManager = SongCardManager()
    let blivechatClient = BlivechatClient()
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
            if let _ = canvasComposer {
                return nil
            }
            return stabilizer?.outputTexture
        }
        return nil
    }
    
    var stabTexture: MTLTexture? {
        stabilizer?.outputTexture
    }

    var isCropActive: Bool { canvasComposer != nil }

    let pipelineQueue = DispatchQueue(label: "com.maimai.pipeline", qos: .userInteractive)

    private var ioSurfacePool: IOSurfaceOutputPool?
    private var frameCount: Int = 0
    private var streamFrameCount: Int = 0
    private var fpsTimer: Timer?
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        songCardManager.forceSave()
    }

    private func setupBlivechatCallbacks() {
        blivechatClient.onDanmaku = { [weak self] msg in
            guard let self = self else { return }
            self.latestDanmaku = "\(msg.authorName): \(msg.content)"
            self.danmakuCount += 1
            DispatchQueue.main.async { self.debug.log("[弹幕] \(msg.authorName): \(msg.content)") }
            self.handleDanmakuForSongRequest(msg)
        }

        blivechatClient.onGift = { [weak self] msg in
            guard let self = self else { return }
            let coinValue = max(msg.totalCoin, msg.totalFreeCoin)
            DispatchQueue.main.async { self.debug.log("[礼物] \(msg.authorName) 送 \(msg.giftName) x\(msg.num) (金瓜子:\(coinValue))") }
            let prefix = "🎁 感谢 \(msg.authorName) 送出 \(msg.giftName)"
            self.postMarquee("\(prefix) ×\(msg.num)", type: .gift, mergeKey: "gift_\(msg.authorName)_\(msg.giftName)", mergeCount: msg.num, textPrefix: prefix)
            if coinValue > 0 {
                let name = msg.authorName
                self.songCardManager.userGiftPool[name, default: 0] += coinValue
                if let index = self.songCardManager.findSongIndex(byName: name) {
                    self.songCardManager.updateGiftValue(name: name, delta: coinValue)
                    let lockedEnd = self.songCardManager.lockedEndIndex
                    if index >= lockedEnd {
                        self.songCardManager.reorderQueueByGiftValue()
                    }
                    DispatchQueue.main.async { self.debug.log("[礼物追踪] \(name) 累积 \(self.songCardManager.userGiftPool[name] ?? 0) 金瓜子") }
                } else {
                    self.scheduleRefreshLeftPanel()
                }
            }
        }

        blivechatClient.onSuperChat = { [weak self] msg in
            guard let self = self else { return }
            DispatchQueue.main.async { self.debug.log("[SC] \(msg.authorName): ¥\(msg.price) \(msg.content)") }
            self.handleSuperChatForSongRequest(msg)
        }

        blivechatClient.onMember = { [weak self] msg in
            guard let self = self else { return }
            let name = msg.authorName
            let coinValue = 198 * 1000
            self.songCardManager.userGiftPool[name, default: 0] += coinValue
            if let index = self.songCardManager.findSongIndex(byName: name) {
                self.songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = self.songCardManager.lockedEndIndex
                if index >= lockedEnd {
                    self.songCardManager.reorderQueueByGiftValue()
                }
            } else {
                self.scheduleRefreshLeftPanel()
            }
            DispatchQueue.main.async { self.debug.log("[上舰] \(msg.authorName)") }
            self.postMarquee("⭐ \(msg.authorName) 上舰了!", type: .member)
        }

        blivechatClient.onError = { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async { self.debug.log("[blivechat错误] code=\(error.code) \(error.message)") }
        }

        blivechatClient.onReconnectLog = { [weak self] message in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.debug.log(message)
            }
        }
    }

    func postMarquee(_ text: String, type: MarqueeItem.MarqueeItemType, mergeKey: String? = nil, mergeCount: Int = 1, textPrefix: String? = nil) {
        guard let manager = marqueeManager else { return }
        let item = MarqueeItem(text: text, type: type, mergeKey: mergeKey, mergeCount: mergeCount, textPrefix: textPrefix)
        manager.enqueue(item)
    }

    func handleDanmakuForSongRequest(_ msg: DanmakuMessage) {
        let result = danmakuParser.parse(msg.content)

        switch result.type {
        case .songRequest(let query, let diffInput, let chartTypePreference):
            let name = msg.authorName
            let originalQuery = result.originalQuery

            DispatchQueue.main.async {
                self.debug.log("[点歌] 解析: query=\"\(query)\" original=\"\(originalQuery)\" diff=\(diffInput ?? "nil") chart=\(chartTypePreference ?? "nil") db=\(self.songDatabase.songCount)")
            }

            guard !songCardManager.hasSongInQueue(name: name) else {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] \(msg.authorName) 已有歌曲在队列中")
                    self.postMarquee("❌ \(name) 已有歌曲在队列中", type: .songFailure)
                }
                return
            }

            var candidates = songDatabase.findCandidates(query: originalQuery)
            var resolvedDiffInput: String? = nil
            var resolvedChartTypePreference: String? = nil
            var usedOriginalQuery = false

            if !candidates.candidates.isEmpty && originalQuery != query {
                usedOriginalQuery = true
            } else {
                candidates = songDatabase.findCandidates(query: query)
                resolvedDiffInput = diffInput
                resolvedChartTypePreference = chartTypePreference
            }

            if candidates.candidates.isEmpty {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] 未找到歌曲: \"\(query)\"")
                    self.postMarquee("❌ \(name) 未找到\"\(query)\"", type: .songFailure)
                }
                return
            }

            guard let song = songDatabase.pickByChartType(
                candidates: candidates.candidates,
                chartTypePreference: resolvedChartTypePreference,
                diffInput: resolvedDiffInput
            ) else {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] 候选\(candidates.candidates.count)首但无法选择")
                    self.postMarquee("❌ \(name) 无法匹配歌曲", type: .songFailure)
                }
                return
            }

            let targetDiffNum = songDatabase.resolveDiffInput(resolvedDiffInput)
            guard let noteResult = songDatabase.findNote(song: song, targetDiffNum: targetDiffNum) else {
                DispatchQueue.main.async {
                    self.debug.log("[点歌] \(song.title) 没有可用难度")
                    self.postMarquee("❌ \(name): \(song.title) 没有可用难度", type: .songFailure)
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

                let giftTag = giftVal > 0 ? " [🎁\(giftVal)]" : ""
                self.debug.log("[点歌] ✅ \(msg.authorName) → \(song.title) (\(ctDisplay) \(diffName) \(levelStr)) [\(candidates.matchKind?.rawValue ?? "?")]\(giftTag)")
                self.postMarquee("🎵 \(name) 点歌 \(song.title) (\(ctDisplay) \(diffName) \(levelStr))", type: .songSuccess)
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
            let originalQuery = result.originalQuery

            DispatchQueue.main.async {
                self.debug.log("[SC点歌] 解析: query=\"\(query)\" original=\"\(originalQuery)\" diff=\(diffInput ?? "nil") chart=\(chartTypePreference ?? "nil") price=\(sc.price)")
            }

            if songCardManager.hasSongInQueue(name: name) {
                let coinValue = sc.price * 1000
                songCardManager.userGiftPool[name, default: 0] += coinValue
                songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = songCardManager.lockedEndIndex
                if let idx = songCardManager.findSongIndex(byName: name), idx >= lockedEnd {
                    songCardManager.reorderQueueByGiftValue()
                }
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] \(sc.authorName) 已有歌曲在队列中，SC金额累加到送礼池")
                    self.postMarquee("❌ \(name) 已有歌曲在队列中", type: .songFailure)
                }
                return
            }

            var candidates = songDatabase.findCandidates(query: originalQuery)
            var resolvedDiffInput: String? = nil
            var resolvedChartTypePreference: String? = nil

            if !candidates.candidates.isEmpty && originalQuery != query {
                // whole match succeeded, don't apply difficulty/chartType filters
            } else {
                candidates = songDatabase.findCandidates(query: query)
                resolvedDiffInput = diffInput
                resolvedChartTypePreference = chartTypePreference
            }

            if candidates.candidates.isEmpty {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] 未找到歌曲: \"\(query)\"，SC金额累积到送礼池")
                    self.postMarquee("❌ \(name) 未找到\"\(query)\"", type: .songFailure)
                }
                return
            }

            guard let song = songDatabase.pickByChartType(
                candidates: candidates.candidates,
                chartTypePreference: resolvedChartTypePreference,
                diffInput: resolvedDiffInput
            ) else {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] 候选\(candidates.candidates.count)首但无法选择，SC金额累积到送礼池")
                    self.postMarquee("❌ \(name) 无法匹配歌曲", type: .songFailure)
                }
                return
            }

            let targetDiffNum = songDatabase.resolveDiffInput(resolvedDiffInput)
            guard let noteResult = songDatabase.findNote(song: song, targetDiffNum: targetDiffNum) else {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                DispatchQueue.main.async {
                    self.debug.log("[SC点歌] \(song.title) 没有可用难度，SC金额累积到送礼池")
                    self.postMarquee("❌ \(name): \(song.title) 没有可用难度", type: .songFailure)
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

                let giftTag = giftVal > 0 ? " [🎁\(giftVal)]" : ""
                self.debug.log("[SC点歌] ✅ \(sc.authorName) → \(song.title) (\(ctDisplay) \(diffName) \(levelStr)) [🎁\(giftVal)]")
                self.postMarquee("💰 \(name) SC点歌 \(song.title) (\(ctDisplay) \(diffName) \(levelStr))", type: .superChat)
            }

        case .notACommand:
            let name = sc.authorName
            let coinValue = sc.price * 1000
            songCardManager.userGiftPool[name, default: 0] += coinValue
            if let index = songCardManager.findSongIndex(byName: name) {
                songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = songCardManager.lockedEndIndex
                if index >= lockedEnd {
                    songCardManager.reorderQueueByGiftValue()
                }
                DispatchQueue.main.async {
                    self.debug.log("[SC追踪] \(name) 累积 \(self.songCardManager.userGiftPool[name] ?? 0) 金瓜子")
                }
            }
            DispatchQueue.main.async {
                self.postMarquee("💰 感谢 \(sc.authorName) 的SC ¥\(sc.price)", type: .superChat)
            }
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

        observeBlivechatState()
    }

    @MainActor func disconnectBlivechat() {
        blivechatClient.disconnect()
        blivechatConnectionState = .disconnected
    }

    @MainActor func restoreQueueFromSnapshot() {
        guard let snapshot = QueuePersistenceManager.shared.load() else { return }
        songCardManager.restoreFromSnapshot(snapshot)
        songCardManager.forceSave()
        debug.log("[持久化] 已恢复队列: \(snapshot.queue.count) 首歌曲")
    }

    @MainActor func discardSnapshot() {
        QueuePersistenceManager.shared.clearSnapshot()
    }

    var hasRestorableSnapshot: Bool {
        QueuePersistenceManager.shared.hasSnapshot()
    }

    var snapshotAgeString: String {
        guard let age = QueuePersistenceManager.shared.snapshotAge() else { return "" }
        if age < 60 { return "\(Int(age))秒前" }
        if age < 3600 { return "\(Int(age / 60))分钟前" }
        if age < 86400 { return "\(Int(age / 3600))小时前" }
        return "\(Int(age / 86400))天前"
    }

    private func observeBlivechatState() {
        blivechatClient.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.blivechatConnectionState = state
                if case .disconnected = state, self.blivechatClient.isManuallyDisconnected {
                    return
                }
            }
            .store(in: &cancellables)
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

        self.canvasComposer = CanvasComposer(device: device)

        self.overlayCompositor = OverlayCompositor(device: device)
        self.overlayCompositor?.enabled = overlayEnabled
        self.overlayCompositor?.posX = overlayPosX
        self.overlayCompositor?.posY = overlayPosY
        self.overlayCompositor?.scale = overlayScale
        self.overlayCompositor?.opacity = overlayOpacity
        self.overlayCompositor?.rotation = overlayRotation * .pi / 180.0

        songCardManager.delegate = self

        if Config.leftPanelEnabled {
            self.leftPanelRenderer = LeftPanelRenderer(device: device)
            self.leftPanelCompositor = LeftPanelCompositor(device: device)
            renderLeftPanelAnnouncement()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshLeftPanel()
            }
        }

        self.rightPanelRenderer = RightPanelRenderer(device: device)
        self.rightPanelCompositor = RightPanelCompositor(device: device)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshRightPanel()
        }

        self.marqueeManager = MarqueeManager()
        self.marqueeRenderer = MarqueeRenderer(device: device)
        self.marqueeCompositor = MarqueeCompositor(device: device, manager: marqueeManager!, renderer: marqueeRenderer!)

        self.deviceStatusManager = DeviceStatusManager()
        self.deviceStatusRenderer = DeviceStatusRenderer(device: device)
        self.deviceStatusCompositor = DeviceStatusCompositor(device: device, manager: deviceStatusManager!, renderer: deviceStatusRenderer!)
        self.deviceStatusManager?.startMonitoring()

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
        webServerManager.start()

        if songDatabase.songCount == 0 {
            songDatabase.loadFromBundle()
            if songDatabase.songCount == 0 {
                debug.log("[曲库] ❌ 加载失败: \(songDatabase.lastError ?? "unknown")")
            } else {
                debug.log("[曲库] 加载完成: \(songDatabase.songCount) 首歌曲")
            }
        }

        camera.onVideoFrame = { [weak self] pixelBuffer, alignedTime in
            let pipelineEnterTime = CACurrentMediaTime()
            self?.pipelineQueue.async {
                autoreleasepool {
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

                    if let bufferIdx = pool.indexOfBuffer(writeBuffer) {
                        pool.markBufferInUse(bufferIdx, commandBuffer: cmdBuf)
                    }

                    cc.encode(into: encoder,
                              stabTexture: stab.outputTexture,
                              cx: offsetCx, cy: track.cy,
                              cropW: track.cropW, cropH: track.cropH,
                              outputTexture: writeBuffer.texture)

                    if let panel = self.leftPanelCompositor, panel.enabled {
                        panel.updateAnimations()
                        panel.encode(into: encoder, outputTexture: writeBuffer.texture)
                    }

                    if let rpc = self.rightPanelCompositor, rpc.enabled {
                        rpc.updateAnimations()
                        rpc.encode(into: encoder, outputTexture: writeBuffer.texture)
                    }

                    if let marquee = self.marqueeCompositor, marquee.enabled {
                        marquee.updateAnimations()
                        marquee.encode(into: encoder, outputTexture: writeBuffer.texture)
                    }

                    if let ds = self.deviceStatusCompositor, ds.enabled {
                        ds.updateIfNeeded()
                        ds.encode(into: encoder, outputTexture: writeBuffer.texture)
                    }

                    encoder.endEncoding()

                    cmdBuf.addCompletedHandler { [weak self] _ in
                        if let pool = self?.ioSurfacePool, let idx = pool.indexOfBuffer(writeBuffer) {
                            pool.notifyBufferCompleted(idx)
                        }
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
                }
                }
            }
        }

        camera.onAudioSample = { [weak self] sample, alignedTime in
            self?.onAudioSampleAvailable?(sample, alignedTime)
            self?.streamManager.appendAudio(sampleBuffer: sample, alignedTime: alignedTime)
        }

        startFPSTimer()
        debug.startFlushTimer()
    }

    func stop() {
        camera.onVideoFrame = nil
        camera.stopRunning()
        MotionManager.shared.stopUpdates()
        deviceStatusManager?.stopMonitoring()
        stopFPSTimer()
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

    @MainActor func updateCropHorizontalOffset() {
        Config.cropHorizontalOffset = cropHorizontalOffset
        debug.cropHorizontalOffset = cropHorizontalOffset
    }

    func loadOverlayImage(_ image: UIImage) {
        overlayCompositor?.loadImage(image)
    }

    func onCurrentSongChanged(_ song: SongCardData?) {
        if !isSwitchingSong {
            renderLeftPanelCurrentSong(song)
        }
    }

    func onQueueUpdated(_ songs: [SongCardData], change: QueueChange) {
        scheduleRefreshLeftPanel()
        switch change {
        case .added:
            break
        case .removed:
            scheduleReorderRightPanel()
        case .reordered:
            scheduleReorderRightPanel()
        case .fullRefresh:
            refreshRightPanel()
        }
    }

    func onSongRemoved(queueIndex: Int) {
        rightPanelCompositor?.removeRow(queueIndex: queueIndex)
        rightPanelRenderer?.invalidateRow(queueIndex: queueIndex)
    }

    func onGiftValueChanged(_ song: SongCardData, queueIndex: Int) {
        scheduleRefreshLeftPanel()
    }

    func triggerSongCardSwitch() {
        guard leftPanelCompositor != nil else { return }

        let newCurrentData = songCardManager.nextSong
        isSwitchingSong = true

        if let data = newCurrentData {
            if let musicId = data.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { [weak self] base64 in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.leftPanelRenderer?.renderCurrentSong(data, coverBase64: base64) { [weak self] texture in
                            guard let self = self else { return }
                            self.leftPanelCompositor?.switchToNext(newCurrentTexture: texture, newCurrentData: data)
                            self.songCardManager.switchToNext()
                            self.isSwitchingSong = false
                            self.switchRightPanelToNext()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.leftPanelRenderer?.renderCurrentSong(data, coverBase64: nil) { [weak self] texture in
                        guard let self = self else { return }
                        self.leftPanelCompositor?.switchToNext(newCurrentTexture: texture, newCurrentData: data)
                        self.songCardManager.switchToNext()
                        self.isSwitchingSong = false
                        self.switchRightPanelToNext()
                    }
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.leftPanelRenderer?.renderCurrentSong(nil, coverBase64: nil) { [weak self] texture in
                    guard let self = self else { return }
                    self.leftPanelCompositor?.switchToNext(newCurrentTexture: texture, newCurrentData: nil)
                    self.songCardManager.switchToNext()
                    self.isSwitchingSong = false
                    self.switchRightPanelToNext()
                }
            }
        }
    }

    func addSongToQueue(_ song: SongCardData) {
        if song.giftValue > 0 {
            songCardManager.addSong(song)
            songCardManager.reorderQueueByGiftValue()
            ensureTitleTexture()
            scheduleReorderRightPanel()
        } else {
            songCardManager.addSong(song)
            addRightPanelRow(song: song)
        }
    }

    func addSongAtNextToQueue(_ song: SongCardData) {
        songCardManager.addSongAtNext(song)
        refreshRightPanel()
    }

    func updateSongQueue(_ songs: [SongCardData]) {
        songCardManager.updateQueue(songs)
        refreshRightPanel()
    }

    func clearSongQueue() {
        leftPanelCompositor?.clearAll()
        rightPanelCompositor?.clearAll()
        rightPanelRenderer?.invalidateCache()
        leftPanelRenderer?.invalidateCache()
        songCardManager.clearQueue()
        if leftPanelCompositor != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.leftPanelCompositor?.resetToEmpty()
                self?.refreshLeftPanel()
            }
        }
    }

    func refreshDisplayedCardsIfNeeded() {
        refreshRightPanel()
    }

    private func renderLeftPanelCurrentSong(_ song: SongCardData?) {
        guard let renderer = leftPanelRenderer, let compositor = leftPanelCompositor else { return }

        if let song = song {
            if let musicId = song.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { [weak self] base64 in
                    guard self != nil else { return }
                    DispatchQueue.main.async {
                        renderer.renderCurrentSong(song, coverBase64: base64) { texture in
                            if let texture = texture {
                                compositor.setCurrentSong(texture: texture, data: song)
                            }
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    renderer.renderCurrentSong(song, coverBase64: nil) { texture in
                        if let texture = texture {
                            compositor.setCurrentSong(texture: texture, data: song)
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                renderer.renderCurrentSong(nil, coverBase64: nil) { texture in
                    if let texture = texture {
                        compositor.setCurrentSong(texture: texture, data: nil)
                    }
                }
            }
        }
    }

    func scheduleRefreshLeftPanel(delay: TimeInterval = 0.1) {
        refreshLeftPanelWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshLeftPanel()
        }
        refreshLeftPanelWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func scheduleReorderRightPanel() {
        rightPanelCompositor?.cancelPreScroll()
        reorderRightPanelWorkItem?.cancel()
        rightPanelGeneration += 1
        let currentGeneration = rightPanelGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.rightPanelGeneration == currentGeneration else { return }
            self.performReorderRightPanel()
        }
        reorderRightPanelWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func refreshLeftPanel() {
        let current = songCardManager.currentSong
        renderLeftPanelCurrentSong(current)
    }

    func renderLeftPanelAnnouncement() {
        guard let renderer = leftPanelRenderer, let compositor = leftPanelCompositor else { return }
        DispatchQueue.main.async {
            renderer.renderAnnouncement(Config.announcementText) { texture in
                if let texture = texture {
                    compositor.setAnnouncement(texture: texture)
                }
            }
        }
    }

    private func addRightPanelRow(song: SongCardData) {
        guard let renderer = rightPanelRenderer, let compositor = rightPanelCompositor else { return }

        let ci = songCardManager.currentIndex
        let startQueueIndex = ci + 1
        let queueIndex = songCardManager.queue.count - 1

        guard queueIndex >= startQueueIndex else { return }

        if !compositor.hasTitleTexture {
            renderer.renderTitle { [weak self] texture in
                self?.rightPanelCompositor?.updateTitleTexture(texture)
            }
        }

        let gen = rightPanelGeneration
        let maxOffset = Float(max(0, (compositor.totalRowCount + 1) - compositor.maxVisibleRows))
        let currentOffset = compositor.currentScrollOffset

        if currentOffset < maxOffset - 0.01 {
            compositor.animateScrollTo(targetOffset: maxOffset, duration: 0.3, extraRows: 1) { [weak self] in
                guard let self = self, self.rightPanelGeneration == gen else { return }
                self.performAddRightPanelRow(song: song, queueIndex: queueIndex)
            }
        } else {
            performAddRightPanelRow(song: song, queueIndex: queueIndex)
        }
    }

    private func performAddRightPanelRow(song: SongCardData, queueIndex: Int) {
        guard let renderer = rightPanelRenderer else { return }

        if rightPanelCompositor?.getRowDataForId(song.id) != nil {
            return
        }

        if let musicId = song.musicId {
            CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { [weak self] base64 in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.rightPanelRenderer?.renderRow(data: song, queueIndex: queueIndex, coverBase64: base64) { [weak self] _, texture in
                        guard let self = self, let texture = texture else { return }
                        if self.rightPanelCompositor?.getRowDataForId(song.id) != nil { return }
                        self.rightPanelCompositor?.addRowAtBottom(texture: texture, data: song, queueIndex: queueIndex)
                    }
                }
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.rightPanelRenderer?.renderRow(data: song, queueIndex: queueIndex, coverBase64: nil) { [weak self] _, texture in
                    guard let self = self, let texture = texture else { return }
                    self.rightPanelCompositor?.addRowAtBottom(texture: texture, data: song, queueIndex: queueIndex)
                }
            }
        }
    }

    func reorderRightPanel() {
        scheduleReorderRightPanel()
    }

    private func ensureTitleTexture() {
        guard let compositor = rightPanelCompositor, !compositor.hasTitleTexture, let renderer = rightPanelRenderer else { return }
        renderer.renderTitle { [weak self] texture in
            self?.rightPanelCompositor?.updateTitleTexture(texture)
        }
    }

    private func performReorderRightPanel() {
        guard let compositor = rightPanelCompositor else { return }
        guard let renderer = rightPanelRenderer else { return }

        ensureTitleTexture()

        let ci = songCardManager.currentIndex
        let queue = songCardManager.queue
        let startQueueIndex = ci + 1

        guard startQueueIndex < queue.count else {
            compositor.clearAll()
            return
        }

        let allSongs = Array(queue[startQueueIndex...])

        var targetScrollRow = 0
        var maxGift = 0
        for (i, song) in allSongs.enumerated() {
            if song.giftValue > maxGift {
                maxGift = song.giftValue
                targetScrollRow = i
            }
        }

        let currentOffset = compositor.currentScrollOffset
        var neededOffset = currentOffset
        if targetScrollRow < Int(currentOffset) {
            neededOffset = Float(targetScrollRow)
        } else if targetScrollRow >= Int(currentOffset) + compositor.maxVisibleRows {
            neededOffset = Float(targetScrollRow - compositor.maxVisibleRows + 1)
        }

        var preScrollSongId: UUID? = nil
        var maxUpwardMovement = 0
        for (newIndex, song) in allSongs.enumerated() {
            if let oldIndex = compositor.listIndexForSong(id: song.id) {
                let movement = oldIndex - newIndex
                if movement > maxUpwardMovement {
                    maxUpwardMovement = movement
                    preScrollSongId = song.id
                }
            }
        }

        if let scrollId = preScrollSongId,
           let oldListIndex = compositor.listIndexForSong(id: scrollId) {
            if !compositor.isRowVisible(listIndex: oldListIndex) {
                let oldNeededOffset = compositor.scrollOffsetNeededForRow(listIndex: oldListIndex)

                let gen = rightPanelGeneration
                compositor.animateScrollTo(targetOffset: oldNeededOffset, duration: 0.3, isPreScroll: true) { [weak self] in
                    guard let self = self else { return }
                    guard self.rightPanelGeneration == gen else { return }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        guard let self = self else { return }
                        guard self.rightPanelGeneration == gen else { return }

                        let currentAfterPreScroll = self.rightPanelCompositor?.currentScrollOffset ?? currentOffset
                        let targetScrollOffset = abs(neededOffset - currentAfterPreScroll) > 0.01 ? neededOffset : nil
                        self.doReorderRightPanel(
                            compositor: compositor,
                            renderer: renderer,
                            allSongs: allSongs,
                            startQueueIndex: startQueueIndex,
                            targetScrollOffset: targetScrollOffset
                        )
                    }
                }
                return
            }
        }

        let needsScroll = abs(neededOffset - currentOffset) > 0.01
        let targetScrollOffset = needsScroll ? neededOffset : nil
        doReorderRightPanel(compositor: compositor, renderer: renderer, allSongs: allSongs, startQueueIndex: startQueueIndex, targetScrollOffset: targetScrollOffset)
    }

    private func doReorderRightPanel(compositor: RightPanelCompositor, renderer: RightPanelRenderer, allSongs: [SongCardData], startQueueIndex: Int, targetScrollOffset: Float? = nil) {

        var newOrder: [(queueIndex: Int, data: SongCardData)] = []
        var existingGiftChanged: [(queueIndex: Int, data: SongCardData)] = []
        var newRowsNeedTexture: [(queueIndex: Int, data: SongCardData)] = []

        for (i, song) in allSongs.enumerated() {
            let queueIndex = startQueueIndex + i
            newOrder.append((queueIndex: queueIndex, data: song))

            let existingData = compositor.getRowDataForId(song.id)
            if let existing = existingData {
                if existing.giftValue != song.giftValue {
                    existingGiftChanged.append((queueIndex: queueIndex, data: song))
                }
            } else {
                newRowsNeedTexture.append((queueIndex: queueIndex, data: song))
            }
        }

        if newRowsNeedTexture.isEmpty {
            compositor.reorderRows(newOrder: newOrder, textures: [:], targetScrollOffset: targetScrollOffset)

            for item in existingGiftChanged {
                let song = item.data
                let songId = song.id
                if let musicId = song.musicId {
                    CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { base64 in
                        DispatchQueue.main.async {
                            renderer.renderRow(data: song, queueIndex: item.queueIndex, coverBase64: base64) { _, texture in
                                if let texture = texture {
                                    compositor.updateRowTexture(bySongId: songId, texture: texture)
                                }
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        renderer.renderRow(data: song, queueIndex: item.queueIndex, coverBase64: nil) { _, texture in
                            if let texture = texture {
                                compositor.updateRowTexture(bySongId: songId, texture: texture)
                            }
                        }
                    }
                }
            }
            return
        }

        var renderedTextures: [Int: MTLTexture] = [:]
        let group = DispatchGroup()
        let currentGeneration = rightPanelGeneration

        for item in newRowsNeedTexture {
            group.enter()
            let queueIndex = item.queueIndex
            let song = item.data
            if let musicId = song.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { base64 in
                    DispatchQueue.main.async {
                        renderer.renderRow(data: song, queueIndex: queueIndex, coverBase64: base64) { _, texture in
                            if let texture = texture {
                                renderedTextures[queueIndex] = texture
                            }
                            group.leave()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    renderer.renderRow(data: song, queueIndex: queueIndex, coverBase64: nil) { _, texture in
                        if let texture = texture {
                            renderedTextures[queueIndex] = texture
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.rightPanelGeneration == currentGeneration else { return }
            compositor.reorderRows(newOrder: newOrder, textures: renderedTextures, targetScrollOffset: targetScrollOffset)

            for item in existingGiftChanged {
                let song = item.data
                let songId = song.id
                if let musicId = song.musicId {
                    CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { base64 in
                        DispatchQueue.main.async {
                            renderer.renderRow(data: song, queueIndex: item.queueIndex, coverBase64: base64) { _, texture in
                                if let texture = texture {
                                    compositor.updateRowTexture(bySongId: songId, texture: texture)
                                }
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        renderer.renderRow(data: song, queueIndex: item.queueIndex, coverBase64: nil) { _, texture in
                            if let texture = texture {
                                compositor.updateRowTexture(bySongId: songId, texture: texture)
                            }
                        }
                    }
                }
            }
        }
    }

    func refreshRightPanel() {
        guard let renderer = rightPanelRenderer, let compositor = rightPanelCompositor else { return }

        let ci = songCardManager.currentIndex
        let queue = songCardManager.queue
        let startQueueIndex = ci + 1

        guard startQueueIndex < queue.count else {
            compositor.clearAll()
            return
        }

        let allRightPanelSongs = Array(queue[startQueueIndex...])

        renderer.renderTitle { [weak self] texture in
            guard let self = self else { return }
            self.rightPanelCompositor?.updateTitleTexture(texture)

            var covers: [Int: String] = [:]
            let group = DispatchGroup()
            let lock = NSLock()

            for (i, song) in allRightPanelSongs.enumerated() {
                guard let musicId = song.musicId else { continue }
                let qIdx = startQueueIndex + i
                group.enter()
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { base64 in
                    lock.lock()
                    covers[qIdx] = base64
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                renderer.renderVisibleRows(
                    songs: allRightPanelSongs,
                    startQueueIndex: startQueueIndex,
                    covers: covers
                ) { [weak self] textures in
                    guard let self = self else { return }
                    self.rightPanelCompositor?.setRows(
                        textures: textures,
                        data: allRightPanelSongs,
                        startQueueIndex: startQueueIndex
                    )
                }
            }
        }
    }

    private func switchRightPanelToNext() {
        rightPanelGeneration += 1
        guard let compositor = rightPanelCompositor else { return }

        let ci = songCardManager.currentIndex
        let queue = songCardManager.queue
        let startQueueIndex = ci + 1

        guard startQueueIndex < queue.count else {
            compositor.clearAll()
            return
        }

        if compositor.currentScrollOffset > 0.01 {
            compositor.animateScrollTo(targetOffset: 0, duration: 0.3) { [weak self] in
                self?.performSwitchToNext()
            }
        } else {
            performSwitchToNext()
        }
    }

    private func performSwitchToNext() {
        guard let renderer = rightPanelRenderer, let compositor = rightPanelCompositor else { return }

        rightPanelRenderer?.invalidateCache()
        leftPanelRenderer?.invalidateCache()

        let ci = songCardManager.currentIndex
        let queue = songCardManager.queue
        let startQueueIndex = ci + 1

        guard startQueueIndex < queue.count else {
            compositor.clearAll()
            return
        }

        let rightPanelSongCount = queue.count - startQueueIndex
        let currentRowCount = compositor.currentRowCount()
        let needsNewBottom = rightPanelSongCount > (currentRowCount - 1)

        if needsNewBottom {
            let bottomQueueIndex = startQueueIndex + rightPanelSongCount - 1
            let bottomSong = queue[bottomQueueIndex]

            if let musicId = bottomSong.musicId {
                CoverImageLoader.shared.loadCoverBase64(musicId: musicId) { [weak self] base64 in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.rightPanelRenderer?.renderRow(data: bottomSong, queueIndex: bottomQueueIndex, coverBase64: base64) { [weak self] _, texture in
                            guard let self = self, let texture = texture else { return }
                            self.rightPanelCompositor?.switchToNext(
                                newBottomRowTexture: texture,
                                newBottomRowData: bottomSong,
                                newBottomQueueIndex: bottomQueueIndex
                            )
                        }
                    }
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.rightPanelRenderer?.renderRow(data: bottomSong, queueIndex: bottomQueueIndex, coverBase64: nil) { [weak self] _, texture in
                        guard let self = self, let texture = texture else { return }
                        self.rightPanelCompositor?.switchToNext(
                            newBottomRowTexture: texture,
                            newBottomRowData: bottomSong,
                            newBottomQueueIndex: bottomQueueIndex
                        )
                    }
                }
            }
        } else {
            compositor.switchToNext(newBottomRowTexture: nil, newBottomRowData: nil, newBottomQueueIndex: -1)
        }
    }
}
