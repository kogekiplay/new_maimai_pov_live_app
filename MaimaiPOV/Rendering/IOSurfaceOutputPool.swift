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
    private var unfairLock = os_unfair_lock_s()

    init?(device: MTLDevice, width: Int, height: Int, count: Int = 3) {
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]

        for _ in 0..<count {
            var pixelBuffer: CVPixelBuffer?
            let result = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width, height,
                kCVPixelFormatType_32BGRA,
                bufferAttrs as CFDictionary,
                &pixelBuffer
            )
            guard result == kCVReturnSuccess, let pb = pixelBuffer else { continue }

            guard let unmanagedSurface = CVPixelBufferGetIOSurface(pb) else { continue }
            let ioSurface = unmanagedSurface.takeUnretainedValue()

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

            buffers.append(PooledBuffer(pixelBuffer: pb, texture: texture))
        }

        guard buffers.count == count else { return nil }
    }

    func nextWriteBuffer() -> PooledBuffer? {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        guard !buffers.isEmpty else { return nil }
        let buffer = buffers[writeIndex]
        writeIndex = (writeIndex + 1) % buffers.count
        return buffer
    }

    var lastCompletedBuffer: PooledBuffer? {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        guard !buffers.isEmpty else { return nil }
        let readIndex = (writeIndex + buffers.count - 1) % buffers.count
        return buffers[readIndex]
    }
}
