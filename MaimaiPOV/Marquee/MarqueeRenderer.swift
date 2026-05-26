import UIKit
import Metal

class MarqueeRenderer {
    private let device: MTLDevice

    private let fontSize: CGFloat = 28
    private let paddingH: CGFloat = 24
    private let paddingV: CGFloat = 10
    private let cornerRadius: CGFloat = 12
    private let maxTextureWidth: Int = 1800
    private let barHeight: Int = 64

    init(device: MTLDevice) {
        self.device = device
    }

    func render(text: String, type: MarqueeItem.MarqueeItemType) -> (MTLTexture?, Int) {
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

        let texture = cgImageToTexture(cgImage)
        return (texture, textureWidth)
    }

    private func cgImageToTexture(_ cgImage: CGImage) -> MTLTexture? {
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
