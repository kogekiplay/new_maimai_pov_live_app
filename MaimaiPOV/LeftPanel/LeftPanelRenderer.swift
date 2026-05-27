import UIKit
import WebKit
import Metal

class LeftPanelRenderer {
    private let device: MTLDevice

    private let currentSongWebView: WKWebView
    private let nextSongWebView: WKWebView
    private let announcementWebView: WKWebView

    private let songCardWidth: Int
    private let songCardHeight: Int
    private let announcementWidth: Int
    private let announcementHeight: Int

    private var cachedCurrentSongTexture: MTLTexture?
    private var cachedCurrentSongKey: String?
    private var cachedNextSongTexture: MTLTexture?
    private var cachedNextSongKey: String?

    init(device: MTLDevice) {
        self.device = device
        self.songCardWidth = LeftPanelTemplate.songCardWidth
        self.songCardHeight = LeftPanelTemplate.songCardHeight
        self.announcementWidth = LeftPanelTemplate.announcementWidth
        self.announcementHeight = LeftPanelTemplate.announcementHeight

        let songConfig = WKWebViewConfiguration()
        songConfig.websiteDataStore = .nonPersistent()
        currentSongWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: songCardWidth, height: songCardHeight), configuration: songConfig)
        currentSongWebView.isOpaque = false
        currentSongWebView.backgroundColor = .clear
        currentSongWebView.scrollView.isScrollEnabled = false

        let nextSongConfig = WKWebViewConfiguration()
        nextSongConfig.websiteDataStore = .nonPersistent()
        nextSongWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: songCardWidth, height: songCardHeight), configuration: nextSongConfig)
        nextSongWebView.isOpaque = false
        nextSongWebView.backgroundColor = .clear
        nextSongWebView.scrollView.isScrollEnabled = false

        let annConfig = WKWebViewConfiguration()
        annConfig.websiteDataStore = .nonPersistent()
        announcementWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: announcementWidth, height: announcementHeight), configuration: annConfig)
        announcementWebView.isOpaque = false
        announcementWebView.backgroundColor = .clear
        announcementWebView.scrollView.isScrollEnabled = false
    }

    private func cacheKey(for data: SongCardData?) -> String {
        guard let data = data else { return "_empty_" }
        return "\(data.requesterName ?? "")_\(data.songName)_\(data.giftValue)"
    }

    func renderCurrentSong(_ data: SongCardData?, coverBase64: String?, completion: @escaping (MTLTexture?) -> Void) {
        let key = cacheKey(for: data)
        if cachedCurrentSongKey == key, let cached = cachedCurrentSongTexture {
            completion(cached)
            return
        }

        let html: String
        if let data = data {
            html = LeftPanelTemplate.renderSongCard(data: data, coverBase64: coverBase64)
        } else {
            html = LeftPanelTemplate.renderEmptyState()
        }
        renderHTML(html, webView: currentSongWebView, width: songCardWidth, height: songCardHeight) { [weak self] texture in
            if let texture = texture {
                self?.cachedCurrentSongTexture = texture
                self?.cachedCurrentSongKey = key
            }
            completion(texture)
        }
    }

    func renderNextSong(_ data: SongCardData?, coverBase64: String?, completion: @escaping (MTLTexture?) -> Void) {
        let key = cacheKey(for: data)
        if cachedNextSongKey == key, let cached = cachedNextSongTexture {
            completion(cached)
            return
        }

        let html: String
        if let data = data {
            html = LeftPanelTemplate.renderSongCard(data: data, coverBase64: coverBase64)
        } else {
            html = LeftPanelTemplate.renderEmptyState()
        }
        renderHTML(html, webView: nextSongWebView, width: songCardWidth, height: songCardHeight) { [weak self] texture in
            if let texture = texture {
                self?.cachedNextSongTexture = texture
                self?.cachedNextSongKey = key
            }
            completion(texture)
        }
    }

    func renderAnnouncement(_ text: String, completion: @escaping (MTLTexture?) -> Void) {
        let html = LeftPanelTemplate.renderAnnouncement(text: text)
        renderHTML(html, webView: announcementWebView, width: announcementWidth, height: announcementHeight, completion: completion)
    }

    func invalidateCache() {
        cachedCurrentSongTexture = nil
        cachedCurrentSongKey = nil
        cachedNextSongTexture = nil
        cachedNextSongKey = nil
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
