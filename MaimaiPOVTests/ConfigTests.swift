import XCTest
@testable import MaimaiPOV

final class ConfigTests: XCTestCase {
    private let yoloPaddingKey = "com.maimai.yoloPadding"
    private let streamBitrateKey = "com.maimai.streamBitrate"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: yoloPaddingKey)
        UserDefaults.standard.removeObject(forKey: streamBitrateKey)
        super.tearDown()
    }

    func testYoloPaddingClampsPersistedValuesToSupportedRange() {
        UserDefaults.standard.set(-20, forKey: yoloPaddingKey)

        XCTAssertEqual(Config.yoloPadding, 0)

        UserDefaults.standard.set(250, forKey: yoloPaddingKey)

        XCTAssertEqual(Config.yoloPadding, 100)
    }

    func testStreamBitrateClampsPersistedValuesToSupportedRange() {
        UserDefaults.standard.set(40_000, forKey: streamBitrateKey)

        XCTAssertEqual(Config.streamBitrate, 10_000)

        UserDefaults.standard.set(-500, forKey: streamBitrateKey)

        XCTAssertEqual(Config.streamBitrate, 1_000)
    }
}
