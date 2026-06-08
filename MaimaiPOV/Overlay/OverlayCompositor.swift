import Metal
import UIKit

final class OverlayCompositor: @unchecked Sendable {
    let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let uniformsBuffer: MTLBuffer

    private(set) var overlayTexture: MTLTexture?
    private var enabled: Bool = false
    private var posX: Float = 0.5
    private var posY: Float = 0.5
    private var scale: Float = 0.2
    private var opacity: Float = 1.0
    private var rotation: Float = 0.0

    private var stateLock = os_unfair_lock_s()
    private var persistedImageLoadTask: Task<Void, Never>?

    let outWidth = Config.outputWidth
    let outHeight = Config.outputHeight

    private static let overlayImageURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("overlay_image.png")
    }()

    init?(device: MTLDevice) {
        self.device = device

        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "overlayBlend"),
              let ps = try? device.makeComputePipelineState(function: kernel) else {
            return nil
        }
        self.pipelineState = ps

        guard let uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<OverlayUniforms>.stride,
            options: .storageModeShared
        ) else {
            return nil
        }
        self.uniformsBuffer = uniformsBuffer

        if FileManager.default.fileExists(atPath: Self.overlayImageURL.path) {
            loadPersistedImage()
        } else {
            createTestTexture()
        }
    }

    deinit {
        persistedImageLoadTask?.cancel()
    }

    private func loadPersistedImage() {
        let url = Self.overlayImageURL
        persistedImageLoadTask?.cancel()
        persistedImageLoadTask = Task.detached(priority: .utility) { [weak self] in
            let image = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
            guard !Task.isCancelled, let self else { return }
            if let image {
                self.loadImageToTexture(image)
            } else {
                self.createTestTexture()
            }
        }
    }

    private func createTestTexture() {
        let size = 100
        var pixelData = [UInt8](repeating: 0, count: size * size * 4)

        for y in 0..<size {
            for x in 0..<size {
                let idx = (y * size + x) * 4
                let cx = abs(x - size / 2)
                let cy = abs(y - size / 2)
                let isBorder = cx > 40 || cy > 40
                if isBorder {
                    pixelData[idx] = 0
                    pixelData[idx + 1] = 0
                    pixelData[idx + 2] = 0
                    pixelData[idx + 3] = 0
                } else {
                    let isInner = cx < 15 && cy < 25
                    if isInner {
                        pixelData[idx] = 255
                        pixelData[idx + 1] = 255
                        pixelData[idx + 2] = 255
                        pixelData[idx + 3] = 255
                    } else {
                        pixelData[idx] = 50
                        pixelData[idx + 1] = 50
                        pixelData[idx + 2] = 200
                        pixelData[idx + 3] = 180
                    }
                }
            }
        }

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        texDesc.usage = .shaderRead
        texDesc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: texDesc) else { return }

        texture.replace(
            region: MTLRegion(origin: .init(x: 0, y: 0, z: 0),
                              size: MTLSize(width: size, height: size, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: size * 4
        )

        setOverlayTexture(texture)
    }

    func loadImage(_ uiImage: UIImage) {
        persistedImageLoadTask?.cancel()
        persistedImageLoadTask = nil
        loadImageToTexture(uiImage)
        persistImage(uiImage)
    }

    func setEnabled(_ enabled: Bool) {
        os_unfair_lock_lock(&stateLock)
        self.enabled = enabled
        os_unfair_lock_unlock(&stateLock)
    }

    func updateSettings(posX: Float, posY: Float, scale: Float, opacity: Float, rotation: Float) {
        os_unfair_lock_lock(&stateLock)
        self.posX = posX
        self.posY = posY
        self.scale = scale
        self.opacity = opacity
        self.rotation = rotation
        os_unfair_lock_unlock(&stateLock)
    }

    private func loadImageToTexture(_ uiImage: UIImage) {
        guard let texture = TextureHelper.shared.imageToTexture(uiImage, device: device) else { return }
        setOverlayTexture(texture)
    }

    private func setOverlayTexture(_ texture: MTLTexture) {
        os_unfair_lock_lock(&stateLock)
        overlayTexture = texture
        os_unfair_lock_unlock(&stateLock)
    }

    private func persistImage(_ uiImage: UIImage) {
        guard let data = uiImage.pngData() else { return }
        let url = Self.overlayImageURL
        Task.detached(priority: .utility) {
            try? data.write(to: url)
        }
    }

    func encode(into encoder: MTLComputeCommandEncoder, outputTexture: MTLTexture) {
        os_unfair_lock_lock(&stateLock)
        let localOverlayTexture = overlayTexture
        let localEnabled = enabled
        let localPosX = posX
        let localPosY = posY
        let localScale = scale
        let localOpacity = opacity
        let localRotation = rotation
        os_unfair_lock_unlock(&stateLock)

        guard localEnabled, let overlayTex = localOverlayTexture else { return }

        var uniforms = OverlayUniforms()
        uniforms.posX = localPosX
        uniforms.posY = localPosY
        uniforms.scale = localScale
        uniforms.opacity = localOpacity
        uniforms.rotation = localRotation
        uniforms.overlayWidth = Float(overlayTex.width)
        uniforms.overlayHeight = Float(overlayTex.height)
        uniforms.outWidth = Float(outWidth)
        uniforms.outHeight = Float(outHeight)

        let overlayPixelW = Float(outWidth) * localScale
        let overlayPixelH = overlayPixelW * (Float(overlayTex.height) / Float(overlayTex.width))
        let centerX = localPosX * Float(outWidth)
        let centerY = localPosY * Float(outHeight)

        let absCos = abs(cos(localRotation))
        let absSin = abs(sin(localRotation))
        let halfW = overlayPixelW / 2.0 * absCos + overlayPixelH / 2.0 * absSin
        let halfH = overlayPixelW / 2.0 * absSin + overlayPixelH / 2.0 * absCos

        let originX = max(0, Int(centerX - halfW))
        let originY = max(0, Int(centerY - halfH))
        let gridW = min(outWidth, Int(centerX + halfW)) - originX
        let gridH = min(outHeight, Int(centerY + halfH)) - originY

        guard gridW > 0 && gridH > 0 else { return }

        uniforms.originX = Float(originX)
        uniforms.originY = Float(originY)
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<OverlayUniforms>.stride)

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(outputTexture, index: 0)
        encoder.setTexture(overlayTex, index: 1)
        encoder.setBuffer(uniformsBuffer, offset: 0, index: 0)

        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: gridW, height: gridH, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
    }
}
