import Foundation

struct CoverFetchResult: Equatable, Sendable {
    let data: Data
    let contentType: String
}

struct CoverResourceCandidate: Equatable, Sendable {
    let url: URL
    let fallbackContentType: String
}

struct CoverResourceResolver: Sendable {
    private let cdnBase: URL
    private let formats: [String]

    init(
        cdnBase: URL = URL(string: "https://munet-res-1251600285.cos.ap-shanghai.myqcloud.com/gameRes/mai2")!,
        formats: [String] = ["webp", "png", "avif"]
    ) {
        self.cdnBase = cdnBase
        self.formats = formats
    }

    func cacheKey(for musicId: Int) -> String? {
        guard musicId > 0 else { return nil }
        return String(format: "%06d", baseCoverId(from: musicId))
    }

    func remoteCandidates(for musicId: Int) -> [CoverResourceCandidate] {
        guard let key = cacheKey(for: musicId) else { return [] }

        return formats.map { format in
            CoverResourceCandidate(
                url: cdnBase.appendingPathComponent("\(key).\(format)"),
                fallbackContentType: "image/\(format)"
            )
        }
    }

    private func baseCoverId(from musicId: Int) -> Int {
        if musicId >= 100000 { return musicId - 100000 }
        if musicId >= 10000 { return musicId - 10000 }
        return musicId
    }
}

final class CoverImageCache: @unchecked Sendable {
    private struct Entry {
        let result: CoverFetchResult
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    init(ttl: TimeInterval = 24 * 60 * 60) {
        self.ttl = ttl
    }

    func value(forKey key: String, now: Date = Date()) -> CoverFetchResult? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > now else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.result
    }

    func store(_ result: CoverFetchResult, forKey key: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        entries[key] = Entry(result: result, expiresAt: now.addingTimeInterval(ttl))
    }
}
