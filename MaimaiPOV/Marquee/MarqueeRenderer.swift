import UIKit
@preconcurrency import Metal

final class MarqueeRenderer: @unchecked Sendable {
    private let device: MTLDevice

    private let fontSize: CGFloat = 28
    private let paddingH: CGFloat = 24
    private let cornerRadius: CGFloat = 12
    private let maxTextureWidth: Int = 1800
    private let barHeight: Int = 64

    init(device: MTLDevice) {
        self.device = device
    }

    func render(text: String, type: MarqueeItem.MarqueeItemType) -> (MTLTexture?, Int) {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                renderOnMainThread(text: text, type: type)
            }
        }

        let sem = DispatchSemaphore(value: 0)
        let result = LockedValue<(MTLTexture?, Int)>((nil, 0))

        Task { @MainActor [self] in
            result.set(renderOnMainThread(text: text, type: type))
            sem.signal()
        }

        sem.wait()
        return result.get()
    }

    @MainActor
    private func renderOnMainThread(text: String, type: MarqueeItem.MarqueeItemType) -> (MTLTexture?, Int) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attributedString = NSAttributedString(string: text, attributes: attrs)

        let maxTextWidth = CGFloat(maxTextureWidth) - paddingH * 2
        let textSize = attributedString.boundingRect(
            with: CGSize(width: maxTextWidth, height: CGFloat(barHeight)),
            options: .usesLineFragmentOrigin,
            context: nil
        ).size

        let textureWidth = min(Int(ceil(textSize.width + paddingH * 2)), maxTextureWidth)
        let textureHeight = barHeight

        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: textureWidth, height: textureHeight), false, 1.0)

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

        guard let image = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = image.cgImage else {
            UIGraphicsEndImageContext()
            return (nil, 0)
        }
        UIGraphicsEndImageContext()

        let texture = TextureHelper.shared.cgImageToTexture(cgImage, device: device)
        return (texture, textureWidth)
    }
}
