import SwiftUI
import UIKit

final class SystemGestureDeferringHostingController<Content: View>: UIHostingController<Content> {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        SystemGestureDeferral.uiKitEdges
    }
}

typealias HomeIndicatorHostingController<Content: View> = SystemGestureDeferringHostingController<Content>
