import CoreMotion
import Foundation
import simd

struct MotionSample {
    var timestamp: Double
    var quaternion: simd_quatf
    var magneticAccuracy: Int32  // CMMagneticFieldCalibrationAccuracy rawValue
    var rawYaw: Float            // 原始 yaw（弧度），调试用
    var filteredYaw: Float       // 滤波后 yaw（弧度），调试用
}

// MARK: - Yaw 补偿滤波器

/// 基于磁力计精度的自适应 Yaw 滤波器
/// 当磁力计精度高时正常跟随，精度低时抑制 yaw 突变
/// 利用陀螺仪角速度检测真实旋转，避免误拦截
class YawCompensationFilter {

    /// 滤波后 yaw 状态（弧度）
    private var filteredYaw: Float? = nil

    // 自适应 alpha 参数
    var alphaHigh: Float = 0.10    // 磁力计精度 HIGH 时的跟随速率
    var alphaMedium: Float = 0.02  // 磁力计精度 MEDIUM 时的跟随速率
    var alphaLow: Float = 0.005    // 磁力计精度 LOW/UNCALIBRATED 时的跟随速率
    var alphaRealRotation: Float = 0.5  // 检测到真实旋转时的快速跟随速率

    /// 陀螺仪角速度阈值（rad/s），超过此值认为是真实旋转
    var gyroYawRateThreshold: Float = 0.05  // ~3 deg/s

    /// 是否启用滤波
    var enabled: Bool = true

    /// 对四元数应用 yaw 滤波
    /// - Parameters:
    ///   - q: 原始 IMU 四元数（设备坐标系）
    ///   - magneticAccuracy: 磁力计校准精度 rawValue
    ///   - gyroYawRate: 陀螺仪 Z 轴角速度 (rad/s)
    /// - Returns: 滤波后的四元数和 (rawYaw, filteredYaw) 元组
    func filter(_ q: simd_quatf, magneticAccuracy: Int32, gyroYawRate: Float) -> (simd_quatf, rawYaw: Float, filteredYaw: Float) {
        let rawYaw = Self.extractYaw(q)

        guard enabled else {
            filteredYaw = rawYaw
            return (q, rawYaw, rawYaw)
        }

        // 首次调用，直接初始化
        if filteredYaw == nil {
            filteredYaw = rawYaw
            return (q, rawYaw, rawYaw)
        }

        // 计算 yaw 增量（带角度环绕处理）
        var delta = rawYaw - filteredYaw!
        delta = wrapAngle(delta)

        // 检测是否为真实旋转（陀螺仪角速度超过阈值）
        let isRealRotation = abs(gyroYawRate) > gyroYawRateThreshold

        // 根据磁力计精度和旋转检测选择 alpha
        let alpha: Float
        if isRealRotation {
            // 陀螺仪检测到真实旋转，快速跟随
            alpha = alphaRealRotation
        } else {
            switch magneticAccuracy {
            case 2:  alpha = alphaHigh
            case 1:  alpha = alphaMedium
            default: alpha = alphaLow
            }
        }

        // 应用低通滤波
        filteredYaw! += alpha * delta
        filteredYaw! = wrapAngle(filteredYaw!)

        // 计算修正量：filteredYaw - rawYaw
        var correction = filteredYaw! - rawYaw
        correction = wrapAngle(correction)

        // 构造绕 Z 轴的修正四元数并应用
        let halfCorr = correction * 0.5
        let qCorrection = simd_quatf(ix: 0, iy: 0, iz: sin(halfCorr), r: cos(halfCorr))
        let filteredQ = qCorrection * q

        return (filteredQ, rawYaw, filteredYaw!)
    }

    /// 重置滤波器状态
    func reset() {
        filteredYaw = nil
    }

    /// 从四元数提取 yaw 角（弧度），ZYX 欧拉角分解
    static func extractYaw(_ q: simd_quatf) -> Float {
        let qw = q.vector.w
        let qx = q.vector.x
        let qy = q.vector.y
        let qz = q.vector.z
        return atan2(2.0 * (qw * qz + qx * qy), 1.0 - 2.0 * (qy * qy + qz * qz))
    }

    /// 将角度环绕到 [-π, π]
    private func wrapAngle(_ angle: Float) -> Float {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}

// MARK: - MotionManager

class MotionManager {

    static let shared = MotionManager()

    private let motionManager = CMMotionManager()
    private var unfairLock = os_unfair_lock_s()
    private var headIndex = 0
    private let bufferSize = 512

    private var buffer: [MotionSample] = (0..<512).map { _ in
        MotionSample(timestamp: 0, quaternion: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), magneticAccuracy: -1, rawYaw: 0, filteredYaw: 0)
    }

    /// Yaw 补偿滤波器
    let yawFilter = YawCompensationFilter()

    /// 最新磁力计校准精度（线程安全读取）
    var latestMagneticAccuracy: Int32 {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        let idx = (headIndex - 1 + bufferSize) % bufferSize
        let s = buffer[idx]
        return s.timestamp > 0 ? s.magneticAccuracy : -1
    }

    /// 最新原始 yaw（度，线程安全读取）
    var latestRawYawDeg: Float {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        let idx = (headIndex - 1 + bufferSize) % bufferSize
        let s = buffer[idx]
        return s.timestamp > 0 ? s.rawYaw * 180.0 / .pi : 0
    }

    /// 最新滤波后 yaw（度，线程安全读取）
    var latestFilteredYawDeg: Float {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        let idx = (headIndex - 1 + bufferSize) % bufferSize
        let s = buffer[idx]
        return s.timestamp > 0 ? s.filteredYaw * 180.0 / .pi : 0
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
            let rawQ = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
            let accuracy = motion.magneticField.accuracy.rawValue
            let gyroYawRate = Float(motion.rotationRate.z)

            // 应用 Yaw 补偿滤波
            let (filteredQ, rawYaw, filteredYaw) = self.yawFilter.filter(rawQ, magneticAccuracy: accuracy, gyroYawRate: gyroYawRate)

            let sample = MotionSample(
                timestamp: motion.timestamp,
                quaternion: filteredQ,
                magneticAccuracy: accuracy,
                rawYaw: rawYaw,
                filteredYaw: filteredYaw
            )

            os_unfair_lock_lock(&self.unfairLock)
            self.buffer[self.headIndex] = sample
            self.headIndex = (self.headIndex + 1) % self.bufferSize
            os_unfair_lock_unlock(&self.unfairLock)
        }
        print("MotionManager: Started at 100Hz (yawFilter: \(yawFilter.enabled ? "ON" : "OFF"))")
    }

    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
        yawFilter.reset()
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
        return YawCompensationFilter.extractYaw(q)
    }
}
