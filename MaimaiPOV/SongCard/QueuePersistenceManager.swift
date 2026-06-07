import Foundation

struct QueueSnapshot: Codable {
    let version: Int
    let savedAt: Date
    var queue: [SongCardData]
    var currentIndex: Int
    var userGiftPool: [String: Int]

    static let currentVersion = 2
}

final class QueuePersistenceManager: @unchecked Sendable {
    private let snapshotDirectory: URL
    private let snapshotURL: URL
    private let backupURL: URL
    private let tempURL: URL
    private let lock = NSLock()

    static let shared = QueuePersistenceManager()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        snapshotDirectory = documents.appendingPathComponent("QueueSnapshot", isDirectory: true)
        snapshotURL = snapshotDirectory.appendingPathComponent("queue_snapshot.json")
        backupURL = snapshotDirectory.appendingPathComponent("queue_snapshot.bak")
        tempURL = snapshotDirectory.appendingPathComponent("queue_snapshot.tmp")
    }

    func save(snapshot: QueueSnapshot) {
        guard !snapshot.queue.isEmpty || !snapshot.userGiftPool.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        do {
            try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)

            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: tempURL, options: .atomic)

            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: snapshotURL.path) {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.moveItem(at: snapshotURL, to: backupURL)
            }

            try fileManager.moveItem(at: tempURL, to: snapshotURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    func load() -> QueueSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        if let snapshot = loadFromURL(snapshotURL) {
            return snapshot
        }
        if let snapshot = loadFromURL(backupURL) {
            return snapshot
        }
        return nil
    }

    func hasSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: snapshotURL.path) || fileManager.fileExists(atPath: backupURL.path)
    }

    func clearSnapshot() {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: snapshotURL)
        try? fileManager.removeItem(at: backupURL)
    }

    func snapshotAge() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: snapshotURL.path),
              let modDate = attrs[.modificationDate] as? Date else {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: backupURL.path),
               let modDate = attrs[.modificationDate] as? Date {
                return Date().timeIntervalSince(modDate)
            }
            return nil
        }
        return Date().timeIntervalSince(modDate)
    }

    private func loadFromURL(_ url: URL) -> QueueSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(QueueSnapshot.self, from: data) else { return nil }
        guard snapshot.version <= QueueSnapshot.currentVersion else { return nil }
        return snapshot
    }
}
