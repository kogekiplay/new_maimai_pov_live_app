import SwiftUI
import XCTest
@testable import MaimaiPOV

final class SystemGestureDeferralTests: XCTestCase {
    func testGlobalDeferredEdgesRequireSecondSwipeFromTopAndBottom() {
        XCTAssertTrue(SystemGestureDeferral.deferredEdges.contains(.top))
        XCTAssertTrue(SystemGestureDeferral.deferredEdges.contains(.bottom))
    }

    @MainActor
    func testUIKitHostDefersSystemGesturesFromTopAndBottom() {
        let controller = SystemGestureDeferringHostingController(rootView: EmptyView())

        XCTAssertTrue(controller.preferredScreenEdgesDeferringSystemGestures.contains(.top))
        XCTAssertTrue(controller.preferredScreenEdgesDeferringSystemGestures.contains(.bottom))
    }

    @MainActor
    func testAppRootViewUsesGlobalDeferredEdges() {
        let rootView = MaimaiPOVRootView()

        XCTAssertTrue(rootView.deferredEdges.contains(.top))
        XCTAssertTrue(rootView.deferredEdges.contains(.bottom))
    }
}
