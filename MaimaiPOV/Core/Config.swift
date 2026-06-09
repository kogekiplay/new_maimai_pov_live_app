import Foundation

enum Config {
    // Resolution
    static let inputWidth  = 1440
    static let inputHeight = 1920
    static let stabWidth   = 1080
    static let stabHeight  = 1440
    static let yoloInputSize = 640
    static let defaultYoloPadding: Int = 40
    static let yoloPaddingRange = 0...100
    static var yoloPadding: Int {
        get {
            guard UserDefaults.standard.object(forKey: yoloPaddingKey) != nil else {
                return defaultYoloPadding
            }
            return clampYoloPadding(UserDefaults.standard.integer(forKey: yoloPaddingKey))
        }
        set {
            UserDefaults.standard.set(clampYoloPadding(newValue), forKey: yoloPaddingKey)
        }
    }
    static let defaultYoloPreviewEnabled: Bool = false
    static var yoloPreviewEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: yoloPreviewEnabledKey) != nil else {
                return defaultYoloPreviewEnabled
            }
            return UserDefaults.standard.bool(forKey: yoloPreviewEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: yoloPreviewEnabledKey) }
    }
    static let defaultYoloOverlayEnabled: Bool = false
    static var yoloOverlayEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: yoloOverlayEnabledKey) != nil else {
                return defaultYoloOverlayEnabled
            }
            return UserDefaults.standard.bool(forKey: yoloOverlayEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: yoloOverlayEnabledKey) }
    }
    static let defaultYoloOverlayScale: Double = 0.6
    static var yoloOverlayScale: Double {
        get {
            guard UserDefaults.standard.object(forKey: yoloOverlayScaleKey) != nil else {
                return defaultYoloOverlayScale
            }
            return UserDefaults.standard.double(forKey: yoloOverlayScaleKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: yoloOverlayScaleKey) }
    }
    static let defaultYoloTargetFPS: Double = 60.0
    static var yoloTargetFPS: Double {
        get {
            guard UserDefaults.standard.object(forKey: yoloTargetFPSKey) != nil else {
                return defaultYoloTargetFPS
            }
            return UserDefaults.standard.double(forKey: yoloTargetFPSKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: yoloTargetFPSKey) }
    }
    static let outputWidth  = 1920
    static let outputHeight = 1080

    static let gameAreaRatio: Float = 1.0
    static var gameAreaWidth: Int {
        Int(Float(outputHeight) * gameAreaRatio)
    }
    static var gameAreaHeight: Int {
        outputHeight
    }
    static var gameAreaX: Int {
        (outputWidth - gameAreaWidth) / 2
    }
    static var gameAreaY: Int {
        0
    }

    // Camera settings
    static let defaultFocusValue: Double = 0.5
    static let focusValueRange = 0.0...1.0
    static var focusValue: Double {
        get {
            guard UserDefaults.standard.object(forKey: focusValueKey) != nil else {
                return defaultFocusValue
            }
            return clampDouble(UserDefaults.standard.double(forKey: focusValueKey), to: focusValueRange)
        }
        set {
            UserDefaults.standard.set(clampDouble(newValue, to: focusValueRange), forKey: focusValueKey)
        }
    }
    static let defaultAutoFocusEnabled: Bool = false
    static var autoFocusEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: autoFocusEnabledKey) != nil else {
                return defaultAutoFocusEnabled
            }
            return UserDefaults.standard.bool(forKey: autoFocusEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoFocusEnabledKey) }
    }
    static let defaultShutterTimescale: Double = 244.0
    static let shutterTimescaleRange = 30.0...1000.0
    static var shutterTimescale: Double {
        get {
            guard UserDefaults.standard.object(forKey: shutterTimescaleKey) != nil else {
                return defaultShutterTimescale
            }
            return clampDouble(UserDefaults.standard.double(forKey: shutterTimescaleKey), to: shutterTimescaleRange)
        }
        set {
            UserDefaults.standard.set(clampDouble(newValue, to: shutterTimescaleRange), forKey: shutterTimescaleKey)
        }
    }
    static let defaultIsoValue: Double = 2000.0
    static var isoValue: Double {
        get {
            guard UserDefaults.standard.object(forKey: isoValueKey) != nil else {
                return defaultIsoValue
            }
            return UserDefaults.standard.double(forKey: isoValueKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: isoValueKey) }
    }
    static let defaultSelectedLens: LensType = .main
    static var selectedLens: LensType {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: selectedLensKey),
                  let lens = LensType(rawValue: rawValue) else {
                return defaultSelectedLens
            }
            return lens
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectedLensKey) }
    }

    // Tracking defaults
    static let defaultTargetRatio: Float = 0.35
    static let trackTargetRatioRange = 0.1...1.0
    static var trackTargetRatio: Double {
        get {
            guard UserDefaults.standard.object(forKey: trackTargetRatioKey) != nil else {
                return Double(defaultTargetRatio)
            }
            return clampDouble(UserDefaults.standard.double(forKey: trackTargetRatioKey), to: trackTargetRatioRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: trackTargetRatioRange), forKey: trackTargetRatioKey) }
    }
    static let defaultRecenterSpeed: Float = 0.15
    static let trackRecenterSpeedRange = 0.05...0.5
    static var trackRecenterSpeed: Double {
        get {
            guard UserDefaults.standard.object(forKey: trackRecenterSpeedKey) != nil else {
                return Double(defaultRecenterSpeed)
            }
            return clampDouble(UserDefaults.standard.double(forKey: trackRecenterSpeedKey), to: trackRecenterSpeedRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: trackRecenterSpeedRange), forKey: trackRecenterSpeedKey) }
    }
    static let defaultRecenterGraceMs: Double = 500.0
    static let recenterGraceMsRange = 0.0...2000.0
    static var recenterGraceMs: Double {
        get {
            guard UserDefaults.standard.object(forKey: recenterGraceMsKey) != nil else {
                return defaultRecenterGraceMs
            }
            return clampDouble(UserDefaults.standard.double(forKey: recenterGraceMsKey), to: recenterGraceMsRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: recenterGraceMsRange), forKey: recenterGraceMsKey) }
    }
    static let defaultAcquireSpeed: Float = 0.15
    static let acquireSpeedRange = 0.05...0.5
    static var acquireSpeed: Double {
        get {
            guard UserDefaults.standard.object(forKey: acquireSpeedKey) != nil else {
                return Double(defaultAcquireSpeed)
            }
            return clampDouble(UserDefaults.standard.double(forKey: acquireSpeedKey), to: acquireSpeedRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: acquireSpeedRange), forKey: acquireSpeedKey) }
    }
    static let defaultConfidenceThreshold: Float = 0.75

    static let defaultSmoothingEnabled: Bool = true
    static let defaultSmoothingBaseAlpha: Double = 0.3
    static let smoothingBaseAlphaRange = 0.05...1.0
    static let defaultSmoothingMinDeviation: Double = 0.02
    static let smoothingMinDeviationRange = 0.0...0.1
    static let defaultSmoothingMaxDeviation: Double = 0.05
    static let smoothingMaxDeviationRange = 0.0...0.15
    static let defaultSmoothingCenterFloor: Double = 0.3
    static let smoothingCenterFloorRange = 0.0...1.0

    static var smoothingEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: smoothingEnabledKey) != nil else {
                return defaultSmoothingEnabled
            }
            return UserDefaults.standard.bool(forKey: smoothingEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: smoothingEnabledKey) }
    }
    static var smoothingBaseAlpha: Double {
        get {
            guard UserDefaults.standard.object(forKey: smoothingBaseAlphaKey) != nil else {
                return defaultSmoothingBaseAlpha
            }
            return clampDouble(UserDefaults.standard.double(forKey: smoothingBaseAlphaKey), to: smoothingBaseAlphaRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: smoothingBaseAlphaRange), forKey: smoothingBaseAlphaKey) }
    }
    static var smoothingMinDeviation: Double {
        get {
            guard UserDefaults.standard.object(forKey: smoothingMinDeviationKey) != nil else {
                return defaultSmoothingMinDeviation
            }
            return clampDouble(UserDefaults.standard.double(forKey: smoothingMinDeviationKey), to: smoothingMinDeviationRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: smoothingMinDeviationRange), forKey: smoothingMinDeviationKey) }
    }
    static var smoothingMaxDeviation: Double {
        get {
            guard UserDefaults.standard.object(forKey: smoothingMaxDeviationKey) != nil else {
                return defaultSmoothingMaxDeviation
            }
            return clampDouble(UserDefaults.standard.double(forKey: smoothingMaxDeviationKey), to: smoothingMaxDeviationRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: smoothingMaxDeviationRange), forKey: smoothingMaxDeviationKey) }
    }
    static var smoothingCenterFloor: Double {
        get {
            guard UserDefaults.standard.object(forKey: smoothingCenterFloorKey) != nil else {
                return defaultSmoothingCenterFloor
            }
            return clampDouble(UserDefaults.standard.double(forKey: smoothingCenterFloorKey), to: smoothingCenterFloorRange)
        }
        set { UserDefaults.standard.set(clampDouble(newValue, to: smoothingCenterFloorRange), forKey: smoothingCenterFloorKey) }
    }

    // Stabilizer defaults
    static let defaultFov: Float = 100.0
    static let fovRange: ClosedRange<Float> = 30.0...160.0
    static var fov: Float {
        get {
            guard UserDefaults.standard.object(forKey: fovKey) != nil else {
                return defaultFov
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: fovKey)), to: fovRange)
        }
        set {
            UserDefaults.standard.set(Double(clampFloat(newValue, to: fovRange)), forKey: fovKey)
        }
    }
    static let defaultDistRatio: Float = 0.0
    static let distRatioRange: ClosedRange<Float> = 0.0...1.0
    static var distRatio: Float {
        get {
            guard UserDefaults.standard.object(forKey: distRatioKey) != nil else {
                return defaultDistRatio
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: distRatioKey)), to: distRatioRange)
        }
        set {
            UserDefaults.standard.set(Double(clampFloat(newValue, to: distRatioRange)), forKey: distRatioKey)
        }
    }
    static let defaultYaw: Float   = 0.0
    static let yawRange: ClosedRange<Float> = -90.0...90.0
    static var yaw: Float {
        get {
            guard UserDefaults.standard.object(forKey: yawKey) != nil else {
                return defaultYaw
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: yawKey)), to: yawRange)
        }
        set {
            UserDefaults.standard.set(Double(clampFloat(newValue, to: yawRange)), forKey: yawKey)
        }
    }
    static let defaultPitch: Float = 0.0
    static let pitchRange: ClosedRange<Float> = -90.0...90.0
    static var pitch: Float {
        get {
            guard UserDefaults.standard.object(forKey: pitchKey) != nil else {
                return defaultPitch
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: pitchKey)), to: pitchRange)
        }
        set {
            UserDefaults.standard.set(Double(clampFloat(newValue, to: pitchRange)), forKey: pitchKey)
        }
    }
    static let defaultRoll: Float  = 0.0
    static let rollRange: ClosedRange<Float> = -45.0...45.0
    static var roll: Float {
        get {
            guard UserDefaults.standard.object(forKey: rollKey) != nil else {
                return defaultRoll
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: rollKey)), to: rollRange)
        }
        set {
            UserDefaults.standard.set(Double(clampFloat(newValue, to: rollRange)), forKey: rollKey)
        }
    }
    static let defaultStabEnabled: Bool = true
    static var stabEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: stabEnabledKey) != nil else {
                return defaultStabEnabled
            }
            return UserDefaults.standard.bool(forKey: stabEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: stabEnabledKey) }
    }
    static let defaultPreviewEnabled: Bool = true
    static var previewEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: previewEnabledKey) != nil else {
                return defaultPreviewEnabled
            }
            return UserDefaults.standard.bool(forKey: previewEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: previewEnabledKey) }
    }
    static let defaultYoloEnabled: Bool = true
    static var yoloEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: yoloEnabledKey) != nil else {
                return defaultYoloEnabled
            }
            return UserDefaults.standard.bool(forKey: yoloEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: yoloEnabledKey) }
    }

    // IMU sync (runtime-adjustable, persisted)
    static let syncOffsetRange = -50.0...50.0
    static var syncOffsetMs: Double {
        get {
            guard UserDefaults.standard.object(forKey: syncOffsetKey) != nil else {
                return defaultSyncOffsetMs
            }
            return clampDouble(UserDefaults.standard.double(forKey: syncOffsetKey), to: syncOffsetRange)
        }
        set {
            UserDefaults.standard.set(clampDouble(newValue, to: syncOffsetRange), forKey: syncOffsetKey)
        }
    }
    static let readoutTimeRange = 5.0...15.0
    static var readoutTimeMs: Double {
        get {
            guard UserDefaults.standard.object(forKey: readoutTimeKey) != nil else {
                return defaultReadoutTimeMs
            }
            return clampDouble(UserDefaults.standard.double(forKey: readoutTimeKey), to: readoutTimeRange)
        }
        set {
            UserDefaults.standard.set(clampDouble(newValue, to: readoutTimeRange), forKey: readoutTimeKey)
        }
    }
    static let defaultSyncOffsetMs: Double = -25.0
    static let defaultReadoutTimeMs: Double = 9.18
    
    static let defaultOverlayEnabled: Bool = false
    static var overlayEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: overlayEnabledKey) != nil else {
                return defaultOverlayEnabled
            }
            return UserDefaults.standard.bool(forKey: overlayEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: overlayEnabledKey) }
    }

    static let defaultOverlayPosX: Float = 0.5
    static let overlayPositionRange: ClosedRange<Float> = -0.5...1.5
    static var overlayPosX: Float {
        get {
            guard UserDefaults.standard.object(forKey: overlayPosXKey) != nil else {
                return defaultOverlayPosX
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: overlayPosXKey)), to: overlayPositionRange)
        }
        set { UserDefaults.standard.set(Double(clampFloat(newValue, to: overlayPositionRange)), forKey: overlayPosXKey) }
    }
    static let defaultOverlayPosY: Float = 0.5
    static var overlayPosY: Float {
        get {
            guard UserDefaults.standard.object(forKey: overlayPosYKey) != nil else {
                return defaultOverlayPosY
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: overlayPosYKey)), to: overlayPositionRange)
        }
        set { UserDefaults.standard.set(Double(clampFloat(newValue, to: overlayPositionRange)), forKey: overlayPosYKey) }
    }
    static let defaultOverlayScale: Float = 0.2
    static let overlayScaleRange: ClosedRange<Float> = 0.05...3.0
    static var overlayScale: Float {
        get {
            guard UserDefaults.standard.object(forKey: overlayScaleKey) != nil else {
                return defaultOverlayScale
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: overlayScaleKey)), to: overlayScaleRange)
        }
        set { UserDefaults.standard.set(Double(clampFloat(newValue, to: overlayScaleRange)), forKey: overlayScaleKey) }
    }
    static let defaultOverlayOpacity: Float = 1.0
    static let overlayOpacityRange: ClosedRange<Float> = 0.0...1.0
    static var overlayOpacity: Float {
        get {
            guard UserDefaults.standard.object(forKey: overlayOpacityKey) != nil else {
                return defaultOverlayOpacity
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: overlayOpacityKey)), to: overlayOpacityRange)
        }
        set { UserDefaults.standard.set(Double(clampFloat(newValue, to: overlayOpacityRange)), forKey: overlayOpacityKey) }
    }
    static let defaultOverlayRotation: Float = 0.0
    static let overlayRotationRange: ClosedRange<Float> = 0.0...360.0
    static var overlayRotation: Float {
        get {
            guard UserDefaults.standard.object(forKey: overlayRotationKey) != nil else {
                return defaultOverlayRotation
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: overlayRotationKey)), to: overlayRotationRange)
        }
        set { UserDefaults.standard.set(Double(clampFloat(newValue, to: overlayRotationRange)), forKey: overlayRotationKey) }
    }

    static let defaultLeftPanelEnabled: Bool = true
    static var leftPanelEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: leftPanelEnabledKey) != nil else {
                return defaultLeftPanelEnabled
            }
            return UserDefaults.standard.bool(forKey: leftPanelEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: leftPanelEnabledKey) }
    }

    static var defaultAnnouncementText: String {
        L10n.string("Default Announcement Text")
    }
    static var announcementText: String {
        get { UserDefaults.standard.string(forKey: announcementTextKey) ?? defaultAnnouncementText }
        set { UserDefaults.standard.set(newValue, forKey: announcementTextKey) }
    }

    static let defaultBlivechatServer: String = BlivechatServer.cn.rawValue
    static var blivechatServer: String {
        get { UserDefaults.standard.string(forKey: blivechatServerKey) ?? defaultBlivechatServer }
        set { UserDefaults.standard.set(newValue, forKey: blivechatServerKey) }
    }

    static var blivechatIdentityCode: String {
        get { UserDefaults.standard.string(forKey: blivechatIdentityCodeKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: blivechatIdentityCodeKey) }
    }

    static let defaultGiftDurationMinutes: Int = 30
    static var giftDurationMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: giftDurationMinutesKey)
            return v == 0 ? defaultGiftDurationMinutes : v
        }
        set { UserDefaults.standard.set(newValue, forKey: giftDurationMinutesKey) }
    }

    static let defaultSuperChatDurationMinutes: Int = 60
    static var superChatDurationMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: superChatDurationMinutesKey)
            return v == 0 ? defaultSuperChatDurationMinutes : v
        }
        set { UserDefaults.standard.set(newValue, forKey: superChatDurationMinutesKey) }
    }

    static let defaultGuardDurationMinutes: Int = 1440
    static var guardDurationMinutes: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: guardDurationMinutesKey)
            return v == 0 ? defaultGuardDurationMinutes : v
        }
        set { UserDefaults.standard.set(newValue, forKey: guardDurationMinutesKey) }
    }

    static let defaultCropHorizontalOffset: Float = 0.0
    static let cropHorizontalOffsetRange: ClosedRange<Float> = -500.0...500.0
    static var cropHorizontalOffset: Float {
        get {
            guard UserDefaults.standard.object(forKey: cropHorizontalOffsetKey) != nil else {
                return defaultCropHorizontalOffset
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: cropHorizontalOffsetKey)), to: cropHorizontalOffsetRange)
        }
        set { UserDefaults.standard.set(Double(clampFloat(newValue, to: cropHorizontalOffsetRange)), forKey: cropHorizontalOffsetKey) }
    }

    static let defaultActivitySmoothFactor: Float = 0.03
    static let activitySmoothFactorRange: ClosedRange<Float> = 0.01...0.2
    static var activitySmoothFactor: Float {
        get {
            guard UserDefaults.standard.object(forKey: activitySmoothFactorKey) != nil else {
                return defaultActivitySmoothFactor
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: activitySmoothFactorKey)), to: activitySmoothFactorRange)
        }
        set {
            UserDefaults.standard.set(Double(clampFloat(newValue, to: activitySmoothFactorRange)), forKey: activitySmoothFactorKey)
        }
    }

    static let defaultStreamBitrate: Int = 4000
    static let streamBitrateRange = 1_000...10_000
    static var streamBitrate: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: streamBitrateKey)
            return clampStreamBitrate(v == 0 ? defaultStreamBitrate : v)
        }
        set {
            UserDefaults.standard.set(clampStreamBitrate(newValue), forKey: streamBitrateKey)
        }
    }

    static let defaultMarqueeSpeed: Float = 3.0
    static let marqueeSpeedRange: ClosedRange<Float> = 0.5...20.0
    static var marqueeSpeed: Float {
        get {
            guard UserDefaults.standard.object(forKey: marqueeSpeedKey) != nil else {
                return defaultMarqueeSpeed
            }
            return clampFloat(Float(UserDefaults.standard.double(forKey: marqueeSpeedKey)), to: marqueeSpeedRange)
        }
        set { UserDefaults.standard.set(Double(clampFloat(newValue, to: marqueeSpeedRange)), forKey: marqueeSpeedKey) }
    }

    static let defaultDeviceStatusEnabled: Bool = true
    static var deviceStatusEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: deviceStatusEnabledKey) != nil else {
                return defaultDeviceStatusEnabled
            }
            return UserDefaults.standard.bool(forKey: deviceStatusEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: deviceStatusEnabledKey) }
    }

    static let defaultSongRequestPaused: Bool = false
    static var songRequestPaused: Bool {
        get {
            guard UserDefaults.standard.object(forKey: songRequestPausedKey) != nil else {
                return defaultSongRequestPaused
            }
            return UserDefaults.standard.bool(forKey: songRequestPausedKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: songRequestPausedKey) }
    }

    static let defaultSongRequestPauseThreshold: Int = 30
    static let songRequestPauseThresholdRange = 1...9_999
    static var songRequestPauseThreshold: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: songRequestPauseThresholdKey)
            return clampSongRequestPauseThreshold(v == 0 ? defaultSongRequestPauseThreshold : v)
        }
        set {
            UserDefaults.standard.set(clampSongRequestPauseThreshold(newValue), forKey: songRequestPauseThresholdKey)
        }
    }

    // UserDefaults keys
    private static let syncOffsetKey = "com.maimai.syncOffsetMs"
    private static let readoutTimeKey = "com.maimai.readoutTimeMs"
    private static let yoloPaddingKey = "com.maimai.yoloPadding"
    private static let yoloPreviewEnabledKey = "com.maimai.yoloPreviewEnabled"
    private static let yoloOverlayEnabledKey = "com.maimai.yoloOverlayEnabled"
    private static let yoloOverlayScaleKey = "com.maimai.yoloOverlayScale"
    private static let yoloTargetFPSKey = "com.maimai.yoloTargetFPS"
    private static let focusValueKey = "com.maimai.focusValue"
    private static let shutterTimescaleKey = "com.maimai.shutterTimescale"
    private static let isoValueKey = "com.maimai.isoValue"
    private static let selectedLensKey = "com.maimai.selectedLens"
    private static let fovKey = "com.maimai.fov"
    private static let distRatioKey = "com.maimai.distRatio"
    private static let yawKey = "com.maimai.yaw"
    private static let pitchKey = "com.maimai.pitch"
    private static let rollKey = "com.maimai.roll"
    private static let stabEnabledKey = "com.maimai.stabEnabled"
    private static let previewEnabledKey = "com.maimai.previewEnabled"
    private static let yoloEnabledKey = "com.maimai.yoloEnabled"
    private static let trackTargetRatioKey = "com.maimai.trackTargetRatio"
    private static let trackRecenterSpeedKey = "com.maimai.trackRecenterSpeed"
    private static let recenterGraceMsKey = "com.maimai.recenterGraceMs"
    private static let acquireSpeedKey = "com.maimai.acquireSpeed"
    private static let smoothingEnabledKey = "com.maimai.smoothingEnabled"
    private static let smoothingBaseAlphaKey = "com.maimai.smoothingBaseAlpha"
    private static let smoothingMinDeviationKey = "com.maimai.smoothingMinDeviation"
    private static let smoothingMaxDeviationKey = "com.maimai.smoothingMaxDeviation"
    private static let smoothingCenterFloorKey = "com.maimai.smoothingCenterFloor"
    private static let overlayEnabledKey = "com.maimai.overlayEnabled"
    private static let overlayPosXKey = "com.maimai.overlayPosX"
    private static let overlayPosYKey = "com.maimai.overlayPosY"
    private static let overlayScaleKey = "com.maimai.overlayScale"
    private static let overlayOpacityKey = "com.maimai.overlayOpacity"
    private static let overlayRotationKey = "com.maimai.overlayRotation"
    private static let cropHorizontalOffsetKey = "com.maimai.cropHorizontalOffset"
    private static let activitySmoothFactorKey = "com.maimai.activitySmoothFactor"
    private static let leftPanelEnabledKey = "com.maimai.leftPanelEnabled"
    private static let announcementTextKey = "com.maimai.announcementText"
    private static let blivechatServerKey = "com.maimai.blivechatServer"
    private static let blivechatIdentityCodeKey = "com.maimai.blivechatIdentityCode"
    private static let giftDurationMinutesKey = "com.maimai.giftDurationMinutes"
    private static let superChatDurationMinutesKey = "com.maimai.superChatDurationMinutes"
    private static let guardDurationMinutesKey = "com.maimai.guardDurationMinutes"
    private static let autoFocusEnabledKey = "com.maimai.autoFocusEnabled"
    private static let streamBitrateKey = "com.maimai.streamBitrate"
    private static let marqueeSpeedKey = "com.maimai.marqueeSpeed"
    private static let deviceStatusEnabledKey = "com.maimai.deviceStatusEnabled"
    private static let songRequestPausedKey = "com.maimai.songRequestPaused"
    private static let songRequestPauseThresholdKey = "com.maimai.songRequestPauseThreshold"
    // Audio encoding
    static let audioSampleRate: Double = 44100.0
    static let audioBitrate: Int = 128_000

    // Streaming buffer & reconnect
    static let streamVideoBufferFrames: Int = 120
    static let streamAudioBufferFrames: Int = 200
    static let maxReconnectAttempts: Int = 5
    static let maxReconnectDelaySeconds: Double = 16.0

    static var streamPresets: [StreamPreset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: streamPresetsKey) else { return [] }
            return (try? JSONDecoder().decode([StreamPreset].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: streamPresetsKey)
            }
        }
    }
    private static let streamPresetsKey = "com.maimai.streamPresets"

    private static func clampStreamBitrate(_ value: Int) -> Int {
        min(max(value, streamBitrateRange.lowerBound), streamBitrateRange.upperBound)
    }

    private static func clampYoloPadding(_ value: Int) -> Int {
        min(max(value, yoloPaddingRange.lowerBound), yoloPaddingRange.upperBound)
    }

    private static func clampSongRequestPauseThreshold(_ value: Int) -> Int {
        min(max(value, songRequestPauseThresholdRange.lowerBound), songRequestPauseThresholdRange.upperBound)
    }

    private static func clampFloat(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clampDouble(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct StreamPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var url: String
    var streamKey: String

    init(id: UUID = UUID(), name: String, url: String, streamKey: String) {
        self.id = id
        self.name = name
        self.url = url
        self.streamKey = streamKey
    }
}
