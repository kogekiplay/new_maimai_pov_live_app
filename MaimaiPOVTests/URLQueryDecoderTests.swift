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
}
