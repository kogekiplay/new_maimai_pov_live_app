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

        server["/api/queue/move"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.queueHandler.move(request: request)
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

        server["/api/debug/permissions"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            switch request.method {
            case "GET":
                return self.debugHandler.getPermissions()
            default:
                return .badRequest(.text("Method not allowed"))
            }
        }

        server["/api/debug/permissions/add"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.addPermission(request: request)
        }

        server["/api/debug/permissions/clear"] = { [weak self] _ in
            guard let self = self else { return .internalServerError }
            return self.debugHandler.clearPermissions()
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
