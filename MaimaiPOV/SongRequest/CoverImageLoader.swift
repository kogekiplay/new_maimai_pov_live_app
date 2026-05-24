import UIKit

class CoverImageLoader {
    static let shared = CoverImageLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheDir: URL

    private let cdnBase = "https://munet-res-1251600285.cos.ap-shanghai.myqcloud.com/cover"
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

    func loadCoverBase64(musicId: Int, completion: @escaping (String?) -> Void) {
        if let cached = loadFromDiskCache(musicId: musicId) {
            let base64 = imageToBase64(cached)
            completion(base64)
            return
        }

        if let cached = memoryCache.object(forKey: "\(musicId)" as NSString) {
            let base64 = imageToBase64(cached)
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
        let urlString = "\(cdnBase)/\(musicId).\(format)"
        guard let url = URL(string: urlString) else {
            tryFormat(musicId: musicId, formatIndex: formatIndex + 1, completion: completion)
            return
        }

        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { completion(nil); return }

            if let data = data, let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let image = UIImage(data: data) {
                self.memoryCache.setObject(image, forKey: "\(musicId)" as NSString)
                self.saveToDiskCache(image: image, musicId: musicId)
                let base64 = self.imageToBase64(image)
                completion(base64)
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

    private func saveToDiskCache(image: UIImage, musicId: Int) {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        let fileURL = diskCacheDir.appendingPathComponent("\(musicId).jpg")
        try? data.write(to: fileURL)
    }

    private func loadFromDiskCache(musicId: Int) -> UIImage? {
        let fileURL = diskCacheDir.appendingPathComponent("\(musicId).jpg")
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        memoryCache.setObject(image, forKey: "\(musicId)" as NSString)
        return image
    }
}
