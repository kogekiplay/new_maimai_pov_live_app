import XCTest
@testable import MaimaiPOV

final class AntiTouchGateTests: XCTestCase {
    func testExpandedSurfaceCanAlwaysCollapse() {
        XCTAssertTrue(AntiTouchGate.allowsToggle(isExpanded: true, isAntiTouchMode: false))
        XCTAssertTrue(AntiTouchGate.allowsToggle(isExpanded: true, isAntiTouchMode: true))
    }

    func testCollapsedSurfaceCanExpandDuringGracePeriod() {
        XCTAssertTrue(AntiTouchGate.allowsToggle(isExpanded: false, isAntiTouchMode: false))
    }

    func testCollapsedSurfaceCannotExpandAfterAntiTouchLockEngages() {
        XCTAssertFalse(AntiTouchGate.allowsToggle(isExpanded: false, isAntiTouchMode: true))
    }
}
