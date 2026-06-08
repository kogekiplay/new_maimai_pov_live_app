import SwiftUI
import Combine
import AVFoundation
import CoreMedia
@preconcurrency import Metal
import simd
import QuartzCore
import UIKit
import CoreImage

private final class WeakLivePipelineManager: @unchecked Sendable {
    weak var value: LivePipelineManager?

    init(_ value: LivePipelineManager?) {
        self.value = value
    }
}

private struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

struct QueueSnapshotRestoreInfo: Sendable {
    let ageText: String
    let pendingGiftUserCount: Int
    let allGiftUserCount: Int
}

private final class LockedTextureMap: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int: MTLTexture] = [:]

    func set(_ texture: MTLTexture, for queueIndex: Int) {
        lock.withLock {
            values[queueIndex] = texture
        }
    }

    func snapshot() -> [Int: MTLTexture] {
        lock.withLock {
            values
        }
    }
}

final class LivePipelineManager: ObservableObject, SongCardDataProvider, @unchecked Sendable {
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
    @Published var activityMode: Bool = false {
        didSet {
            if activityMode && !oldValue {
                savedYoloEnabled = yoloEnabled
                yoloEnabled = false
                Config.yoloEnabled = false
            } else if !activityMode && oldValue {
                yoloEnabled = savedYoloEnabled
                Config.yoloEnabled = savedYoloEnabled
            }
        }
    }
    private var savedYoloEnabled: Bool = true
    @Published var activitySmoothFactor: Float = Config.activitySmoothFactor
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
    let debug: DebugInfoManager
    let device: MTLDevice = MTLCreateSystemDefaultDevice()!
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    let sharedCommandQueue: MTLCommandQueue
    let streamManager = RTMPStreamManager()
    let audioMixer = AudioMixer()
    let audioDeviceManager = AudioDeviceManager()

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

    private(set) var ioSurfacePool: IOSurfaceOutputPool?
    private var frameCount: Int = 0
    private var streamFrameCount: Int = 0
    private var fpsTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var songDatabaseLoadTask: Task<Void, Never>?
    private var isObservingBlivechatState = false
    private var blivechatConnectGeneration = 0
    private var yoloPreviewFrameCount: Int = 0
    private var lastStabOnlyMs: Double = 0

