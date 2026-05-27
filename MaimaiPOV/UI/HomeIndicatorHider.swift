import SwiftUI
import UIKit

class HomeIndicatorHostingController<Content: View>: UIHostingController<Content> {
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
