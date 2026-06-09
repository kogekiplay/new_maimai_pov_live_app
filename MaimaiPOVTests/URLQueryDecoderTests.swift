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