    @MainActor init(debug: DebugInfoManager = .shared) {
        self.debug = debug
        sharedCommandQueue = device.makeCommandQueue()!

        streamManager.audioMixer = audioMixer

        camera.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        streamManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        audioMixer.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        audioDeviceManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        streamManager.$isStreaming.sink { [weak self] streaming in
            Task { @MainActor in
                self?.debug.isStreaming = streaming
            }
        }.store(in: &cancellables)

        audioDeviceManager.onSourceChanged = { [weak self] source in
            self?.camera.switchAudioInput(to: source)
            self?.audioMixer.isStereoMixEnabled = (source == .externalStereo)
            self?.streamManager.resetAudioState()
        }

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
        let danmakuBuffer = DanmakuBufferManager.shared

        blivechatClient.onDanmaku = { [weak self] msg in
            guard let self = self else { return }
            self.latestDanmaku = "\(msg.authorName): \(msg.content)"
            self.danmakuCount += 1
            DebugInfoManager.logAsync("[弹幕] \(msg.authorName): \(msg.content)")

            let parseResult = self.danmakuParser.parse(msg.content)
            let isSongRequest: Bool
            let isCancelRequest: Bool
            if case .songRequest = parseResult.type {
                isSongRequest = true
                isCancelRequest = false
            } else if case .cancelRequest = parseResult.type {
                isSongRequest = true
                isCancelRequest = true
            } else {
                isSongRequest = false
                isCancelRequest = false
            }

            _ = danmakuBuffer.addEntry(
                type: .danmaku,
                username: msg.authorName,
                content: msg.content,
                timestamp: msg.timestamp,
                avatarUrl: msg.avatarUrl,
                isSongRequest: isSongRequest,
                uid: msg.effectiveUid,
                originalDanmakuId: msg.id,
                userGiftValue: self.songCardManager.userGiftPool[msg.authorName] ?? 0
            )

            if isCancelRequest {
                self.handleCancelSongRequest(msg)
            } else {
                self.handleDanmakuForSongRequest(msg)
            }
            self.songCardManager.updateOwnerActivity(forName: msg.authorName)
        }

        blivechatClient.onGift = { [weak self] msg in
            guard let self = self else { return }
            let coinValue = max(msg.totalCoin, msg.totalFreeCoin)
            DebugInfoManager.logAsync("[礼物] \(msg.authorName) 送 \(msg.giftName) x\(msg.num) (金瓜子:\(coinValue))")

            _ = danmakuBuffer.addEntry(
                type: .gift,
                username: msg.authorName,
                content: "送出 \(msg.giftName) ×\(msg.num)",
                timestamp: msg.timestamp,
                avatarUrl: msg.avatarUrl,
                giftName: msg.giftName,
                giftPrice: coinValue,
                uid: msg.effectiveUid,
                originalDanmakuId: msg.id,
                userGiftValue: self.songCardManager.userGiftPool[msg.authorName] ?? 0
            )

            let prefix = "🎁 感谢 \(msg.authorName) 送出 \(msg.giftName)"
            self.postMarquee("\(prefix) ×\(msg.num)", type: .gift, mergeKey: "gift_\(msg.authorName)_\(msg.giftName)", mergeCount: msg.num, textPrefix: prefix)
            if coinValue > 0 {
                let name = msg.authorName
                self.songCardManager.userGiftPool[name, default: 0] += coinValue
                if let index = self.songCardManager.findSongIndex(byName: name) {
                    _ = self.songCardManager.updateGiftValue(name: name, delta: coinValue)
                    let lockedEnd = self.songCardManager.lockedEndIndex
                    if index >= lockedEnd {
                        self.songCardManager.reorderQueueByGiftValue()
                    }
                    DebugInfoManager.logAsync("[礼物追踪] \(name) 累积 \(self.songCardManager.userGiftPool[name] ?? 0) 金瓜子")
                } else {
                    self.scheduleRefreshLeftPanel()
                    self.songCardManager.scheduleSave()
                }
            }
        }

        blivechatClient.onSuperChat = { [weak self] msg in
            guard let self = self else { return }
            DebugInfoManager.logAsync("[SC] \(msg.authorName): ¥\(msg.price) \(msg.content)")

            _ = danmakuBuffer.addEntry(
                type: .sc,
                username: msg.authorName,
                content: msg.content,
                timestamp: msg.timestamp,
                avatarUrl: msg.avatarUrl,
                giftPrice: msg.price,
                uid: msg.effectiveUid,
                originalDanmakuId: msg.id,
                userGiftValue: self.songCardManager.userGiftPool[msg.authorName] ?? 0
            )

            self.handleSuperChatForSongRequest(msg)
        }

        blivechatClient.onMember = { [weak self] msg in
            guard let self = self else { return }
            let name = msg.authorName
            let coinValue = 198 * 1000
            self.songCardManager.userGiftPool[name, default: 0] += coinValue
            if let index = self.songCardManager.findSongIndex(byName: name) {
                _ = self.songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = self.songCardManager.lockedEndIndex
                if index >= lockedEnd {
                    self.songCardManager.reorderQueueByGiftValue()
                }
            } else {
                self.scheduleRefreshLeftPanel()
                self.songCardManager.scheduleSave()
            }
            DebugInfoManager.logAsync("[上舰] \(msg.authorName)")

            _ = danmakuBuffer.addEntry(
                type: .member,
                username: msg.authorName,
                content: "上舰了",
                timestamp: msg.timestamp,
                avatarUrl: msg.avatarUrl,
                giftPrice: msg.price,
                uid: msg.effectiveUid,
                originalDanmakuId: msg.id,
                userGiftValue: self.songCardManager.userGiftPool[msg.authorName] ?? 0
            )

            self.postMarquee("⭐ \(msg.authorName) 上舰了!", type: .member)
        }

        blivechatClient.onError = { error in
            DebugInfoManager.logAsync("[blivechat错误] code=\(error.code) \(error.message)")
        }

        blivechatClient.onReconnectLog = { message in
            DebugInfoManager.logAsync(message)
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

            if Config.songRequestPaused {
                let giftValue = songCardManager.userGiftPool[name] ?? 0
                let thresholdCoins = Config.songRequestPauseThreshold * 1000
                if giftValue < thresholdCoins {
                    DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: msg.id, status: "rejected_paused")
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.debug.log("[点歌] 🚫 \(name) 点歌已暂停，送礼值不足(\(giftValue)/\(thresholdCoins))")
                        self.postMarquee("🚫 \(name) 点歌已暂停，SC点歌仍可使用", type: .songFailure)
                    }
                    return
                }
            }

