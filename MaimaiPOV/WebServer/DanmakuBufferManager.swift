import Foundation

enum DanmakuEntryType: String, Codable {
    case danmaku
    case gift
    case sc
    case member
}

struct DanmakuEntry: Codable {
    let id: Int
    let type: DanmakuEntryType
    let username: String
    let content: String
    let timestamp: Int
    let avatarUrl: String
    let giftName: String?
    let giftPrice: Int?
    let isSongRequest: Bool
    var songRequestStatus: String?
    let uid: String
    let originalDanmakuId: String
}

class DanmakuBufferManager {
    static let shared = DanmakuBufferManager()

    private var buffer: [DanmakuEntry] = []
    private var nextId: Int = 1
    private let maxEntries = 200
    private let lock = NSLock()

    private var sseClients: [SSEClient] = []
    private let clientLock = NSLock()

    private init() {}

    func addEntry(
        type: DanmakuEntryType,
        username: String,
        content: String,
        timestamp: Int,
        avatarUrl: String,
        giftName: String? = nil,
        giftPrice: Int? = nil,
        isSongRequest: Bool = false,
        uid: String = "",
        originalDanmakuId: String = ""
    ) -> DanmakuEntry {
        lock.lock()
        let entry = DanmakuEntry(
            id: nextId,
            type: type,
            username: username,
            content: content,
            timestamp: timestamp,
            avatarUrl: avatarUrl,
            giftName: giftName,
            giftPrice: giftPrice,
            isSongRequest: isSongRequest,
            songRequestStatus: isSongRequest ? "pending" : nil,
            uid: uid,
            originalDanmakuId: originalDanmakuId
        )
        nextId += 1
        buffer.append(entry)
        if buffer.count > maxEntries {
            buffer.removeFirst(buffer.count - maxEntries)
        }
        lock.unlock()

        broadcastToClients(entry: entry)
        return entry
    }

    func updateSongRequestStatus(originalDanmakuId: String, status: String) {
        lock.lock()
        for i in buffer.indices {
            if buffer[i].originalDanmakuId == originalDanmakuId && buffer[i].isSongRequest {
                buffer[i].songRequestStatus = status
                let entry = buffer[i]
                lock.unlock()
                broadcastStatusUpdate(originalDanmakuId: originalDanmakuId, status: status, entryId: entry.id)
                return
            }
        }
        lock.unlock()
    }

    func getHistory(sinceId: Int = 0) -> [DanmakuEntry] {
        lock.lock()
        defer { lock.unlock() }
        if sinceId == 0 {
            return buffer
        }
        return buffer.filter { $0.id > sinceId }
    }

    func addClient(_ client: SSEClient) {
        clientLock.lock()
        sseClients.append(client)
        clientLock.unlock()
    }

    func removeClient(_ client: SSEClient) {
        clientLock.lock()
        sseClients.removeAll { $0 === client }
        clientLock.unlock()
    }

    func currentClientCount() -> Int {
        clientLock.lock()
        defer { clientLock.unlock() }
        return sseClients.filter { $0.isActive }.count
    }

    private func broadcastToClients(entry: DanmakuEntry) {
        guard let data = try? JSONEncoder().encode(entry),
              let jsonStr = String(data: data, encoding: .utf8) else { return }

        let message = "data: \(jsonStr)\n\n"

        clientLock.lock()
        let clients = sseClients
        clientLock.unlock()

        for client in clients {
            client.send(message)
        }
    }

    private func broadcastStatusUpdate(originalDanmakuId: String, status: String, entryId: Int) {
        let payload: [String: Any] = [
            "type": "songRequestStatusUpdate",
            "originalDanmakuId": originalDanmakuId,
            "status": status,
            "entryId": entryId
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: data, encoding: .utf8) else { return }

        let message = "event: statusUpdate\ndata: \(jsonStr)\n\n"

        clientLock.lock()
        let clients = sseClients
        clientLock.unlock()

        for client in clients {
            client.send(message)
        }
    }
}

class SSEClient {
    private let writer: SocketWriter
    private let semaphore: DispatchSemaphore
    var isActive: Bool = true
    private let sendLock = NSLock()

    init(writer: SocketWriter, semaphore: DispatchSemaphore) {
        self.writer = writer
        self.semaphore = semaphore
    }

    func send(_ message: String) {
        guard isActive else { return }
        sendLock.lock()
        defer { sendLock.unlock() }
        do {
            try writer.write(message)
        } catch {
            isActive = false
            semaphore.signal()
        }
    }

    func close() {
        isActive = false
        semaphore.signal()
    }
}
