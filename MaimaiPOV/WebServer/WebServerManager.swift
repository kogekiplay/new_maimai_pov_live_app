import Foundation
import Swifter
import CoreImage
import UIKit

final class WebServerManager: @unchecked Sendable {
    private let server = HttpServer()
    private(set) var isRunning: Bool = false
    private(set) var serverURL: String = ""
    weak var pipeline: LivePipelineManager?

    private let queueHandler = QueueAPIHandler()
    private let searchHandler = SearchAPIHandler()
    private let debugHandler = DebugAPIHandler()
    private let danmakuBuffer = DanmakuBufferManager.shared
    private let coverResolver = CoverResourceResolver()
    private let coverCache = CoverImageCache()
    private let coverFetchTimeout: TimeInterval = 4
    private static let maxSSEConnections = 5

    func start() {
        guard !isRunning else { return }

        queueHandler.pipeline = pipeline
        searchHandler.pipeline = pipeline
        debugHandler.pipeline = pipeline

        setupRoutes()

        do {
            try server.start(8080)
            isRunning = true

            if let ip = getLocalIPAddress() {
                serverURL = "http://\(ip):8080"
            } else {
                serverURL = "http://localhost:8080"
            }

            let currentServerURL = serverURL
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.pipeline?.webServerURL = currentServerURL
                self.pipeline?.debug.log("[LAN] HTTP服务器已启动: \(currentServerURL)")
            }
        } catch {
            let errorMessage = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.pipeline?.debug.log("[LAN] HTTP服务器启动失败: \(errorMessage)")
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        server.stop()
        isRunning = false
        serverURL = ""

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.pipeline?.webServerURL = ""
            self.pipeline?.debug.log("[LAN] HTTP服务器已停止")
        }
    }

    private func setupRoutes() {
        server["/"] = { [weak self] _ in
            guard let self = self else { return .notFound }
            if let html = self.loadControlHTML() {
                return .raw(200, "OK", ["Content-Type": "text/html; charset=utf-8"]) { writer in
                    try writer.write(html)
                }
            }
            return .notFound
        }

        server["/api/queue"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            switch request.method {
            case "GET":
                return self.queueHandler.getQueue()
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/queue/skip"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.skip()
        }

        server["/api/queue/clear"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.clear()
        }

        server["/api/queue/remove"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.remove(request: request)
        }

        server["/api/queue/add"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.add(request: request)
        }

        server["/api/queue/add-for-user"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.addForUser(request: request)
        }

        server["/api/queue/cancel-for-user"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.cancelSongForUser(request: request)
        }

        server["/api/user-info"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.getUserInfo(request: request)
        }

        server["/api/search"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.searchHandler.search(request: request)
        }

        server["/api/cover/:musicId"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.serveCover(request: request)
        }

        server["/api/debug/simulate/gift"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.simulateGift(request: request)
        }

        server["/api/debug/simulate/sc"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.simulateSC(request: request)
        }

        server["/api/debug/simulate/member"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.simulateMember(request: request)
        }

        server["/api/debug/simulate/danmaku"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.simulateDanmaku(request: request)
        }

        server["/api/debug/gift-pool"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.getGiftPool()
        }

        server["/api/debug/simulate/marquee"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.simulateMarquee(request: request)
        }

        server["/api/debug/simulate/battery"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.simulateBattery(request: request)
        }

        server["/api/debug/set-expiration-timeout"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.setExpirationTimeout(request: request)
        }

        server["/api/debug/trigger-expiration-check"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.triggerExpirationCheck(request: request)
        }

        server["/api/announcement"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            switch request.method {
            case "GET":
                let text = Config.announcementText
                let data = try? JSONSerialization.data(withJSONObject: ["text": text])
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            case "POST":
                guard let bodyData = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any],
                      let text = bodyData["text"] as? String else {
                    return .badRequest(.text("Missing 'text' field"))
                }
                Config.announcementText = text
                Task { @MainActor in
                    self.pipeline?.renderLeftPanelAnnouncement()
                }
                let data = try? JSONSerialization.data(withJSONObject: ["success": true])
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/activity-mode"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            switch request.method {
            case "GET":
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    result.set([
                        "activityMode": self.pipeline?.activityMode ?? false,
                        "smoothFactor": Double(self.pipeline?.activitySmoothFactor ?? Config.activitySmoothFactor)
                    ])
                    sem.signal()
                }
                sem.wait()
                let data = try? JSONSerialization.data(withJSONObject: result.get())
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            case "POST":
                guard let bodyData = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] else {
                    return .badRequest(.text("Invalid JSON"))
                }
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    guard let pipeline = self.pipeline else {
                        result.set([
                            "success": true,
                            "activityMode": false,
                            "smoothFactor": Double(Config.activitySmoothFactor)
                        ])
                        sem.signal()
                        return
                    }

                    if let enabled = bodyData["activityMode"] as? Bool {
                        pipeline.activityMode = enabled
                        pipeline.updateActivityMode()
                    }
                    if let sf = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "smoothFactor",
                        range: WebControlInput.activitySmoothFactorRange
                    ) {
                        pipeline.activitySmoothFactor = Float(sf)
                        pipeline.updateActivitySmoothFactor()
                    }
                    result.set([
                        "success": true,
                        "activityMode": pipeline.activityMode,
                        "smoothFactor": Double(pipeline.activitySmoothFactor)
                    ])
                    sem.signal()
                }
                sem.wait()
                let data = try? JSONSerialization.data(withJSONObject: result.get())
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/song-request-config"] = { request in
            switch request.method {
            case "GET":
                let data = try? JSONSerialization.data(withJSONObject: [
                    "paused": Config.songRequestPaused,
                    "threshold": Config.songRequestPauseThreshold
                ])
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            case "POST":
                guard let bodyData = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] else {
                    return .badRequest(.text("Invalid JSON"))
                }
                if let paused = bodyData["paused"] as? Bool {
                    Config.songRequestPaused = paused
                }
                if let threshold = WebControlInput.clampedInt(
                    in: bodyData,
                    key: "threshold",
                    range: WebControlInput.songRequestPauseThresholdRange
                ) {
                    Config.songRequestPauseThreshold = threshold
                }
                let data = try? JSONSerialization.data(withJSONObject: [
                    "success": true,
                    "paused": Config.songRequestPaused,
                    "threshold": Config.songRequestPauseThreshold
                ])
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/danmaku/stream"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }

            let clientCount = self.danmakuBuffer.currentClientCount()
            if clientCount >= WebServerManager.maxSSEConnections {
                return .raw(503, "Too Many Connections", ["Content-Type": "text/plain; charset=utf-8"]) { writer in
                    try writer.write(Data("Max SSE connections reached".utf8))
                }
            }

            return .raw(200, "OK", [
                "Content-Type": "text/event-stream; charset=utf-8",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "Access-Control-Allow-Origin": "*"
            ]) { [weak self] writer in
                let semaphore = DispatchSemaphore(value: 0)

                let client = SSEClient(
                    sendCallback: { message in
                        do {
                            try writer.write(Data(message.utf8))
                            return true
                        } catch {
                            return false
                        }
                    },
                    onDisconnect: {
                        semaphore.signal()
                    }
                )
                self?.danmakuBuffer.addClient(client)

                let keepAliveTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                keepAliveTimer.schedule(deadline: .now(), repeating: 15)
                keepAliveTimer.setEventHandler {
                    guard client.isActive else {
                        keepAliveTimer.cancel()
                        return
                    }
                    client.send(": keepalive\n\n")
                }
                keepAliveTimer.resume()

                _ = semaphore.wait(timeout: .now() + 3600)

                keepAliveTimer.cancel()
                client.isActive = false
                self?.danmakuBuffer.removeClient(client)
            }
        }

        server["/api/danmaku/history"] = { [weak self] request in
            guard self != nil else { return .internalServerError }

            let sinceId = request.queryParams
                .first(where: { $0.0 == "sinceId" })
                .flatMap { URLQueryDecoder.decodeIntComponent($0.1) } ?? 0
            let entries = DanmakuBufferManager.shared.getHistory(sinceId: sinceId)

            guard let jsonData = try? JSONEncoder().encode(entries) else {
                return .internalServerError
            }
            return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                try writer.write(jsonData)
            }
        }

        server["/api/camera/settings"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            switch request.method {
            case "GET":
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    guard let pipeline = self.pipeline else { sem.signal(); return }
                    result.set([
                        "iso": pipeline.isoValue,
                        "minISO": pipeline.minISO,
                        "maxISO": pipeline.maxISO,
                        "shutterTimescale": pipeline.shutterTimescale,
                        "focusValue": pipeline.focusValue,
                        "autoFocusEnabled": pipeline.autoFocusEnabled,
                        "selectedLens": pipeline.selectedLens.rawValue,
                        "awbLocked": pipeline.camera.awbLocked
                    ])
                    sem.signal()
                }
                sem.wait()
                guard let jsonData = try? JSONSerialization.data(withJSONObject: result.get()) else {
                    return .internalServerError
                }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            case "POST":
                guard let bodyData = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] else {
                    return .badRequest(.text("Invalid JSON"))
                }
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    guard let pipeline = self.pipeline else { sem.signal(); return }
                    if let iso = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "iso",
                        range: pipeline.minISO...pipeline.maxISO
                    ) {
                        pipeline.isoValue = iso
                        pipeline.applyExposure()
                    }
                    if let shutter = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "shutterTimescale",
                        range: WebControlInput.shutterTimescaleRange
                    ) {
                        pipeline.shutterTimescale = shutter
                        pipeline.applyExposure()
                    }
                    if let focus = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "focusValue",
                        range: WebControlInput.focusValueRange
                    ) {
                        pipeline.focusValue = focus
                        pipeline.applyExposure()
                    }
                    if let autoFocus = bodyData["autoFocusEnabled"] as? Bool {
                        pipeline.autoFocusEnabled = autoFocus
                        Config.autoFocusEnabled = autoFocus
                        pipeline.camera.setAutoFocus(autoFocus)
                    }
                    if let lensType = WebControlInput.lensType(in: bodyData, key: "selectedLens") {
                        pipeline.selectedLens = lensType
                        pipeline.handleLensChange(lensType)
                    }
                    if let awbLock = bodyData["awbLocked"] as? Bool {
                        if awbLock && !pipeline.camera.awbLocked {
                            pipeline.camera.lockWhiteBalance()
                        } else if !awbLock && pipeline.camera.awbLocked {
                            pipeline.camera.unlockWhiteBalance()
                        }
                    }
                    result.set([
                        "success": true,
                        "iso": pipeline.isoValue,
                        "minISO": pipeline.minISO,
                        "maxISO": pipeline.maxISO,
                        "shutterTimescale": pipeline.shutterTimescale,
                        "focusValue": pipeline.focusValue,
                        "autoFocusEnabled": pipeline.autoFocusEnabled,
                        "selectedLens": pipeline.selectedLens.rawValue,
                        "awbLocked": pipeline.camera.awbLocked
                    ])
                    sem.signal()
                }
                sem.wait()
                guard let jsonData = try? JSONSerialization.data(withJSONObject: result.get()) else {
                    return .internalServerError
                }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/stabilizer/settings"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            switch request.method {
            case "GET":
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    guard let pipeline = self.pipeline else { sem.signal(); return }
                    result.set([
                        "stabEnabled": pipeline.stabEnabled,
                        "yaw": Double(pipeline.yaw),
                        "pitch": Double(pipeline.pitch),
                        "roll": Double(pipeline.roll),
                        "fov": Double(pipeline.fov),
                        "distRatio": Double(pipeline.distRatio),
                        "activityMode": pipeline.activityMode,
                        "activitySmoothFactor": Double(pipeline.activitySmoothFactor)
                    ])
                    sem.signal()
                }
                sem.wait()
                guard let jsonData = try? JSONSerialization.data(withJSONObject: result.get()) else {
                    return .internalServerError
                }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            case "POST":
                guard let bodyData = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] else {
                    return .badRequest(.text("Invalid JSON"))
                }
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    guard let pipeline = self.pipeline else { sem.signal(); return }
                    if let enabled = bodyData["stabEnabled"] as? Bool {
                        pipeline.stabEnabled = enabled
                        pipeline.updateStabilizerEnabled()
                    }
                    if let yaw = WebControlInput.clampedDouble(in: bodyData, key: "yaw", range: WebControlInput.yawRange) {
                        pipeline.yaw = Float(yaw)
                        pipeline.updateYaw()
                    }
                    if let pitch = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "pitch",
                        range: WebControlInput.yawRange
                    ) {
                        pipeline.pitch = Float(pitch)
                        pipeline.updatePitch()
                    }
                    if let roll = WebControlInput.clampedDouble(in: bodyData, key: "roll", range: WebControlInput.rollRange) {
                        pipeline.roll = Float(roll)
                        pipeline.updateRoll()
                    }
                    if let fov = WebControlInput.clampedDouble(in: bodyData, key: "fov", range: WebControlInput.fovRange) {
                        pipeline.fov = Float(fov)
                        pipeline.updateFov()
                    }
                    if let dist = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "distRatio",
                        range: WebControlInput.distRatioRange
                    ) {
                        pipeline.distRatio = Float(dist)
                        pipeline.updateDistRatio()
                    }
                    if let activityMode = bodyData["activityMode"] as? Bool {
                        pipeline.activityMode = activityMode
                        pipeline.updateActivityMode()
                    }
                    if let sf = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "activitySmoothFactor",
                        range: WebControlInput.activitySmoothFactorRange
                    ) {
                        pipeline.activitySmoothFactor = Float(sf)
                        pipeline.updateActivitySmoothFactor()
                    }
                    result.set([
                        "success": true,
                        "stabEnabled": pipeline.stabEnabled,
                        "yaw": Double(pipeline.yaw),
                        "pitch": Double(pipeline.pitch),
                        "roll": Double(pipeline.roll),
                        "fov": Double(pipeline.fov),
                        "distRatio": Double(pipeline.distRatio),
                        "activityMode": pipeline.activityMode,
                        "activitySmoothFactor": Double(pipeline.activitySmoothFactor)
                    ])
                    sem.signal()
                }
                sem.wait()
                guard let jsonData = try? JSONSerialization.data(withJSONObject: result.get()) else {
                    return .internalServerError
                }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/audio/gain"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            switch request.method {
            case "GET":
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    guard let pipeline = self.pipeline else { sem.signal(); return }
                    result.set([
                        "leftGain": Double(pipeline.audioMixer.leftGain),
                        "rightGain": Double(pipeline.audioMixer.rightGain),
                        "isStereoMixEnabled": pipeline.audioMixer.isStereoMixEnabled,
                        "leftLevel": Double(pipeline.audioMixer.leftLevel),
                        "rightLevel": Double(pipeline.audioMixer.rightLevel),
                        "mixedLevel": Double(pipeline.audioMixer.mixedLevel)
                    ])
                    sem.signal()
                }
                sem.wait()
                guard let jsonData = try? JSONSerialization.data(withJSONObject: result.get()) else {
                    return .internalServerError
                }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            case "POST":
                guard let bodyData = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] else {
                    return .badRequest(.text("Invalid JSON"))
                }
                let sem = DispatchSemaphore(value: 0)
                let result = LockedValue<[String: Any]>([:])
                Task { @MainActor in
                    guard let pipeline = self.pipeline else { sem.signal(); return }
                    if let leftGain = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "leftGain",
                        range: WebControlInput.audioGainRange
                    ) {
                        pipeline.audioMixer.leftGain = Float(leftGain)
                    }
                    if let rightGain = WebControlInput.clampedDouble(
                        in: bodyData,
                        key: "rightGain",
                        range: WebControlInput.audioGainRange
                    ) {
                        pipeline.audioMixer.rightGain = Float(rightGain)
                    }
                    result.set([
                        "success": true,
                        "leftGain": Double(pipeline.audioMixer.leftGain),
                        "rightGain": Double(pipeline.audioMixer.rightGain),
                        "isStereoMixEnabled": pipeline.audioMixer.isStereoMixEnabled
                    ])
                    sem.signal()
                }
                sem.wait()
                guard let jsonData = try? JSONSerialization.data(withJSONObject: result.get()) else {
                    return .internalServerError
                }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/preview/mjpeg"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }

            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            let targetWidth = 640
            let targetHeight = 360
            let jpegQuality: CGFloat = 0.5
            let frameIntervalMs: Int = 150 // ~6-7 fps

            return .raw(200, "OK", [
                "Content-Type": "multipart/x-mixed-replace; boundary=frame",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "Access-Control-Allow-Origin": "*"
            ]) { [weak self] writer in
                var running = true

                while running {
                    guard let pool = self?.pipeline?.ioSurfacePool,
                          let completedBuffer = pool.lastCompletedBuffer else {
                        Thread.sleep(forTimeInterval: 0.1)
                        continue
                    }

                    let pixelBuffer = completedBuffer.pixelBuffer
                    var jpegData: Data?

                    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let scaleX = CGFloat(targetWidth) / ciImage.extent.width
                    let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleX))

                    if let cgImage = ciContext.createCGImage(scaledImage, from: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)) {
                        jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality)
                    }

                    if let data = jpegData {
                        let header = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(data.count)\r\n\r\n"
                        let footer = "\r\n"
                        var frameData = Data(header.utf8)
                        frameData.append(data)
                        frameData.append(Data(footer.utf8))

                        do {
                            try writer.write(frameData)
                        } catch {
                            running = false
                            break
                        }
                    }

                    Thread.sleep(forTimeInterval: Double(frameIntervalMs) / 1000.0)
                }
            }
        }

        server["/api/status"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }

            let sem = DispatchSemaphore(value: 0)
            let result = LockedValue<[String: Any]>([:])

            Task { @MainActor in
                let streamManager = self.pipeline?.streamManager
                let debug = self.pipeline?.debug ?? DebugInfoManager.shared
                let deviceManager = self.pipeline?.deviceStatusManager

                let thermalState: String
                switch ProcessInfo.processInfo.thermalState {
                case .nominal: thermalState = "nominal"
                case .fair: thermalState = "fair"
                case .serious: thermalState = "serious"
                case .critical: thermalState = "critical"
                @unknown default: thermalState = "unknown"
                }

                let batteryStateStr: String
                switch deviceManager?.batteryState ?? .unknown {
                case .unknown: batteryStateStr = "unknown"
                case .unplugged: batteryStateStr = "unplugged"
                case .charging: batteryStateStr = "charging"
                case .full: batteryStateStr = "full"
                @unknown default: batteryStateStr = "unknown"
                }

                let resolution: String
                switch streamManager?.streamResolution ?? .r720p {
                case .r720p: resolution = "1280x720"
                case .r1080p: resolution = "1920x1080"
                }

                result.set([
                    "streaming": [
                        "isStreaming": streamManager?.isStreaming ?? false,
                        "status": streamManager?.streamStatus ?? "Idle",
                        "duration": debug.streamingDuration,
                        "bitrate": debug.rtmpBitrate,
                        "resolution": resolution,
                        "fps": debug.rtmpFPS
                    ],
                    "device": [
                        "batteryLevel": deviceManager?.effectiveBatteryLevel ?? -1,
                        "batteryState": batteryStateStr,
                        "thermalState": thermalState
                    ],
                    "pipeline": [
                        "lagMs": debug.pipelineLagMs
                    ]
                ])
                sem.signal()
            }

            sem.wait()

            guard let jsonData = try? JSONSerialization.data(withJSONObject: result.get()) else {
                return .internalServerError
            }
            return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                try writer.write(jsonData)
            }
        }
    }

    private func serveCover(request: HttpRequest) -> HttpResponse {
        guard let musicIdStr = request.params[":musicId"],
              let musicId = Int(musicIdStr),
              let cacheKey = coverResolver.cacheKey(for: musicId) else {
            return .badRequest(.text("Invalid musicId"))
        }

        if let cached = coverCache.value(forKey: cacheKey) {
            return coverResponse(cached)
        }

        for candidate in coverResolver.remoteCandidates(for: musicId) {
            if let result = fetchCover(candidate) {
                coverCache.store(result, forKey: cacheKey)
                return coverResponse(result)
            }
        }

        return .notFound
    }

    private func fetchCover(_ candidate: CoverResourceCandidate) -> CoverFetchResult? {
        let requestSem = DispatchSemaphore(value: 0)
        let foundResult = LockedValue<CoverFetchResult?>(nil)
        var request = URLRequest(url: candidate.url)
        request.timeoutInterval = coverFetchTimeout

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { requestSem.signal() }
            guard let data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            foundResult.set(CoverFetchResult(
                data: data,
                contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? candidate.fallbackContentType
            ))
        }
        task.resume()

        if requestSem.wait(timeout: .now() + coverFetchTimeout + 1) == .timedOut {
            task.cancel()
            return nil
        }
        return foundResult.get()
    }

    private func coverResponse(_ result: CoverFetchResult) -> HttpResponse {
        .raw(200, "OK", ["Content-Type": result.contentType, "Cache-Control": "public, max-age=86400"]) { writer in
            try writer.write(result.data)
        }
    }

    private func loadControlHTML() -> Data? {
        guard let url = Bundle.main.url(forResource: "control", withExtension: "html", subdirectory: "WebServer") else {
            if let url = Bundle.main.url(forResource: "control", withExtension: "html") {
                return try? Data(contentsOf: url)
            }
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    let addressBytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    address = String(decoding: addressBytes, as: UTF8.self)
                    break
                }
            }
        }

        return address
    }
}

