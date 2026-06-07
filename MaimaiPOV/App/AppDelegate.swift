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
        Task { @MainActor in
            replaceRootViewController()
        }
        return true
    }

    @MainActor
    private func replaceRootViewController() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        let hostingController = HomeIndicatorHostingController(rootView: Phase2View())
        window.rootViewController = hostingController
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
