import CoreMotion
import Foundation
import simd

struct MotionSample {
    var timestamp: Double
    var quaternion: simd_quatf
    var magneticAccuracy: Int32  // CMMagneticFieldCalibrationAccuracy rawValue
}

final class MotionManager: @unchecked Sendable {

    static let shared = MotionManager()

    private let motionManager = CMMotionManager()
    private var unfairLock = os_unfair_lock_s()
    private var headIndex = 0
    private let bufferSize = 512

    private var buffer: [MotionSample] = (0..<512).map { _ in
        MotionSample(timestamp: 0, quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), magneticAccuracy: -1)
    }

    /// 最新磁力计校准精度（线程安全读取）
    var latestMagneticAccuracy: Int32 {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        let idx = (headIndex - 1 + bufferSize) % bufferSize
        let s = buffer[idx]
        return s.timestamp > 0 ? s.magneticAccuracy : -1
    }

    private init() {}

    var isRunning: Bool { motionManager.isDeviceMotionActive }

    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("MotionManager: DeviceMotion not available")
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: OperationQueue()) { [weak self] motion, error in
            guard let self, let motion else { return }
            if let error {
                print("MotionManager: Error: \(error.localizedDescription)")
                return
            }

            let q = motion.attitude.quaternion
            let accuracy = motion.magneticField.accuracy.rawValue
            let sample = MotionSample(
                timestamp: motion.timestamp,
                quaternion: simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)),
                magneticAccuracy: accuracy
            )

            os_unfair_lock_lock(&self.unfairLock)
            self.buffer[self.headIndex] = sample
            self.headIndex = (self.headIndex + 1) % self.bufferSize
            os_unfair_lock_unlock(&self.unfairLock)
        }
        print("MotionManager: Started at 100Hz")
    }

    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
        print("MotionManager: Stopped")
    }

    func getQuaternion(at targetTime: Double) -> simd_quatf? {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }

        let n = bufferSize

        var low = 0
        var high = n - 1

        while low <= high && buffer[(headIndex + low) % n].timestamp == 0 {
            low += 1
        }
        if low > high { return nil }

        let oldestTime = buffer[(headIndex + low) % n].timestamp
        let newestTime = buffer[(headIndex + high) % n].timestamp
        if targetTime < oldestTime || targetTime > newestTime { return nil }

        var result = low
        while low <= high {
            let mid = low + (high - low) / 2
            let midTime = buffer[(headIndex + mid) % n].timestamp
            if midTime <= targetTime {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let idx1 = (headIndex + result) % n
        let idx2 = (idx1 + 1) % n
        let s1 = buffer[idx1]
        let s2 = buffer[idx2]

        guard s2.timestamp > s1.timestamp else { return nil }
        let dt = s2.timestamp - s1.timestamp
        guard dt > 0, dt < 0.1 else { return nil }

        let ratio = Float((targetTime - s1.timestamp) / dt)
        let clampedRatio = max(0.0, min(1.0, ratio))

        return simd_slerp(s1.quaternion, s2.quaternion, clampedRatio)
    }

    func latestQuaternion() -> simd_quatf? {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        let idx = (headIndex - 1 + bufferSize) % bufferSize
        let s = buffer[idx]
        return s.timestamp > 0 ? s.quaternion : nil
    }

    /// 从四元数提取 yaw 角（弧度），使用 ZYX 欧拉角分解
    /// 适用于 alignIMU 后的相机坐标系四元数
    static func extractYaw(from q: simd_quatf) -> Float {
        // ZYX Euler: yaw = atan2(2*(qw*qz + qx*qy), 1 - 2*(qy*qy + qz*qz))
        let qw = q.vector.w
        let qx = q.vector.x
        let qy = q.vector.y
        let qz = q.vector.z
        return atan2(2.0 * (qw * qz + qx * qy), 1.0 - 2.0 * (qy * qy + qz * qz))
    }
}
