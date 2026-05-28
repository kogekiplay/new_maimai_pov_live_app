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

    private struct PendingRowRender {
        let data: SongCardData
        let queueIndex: Int
        let coverBase64: String?
        let completion: (Int, MTLTexture?) -> Void
    }

    private var pendingRowRenders: [PendingRowRender] = []
    private var isRenderingRow = false
    private var pendingFullRefresh: (() -> Void)?

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

        pendingRowRenders.append(PendingRowRender(data: data, queueIndex: queueIndex, coverBase64: coverBase64, completion: completion))

        if !isRenderingRow {
            processNextPendingRender()
        }
    }

    private func processNextPendingRender() {
        guard !pendingRowRenders.isEmpty else {
            isRenderingRow = false
            if let refresh = pendingFullRefresh {
                pendingFullRefresh = nil
                refresh()
            }
            return
        }

        isRenderingRow = true
        let item = pendingRowRenders.removeFirst()
        let key = cacheKey(for: item.data)

        if let cached = rowTextureCache[key] {
            item.completion(item.queueIndex, cached)
            processNextPendingRender()
            return
        }

        let html = RightPanelTemplate.renderRow(data: item.data, coverBase64: item.coverBase64)
        renderHTML(html, webView: rowWebView, width: rowWidth, height: rowHeight) { [weak self] texture in
            guard let self = self else { return }
            if let texture = texture {
                self.rowTextureCache[key] = texture
                self.trimCacheIfNeeded()
            }
            item.completion(item.queueIndex, texture)
            self.processNextPendingRender()
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

        let staleRenders = pendingRowRenders
        pendingRowRenders.removeAll()
        for item in staleRenders {
            item.completion(item.queueIndex, nil)
        }

        func startBatch() {
            isRenderingRow = true

            func renderNext(index: Int) {
                guard index < rowsToRender.count else {
                    isRenderingRow = false
                    if !pendingRowRenders.isEmpty {
                        processNextPendingRender()
                    } else if let refresh = pendingFullRefresh {
                        pendingFullRefresh = nil
                        refresh()
                    }
                    completion(results)
                    return
                }

                let item = rowsToRender[index]
                let key = cacheKey(for: item.song)
                let coverBase64 = covers[item.queueIndex]

                if let cached = rowTextureCache[key] {
                    results[item.queueIndex] = cached
                    renderNext(index: index + 1)
                    return
                }

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

        if isRenderingRow {
            pendingFullRefresh = startBatch
        } else {
            startBatch()
        }
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
                let texture = TextureHelper.shared.imageToTexture(image, device: self.device)
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
}
