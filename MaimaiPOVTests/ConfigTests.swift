import XCTest
@testable import MaimaiPOV

final class ConfigTests: XCTestCase {
    private let focusValueKey = "com.maimai.focusValue"
    private let shutterTimescaleKey = "com.maimai.shutterTimescale"
    private let syncOffsetKey = "com.maimai.syncOffsetMs"
    private let readoutTimeKey = "com.maimai.readoutTimeMs"
    private let fovKey = "com.maimai.fov"
    private let distRatioKey = "com.maimai.distRatio"
    private let yawKey = "com.maimai.yaw"
    private let pitchKey = "com.maimai.pitch"
    private let rollKey = "com.maimai.roll"
    private let yoloPaddingKey = "com.maimai.yoloPadding"
    private let streamBitrateKey = "com.maimai.streamBitrate"
    private let activitySmoothFactorKey = "com.maimai.activitySmoothFactor"
    private let songRequestPauseThresholdKey = "com.maimai.songRequestPauseThreshold"
    private let trackTargetRatioKey = "com.maimai.trackTargetRatio"
    private let trackRecenterSpeedKey = "com.maimai.trackRecenterSpeed"
    private let recenterGraceMsKey = "com.maimai.recenterGraceMs"
    private let acquireSpeedKey = "com.maimai.acquireSpeed"
    private let overlayPosXKey = "com.maimai.overlayPosX"
    private let overlayPosYKey = "com.maimai.overlayPosY"
    private let overlayScaleKey = "com.maimai.overlayScale"
    private let overlayOpacityKey = "com.maimai.overlayOpacity"
    private let overlayRotationKey = "com.maimai.overlayRotation"
    private let cropHorizontalOffsetKey = "com.maimai.cropHorizontalOffset"
    private let smoothingBaseAlphaKey = "com.maimai.smoothingBaseAlpha"
    private let smoothingMinDeviationKey = "com.maimai.smoothingMinDeviation"
    private let smoothingMaxDeviationKey = "com.maimai.smoothingMaxDeviation"
    private let smoothingCenterFloorKey = "com.maimai.smoothingCenterFloor"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: focusValueKey)
        UserDefaults.standard.removeObject(forKey: shutterTimescaleKey)
        UserDefaults.standard.removeObject(forKey: syncOffsetKey)
        UserDefaults.standard.removeObject(forKey: readoutTimeKey)
        UserDefaults.standard.removeObject(forKey: fovKey)
        UserDefaults.standard.removeObject(forKey: distRatioKey)
        UserDefaults.standard.removeObject(forKey: yawKey)
        UserDefaults.standard.removeObject(forKey: pitchKey)
        UserDefaults.standard.removeObject(forKey: rollKey)
        UserDefaults.standard.removeObject(forKey: yoloPaddingKey)
        UserDefaults.standard.removeObject(forKey: streamBitrateKey)
        UserDefaults.standard.removeObject(forKey: activitySmoothFactorKey)
        UserDefaults.standard.removeObject(forKey: songRequestPauseThresholdKey)
        UserDefaults.standard.removeObject(forKey: trackTargetRatioKey)
        UserDefaults.standard.removeObject(forKey: trackRecenterSpeedKey)
        UserDefaults.standard.removeObject(forKey: recenterGraceMsKey)
        UserDefaults.standard.removeObject(forKey: acquireSpeedKey)
        UserDefaults.standard.removeObject(forKey: overlayPosXKey)
        UserDefaults.standard.removeObject(forKey: overlayPosYKey)
        UserDefaults.standard.removeObject(forKey: overlayScaleKey)
        UserDefaults.standard.removeObject(forKey: overlayOpacityKey)
        UserDefaults.standard.removeObject(forKey: overlayRotationKey)
        UserDefaults.standard.removeObject(forKey: cropHorizontalOffsetKey)
        UserDefaults.standard.removeObject(forKey: smoothingBaseAlphaKey)
        UserDefaults.standard.removeObject(forKey: smoothingMinDeviationKey)
        UserDefaults.standard.removeObject(forKey: smoothingMaxDeviationKey)
        UserDefaults.standard.removeObject(forKey: smoothingCenterFloorKey)
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

    func testStabilizerOrientationClampsPersistedValuesToControlRanges() {
        UserDefaults.standard.set(-200.0, forKey: yawKey)

        XCTAssertEqual(Config.yaw, -90, accuracy: 0.0001)

        UserDefaults.standard.set(200.0, forKey: yawKey)

        XCTAssertEqual(Config.yaw, 90, accuracy: 0.0001)

        UserDefaults.standard.set(-200.0, forKey: pitchKey)

        XCTAssertEqual(Config.pitch, -90, accuracy: 0.0001)

        UserDefaults.standard.set(200.0, forKey: pitchKey)

        XCTAssertEqual(Config.pitch, 90, accuracy: 0.0001)

        UserDefaults.standard.set(-90.0, forKey: rollKey)

        XCTAssertEqual(Config.roll, -45, accuracy: 0.0001)

        UserDefaults.standard.set(90.0, forKey: rollKey)

        XCTAssertEqual(Config.roll, 45, accuracy: 0.0001)
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

    func testTrackingControlValuesClampPersistedValuesToControlRanges() {
        UserDefaults.standard.set(0.01, forKey: trackTargetRatioKey)

        XCTAssertEqual(Config.trackTargetRatio, 0.1, accuracy: 0.0001)

        UserDefaults.standard.set(2.0, forKey: trackTargetRatioKey)

        XCTAssertEqual(Config.trackTargetRatio, 1.0, accuracy: 0.0001)

        UserDefaults.standard.set(0.01, forKey: trackRecenterSpeedKey)

        XCTAssertEqual(Config.trackRecenterSpeed, 0.05, accuracy: 0.0001)

        UserDefaults.standard.set(0.8, forKey: trackRecenterSpeedKey)

        XCTAssertEqual(Config.trackRecenterSpeed, 0.5, accuracy: 0.0001)

        UserDefaults.standard.set(-10.0, forKey: recenterGraceMsKey)

        XCTAssertEqual(Config.recenterGraceMs, 0, accuracy: 0.0001)

        UserDefaults.standard.set(3_000.0, forKey: recenterGraceMsKey)

        XCTAssertEqual(Config.recenterGraceMs, 2_000, accuracy: 0.0001)

        UserDefaults.standard.set(0.01, forKey: acquireSpeedKey)

        XCTAssertEqual(Config.acquireSpeed, 0.05, accuracy: 0.0001)

        UserDefaults.standard.set(0.8, forKey: acquireSpeedKey)

        XCTAssertEqual(Config.acquireSpeed, 0.5, accuracy: 0.0001)
    }

    func testOverlayControlValuesClampPersistedValuesToControlRanges() {
        UserDefaults.standard.set(-2.0, forKey: overlayPosXKey)

        XCTAssertEqual(Config.overlayPosX, -0.5, accuracy: 0.0001)

        UserDefaults.standard.set(3.0, forKey: overlayPosXKey)

        XCTAssertEqual(Config.overlayPosX, 1.5, accuracy: 0.0001)

        UserDefaults.standard.set(-2.0, forKey: overlayPosYKey)

        XCTAssertEqual(Config.overlayPosY, -0.5, accuracy: 0.0001)

        UserDefaults.standard.set(3.0, forKey: overlayPosYKey)

        XCTAssertEqual(Config.overlayPosY, 1.5, accuracy: 0.0001)

        UserDefaults.standard.set(0.001, forKey: overlayScaleKey)

        XCTAssertEqual(Config.overlayScale, 0.05, accuracy: 0.0001)

        UserDefaults.standard.set(5.0, forKey: overlayScaleKey)

        XCTAssertEqual(Config.overlayScale, 3.0, accuracy: 0.0001)

        UserDefaults.standard.set(-0.5, forKey: overlayOpacityKey)

        XCTAssertEqual(Config.overlayOpacity, 0.0, accuracy: 0.0001)

        UserDefaults.standard.set(2.0, forKey: overlayOpacityKey)

        XCTAssertEqual(Config.overlayOpacity, 1.0, accuracy: 0.0001)

        UserDefaults.standard.set(-45.0, forKey: overlayRotationKey)

        XCTAssertEqual(Config.overlayRotation, 0.0, accuracy: 0.0001)

        UserDefaults.standard.set(720.0, forKey: overlayRotationKey)

        XCTAssertEqual(Config.overlayRotation, 360.0, accuracy: 0.0001)

        UserDefaults.standard.set(-750.0, forKey: cropHorizontalOffsetKey)

        XCTAssertEqual(Config.cropHorizontalOffset, -500.0, accuracy: 0.0001)

        UserDefaults.standard.set(750.0, forKey: cropHorizontalOffsetKey)

        XCTAssertEqual(Config.cropHorizontalOffset, 500.0, accuracy: 0.0001)
    }

    func testSmoothingControlValuesClampPersistedValuesToControlRanges() {
        UserDefaults.standard.set(0.001, forKey: smoothingBaseAlphaKey)

        XCTAssertEqual(Config.smoothingBaseAlpha, 0.05, accuracy: 0.0001)

        UserDefaults.standard.set(2.0, forKey: smoothingBaseAlphaKey)

        XCTAssertEqual(Config.smoothingBaseAlpha, 1.0, accuracy: 0.0001)

        UserDefaults.standard.set(-0.5, forKey: smoothingMinDeviationKey)

        XCTAssertEqual(Config.smoothingMinDeviation, 0.0, accuracy: 0.0001)

        UserDefaults.standard.set(0.5, forKey: smoothingMinDeviationKey)

        XCTAssertEqual(Config.smoothingMinDeviation, 0.1, accuracy: 0.0001)

        UserDefaults.standard.set(-0.5, forKey: smoothingMaxDeviationKey)

        XCTAssertEqual(Config.smoothingMaxDeviation, 0.0, accuracy: 0.0001)

        UserDefaults.standard.set(0.5, forKey: smoothingMaxDeviationKey)

        XCTAssertEqual(Config.smoothingMaxDeviation, 0.15, accuracy: 0.0001)

        UserDefaults.standard.set(-0.5, forKey: smoothingCenterFloorKey)

        XCTAssertEqual(Config.smoothingCenterFloor, 0.0, accuracy: 0.0001)

        UserDefaults.standard.set(2.0, forKey: smoothingCenterFloorKey)

        XCTAssertEqual(Config.smoothingCenterFloor, 1.0, accuracy: 0.0001)
    }
}
