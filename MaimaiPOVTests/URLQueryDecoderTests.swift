import XCTest
import Swifter
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
    private func jsonData(_ body: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: body)
    }

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

    func testOptionalPositiveIntUsesDefaultForMissingOrNullValue() {
        XCTAssertEqual(DebugAPIHandler.optionalPositiveInt(in: [:], key: "totalCoin", defaultValue: 1000), 1000)
        XCTAssertEqual(DebugAPIHandler.optionalPositiveInt(in: ["totalCoin": NSNull()], key: "totalCoin", defaultValue: 1000), 1000)
    }

    func testOptionalPositiveIntAcceptsPositiveValue() {
        XCTAssertEqual(DebugAPIHandler.optionalPositiveInt(in: ["price": 30], key: "price", defaultValue: 1), 30)
    }

    func testOptionalPositiveIntRejectsZeroNegativeAndNonNumericValues() {
        XCTAssertNil(DebugAPIHandler.optionalPositiveInt(in: ["mergeCount": 0], key: "mergeCount", defaultValue: 1))
        XCTAssertNil(DebugAPIHandler.optionalPositiveInt(in: ["mergeCount": -1], key: "mergeCount", defaultValue: 1))
        XCTAssertNil(DebugAPIHandler.optionalPositiveInt(in: ["mergeCount": "1"], key: "mergeCount", defaultValue: 1))
    }

    func testSimulateDanmakuRejectsBlankContent() async throws {
        let body = try jsonData(["authorName": "Alice", "content": " \n "])

        let statusCode = await Task.detached {
            let request = HttpRequest()
            request.body = Array(body)
            return DebugAPIHandler().simulateDanmaku(request: request).statusCode
        }.value

        XCTAssertEqual(statusCode, 400)
    }

    func testSimulateMarqueeRejectsBlankText() async throws {
        let body = try jsonData(["text": " \n "])

        let statusCode = await Task.detached {
            let request = HttpRequest()
            request.body = Array(body)
            return DebugAPIHandler().simulateMarquee(request: request).statusCode
        }.value

        XCTAssertEqual(statusCode, 400)
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

    func testClampedDoubleAcceptsIntegerJSONValues() {
        XCTAssertEqual(WebControlInput.clampedDouble(in: ["fov": 100], key: "fov", range: WebControlInput.fovRange), 100)
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

    func testClampedIntUsesControlSurfaceRange() {
        XCTAssertNil(WebControlInput.clampedInt(in: [:], key: "threshold", range: WebControlInput.songRequestPauseThresholdRange))
        XCTAssertNil(WebControlInput.clampedInt(in: ["threshold": "30"], key: "threshold", range: WebControlInput.songRequestPauseThresholdRange))
        XCTAssertEqual(WebControlInput.clampedInt(in: ["threshold": 0], key: "threshold", range: WebControlInput.songRequestPauseThresholdRange), 1)
        XCTAssertEqual(WebControlInput.clampedInt(in: ["threshold": 30], key: "threshold", range: WebControlInput.songRequestPauseThresholdRange), 30)
        XCTAssertEqual(WebControlInput.clampedInt(in: ["threshold": 10_000], key: "threshold", range: WebControlInput.songRequestPauseThresholdRange), 9_999)
    }

    func testClampedIntAcceptsIntegralDoubleJSONValues() {
        XCTAssertEqual(WebControlInput.clampedInt(in: ["threshold": 30.0], key: "threshold", range: WebControlInput.songRequestPauseThresholdRange), 30)
        XCTAssertNil(WebControlInput.clampedInt(in: ["threshold": 30.5], key: "threshold", range: WebControlInput.songRequestPauseThresholdRange))
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

    func testRequiredPositiveMusicIdRejectsMissingZeroAndNegativeValues() {
        XCTAssertNil(QueueAPIHandler.requiredPositiveMusicId(in: [:]))
        XCTAssertNil(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": 0]))
        XCTAssertNil(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": -1]))
    }

    func testRequiredPositiveMusicIdAcceptsPositiveValue() {
        XCTAssertEqual(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": 123]), 123)
    }
}
