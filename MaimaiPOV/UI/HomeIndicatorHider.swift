import SwiftUI
import UIKit

struct HomeIndicatorHider: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HomeIndicatorViewController {
        return HomeIndicatorViewController()
    }

    func updateUIViewController(_ uiViewController: HomeIndicatorViewController, context: Context) {}
}

class HomeIndicatorViewController: UIViewController {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
}
