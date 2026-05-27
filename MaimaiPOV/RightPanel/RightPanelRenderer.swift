import UIKit
import WebKit
import Metal

class RightPanelRenderer {
    private let device: MTLDevice

    private let rowWebView: WKWebView
    private let titleWebView: WKWebView

    let rowWidth: Int = RightPanelTemplate.rowWidth
    let rowHeight: Int = RightPanelTemplate.rowHeight
    let titleWidth: Int = RightPanelTemplate.titleWidth
    let titleHeight: Int = RightPanelTemplate.titleHeight

    private var rowTextureCache: [String: MTLTexture] = [:]
    private var cachedTitleTexture: MTLTexture?
    private let maxCacheSize = 20

    init(device: MTLDevice) {
        self.device = device

        let rowConfig = WKWebViewConfiguration()
        rowConfig.websiteDataStore = .nonPersistent()
        rowWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: rowWidth, height: rowHeight), configuration: rowConfig)
        rowWebView.isOpaque = false
        rowWebView.backgroundColor = .clear
        rowWebView.scrollView.isScrollEnabled = false

        let titleConfig = WKWebViewConfiguration()
        titleConfig.websiteDataStore = .nonPersistent()
        titleWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: titleWidth, height: titleHeight), configuration: titleConfig)
        titleWebView.isOpaque = false
        titleWebView.backgroundColor = .clear
        titleWebView.scrollView.isScrollEnabled = false
    }

    private func cacheKey(for data: SongCardData) -> String {
        return "\(data.requesterName ?? "")_\(data.songName)_\(data.giftValue)"
    }

    func renderTitle(completion: @escaping (MTLTexture?) -> Void) {
        if let cached = cachedTitleTexture {
            completion(cached)
            return
        }
        let html = RightPanelTemplate.renderTitle()
        renderHTML(html, webView: titleWebView, width: titleWidth, height: titleHeight) { [weak self] texture in
            if let texture = texture {
                self?.cachedTitleTexture = texture
            }
            completion(texture)
        }
    }

    func renderRow(data: SongCardData, queueIndex: Int, coverBase64: String?, completion: @escaping (Int, MTLTexture?) -> Void) {
        let key = cacheKey(for: data)
        if let cached = rowTextureCache[key] {
            completion(queueIndex, cached)
            return
        }
        let html = RightPanelTemplate.renderRow(data: data, coverBase64: coverBase64)
        renderHTML(html, webView: rowWebView, width: rowWidth, height: rowHeight) { [weak self] texture in
            guard let self = self else {
                completion(queueIndex, nil)
                return
            }
            if let texture = texture {
                self.rowTextureCache[key] = texture
                self.trimCacheIfNeeded()
            }
            completion(queueIndex, texture)
        }
    }

    func renderVisibleRows(songs: [SongCardData], startQueueIndex: Int, covers: [Int: String], completion: @escaping ([Int: MTLTexture]) -> Void) {
        var results: [Int: MTLTexture] = [:]
        var rowsToRender: [(song: SongCardData, queueIndex: Int)] = []

        for (i, song) in songs.enumerated() {
            let queueIndex = startQueueIndex + i
            let key = cacheKey(for: song)
            if let cached = rowTextureCache[key] {
                results[queueIndex] = cached
            } else {
                rowsToRender.append((song: song, queueIndex: queueIndex))
            }
        }

        guard !rowsToRender.isEmpty else {
            completion(results)
            return
        }

        func renderNext(index: Int) {
            guard index < rowsToRender.count else {
                completion(results)
                return
            }

            let item = rowsToRender[index]
            let coverBase64 = covers[item.queueIndex]
            let key = cacheKey(for: item.song)

            let html = RightPanelTemplate.renderRow(data: item.song, coverBase64: coverBase64)
            renderHTML(html, webView: rowWebView, width: rowWidth, height: rowHeight) { [weak self] texture in
                guard let self = self else { return }
                if let texture = texture {
                    results[item.queueIndex] = texture
                    self.rowTextureCache[key] = texture
                    self.trimCacheIfNeeded()
                }
                renderNext(index: index + 1)
            }
        }

        renderNext(index: 0)
    }

    func invalidateCache() {
        rowTextureCache.removeAll()
    }

    func invalidateRow(data: SongCardData) {
        rowTextureCache.removeValue(forKey: cacheKey(for: data))
    }

    func invalidateRow(queueIndex: Int) {
    }

    func getCachedRow(data: SongCardData) -> MTLTexture? {
        return rowTextureCache[cacheKey(for: data)]
    }

    func getCachedRow(queueIndex: Int) -> MTLTexture? {
        return nil
    }

    func getTitleTexture() -> MTLTexture? {
        return cachedTitleTexture
    }

    private func trimCacheIfNeeded() {
        if rowTextureCache.count > maxCacheSize {
            let keysToRemove = Array(rowTextureCache.keys.prefix(rowTextureCache.count - maxCacheSize))
            for key in keysToRemove {
                rowTextureCache.removeValue(forKey: key)
            }
        }
    }

    private func renderHTML(_ html: String, webView: WKWebView, width: Int, height: Int, completion: @escaping (MTLTexture?) -> Void) {
        webView.loadHTMLString(html, baseURL: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            self.takeSnapshot(webView: webView, width: width, height: height) { [weak self] image in
                guard let self = self, let image = image else {
                    completion(nil)
                    return
                }
                let texture = self.imageToTexture(image)
                completion(texture)
            }
        }
    }

    private func takeSnapshot(webView: WKWebView, width: Int, height: Int, completion: @escaping (UIImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)
        webView.takeSnapshot(with: config) { image, _ in
            completion(image)
        }
    }

    private func imageToTexture(_ image: UIImage) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = .shaderRead
        texDesc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: texDesc) else { return nil }

        texture.replace(
            region: MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                              size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        return texture
    }
}
