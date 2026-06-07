import UIKit

final class DeviceStatusManager: @unchecked Sendable {
    private let lock = NSLock()
    private var storedBatteryLevel: Int = -1
    private var storedBatteryState: UIDevice.BatteryState = .unknown
    private var storedSimulatedBatteryLevel: Int?

    var onBatteryLevelChanged: (() -> Void)?

    var deviceTemperature: Double = 0.0

    var batteryLevel: Int {
        lock.withLock {
            storedBatteryLevel
        }
    }

    var batteryState: UIDevice.BatteryState {
        lock.withLock {
            storedBatteryState
        }
    }

    var simulatedBatteryLevel: Int? {
        lock.withLock {
            storedSimulatedBatteryLevel
        }
    }

    var effectiveBatteryLevel: Int {
        lock.withLock {
            storedSimulatedBatteryLevel ?? storedBatteryLevel
        }
    }

    func setSimulatedBatteryLevel(_ level: Int?) {
        lock.withLock {
            storedSimulatedBatteryLevel = level
        }
        onBatteryLevelChanged?()
    }

    @MainActor
    func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryInfo()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateChanged),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }

    @MainActor
    func stopMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self)
    }

    @MainActor
    @objc private func batteryLevelChanged() {
        updateBatteryInfo()
    }

    @MainActor
    @objc private func batteryStateChanged() {
        updateBatteryInfo()
    }

    @MainActor
    private func updateBatteryInfo() {
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel < 0 ? -1 : Int(rawLevel * 100)
        let state = UIDevice.current.batteryState

        let didChange = lock.withLock {
            guard level != storedBatteryLevel || state != storedBatteryState else {
                return false
            }
            storedBatteryLevel = level
            storedBatteryState = state
            return true
        }

        if didChange {
            onBatteryLevelChanged?()
        }
    }
}
