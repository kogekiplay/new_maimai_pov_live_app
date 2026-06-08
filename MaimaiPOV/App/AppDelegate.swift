import UIKit
import AVFoundation
import OSLog

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let logger = Logger(subsystem: "com.maimai.MaimaiPOV", category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAudioSession()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            Self.logger.error("AudioSession config failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
