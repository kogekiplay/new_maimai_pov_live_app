import XCTest
@testable import MaimaiPOV

final class ConfigTests: XCTestCase {
    private let streamBitrateKey = "com.maimai.streamBitrate"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: streamBitrateKey)
        super.tearDown()
    }

    func testStreamBitrateClampsPersistedValuesToSupportedRange() {
        UserDefaults.standard.set(40_000, forKey: streamBitrateKey)

        XCTAssertEqual(Config.streamBitrate, 10_000)

        UserDefaults.standard.set(-500, forKey: streamBitrateKey)

        XCTAssertEqual(Config.streamBitrate, 1_000)
    }
}
