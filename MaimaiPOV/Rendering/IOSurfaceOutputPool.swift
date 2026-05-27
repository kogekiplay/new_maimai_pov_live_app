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
    private var bufferCommandBuffers: [Int: MTLCommandBuffer] = [:]
    private var lastCompletedIndex: Int = -1

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

        let startIndex = writeIndex
        for _ in 0..<buffers.count {
            let buffer = buffers[writeIndex]
            let idx = writeIndex
            writeIndex = (writeIndex + 1) % buffers.count

            if let cmdBuf = bufferCommandBuffers[idx] {
                if cmdBuf.status == .completed || cmdBuf.status == .error {
                    bufferCommandBuffers.removeValue(forKey: idx)
                    lastCompletedIndex = idx
                } else {
                    continue
                }
            }
            return buffer
        }

        let buffer = buffers[startIndex]
        bufferCommandBuffers.removeValue(forKey: startIndex)
        lastCompletedIndex = startIndex
        writeIndex = (startIndex + 1) % buffers.count
        return buffer
    }

    func markBufferInUse(_ bufferIndex: Int, commandBuffer: MTLCommandBuffer) {
        os_unfair_lock_lock(&unfairLock)
        bufferCommandBuffers[bufferIndex] = commandBuffer
        os_unfair_lock_unlock(&unfairLock)
    }

    func notifyBufferCompleted(_ bufferIndex: Int) {
        os_unfair_lock_lock(&unfairLock)
        bufferCommandBuffers.removeValue(forKey: bufferIndex)
        lastCompletedIndex = bufferIndex
        os_unfair_lock_unlock(&unfairLock)
    }

    func indexOfBuffer(_ buffer: PooledBuffer) -> Int? {
        return buffers.firstIndex(where: { $0.pixelBuffer === buffer.pixelBuffer })
    }

    var lastCompletedBuffer: PooledBuffer? {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        guard !buffers.isEmpty else { return nil }

        if lastCompletedIndex >= 0 && lastCompletedIndex < buffers.count {
            if let cmdBuf = bufferCommandBuffers[lastCompletedIndex] {
                if cmdBuf.status != .completed && cmdBuf.status != .error {
                    let readIndex = (writeIndex + buffers.count - 1) % buffers.count
                    return buffers[readIndex]
                }
            }
            return buffers[lastCompletedIndex]
        }

        let readIndex = (writeIndex + buffers.count - 1) % buffers.count
        return buffers[readIndex]
    }
}