            let songCount = songDatabase.songCount
            Task { @MainActor [weak self] in
                self?.debug.log("[点歌] 解析: query=\"\(query)\" original=\"\(originalQuery)\" diff=\(diffInput ?? "nil") chart=\(chartTypePreference ?? "nil") db=\(songCount)")
            }

            guard !songCardManager.hasSongInQueue(name: name) else {
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: msg.id, status: "rejected_duplicate")
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.debug.log("[点歌] \(name) 已有歌曲在队列中")
                    self.postMarquee("❌ \(name) 已有歌曲在队列中", type: .songFailure)
                }
                return
            }

            var candidates = songDatabase.findCandidates(query: originalQuery)
            var resolvedDiffInput: String? = nil
            var resolvedChartTypePreference: String? = nil
            if !candidates.candidates.isEmpty && originalQuery != query {
                // Whole-query match succeeded; keep chart/difficulty filters disabled.
            } else {
                candidates = songDatabase.findCandidates(query: query)
                resolvedDiffInput = diffInput
                resolvedChartTypePreference = chartTypePreference
            }

            if candidates.candidates.isEmpty {
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: msg.id, status: "rejected_not_found")
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
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
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: msg.id, status: "rejected_no_match")
                let candidateCount = candidates.candidates.count
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.debug.log("[点歌] 候选\(candidateCount)首但无法选择")
                    self.postMarquee("❌ \(name) 无法匹配歌曲", type: .songFailure)
                }
                return
            }

            let targetDiffNum = songDatabase.resolveDiffInput(resolvedDiffInput)
            guard let noteResult = songDatabase.findNote(song: song, targetDiffNum: targetDiffNum) else {
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: msg.id, status: "rejected_no_diff")
                let songTitle = song.title
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.debug.log("[点歌] \(songTitle) 没有可用难度")
                    self.postMarquee("❌ \(name): \(songTitle) 没有可用难度", type: .songFailure)
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

            let songTitle = song.title
            let matchKind = candidates.matchKind?.rawValue ?? "?"
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.addSongToQueue(cardData)

                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: msg.id, status: "success")

                let giftTag = giftVal > 0 ? " [🎁\(giftVal)]" : ""
                self.debug.log("[点歌] ✅ \(name) → \(songTitle) (\(ctDisplay) \(diffName) \(levelStr)) [\(matchKind)]\(giftTag)")
                self.postMarquee("🎵 \(name) 点歌 \(songTitle) (\(ctDisplay) \(diffName) \(levelStr))", type: .songSuccess)
            }

        case .notACommand:
            break
        case .cancelRequest:
            break
        }
    }

    func handleCancelSongRequest(_ msg: DanmakuMessage) {
        let name = msg.authorName

        guard let index = songCardManager.findSongIndex(byName: name) else {
            let danmakuId = msg.id
            DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: danmakuId, status: "rejected_not_found")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.debug.log("[取消] ❌ \(name) 没有在队列中的歌曲")
                self.postMarquee("❌ \(name) 没有在队列中的歌曲", type: .songFailure)
            }
            return
        }

        let removedSong = songCardManager.queue[index]
        let giftVal = removedSong.giftValue
        let danmakuId = msg.id
        let removedSongName = removedSong.songName

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.songCardManager.removeSong(at: index, preserveGift: true)

            DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: danmakuId, status: "cancelled")

            let giftTag = giftVal > 0 ? "，礼物值已保留" : ""
            self.debug.log("[取消] 🗑 \(name) 取消了点歌 \(removedSongName)\(giftTag)")
            self.postMarquee("🗑 \(name) 取消了点歌\(giftTag)", type: .songFailure)
        }
    }

    func handleSuperChatForSongRequest(_ sc: SuperChatMessage) {
        let result = danmakuParser.parse(sc.content)

        switch result.type {
        case .songRequest(let query, let diffInput, let chartTypePreference):
            let name = sc.authorName
            let originalQuery = result.originalQuery

            let parseLog = "[SC点歌] 解析: query=\"\(query)\" original=\"\(originalQuery)\" diff=\(diffInput ?? "nil") chart=\(chartTypePreference ?? "nil") price=\(sc.price)"
            Task { @MainActor [weak self] in
                self?.debug.log(parseLog)
            }

            if songCardManager.hasSongInQueue(name: name) {
                let coinValue = sc.price * 1000
                songCardManager.userGiftPool[name, default: 0] += coinValue
                _ = songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = songCardManager.lockedEndIndex
                if let idx = songCardManager.findSongIndex(byName: name), idx >= lockedEnd {
                    songCardManager.reorderQueueByGiftValue()
                }
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: sc.id, status: "rejected_duplicate")
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.debug.log("[SC点歌] \(name) 已有歌曲在队列中，SC金额累加到送礼池")
                    self.postMarquee("❌ \(name) 已有歌曲在队列中", type: .songFailure)
                }
                return
            }

            if Config.songRequestPaused {
                let currentGiftValue = songCardManager.userGiftPool[name] ?? 0
                let totalWithSC = currentGiftValue + sc.price * 1000
                let thresholdCoins = Config.songRequestPauseThreshold * 1000
                if totalWithSC < thresholdCoins {
                    songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                    songCardManager.scheduleSave()
                    DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: sc.id, status: "rejected_paused")
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.debug.log("[SC点歌] 🚫 \(name) 点歌已暂停，送礼值不足(\(totalWithSC)/\(thresholdCoins))")
                        self.postMarquee("🚫 \(name) 点歌已暂停，SC点歌仍可使用", type: .songFailure)
                    }
                    return
                }
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
                songCardManager.scheduleSave()
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: sc.id, status: "rejected_not_found")
                let logText = "[SC点歌] 未找到歌曲: \"\(query)\"，SC金额累积到送礼池"
                let marqueeText = "❌ \(name) 未找到\"\(query)\""
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.debug.log(logText)
                    self.postMarquee(marqueeText, type: .songFailure)
                }
                return
            }

            guard let song = songDatabase.pickByChartType(
                candidates: candidates.candidates,
                chartTypePreference: resolvedChartTypePreference,
                diffInput: resolvedDiffInput
            ) else {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                songCardManager.scheduleSave()
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: sc.id, status: "rejected_no_match")
                let candidateCount = candidates.candidates.count
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.debug.log("[SC点歌] 候选\(candidateCount)首但无法选择，SC金额累积到送礼池")
                    self.postMarquee("❌ \(name) 无法匹配歌曲", type: .songFailure)
                }
                return
            }

            let targetDiffNum = songDatabase.resolveDiffInput(resolvedDiffInput)
            guard let noteResult = songDatabase.findNote(song: song, targetDiffNum: targetDiffNum) else {
                songCardManager.userGiftPool[name, default: 0] += sc.price * 1000
                songCardManager.scheduleSave()
                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: sc.id, status: "rejected_no_diff")
                let songTitle = song.title
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.debug.log("[SC点歌] \(songTitle) 没有可用难度，SC金额累积到送礼池")
                    self.postMarquee("❌ \(name): \(songTitle) 没有可用难度", type: .songFailure)
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

            let songTitle = song.title
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.addSongToQueue(cardData)

                DanmakuBufferManager.shared.updateSongRequestStatus(originalDanmakuId: sc.id, status: "success")

                let giftTag = giftVal > 0 ? " [🎁\(giftVal)]" : ""
                self.debug.log("[SC点歌] ✅ \(name) → \(songTitle) (\(ctDisplay) \(diffName) \(levelStr))\(giftTag)")
                self.postMarquee("💰 \(name) SC点歌 \(songTitle) (\(ctDisplay) \(diffName) \(levelStr))", type: .superChat)
            }

        case .notACommand:
            let name = sc.authorName
            let coinValue = sc.price * 1000
            let price = sc.price
            songCardManager.userGiftPool[name, default: 0] += coinValue
            let trackedGiftValue: Int?
            if let index = songCardManager.findSongIndex(byName: name) {
                _ = songCardManager.updateGiftValue(name: name, delta: coinValue)
                let lockedEnd = songCardManager.lockedEndIndex
                if index >= lockedEnd {
                    songCardManager.reorderQueueByGiftValue()
                }
                trackedGiftValue = songCardManager.userGiftPool[name] ?? 0
            } else {
                trackedGiftValue = nil
                songCardManager.scheduleSave()
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let trackedGiftValue {
                    self.debug.log("[SC追踪] \(name) 累积 \(trackedGiftValue) 金瓜子")
                }
                self.postMarquee("💰 感谢 \(name) 的SC ¥\(price)", type: .superChat)
            }
        case .cancelRequest:
            break
        }
    }

    @MainActor func connectBlivechat() {
        Config.blivechatServer = blivechatServer.rawValue
        Config.blivechatIdentityCode = blivechatIdentityCode
        blivechatConnectGeneration += 1
        let connectGeneration = blivechatConnectGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.ensureSongDatabaseLoaded()
            guard self.blivechatConnectGeneration == connectGeneration else { return }
            guard self.songDatabase.songCount > 0 else { return }

            self.debug.log("[曲库] 已加载: \(self.songDatabase.songCount) 首歌曲")
            self.blivechatClient.connect(
                server: self.blivechatServer,
                roomKeyType: .authCode,
                roomKeyValue: self.blivechatIdentityCode
            )

            self.observeBlivechatState()
        }
    }

    @MainActor func disconnectBlivechat() {
        blivechatConnectGeneration += 1
        blivechatClient.disconnect()
        blivechatConnectionState = .disconnected
    }

    @MainActor func restoreQueueFromSnapshot() {
        guard let snapshot = QueuePersistenceManager.shared.load() else { return }
        songCardManager.restoreFromSnapshot(snapshot)
        songCardManager.forceSave()
        debug.log("[持久化] 已恢复队列: \(snapshot.queue.count) 首歌曲")
    }

    @MainActor func restoreGiftValuesOnlyFromSnapshot() {
        guard let snapshot = QueuePersistenceManager.shared.load() else { return }
        songCardManager.restoreGiftValuesOnly(from: snapshot)
        discardSnapshot()
        let count = Self.preservableGiftValueCount(from: snapshot)
        debug.log("[持久化] 已继承\(count)位用户的礼物值")
    }

    @MainActor func restoreAllGiftValuesFromSnapshot() {
        guard let snapshot = QueuePersistenceManager.shared.load() else { return }
        songCardManager.restoreAllGiftValues(from: snapshot)
        discardSnapshot()
        let count = Self.allPreservableGiftValueCount(from: snapshot)
        debug.log("[持久化] 已继承全部\(count)位用户的礼物值")
    }

    @MainActor func discardSnapshot() {
        QueuePersistenceManager.shared.clearSnapshot()
    }

    static func makeRestoreSnapshotInfo() -> QueueSnapshotRestoreInfo? {
        guard let snapshot = QueuePersistenceManager.shared.load() else { return nil }
        return QueueSnapshotRestoreInfo(
            ageText: snapshotAgeString(savedAt: snapshot.savedAt),
            pendingGiftUserCount: preservableGiftValueCount(from: snapshot),
            allGiftUserCount: allPreservableGiftValueCount(from: snapshot)
        )
    }

    private static func preservableGiftValueCount(from snapshot: QueueSnapshot) -> Int {
        let startIndex = snapshot.currentIndex + 1
        guard startIndex < snapshot.queue.count else { return 0 }
        var names = Set<String>()
        for i in startIndex..<snapshot.queue.count {
            let song = snapshot.queue[i]
            if let name = song.requesterName, song.giftValue > 0 {
                names.insert(name)
            }
        }
        return names.count
    }

    private static func allPreservableGiftValueCount(from snapshot: QueueSnapshot) -> Int {
        var playedNames = Set<String>()
        if snapshot.currentIndex >= 0 {
            for i in 0...snapshot.currentIndex where i < snapshot.queue.count {
                if let name = snapshot.queue[i].requesterName {
                    playedNames.insert(name)
                }
            }
        }
        return snapshot.userGiftPool.filter { $0.value > 0 && !playedNames.contains($0.key) }.count
    }

    private static func snapshotAgeString(savedAt: Date) -> String {
        let age = max(0, Date().timeIntervalSince(savedAt))
        if age < 60 { return L10n.string("time.seconds.ago", Int(age)) }
        if age < 3600 { return L10n.string("time.minutes.ago", Int(age / 60)) }
        if age < 86400 { return L10n.string("time.hours.ago", Int(age / 3600)) }
        return L10n.string("time.days.ago", Int(age / 86400))
    }

    private func observeBlivechatState() {
        guard !isObservingBlivechatState else { return }
        isObservingBlivechatState = true

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

    @MainActor private func preloadSongDatabaseIfNeeded() {
        guard songDatabase.songCount == 0, songDatabaseLoadTask == nil else { return }

        Task { @MainActor [weak self] in
            await self?.ensureSongDatabaseLoaded()
        }
    }

    @MainActor private func ensureSongDatabaseLoaded() async {
        if songDatabase.songCount > 0 { return }

        if let task = songDatabaseLoadTask {
            await task.value
            return
        }

        debug.log("[曲库] 后台加载中...")
        let task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                SongDatabase.makeBundleSnapshot()
            }.value
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard !Task.isCancelled else {
                    self.songDatabaseLoadTask = nil
                    return
                }
                self.songDatabase.install(result)
                if self.songDatabase.songCount == 0 {
                    self.debug.log("[曲库] ❌ 加载失败: \(self.songDatabase.lastError ?? "unknown")")
                } else {
                    self.debug.log("[曲库] 加载完成: \(self.songDatabase.songCount) 首歌曲")
                }
                self.songDatabaseLoadTask = nil
            }
        }
        songDatabaseLoadTask = task
        await task.value
    }

    @MainActor func findSongCandidates(query: String) async -> FindCandidatesResult {
        await ensureSongDatabaseLoaded()
        return songDatabase.findCandidates(query: query)
    }

    @MainActor func start() {
        let lensCfg = LensCalibration.config(for: selectedLens, inputWidth: Config.inputWidth)
        let stab = MetalStabilizer(device: device, commandQueue: sharedCommandQueue, lensConfig: lensCfg)
        stab?.stabilizerEnabled = stabEnabled
        stab?.activitySmoothFactor = activitySmoothFactor
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

        let marqueeManager = MarqueeManager()
        let marqueeRenderer = MarqueeRenderer(device: device)
        self.marqueeManager = marqueeManager
        self.marqueeRenderer = marqueeRenderer
        self.marqueeCompositor = MarqueeCompositor(device: device, manager: marqueeManager, renderer: marqueeRenderer)

        let deviceStatusManager = DeviceStatusManager()
        let deviceStatusRenderer = DeviceStatusRenderer(device: device)
        self.deviceStatusManager = deviceStatusManager
        self.deviceStatusRenderer = deviceStatusRenderer
        self.deviceStatusCompositor = DeviceStatusCompositor(device: device, manager: deviceStatusManager, renderer: deviceStatusRenderer)
        deviceStatusManager.startMonitoring()

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

        preloadSongDatabaseIfNeeded()

        camera.onVideoFrame = { [weak self] pixelBuffer, alignedTime in
            let pipelineEnterTime = CACurrentMediaTime()
            let manager = WeakLivePipelineManager(self)
            let frame = SendablePixelBuffer(value: pixelBuffer)
            self?.pipelineQueue.async {
                autoreleasepool {
                guard let self = manager.value else { return }
                let pixelBuffer = frame.value
                self.frameCount += 1
                guard let stab = self.stabilizer, stab.stabilizerEnabled else { return }

                let centerTime = alignedTime + (Config.syncOffsetMs / 1000.0)
                let topTime    = centerTime - (Config.readoutTimeMs / 2000.0)
                let bottomTime = centerTime + (Config.readoutTimeMs / 2000.0)

                guard let qCenter = MotionManager.shared.getQuaternion(at: centerTime),
                      let qTop    = MotionManager.shared.getQuaternion(at: topTime),
                      let qBottom = MotionManager.shared.getQuaternion(at: bottomTime) else { return }

                // 磁力计 & Yaw 诊断数据
                let magAccuracy = MotionManager.shared.latestMagneticAccuracy
                let alignedQC = MetalStabilizer.alignIMU(qCenter)
                let rawYaw = MotionManager.extractYaw(from: alignedQC) * 180.0 / .pi

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
                    if self.yoloEnabled {
                        track = self.bboxTracker.freeze()
                    } else {
                        track = self.bboxTracker.update(detected: false, stabCx: 0, stabCy: 0, stabW: 0, stabH: 0)
                        self.latestTrackOutput = track
                    }
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
                    snapshot.magneticAccuracy = magAccuracy
                    snapshot.rawYawDeg = rawYaw
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

                    let completionManager = WeakLivePipelineManager(self)
                    cmdBuf.addCompletedHandler { _ in
                        if let pool = completionManager.value?.ioSurfacePool, let idx = pool.indexOfBuffer(writeBuffer) {
                            pool.notifyBufferCompleted(idx)
                        }
                        completionManager.value?.pipelineQueue.async {
                            guard let self = completionManager.value else { return }
                            self.streamFrameCount += 1
                            let pipelineLatencyMs = (CACurrentMediaTime() - pipelineEnterTime) * 1000.0
                            self.onStreamBufferAvailable?(writeBuffer.pixelBuffer, timestamp)
                            self.streamManager.appendVideo(pixelBuffer: writeBuffer.pixelBuffer, timestamp: timestamp)
                            let audioDepth = self.streamManager.audioSyncQueueDepth
                            DispatchQueue.main.async {
                                self.lagMs = pipelineLatencyMs
                                self.debug.stageLagData(ms: pipelineLatencyMs, audioDepth: audioDepth)
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
        songCardManager.startExpirationTimer()
    }

    func stop() {
        songDatabaseLoadTask?.cancel()
        songDatabaseLoadTask = nil
        camera.onVideoFrame = nil
        camera.onAudioSample = nil
        camera.stopRunning()
        MotionManager.shared.stopUpdates()
        webServerManager.stop()
        stopFPSTimer()
        songCardManager.stopExpirationTimer()
        Task { @MainActor [weak self] in
            self?.deviceStatusManager?.stopMonitoring()
            self?.debug.stopFlushTimer()
        }
    }

    private func startFPSTimer() {
        let manager = WeakLivePipelineManager(self)
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            manager.value?.pipelineQueue.async {
                guard let self = manager.value else { return }
                let count = self.frameCount
                let streamCount = self.streamFrameCount
                let yoloActualFPS = self.yoloDetector?.actualFPS ?? 0
                self.frameCount = 0
                self.streamFrameCount = 0
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentFPS = Double(count)
                    self.debug.fps = Double(count)
                    self.debug.frameCount = count
                    self.debug.streamInfo = "\(streamCount) bufs/s \(Config.outputWidth)x\(Config.outputHeight)"
                    self.debug.yoloActualFPS = yoloActualFPS
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

    func updateActivityMode() {
        stabilizer?.activityMode = activityMode
    }

    func updateActivitySmoothFactor() {
        Config.activitySmoothFactor = activitySmoothFactor
        stabilizer?.activitySmoothFactor = activitySmoothFactor
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
    }

    func onGiftValueChanged(_ song: SongCardData, queueIndex: Int) {
        scheduleRefreshLeftPanel()
    }

    func onSongsExpired(_ songs: [SongCardData]) {
        for song in songs {
            let name = song.requesterName ?? "未知"
            let title = song.songName
            postMarquee("⏰ 超过15分钟未互动 \(name) 的 \(title) 已过期，欢迎重新点歌～", type: .songExpired)
        }
    }

    func triggerSongCardSwitch() {
        guard leftPanelCompositor != nil else { return }

        let newCurrentData = songCardManager.nextSong
        isSwitchingSong = true

        if let data = newCurrentData {
            if let musicId = data.musicId {
                Task { [weak self] in
                    let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
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
                Task { @MainActor [weak self] in
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
            Task { @MainActor [weak self] in
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
        Task { @MainActor [weak self] in
            self?.rightPanelRenderer?.invalidateCache()
            self?.leftPanelRenderer?.invalidateCache()
        }
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
        guard leftPanelRenderer != nil, leftPanelCompositor != nil else { return }

        if let song = song {
            if let musicId = song.musicId {
                Task { [weak self] in
                    let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                    await MainActor.run { [weak self] in
                        guard let self = self,
                              let renderer = self.leftPanelRenderer,
                              let compositor = self.leftPanelCompositor else { return }
                        renderer.renderCurrentSong(song, coverBase64: base64) { texture in
                            if let texture = texture {
                                compositor.setCurrentSong(texture: texture, data: song)
                            }
                        }
                    }
                }
            } else {
                Task { @MainActor [weak self] in
                    guard let self = self,
                          let renderer = self.leftPanelRenderer,
                          let compositor = self.leftPanelCompositor else { return }
                    renderer.renderCurrentSong(song, coverBase64: nil) { texture in
                        if let texture = texture {
                            compositor.setCurrentSong(texture: texture, data: song)
                        }
                    }
                }
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self = self,
                      let renderer = self.leftPanelRenderer,
                      let compositor = self.leftPanelCompositor else { return }
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
        Task { @MainActor [weak self] in
            guard let self = self,
                  let renderer = self.leftPanelRenderer,
                  let compositor = self.leftPanelCompositor else { return }
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
            let manager = WeakLivePipelineManager(self)
            Task { @MainActor in
                renderer.renderTitle { texture in
                    manager.value?.rightPanelCompositor?.updateTitleTexture(texture)
                }
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
        guard rightPanelRenderer != nil else { return }

        if rightPanelCompositor?.getRowDataForId(song.id) != nil {
            return
        }

        if let musicId = song.musicId {
            Task { [weak self] in
                let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.rightPanelRenderer?.renderRow(data: song, queueIndex: queueIndex, coverBase64: base64) { [weak self] _, texture in
                        guard let self = self, let texture = texture else { return }
                        if self.rightPanelCompositor?.getRowDataForId(song.id) != nil { return }
                        self.rightPanelCompositor?.addRowAtBottom(texture: texture, data: song, queueIndex: queueIndex)
                    }
                }
            }
        } else {
            Task { @MainActor [weak self] in
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
        let manager = WeakLivePipelineManager(self)
        Task { @MainActor in
            renderer.renderTitle { texture in
                manager.value?.rightPanelCompositor?.updateTitleTexture(texture)
            }
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
                let finalNeededOffset = neededOffset

                let gen = rightPanelGeneration
                compositor.animateScrollTo(targetOffset: oldNeededOffset, duration: 0.3, isPreScroll: true) { [weak self] in
                    guard let self = self else { return }
                    guard self.rightPanelGeneration == gen else { return }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        guard let self = self else { return }
                        guard self.rightPanelGeneration == gen else { return }

                        let currentAfterPreScroll = self.rightPanelCompositor?.currentScrollOffset ?? currentOffset
                        let targetScrollOffset = abs(finalNeededOffset - currentAfterPreScroll) > 0.01 ? finalNeededOffset : nil
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
                    Task { [weak self] in
                        let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                        await MainActor.run { [weak self] in
                            guard let self = self,
                                  let renderer = self.rightPanelRenderer,
                                  let compositor = self.rightPanelCompositor else { return }
                            renderer.renderRow(data: song, queueIndex: item.queueIndex, coverBase64: base64) { _, texture in
                                if let texture = texture {
                                    compositor.updateRowTexture(bySongId: songId, texture: texture)
                                }
                            }
                        }
                    }
                } else {
                    Task { @MainActor in
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

        let renderedTextures = LockedTextureMap()
        let group = DispatchGroup()
        let currentGeneration = rightPanelGeneration

        for item in newRowsNeedTexture {
            group.enter()
            let queueIndex = item.queueIndex
            let song = item.data
            if let musicId = song.musicId {
                Task { [weak self] in
                    let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                    await MainActor.run { [weak self] in
                        guard let self = self,
                              let renderer = self.rightPanelRenderer else {
                            group.leave()
                            return
                        }
                        renderer.renderRow(data: song, queueIndex: queueIndex, coverBase64: base64) { _, texture in
                            if let texture = texture {
                                renderedTextures.set(texture, for: queueIndex)
                            }
                            group.leave()
                        }
                    }
                }
            } else {
                Task { @MainActor in
                    renderer.renderRow(data: song, queueIndex: queueIndex, coverBase64: nil) { _, texture in
                        if let texture = texture {
                            renderedTextures.set(texture, for: queueIndex)
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.rightPanelGeneration == currentGeneration else { return }
            compositor.reorderRows(newOrder: newOrder, textures: renderedTextures.snapshot(), targetScrollOffset: targetScrollOffset)

            for item in existingGiftChanged {
                let song = item.data
                let songId = song.id
                if let musicId = song.musicId {
                    Task { [weak self] in
                        let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                        await MainActor.run { [weak self] in
                            guard let self = self,
                                  let renderer = self.rightPanelRenderer,
                                  let compositor = self.rightPanelCompositor else { return }
                            renderer.renderRow(data: song, queueIndex: item.queueIndex, coverBase64: base64) { _, texture in
                                if let texture = texture {
                                    compositor.updateRowTexture(bySongId: songId, texture: texture)
                                }
                            }
                        }
                    }
                } else {
                    Task { @MainActor in
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

        Task { @MainActor [weak self] in
            renderer.renderTitle { texture in
                guard let self = self else { return }
                self.rightPanelCompositor?.updateTitleTexture(texture)

                Task { [weak self] in
                    let covers = await Self.loadCovers(for: allRightPanelSongs, startQueueIndex: startQueueIndex)
                    await MainActor.run { [weak self] in
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
        }
    }

    private static func loadCovers(for songs: [SongCardData], startQueueIndex: Int) async -> [Int: String] {
        await withTaskGroup(of: (Int, String?).self, returning: [Int: String].self) { group in
            for (index, song) in songs.enumerated() {
                guard let musicId = song.musicId else { continue }
                let queueIndex = startQueueIndex + index
                group.addTask {
                    let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                    return (queueIndex, base64)
                }
            }

            var covers: [Int: String] = [:]
            for await (queueIndex, base64) in group {
                if let base64 = base64 {
                    covers[queueIndex] = base64
                }
            }
            return covers
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

        Task { @MainActor [weak self] in
            renderer.invalidateCache()
            self?.leftPanelRenderer?.invalidateCache()
        }

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
                Task { [weak self] in
                    let base64 = await CoverImageLoader.shared.loadCoverBase64(musicId: musicId)
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
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
                Task { @MainActor [weak self] in
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
