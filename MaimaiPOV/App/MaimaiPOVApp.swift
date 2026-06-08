import SwiftUI

@main
struct MaimaiPOVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Phase2View()
                .defersSystemGestures(on: .bottom)
        }
        .defaultSize(.init(width: 393, height: 852))
    }
}
