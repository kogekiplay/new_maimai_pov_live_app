import SwiftUI

@main
struct MaimaiPOVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MaimaiPOVRootView()
        }
        .defaultSize(.init(width: 393, height: 852))
    }
}

struct MaimaiPOVRootView: View {
    let deferredEdges: Edge.Set = SystemGestureDeferral.deferredEdges

    var body: some View {
        Phase2View()
            .defersSystemGestures(on: deferredEdges)
    }
}
