import SwiftUI
import XCTest
@testable import MaimaiPOV

final class SystemGestureDeferralTests: XCTestCase {
    func testGlobalDeferredEdgesRequireSecondSwipeFromTopAndBottom() {
        XCTAssertTrue(SystemGestureDeferral.deferredEdges.contains(.top))
        XCTAssertTrue(SystemGestureDeferral.deferredEdges.contains(.bottom))
    }
}
