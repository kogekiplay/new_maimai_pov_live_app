import XCTest
@testable import MaimaiPOV

final class URLQueryDecoderTests: XCTestCase {
    func testDecodeComponentTreatsPlusAsSpace() {
        XCTAssertEqual(URLQueryDecoder.decodeComponent("Our+Wrenally"), "Our Wrenally")
    }

    func testDecodeComponentPreservesEscapedPlusSign() {
        XCTAssertEqual(URLQueryDecoder.decodeComponent("A%2BB+DX"), "A+B DX")
    }

    func testDecodeNonBlankComponentRejectsPlusOnlyWhitespace() {
        XCTAssertNil(URLQueryDecoder.decodeNonBlankComponent("+++"))
    }

    func testDecodeNonBlankComponentRejectsEscapedWhitespace() {
        XCTAssertNil(URLQueryDecoder.decodeNonBlankComponent("%0A%20"))
    }

    func testDecodeIntComponentDecodesPercentEncodedDigits() {
        XCTAssertEqual(URLQueryDecoder.decodeIntComponent("%31"), 1)
    }
}

final class DebugAPIHandlerTests: XCTestCase {
    func testRequiredNonBlankStringRejectsBlankValue() {
        XCTAssertNil(
            DebugAPIHandler.requiredNonBlankString(
                in: ["authorName": " \n "],
                key: "authorName"
            )
        )
    }

    func testRequiredNonBlankStringKeepsNonBlankValue() {
        XCTAssertEqual(
            DebugAPIHandler.requiredNonBlankString(
                in: ["authorName": " Alice "],
                key: "authorName"
            ),
            " Alice "
        )
    }

    func testRequiredPositiveIntRejectsZeroAndNegativeValues() {
        XCTAssertNil(DebugAPIHandler.requiredPositiveInt(in: ["timeout": 0], key: "timeout"))
        XCTAssertNil(DebugAPIHandler.requiredPositiveInt(in: ["timeout": -1], key: "timeout"))
    }

    func testRequiredPositiveIntAcceptsPositiveValue() {
        XCTAssertEqual(DebugAPIHandler.requiredPositiveInt(in: ["timeout": 30], key: "timeout"), 30)
    }

    func testOptionalBatteryLevelAllowsMissingOrNullLevel() {
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: [:], key: "level"), .valid(nil))
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": NSNull()], key: "level"), .valid(nil))
    }

    func testOptionalBatteryLevelAcceptsInclusivePercentageRange() {
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": 0], key: "level"), .valid(0))
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": 100], key: "level"), .valid(100))
    }

    func testOptionalBatteryLevelRejectsOutOfRangePercentages() {
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": -1], key: "level"), .invalid)
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": 101], key: "level"), .invalid)
    }
}

final class WebControlInputTests: XCTestCase {
    func testClampedDoubleReturnsNilForMissingOrNonNumericValues() {
        XCTAssertNil(WebControlInput.clampedDouble(in: [:], key: "focus", range: 0...1))
        XCTAssertNil(WebControlInput.clampedDouble(in: ["focus": "0.5"], key: "focus", range: 0...1))
    }

    func testClampedDoubleKeepsValuesInsideRange() {
        XCTAssertEqual(WebControlInput.clampedDouble(in: ["focus": 0.5], key: "focus", range: 0...1), 0.5)
    }

    func testClampedDoubleClampsValuesOutsideRange() {
        XCTAssertEqual(WebControlInput.clampedDouble(in: ["focus": -0.25], key: "focus", range: 0...1), 0)
        XCTAssertEqual(WebControlInput.clampedDouble(in: ["focus": 1.25], key: "focus", range: 0...1), 1)
    }

    func testAudioGainRangeMatchesControlSurfaces() {
        XCTAssertEqual(WebControlInput.clampedDouble(in: ["gain": -0.5], key: "gain", range: WebControlInput.audioGainRange), 0)
        XCTAssertEqual(WebControlInput.clampedDouble(in: ["gain": 1.25], key: "gain", range: WebControlInput.audioGainRange), 1.25)
        XCTAssertEqual(WebControlInput.clampedDouble(in: ["gain": 3.0], key: "gain", range: WebControlInput.audioGainRange), 2)
    }
}

final class QueueAPIHandlerTests: XCTestCase {
    func testUsernameOrLANDefaultsMissingUsernameToLAN() {
        XCTAssertEqual(QueueAPIHandler.usernameOrLAN(in: [:]), "LAN")
    }

    func testUsernameOrLANRejectsBlankUsername() {
        XCTAssertNil(QueueAPIHandler.usernameOrLAN(in: ["username": " \n "]))
    }

    func testUsernameOrLANKeepsNonBlankUsername() {
        XCTAssertEqual(QueueAPIHandler.usernameOrLAN(in: ["username": " Alice "]), " Alice ")
    }

    func testRequiredUsernameRejectsMissingUsername() {
        XCTAssertNil(QueueAPIHandler.requiredUsername(in: [:]))
    }

    func testRequiredUsernameRejectsBlankUsername() {
        XCTAssertNil(QueueAPIHandler.requiredUsername(in: ["username": " \n "]))
    }

    func testRequiredUsernameAcceptsExplicitLANUsername() {
        XCTAssertEqual(QueueAPIHandler.requiredUsername(in: ["username": "LAN"]), "LAN")
    }
}
