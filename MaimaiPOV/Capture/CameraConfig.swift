import AVFoundation

enum LensType: String, CaseIterable {
    case main = "Main (1x)"
    case ultraWide = "Ultra-Wide (0.5x)"

    var displayName: String {
        L10n.string(rawValue)
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .main:      return .builtInWideAngleCamera
        case .ultraWide: return .builtInUltraWideCamera
        }
    }
}
