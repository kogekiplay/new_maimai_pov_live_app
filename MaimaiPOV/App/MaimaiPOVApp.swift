import SwiftUI

@main
struct MaimaiPOVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Phase2View()
                .onAppear {
                    patchRootViewControllerForFullScreen()
                }
        }
    }

    private func patchRootViewControllerForFullScreen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootVC = window.rootViewController else { return }

            let selector = sel_registerName("prefersHomeIndicatorAutoHidden")
            if let method = class_getInstanceMethod(object_getClass(rootVC), selector) {
                let block: @convention(block) (AnyObject) -> Bool = { _ in true }
                method_setImplementation(method, imp_implementationWithBlock(block))
            }

            rootVC.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }
}
