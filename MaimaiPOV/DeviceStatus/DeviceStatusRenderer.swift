import UIKit
@preconcurrency import Metal

final class DeviceStatusRenderer: @unchecked Sendable {
    private let device: MTLDevice

    private let fontSize: CGFloat = 24
    private let paddingH: CGFloat = 16
    private let cornerRadius: CGFloat = 12
    private let barHeight: Int = 44

    init(device: MTLDevice) {
        self.device = device
    }

    func render(text: String) -> (MTLTexture?, Int) {
        if Thread.isMainThread {
            return renderOnMainThread(text: text)
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<(MTLTexture?, Int)>((nil, 0))

        Task { @MainActor [self] in
            result.set(renderOnMainThread(text: text))
            sem.signal()
        }

        sem.wait()
        return result.get()
    }

    private func renderOnMainThread(text: String) -> (MTLTexture?, Int) {
        precondition(Thread.isMainThread, "DeviceStatusRenderer must render UIKit content on the main thread")

        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attributedString = NSAttributedString(string: text, attributes: attrs)

        let maxTextWidth = CGFloat(400) - paddingH * 2
        let textSize = attributedString.boundingRect(
            with: CGSize(width: maxTextWidth, height: CGFloat(barHeight)),
            options: .usesLineFragmentOrigin,
            context: nil
        ).size

        let textureWidth = Int(ceil(textSize.width + paddingH * 2))
        let textureHeight = barHeight

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: textureWidth, height: textureHeight),
            format: format
        )

        let image = renderer.image { _ in
            let bgRect = CGRect(x: 0, y: 0, width: CGFloat(textureWidth), height: CGFloat(textureHeight))
            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: cornerRadius)
            UIColor(red: 0, green: 0, blue: 0, alpha: 0.6).setFill()
            bgPath.fill()

            let textRect = CGRect(
                x: paddingH,
                y: (CGFloat(textureHeight) - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            attributedString.draw(in: textRect)
        }

        guard let cgImage = image.cgImage else {
            return (nil, 0)
        }

        let texture = TextureHelper.shared.cgImageToTexture(cgImage, device: device)
        return (texture, textureWidth)
    }
}
