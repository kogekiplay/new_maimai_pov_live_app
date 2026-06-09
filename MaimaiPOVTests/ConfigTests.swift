import XCTest
@testable import MaimaiPOV

final class ConfigTests: XCTestCase {
    private let focusValueKey = "com.maimai.focusValue"
    private let shutterTimescaleKey = "com.maimai.shutterTimescale"
    private let syncOffsetKey = "com.maimai.syncOffsetMs"
    private let readoutTimeKey = "com.maimai.readoutTimeMs"
    private let fovKey = "com.maimai.fov"
    private let distRatioKey = "com.maimai.distRatio"
    private let yoloPaddingKey = "com.maimai.yoloPadding"
    private let streamBitrateKey = "com.maimai.streamBitrate"
    private let activitySmoothFactorKey = "com.maimai.activitySmoothFactor"
    private let songRequestPauseThresholdKey = "com.maimai.songRequestPauseThreshold"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: focusValueKey)
        UserDefaults.standard.removeObject(forKey: shutterTimescaleKey)
        UserDefaults.standard.removeObject(forKey: syncOffsetKey)
        UserDefaults.standard.removeObject(forKey: readoutTimeKey)
        UserDefaults.standard.removeObject(forKey: fovKey)
        UserDefaults.standard.removeObject(forKey: distRatioKey)
        UserDefaults.standard.removeObject(forKey: yoloPaddingKey)
        UserDefaults.standard.removeObject(forKey: streamBitrateKey)
        UserDefaults.standard.removeObject(forKey: activitySmoothFactorKey)
        UserDefaults.standard.removeObject(forKey: songRequestPauseThresholdKey)
        super.tearDown()
    }

    func testCameraControlValuesClampPersistedValuesToControlRanges() {
        UserDefaults.standard.set(-0.5, forKey: focusValueKey)

        XCTAssertEqual(Config.focusValue, 0.0, accuracy: 0.0001)

        UserDefaults.standard.set(1.5, forKey: focusValueKey)

        XCTAssertEqual(Config.focusValue, 1.0, accuracy: 0.0001)

        UserDefaults.standard.set(1.0, forKey: shutterTimescaleKey)

        XCTAssertEqual(Config.shutterTimescale, 30.0, accuracy: 0.0001)

        UserDefaults.standard.set(2_000.0, forKey: shutterTimescaleKey)

        XCTAssertEqual(Config.shutterTimescale, 1_000.0, accuracy: 0.0001)
    }

    func testImuTimingClampsPersistedValuesToControlRanges() {
        UserDefaults.standard.set(-250.0, forKey: syncOffsetKey)

        XCTAssertEqual(Config.syncOffsetMs, -50)

        UserDefaults.standard.set(250.0, forKey: syncOffsetKey)

        XCTAssertEqual(Config.syncOffsetMs, 50)

        UserDefaults.standard.set(1.0, forKey: readoutTimeKey)

        XCTAssertEqual(Config.readoutTimeMs, 5)

        UserDefaults.standard.set(40.0, forKey: readoutTimeKey)

        XCTAssertEqual(Config.readoutTimeMs, 15)
    }

    func testStabilizerGeometryClampsPersistedValuesToControlRanges() {
        UserDefaults.standard.set(5.0, forKey: fovKey)

        XCTAssertEqual(Config.fov, 30)

        UserDefaults.standard.set(250.0, forKey: fovKey)

        XCTAssertEqual(Config.fov, 160)

        UserDefaults.standard.set(-0.5, forKey: distRatioKey)

        XCTAssertEqual(Config.distRatio, 0)

        UserDefaults.standard.set(2.5, forKey: distRatioKey)

        XCTAssertEqual(Config.distRatio, 1)
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

    func testActivitySmoothFactorClampsPersistedValuesToControlRange() {
        UserDefaults.standard.set(0.001, forKey: activitySmoothFactorKey)

        XCTAssertEqual(Config.activitySmoothFactor, 0.01, accuracy: 0.0001)

        UserDefaults.standard.set(0.9, forKey: activitySmoothFactorKey)

        XCTAssertEqual(Config.activitySmoothFactor, 0.2, accuracy: 0.0001)
    }

    func testSongRequestPauseThresholdClampsPersistedValuesToControlRange() {
        UserDefaults.standard.set(-10, forKey: songRequestPauseThresholdKey)

        XCTAssertEqual(Config.songRequestPauseThreshold, 1)

        UserDefaults.standard.set(20_000, forKey: songRequestPauseThresholdKey)

        XCTAssertEqual(Config.songRequestPauseThreshold, 9_999)
    }
}
