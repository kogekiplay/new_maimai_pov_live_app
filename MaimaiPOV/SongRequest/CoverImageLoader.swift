import UIKit

final class CoverImageLoader: @unchecked Sendable {
    static let shared = CoverImageLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private var base64Cache: [Int: String] = [:]
    private var base64CacheOrder: [Int] = []
    private let maxBase64CacheSize = 200
    private var lock = os_unfair_lock_s()
    private let diskCacheDir: URL

    private let cdnBase = "https://munet-res-1251600285.cos.ap-shanghai.myqcloud.com/gameRes/mai2"
    private let formats = ["webp", "png", "avif"]

    private let session: URLSession

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheDir = cacheDir.appendingPathComponent("SongCovers")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        session = URLSession(configuration: config)

        if !FileManager.default.fileExists(atPath: diskCacheDir.path) {
            try? FileManager.default.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
        }
    }

    private func baseCoverId(from musicId: Int) -> Int {
        if musicId >= 100000 { return musicId - 100000 }
        if musicId >= 10000 { return musicId - 10000 }
        return musicId
    }

    private func coverIdPart(from musicId: Int) -> String {
        let baseId = baseCoverId(from: musicId)
        return String(format: "%06d", baseId)
    }

    private func getCachedBase64(musicId: Int) -> String? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return base64Cache[musicId]
    }

    private func setCachedBase64(musicId: Int, base64: String) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if base64Cache[musicId] == nil {
            base64CacheOrder.append(musicId)
        }
        base64Cache[musicId] = base64
        while base64Cache.count > maxBase64CacheSize {
            let oldest = base64CacheOrder.removeFirst()
            base64Cache.removeValue(forKey: oldest)
        }
    }

    func loadCoverBase64(musicId: Int, completion: @escaping (String?) -> Void) {
        if let cached = getCachedBase64(musicId: musicId) {
            completion(cached)
            return
        }

        if let cached = loadFromDiskCache(musicId: musicId) {
            let base64 = imageToBase64(cached)
            if let base64 = base64 {
                setCachedBase64(musicId: musicId, base64: base64)
            }
            completion(base64)
            return
        }

        if let cached = memoryCache.object(forKey: "\(musicId)" as NSString) {
            let base64 = imageToBase64(cached)
            if let base64 = base64 {
                setCachedBase64(musicId: musicId, base64: base64)
            }
            completion(base64)
            return
        }

        tryFormat(musicId: musicId, formatIndex: 0, completion: completion)
    }

    private func tryFormat(musicId: Int, formatIndex: Int, completion: @escaping (String?) -> Void) {
        guard formatIndex < formats.count else {
            completion(nil)
            return
        }

        let format = formats[formatIndex]
        let idPart = coverIdPart(from: musicId)
        let urlString = "\(cdnBase)/\(idPart).\(format)"
        guard let url = URL(string: urlString) else {
            tryFormat(musicId: musicId, formatIndex: formatIndex + 1, completion: completion)
            return
        }

        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { completion(nil); return }

            if let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let image = UIImage(data: data) {
                self.memoryCache.setObject(image, forKey: "\(musicId)" as NSString)
                let jpegData: Data?
                if format == "jpg" || format == "jpeg" {
                    jpegData = data
                } else {
                    jpegData = image.jpegData(compressionQuality: 0.7)
                }
                if let jpegData = jpegData {
                    self.saveToDiskCache(jpegData: jpegData, musicId: musicId)
                    let base64 = jpegData.base64EncodedString()
                    self.setCachedBase64(musicId: musicId, base64: base64)
                    completion(base64)
                } else {
                    completion(nil)
                }
            } else {
                self.tryFormat(musicId: musicId, formatIndex: formatIndex + 1, completion: completion)
            }
        }
        task.resume()
    }

    private func imageToBase64(_ image: UIImage) -> String? {
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else { return nil }
        return jpegData.base64EncodedString()
    }

    private func saveToDiskCache(jpegData: Data, musicId: Int) {
        let fileURL = diskCacheDir.appendingPathComponent("\(musicId).jpg")
        try? jpegData.write(to: fileURL)
    }

    private func loadFromDiskCache(musicId: Int) -> UIImage? {
        let fileURL = diskCacheDir.appendingPathComponent("\(musicId).jpg")
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        memoryCache.setObject(image, forKey: "\(musicId)" as NSString)
        return image
    }
}
