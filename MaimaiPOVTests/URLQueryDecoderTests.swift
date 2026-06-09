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
}
