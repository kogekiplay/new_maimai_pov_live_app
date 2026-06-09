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

    func testDecodeNonBlankComponentTrimsDecodedValue() {
        XCTAssertEqual(URLQueryDecoder.decodeNonBlankComponent("%20Alice%20"), "Alice")
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

    func testRequiredNonBlankStringTrimsNonBlankValue() {
        XCTAssertEqual(
            DebugAPIHandler.requiredNonBlankString(
                in: ["authorName": " Alice "],
                key: "authorName"
            ),
            "Alice"
        )
    }

    func testRequiredPositiveIntRejectsZeroAndNegativeValues() {
        XCTAssertNil(DebugAPIHandler.requiredPositiveInt(in: ["timeout": 0], key: "timeout"))
        XCTAssertNil(DebugAPIHandler.requiredPositiveInt(in: ["timeout": -1], key: "timeout"))
    }

    func testRequiredPositiveIntAcceptsPositiveValue() {
        XCTAssertEqual(DebugAPIHandler.requiredPositiveInt(in: ["timeout": 30], key: "timeout"), 30)
    }

    func testRequiredPositiveIntAcceptsIntegralDoubleValue() {
        XCTAssertEqual(DebugAPIHandler.requiredPositiveInt(in: ["timeout": 30.0], key: "timeout"), 30)
        XCTAssertNil(DebugAPIHandler.requiredPositiveInt(in: ["timeout": 30.5], key: "timeout"))
    }

    func testOptionalBatteryLevelAllowsMissingOrNullLevel() {
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: [:], key: "level"), .valid(nil))
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": NSNull()], key: "level"), .valid(nil))
    }

    func testOptionalBatteryLevelAcceptsInclusivePercentageRange() {
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": 0], key: "level"), .valid(0))
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": 100], key: "level"), .valid(100))
    }

    func testOptionalBatteryLevelAcceptsIntegralDoubleValue() {
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": 50.0], key: "level"), .valid(50))
        XCTAssertEqual(DebugAPIHandler.optionalBatteryLevel(in: ["level": 50.5], key: "level"), .invalid)
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

    func testOptionalPositiveIntAcceptsIntegralDoubleValue() {
        XCTAssertEqual(DebugAPIHandler.optionalPositiveInt(in: ["price": 30.0], key: "price", defaultValue: 1), 30)
        XCTAssertNil(DebugAPIHandler.optionalPositiveInt(in: ["price": 30.5], key: "price", defaultValue: 1))
    }

    func testOptionalPositiveIntRejectsZeroNegativeAndNonNumericValues() {
        XCTAssertNil(DebugAPIHandler.optionalPositiveInt(in: ["mergeCount": 0], key: "mergeCount", defaultValue: 1))
        XCTAssertNil(DebugAPIHandler.optionalPositiveInt(in: ["mergeCount": -1], key: "mergeCount", defaultValue: 1))
        XCTAssertNil(DebugAPIHandler.optionalPositiveInt(in: ["mergeCount": "1"], key: "mergeCount", defaultValue: 1))
    }

    func testOptionalMarqueeTypeRawAcceptsIntegralDoubleValue() {
        XCTAssertEqual(DebugAPIHandler.optionalMarqueeTypeRaw(in: ["type": 2.0], key: "type"), 2)
        XCTAssertEqual(DebugAPIHandler.optionalMarqueeTypeRaw(in: ["type": 2.5], key: "type"), 0)
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
    func testJSONNumberInputParsesIntegralIntValues() {
        XCTAssertEqual(JSONNumberInput.integralInt(30), 30)
        XCTAssertEqual(JSONNumberInput.integralInt(30.0), 30)
        XCTAssertNil(JSONNumberInput.integralInt(30.5))
        XCTAssertNil(JSONNumberInput.integralInt("30"))
    }

    func testJSONNumberInputParsesDoubleValues() {
        XCTAssertEqual(JSONNumberInput.double(30), 30)
        XCTAssertEqual(JSONNumberInput.double(30.5), 30.5)
        XCTAssertNil(JSONNumberInput.double("30.5"))
    }

    func testJSONNumberInputRejectsNonFiniteDoubleValues() {
        XCTAssertNil(JSONNumberInput.double(Double.nan))
        XCTAssertNil(JSONNumberInput.double(Double.infinity))
    }

    func testClampedDoubleReturnsNilForMissingOrNonNumericValues() {
        XCTAssertNil(WebControlInput.clampedDouble(in: [:], key: "focus", range: 0...1))
        XCTAssertNil(WebControlInput.clampedDouble(in: ["focus": "0.5"], key: "focus", range: 0...1))
    }

    func testClampedDoubleRejectsNonFiniteValues() {
        XCTAssertNil(WebControlInput.clampedDouble(in: ["focus": Double.nan], key: "focus", range: 0...1))
        XCTAssertNil(WebControlInput.clampedDouble(in: ["focus": Double.infinity], key: "focus", range: 0...1))
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

    func testLensTypeAcceptsRawValuesAndWebAliases() {
        XCTAssertEqual(WebControlInput.lensType(in: ["selectedLens": "Main (1x)"], key: "selectedLens"), .main)
        XCTAssertEqual(WebControlInput.lensType(in: ["selectedLens": "Main"], key: "selectedLens"), .main)
        XCTAssertEqual(WebControlInput.lensType(in: ["selectedLens": "Ultra-Wide (0.5x)"], key: "selectedLens"), .ultraWide)
        XCTAssertEqual(WebControlInput.lensType(in: ["selectedLens": "Ultra-Wide"], key: "selectedLens"), .ultraWide)
        XCTAssertNil(WebControlInput.lensType(in: ["selectedLens": "Telephoto"], key: "selectedLens"))
    }
}

final class QueueAPIHandlerTests: XCTestCase {
    func testUsernameOrLANDefaultsMissingUsernameToLAN() {
        XCTAssertEqual(QueueAPIHandler.usernameOrLAN(in: [:]), "LAN")
    }

    func testUsernameOrLANRejectsBlankUsername() {
        XCTAssertNil(QueueAPIHandler.usernameOrLAN(in: ["username": " \n "]))
    }

    func testUsernameOrLANTrimsNonBlankUsername() {
        XCTAssertEqual(QueueAPIHandler.usernameOrLAN(in: ["username": " Alice "]), "Alice")
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

    func testRequiredUsernameTrimsExplicitUsername() {
        XCTAssertEqual(QueueAPIHandler.requiredUsername(in: ["username": "\nAlice "]), "Alice")
    }

    func testRequiredPositiveMusicIdRejectsMissingZeroAndNegativeValues() {
        XCTAssertNil(QueueAPIHandler.requiredPositiveMusicId(in: [:]))
        XCTAssertNil(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": 0]))
        XCTAssertNil(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": -1]))
    }

    func testRequiredPositiveMusicIdAcceptsPositiveValue() {
        XCTAssertEqual(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": 123]), 123)
    }

    func testRequiredPositiveMusicIdAcceptsIntegralDoubleValue() {
        XCTAssertEqual(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": 123.0]), 123)
        XCTAssertNil(QueueAPIHandler.requiredPositiveMusicId(in: ["musicId": 123.5]))
    }

    func testRequiredDisplayIndexAcceptsIntegralDoubleValue() {
        XCTAssertEqual(QueueAPIHandler.requiredDisplayIndex(in: ["index": 1.0]), 1)
        XCTAssertNil(QueueAPIHandler.requiredDisplayIndex(in: ["index": 1.5]))
    }
}

final class BlivechatMessageInputTests: XCTestCase {
    func testDanmakuMessageTrimsAuthorName() {
        let data: [Any] = [
            "", 0, " Alice ", 0, " hello ", 0, 0, 0, 0, 0, 0, "id", "", 0, 0, 0, ""
        ]

        let message = DanmakuMessage(fromArray: data)

        XCTAssertEqual(message?.authorName, "Alice")
        XCTAssertEqual(message?.content, " hello ")
    }

    func testDanmakuMessageAcceptsIntegralDoubleNumbers() {
        let data: [Any] = [
            "", 12.0, "Alice", 1.0, "hello", 3.0, 1.0, 25.0, 1.0, 1.0, 18.0, "id", "", 2.0, 0, 0, ""
        ]

        let message = DanmakuMessage(fromArray: data)

        XCTAssertEqual(message?.timestamp, 12)
        XCTAssertEqual(message?.authorType, .member)
        XCTAssertEqual(message?.privilegeType, .captain)
        XCTAssertEqual(message?.isGiftDanmaku, true)
        XCTAssertEqual(message?.authorLevel, 25)
        XCTAssertEqual(message?.isNewbie, true)
        XCTAssertEqual(message?.isMobileVerified, true)
        XCTAssertEqual(message?.medalLevel, 18)
        XCTAssertEqual(message?.contentType, 2)
    }

    func testGiftMessageTrimsAuthorName() {
        let message = GiftMessage(fromDict: ["authorName": "\nAlice ", "giftName": "Gift"])

        XCTAssertEqual(message?.authorName, "Alice")
    }

    func testGiftMessageAcceptsIntegralDoubleNumbers() {
        let message = GiftMessage(fromDict: [
            "authorName": "Alice",
            "timestamp": 12.0,
            "totalCoin": 1000.0,
            "totalFreeCoin": 200.0,
            "num": 3.0,
            "privilegeType": 2.0,
            "medalLevel": 10.0
        ])

        XCTAssertEqual(message?.timestamp, 12)
        XCTAssertEqual(message?.totalCoin, 1000)
        XCTAssertEqual(message?.totalFreeCoin, 200)
        XCTAssertEqual(message?.num, 3)
        XCTAssertEqual(message?.privilegeType, .admiral)
        XCTAssertEqual(message?.medalLevel, 10)
        XCTAssertEqual(message?.isPaidGift, true)
    }

    func testMemberMessageTrimsAuthorName() {
        let message = MemberMessage(fromDict: ["authorName": "\nAlice "])

        XCTAssertEqual(message?.authorName, "Alice")
    }

    func testMemberMessageAcceptsIntegralDoubleNumbers() {
        let message = MemberMessage(fromDict: [
            "authorName": "Alice",
            "timestamp": 12.0,
            "privilegeType": 3.0,
            "num": 2.0,
            "totalCoin": 1000.0,
            "price": 138.0
        ])

        XCTAssertEqual(message?.timestamp, 12)
        XCTAssertEqual(message?.privilegeType, .captain)
        XCTAssertEqual(message?.num, 2)
        XCTAssertEqual(message?.totalCoin, 1000)
        XCTAssertEqual(message?.price, 138)
    }

    func testSuperChatMessageTrimsAuthorName() {
        let message = SuperChatMessage(fromDict: ["authorName": "\nAlice ", "content": " hello "])

        XCTAssertEqual(message?.authorName, "Alice")
        XCTAssertEqual(message?.content, " hello ")
    }

    func testSuperChatMessageAcceptsIntegralDoubleNumbers() {
        let message = SuperChatMessage(fromDict: [
            "authorName": "Alice",
            "timestamp": 12.0,
            "price": 30.0,
            "privilegeType": 1.0,
            "medalLevel": 6.0
        ])

        XCTAssertEqual(message?.timestamp, 12)
        XCTAssertEqual(message?.price, 30)
        XCTAssertEqual(message?.privilegeType, .governor)
        XCTAssertEqual(message?.medalLevel, 6)
    }
}
