import Metal
import CoreVideo
import IOSurface

class IOSurfaceOutputPool {
    struct PooledBuffer {
        let pixelBuffer: CVPixelBuffer
        let texture: MTLTexture
    }

    private var buffers: [PooledBuffer] = []
    private var writeIndex: Int = 0
    private let lock = NSLock()

    init?(device: MTLDevice, width: Int, height: Int, count: Int = 3) {
        for _ in 0..<count {
            let surfaceProps: [IOSurfacePropertyKey: Any] = [
                .width: width,
                .height: height,
                .bytesPerRow: width * 4,
                .pixelFormat: kCVPixelFormatType_32BGRA
            ]
            guard let ioSurface = IOSurface(properties: surfaceProps) else { continue }

            guard let pixelBuffer = IOSurfaceCreateCVPixelBuffer(ioSurface) else { continue }

            let texDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            texDesc.usage = [.shaderWrite, .shaderRead]
            texDesc.storageMode = .shared

            guard let texture = device.makeTexture(
                descriptor: texDesc,
                iosurface: ioSurface,
                plane: 0
            ) else { continue }

            buffers.append(PooledBuffer(pixelBuffer: pixelBuffer, texture: texture))
        }

        guard buffers.count == count else { return nil }
    }

    func nextWriteBuffer() -> PooledBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffers.isEmpty else { return nil }
        let buffer = buffers[writeIndex]
        writeIndex = (writeIndex + 1) % buffers.count
        return buffer
    }

    var lastCompletedBuffer: PooledBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffers.isEmpty else { return nil }
        let readIndex = (writeIndex + buffers.count - 1) % buffers.count
        return buffers[readIndex]
    }
}
