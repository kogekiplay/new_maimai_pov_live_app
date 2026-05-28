import UIKit

class DeviceStatusManager {
    private(set) var batteryLevel: Int = -1
    private(set) var batteryState: UIDevice.BatteryState = .unknown
    var onBatteryLevelChanged: (() -> Void)?

    var deviceTemperature: Double = 0.0

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

    func stopMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func batteryLevelChanged() {
        updateBatteryInfo()
    }

    @objc private func batteryStateChanged() {
        updateBatteryInfo()
    }

    private func updateBatteryInfo() {
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel < 0 ? -1 : Int(rawLevel * 100)
        let state = UIDevice.current.batteryState
        if level != batteryLevel || state != batteryState {
            batteryLevel = level
            batteryState = state
            onBatteryLevelChanged?()
        }
    }
}
