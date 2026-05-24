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

    func renderCard(data: SongCardData, completion: @escaping (MTLTexture?) -> Void) {
        let html = SongCardTemplate.render(data: data)
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
                let texture = self.imageToTexture(image)
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
