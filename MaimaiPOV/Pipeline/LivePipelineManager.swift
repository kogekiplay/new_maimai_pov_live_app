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

    @Published var cropVerticalOffset: Float = Config.cropVerticalOffset

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
    let songCardManager = SongCardManager()
    var bboxTracker = BBoxTracker()
    var latestTrackOutput: BBoxTracker.TrackOutput?

    var onStreamBufferAvailable: ((CVPixelBuffer, CMTime) -> Void)?
    var onAudioSampleAvailable: ((CMSampleBuffer, Double) -> Void)?

    var previewTexture: MTLTexture? {
        if previewEnabled {
            if let pool = ioSurfacePool, let buf = pool.lastCompletedBuffer {
                return buf.texture
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

    var isCropActive: Bool { cropRenderer != nil }

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
                } else if let cr = self.cropRenderer {
                    let fb = cr.makeFallbackTrack()
                    track = BBoxTracker.TrackOutput(
                        cx: fb.cx, cy: fb.cy, cropW: fb.cropW, cropH: fb.cropH,
                        detected: false, state: "fallback"
                    )
                } else {
                    let stabW = Float(Config.stabWidth)
                    let stabH = Float(Config.stabHeight)
                    let outputRatio = Float(Config.outputWidth) / Float(Config.outputHeight)
                    track = BBoxTracker.TrackOutput(
                        cx: stabW / 2.0, cy: stabH / 2.0,
                        cropW: stabH * outputRatio, cropH: stabH,
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

                let offsetCy = track.cy + self.cropVerticalOffset

                if let pool = self.ioSurfacePool,
                   let cr = self.cropRenderer,
                   let writeBuffer = pool.nextWriteBuffer() {
                    let timestamp = CMTime(seconds: alignedTime, preferredTimescale: 1000000000)

                    guard let cmdBuf = self.sharedCommandQueue.makeCommandBuffer(),
                          let encoder = cmdBuf.makeComputeCommandEncoder() else {
                        cr.process(
                            stabTexture: stab.outputTexture,
                            cx: track.cx, cy: offsetCy,
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
                              cx: track.cx, cy: offsetCy,
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
                        let offsetCy = track.cy + self.cropVerticalOffset
                        cr.process(stabTexture: stab.outputTexture,
                                   cx: track.cx, cy: offsetCy,
                                   cropW: track.cropW, cropH: track.cropH)
                    } else {
                        let fb = cr.makeFallbackTrack()
                        let offsetCy = fb.cy + self.cropVerticalOffset
                        cr.process(stabTexture: stab.outputTexture,
                                   cx: fb.cx, cy: offsetCy,
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

    @MainActor func updateCropVerticalOffset() {
        Config.cropVerticalOffset = cropVerticalOffset
        debug.cropVerticalOffset = cropVerticalOffset
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
            renderer.renderCard(data: data) { [weak self] texture in
                guard let self = self, let texture = texture else { return }
                self.songCardCompositor?.switchToNext(newCardTexture: texture, newCardData: data)
                self.songCardManager.switchToNext()
            }
        } else {
            songCardCompositor?.switchToNext()
            songCardManager.switchToNext()
        }
    }

    func addSongToQueue(_ song: SongCardData) {
        guard let compositor = songCardCompositor else { return }

        songCardManager.addSong(song)

        if compositor.cards.count < SongCardCompositor.slots.count {
            compositor.renderer?.renderCard(data: song) { [weak self] texture in
                guard let self = self, let texture = texture else { return }
                if self.songCardCompositor?.cards.count ?? 0 < SongCardCompositor.slots.count {
                    self.songCardCompositor?.addCard(texture: texture, data: song)
                }
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
            compositor.renderer?.renderCard(data: displayData[i]) { texture in
                textures[i] = texture
                group.leave()
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
}
