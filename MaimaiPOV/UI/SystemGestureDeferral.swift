import SwiftUI
import UIKit

enum SystemGestureDeferral {
    static let deferredEdges: Edge.Set = [.top, .bottom]
    static let uiKitEdges: UIRectEdge = [.top, .bottom]
}
