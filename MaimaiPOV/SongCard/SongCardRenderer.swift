import UIKit
import WebKit
import Metal

class SongCardRenderer {
    private let webView: WKWebView
    private let device: MTLDevice
    let cardWidth: Int
    let cardHeight: Int

    init(device: MTLDevice, cardWidth: Int = 240, cardHeight: Int = 360) {
        self.device = device
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: cardWidth, height: cardHeight), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
    }

    func renderCard(data: SongCardData, coverBase64: String? = nil, completion: @escaping (MTLTexture?) -> Void) {
        let html = SongCardTemplate.render(data: data, coverBase64: coverBase64)
        renderHTML(html, completion: completion)
    }

    func renderHTML(_ html: String, completion: @escaping (MTLTexture?) -> Void) {
        webView.loadHTMLString(html, baseURL: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.takeSnapshot { [weak self] image in
                guard let self = self, let image = image else {
                    completion(nil)
                    return
                }
                let texture = TextureHelper.shared.imageToTexture(image, device: self.device)
                completion(texture)
            }
        }
    }

    private func takeSnapshot(completion: @escaping (UIImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        config.rect = CGRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        webView.takeSnapshot(with: config) { image, _ in
            completion(image)
        }
    }
}
