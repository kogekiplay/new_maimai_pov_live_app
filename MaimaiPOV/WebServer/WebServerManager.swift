import Foundation
import Swifter

class WebServerManager {
    private let server = HttpServer()
    private(set) var isRunning: Bool = false
    private(set) var serverURL: String = ""
    weak var pipeline: LivePipelineManager?

    private let queueHandler = QueueAPIHandler()
    private let searchHandler = SearchAPIHandler()
    private let debugHandler = DebugAPIHandler()
    private let danmakuBuffer = DanmakuBufferManager.shared
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

            DispatchQueue.main.async {
                self.pipeline?.webServerURL = self.serverURL
                self.pipeline?.debug.log("[LAN] HTTP服务器已启动: \(self.serverURL)")
            }
        } catch {
            DispatchQueue.main.async {
                self.pipeline?.debug.log("[LAN] HTTP服务器启动失败: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        server.stop()
        isRunning = false
        serverURL = ""

        DispatchQueue.main.async {
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
                DispatchQueue.main.async {
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
                let activityMode = self.pipeline?.activityMode ?? false
                let smoothFactor = self.pipeline?.activitySmoothFactor ?? Config.activitySmoothFactor
                let data = try? JSONSerialization.data(withJSONObject: [
                    "activityMode": activityMode,
                    "smoothFactor": Double(smoothFactor)
                ])
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            case "POST":
                guard let bodyData = try? JSONSerialization.jsonObject(with: Data(request.body)) as? [String: Any] else {
                    return .badRequest(.text("Invalid JSON"))
                }
                DispatchQueue.main.async {
                    if let enabled = bodyData["activityMode"] as? Bool {
                        self.pipeline?.activityMode = enabled
                        self.pipeline?.updateActivityMode()
                    }
                    if let sf = bodyData["smoothFactor"] as? Double {
                        self.pipeline?.activitySmoothFactor = Float(sf)
                        self.pipeline?.updateActivitySmoothFactor()
                    }
                }
                let activityMode = self.pipeline?.activityMode ?? false
                let smoothFactor = self.pipeline?.activitySmoothFactor ?? Config.activitySmoothFactor
                let data = try? JSONSerialization.data(withJSONObject: [
                    "success": true,
                    "activityMode": activityMode,
                    "smoothFactor": Double(smoothFactor)
                ])
                guard let jsonData = data else { return .internalServerError }
                return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                    try writer.write(jsonData)
                }
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/song-request-config"] = { [weak self] request in
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
                if let threshold = bodyData["threshold"] as? Int, threshold > 0 {
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
                let client = SSEClient(writer: writer, semaphore: semaphore)
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

            let sinceId = Int(request.queryParams.first(where: { $0.0 == "sinceId" })?.1 ?? "0") ?? 0
            let entries = DanmakuBufferManager.shared.getHistory(sinceId: sinceId)

            guard let jsonData = try? JSONEncoder().encode(entries) else {
                return .internalServerError
            }
            return .raw(200, "OK", ["Content-Type": "application/json; charset=utf-8"]) { writer in
                try writer.write(jsonData)
            }
        }
    }

    private let cdnBase = "https://munet-res-1251600285.cos.ap-shanghai.myqcloud.com/gameRes/mai2"
    private let coverFormats = ["webp", "png", "avif"]

    private func baseCoverId(from musicId: Int) -> Int {
        if musicId >= 100000 { return musicId - 100000 }
        if musicId >= 10000 { return musicId - 10000 }
        return musicId
    }

    private func serveCover(request: HttpRequest) -> HttpResponse {
        guard let musicIdStr = request.params[":musicId"],
              let musicId = Int(musicIdStr) else {
            return .badRequest(.text("Invalid musicId"))
        }

        let baseId = baseCoverId(from: musicId)
        let idPart = String(format: "%06d", baseId)

        let sem = DispatchSemaphore(value: 0)
        var imageData: Data?
        var contentType: String?

        for format in coverFormats {
            let urlString = "\(cdnBase)/\(idPart).\(format)"
            guard let url = URL(string: urlString) else { continue }

            let requestSem = DispatchSemaphore(value: 0)
            var foundData: Data?
            var foundContentType: String?

            let task = URLSession.shared.dataTask(with: url) { data, response, _ in
                if let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    foundData = data
                    foundContentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "image/\(format)"
                }
                requestSem.signal()
            }
            task.resume()
            requestSem.wait()

            if let data = foundData {
                imageData = data
                contentType = foundContentType
                break
            }
        }

        sem.signal()

        guard let data = imageData, let ct = contentType else {
            return .notFound
        }

        return .raw(200, "OK", ["Content-Type": ct, "Cache-Control": "public, max-age=86400"]) { writer in
            try writer.write(data)
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
                    address = String(cString: hostname)
                    break
                }
            }
        }

        return address
    }
}