enum WebControlInput {
    static let focusValueRange = 0.0...1.0
    static let shutterTimescaleRange = 30.0...1000.0
    static let yawRange = -90.0...90.0
    static let rollRange = -45.0...45.0
    static let fovRange = Double(Config.fovRange.lowerBound)...Double(Config.fovRange.upperBound)
    static let distRatioRange = Double(Config.distRatioRange.lowerBound)...Double(Config.distRatioRange.upperBound)
    static let activitySmoothFactorRange: ClosedRange<Double> = {
        let range = Config.activitySmoothFactorRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }()
    static let audioGainRange = 0.0...2.0
    static let songRequestPauseThresholdRange = Config.songRequestPauseThresholdRange

    static func clampedDouble(in body: [String: Any], key: String, range: ClosedRange<Double>) -> Double? {
        guard let value = JSONNumberInput.double(body[key]) else {
            return nil
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func clampedInt(in body: [String: Any], key: String, range: ClosedRange<Int>) -> Int? {
        guard let value = JSONNumberInput.integralInt(body[key]) else {
            return nil
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func lensType(in body: [String: Any], key: String) -> LensType? {
        guard let rawValue = body[key] as? String else {
            return nil
        }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lens = LensType(rawValue: normalized) {
            return lens
        }
        switch normalized.lowercased() {
        case "main", "main (1x)":
            return .main
        case "ultra-wide", "ultra-wide (0.5x)", "uw":
            return .ultraWide
        default:
            return nil
        }
    }
}
