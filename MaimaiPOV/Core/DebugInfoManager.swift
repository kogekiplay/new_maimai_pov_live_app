import SwiftUI

@MainActor
class DebugInfoManager: ObservableObject {
    static let shared = DebugInfoManager()

    var isDetailVisible: Bool = false
    var isStreaming: Bool = false

    var shouldThrottle: Bool {
        isStreaming || !isDetailVisible
    }

    @Published var fps: Double = 0
    @Published var pipelineLagMs: Double = 0
    @Published var audioQueueDepth: Int = 0
    @Published var yoloLagMs: Double = 0
    @Published var frameCount: Int = 0

    @Published var fov: Float = 0
    @Published var distRatio: Float = 0
    @Published var stabEnabled: Bool = true
    @Published var lensType: String = "main"

    @Published var yoloDetected: Bool = false
    @Published var yoloConfidence: Float = 0
    @Published var yoloBbox: String = "--"
    @Published var yoloInferenceMs: Double = 0
    @Published var yoloPreprocessMs: Double = 0
    @Published var yoloPadding: Int = Config.defaultYoloPadding
    @Published var yoloRawCoord: String = "--"
    @Published var yoloStabCoord: String = "--"
    @Published var yoloUniforms: String = "--"
    @Published var yoloBoxesInfo: String = "--"
    @Published var yoloTopBoxes: String = "--"
    @Published var yoloBestRank: Int = 0
    @Published var yoloPreviewImage: UIImage?
    
    @Published var yoloStabCx: Float = 0
    @Published var yoloStabCy: Float = 0
    @Published var yoloStabW: Float = 0
    @Published var yoloStabH: Float = 0
    @Published var yoloOverlayEnabled: Bool = Config.defaultYoloOverlayEnabled
    @Published var yoloOverlayScale: Double = Config.defaultYoloOverlayScale
    @Published var yoloTargetFPS: Double = Config.defaultYoloTargetFPS
    @Published var yoloActualFPS: Double = 0

    @Published var trackCx: Float = 0
    @Published var trackCy: Float = 0
    @Published var trackCropW: Float = 0
    @Published var trackCropH: Float = 0
    @Published var trackState: String = "idle"
    @Published var trackTargetRatio: Float = Float(Config.defaultTargetRatio)
    @Published var trackRecenterSpeed: Float = Float(Config.defaultRecenterSpeed)
    @Published var trackRawW: Float = 0
    @Published var trackRawH: Float = 0
    @Published var trackSmoothSize: Float = 0
    @Published var trackTrust: Float = 1.0
    @Published var trackAspectRatio: Float = 1.0

    @Published var cropHorizontalOffset: Float = 0

    @Published var logMessages: [String] = []
    @Published var streamInfo: String = "--"
    private let maxLogMessages = 30

    @Published var rtmpStatus: String = "Idle"
    @Published var rtmpBitrate: Int = 0
    @Published var rtmpFPS: Int = 0
    @Published var deviceTemperature: Double = 0.0
    @Published var streamingDuration: String = "--"

    struct FrameDebugData {
        var hasYoloResult: Bool = false
        var yoloDetected: Bool = false
        var yoloConfidence: Float = 0
        var yoloInferenceMs: Double = 0
        var yoloPreprocessMs: Double = 0
        var rawYoloCx: Float = 0
        var rawYoloCy: Float = 0
        var rawYoloW: Float = 0
        var rawYoloH: Float = 0
        var stabCx: Float = 0
        var stabCy: Float = 0
        var stabW: Float = 0
        var stabH: Float = 0
        var innerScreenBoxesCount: Int = 0
        var allBoxesCount: Int = 0
        var topBoxes: String = "--"
        var bestBoxRank: Int = 0
        var yoloPreviewImage: UIImage?
        var trackCx: Float = 0
        var trackCy: Float = 0
        var trackCropW: Float = 0
        var trackCropH: Float = 0
        var trackState: String = "idle"
        var trackRawW: Float = 0
        var trackRawH: Float = 0
        var trackSmoothSize: Float = 0
        var trackTrust: Float = 1.0
        var trackAspectRatio: Float = 1.0
        var pipelineLagMs: Double = 0
        var audioQueueDepth: Int = 0
    }

    private var stagingData: FrameDebugData?
    private var stagingLock = os_unfair_lock_s()
    private var flushTimer: Timer?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func log(_ msg: String) {
        let timestamp = timeFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(msg)"
        logMessages.append(entry)
        if logMessages.count > maxLogMessages {
            logMessages.removeFirst(logMessages.count - maxLogMessages)
        }
    }

    /// 从非 MainActor 上下文安全调用 log
    nonisolated func logAsync(_ msg: String) {
        let msg = msg
        Task { @MainActor in
            DebugInfoManager.shared.log(msg)
        }
    }

    func stageFrameData(_ data: FrameDebugData) {
        os_unfair_lock_lock(&stagingLock)
        stagingData = data
        os_unfair_lock_unlock(&stagingLock)
    }

    func stageLagData(ms: Double, audioDepth: Int) {
        os_unfair_lock_lock(&stagingLock)
        if stagingData == nil {
            stagingData = FrameDebugData()
        }
        stagingData!.pipelineLagMs = ms
        stagingData!.audioQueueDepth = audioDepth
        os_unfair_lock_unlock(&stagingLock)
    }

    func startFlushTimer(interval: TimeInterval = 0.5) {
        flushTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.flushStagingToPublished()
        }
    }

    func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    private func flushStagingToPublished() {
        os_unfair_lock_lock(&stagingLock)
        let data = stagingData
        os_unfair_lock_unlock(&stagingLock)

        guard let data = data else { return }

        if shouldThrottle {
            pipelineLagMs = data.pipelineLagMs
            audioQueueDepth = data.audioQueueDepth
            return
        }

        if data.hasYoloResult {
            yoloDetected = data.yoloDetected
            yoloConfidence = data.yoloConfidence
            yoloInferenceMs = data.yoloInferenceMs
            yoloPreprocessMs = data.yoloPreprocessMs
            if isDetailVisible {
                yoloRawCoord = data.yoloDetected
                    ? String(format: "%.0f,%.0f,%.0f,%.0f",
                        data.rawYoloCx, data.rawYoloCy, data.rawYoloW, data.rawYoloH)
                    : "--"
                yoloStabCoord = data.yoloDetected
                    ? String(format: "%.0f,%.0f,%.0f,%.0f",
                        data.stabCx, data.stabCy, data.stabW, data.stabH)
                    : "--"
                yoloBoxesInfo = "\(data.innerScreenBoxesCount)/\(data.allBoxesCount)"
                yoloTopBoxes = data.topBoxes
            }
            yoloStabCx = data.stabCx
            yoloStabCy = data.stabCy
            yoloStabW = data.stabW
            yoloStabH = data.stabH
            yoloBestRank = data.bestBoxRank
            yoloPreviewImage = data.yoloPreviewImage
        }
        trackCx = data.trackCx
        trackCy = data.trackCy
        trackCropW = data.trackCropW
        trackCropH = data.trackCropH
        trackState = data.trackState
        trackRawW = data.trackRawW
        trackRawH = data.trackRawH
        trackSmoothSize = data.trackSmoothSize
        trackTrust = data.trackTrust
        trackAspectRatio = data.trackAspectRatio
        pipelineLagMs = data.pipelineLagMs
        audioQueueDepth = data.audioQueueDepth
    }
}
