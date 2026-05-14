import SwiftUI
import Combine
import AVFoundation
import CoreMedia
import Metal
import simd
import QuartzCore
import UIKit
import CoreImage

class LivePipelineManager: ObservableObject {
    @Published var focusValue: Double = 0.5
    @Published var shutterTimescale: Double = 244.0
    @Published var isoValue: Double = 2000.0
    @Published var minISO: Double = 50.0
    @Published var maxISO: Double = 3200.0
    @Published var selectedLens: LensType = .main

    @Published var syncOffsetMs: Double = Config.defaultSyncOffsetMs
    @Published var readoutTimeMs: Double = Config.defaultReadoutTimeMs
    @Published var audioDelayMs: Double = 0.0

    @Published var fov: Float = 100.0
    @Published var distRatio: Float = 0.0
    @Published var yaw: Float = 0.0
    @Published var pitch: Float = 0.0
    @Published var roll: Float = 0.0
    @Published var stabEnabled: Bool = true
    @Published var lagMs: Double = 0

    @Published var yoloEnabled: Bool = true
    @Published var yoloPadding: Double = Double(Config.yoloPadding)

    @Published var trackAlpha: Double = Double(Config.defaultAlpha)
    @Published var trackMaxSpeed: Double = Double(Config.defaultMaxSpeed)
    @Published var trackDeadZone: Double = Double(Config.defaultDeadZone)
    @Published var trackTargetRatio: Double = Double(Config.defaultTargetRatio)

    @Published var currentFPS: Double = 0

    let camera = CameraCaptureManager()
    let debug = DebugInfoManager.shared
    let device: MTLDevice = MTLCreateSystemDefaultDevice()!
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var stabilizer: MetalStabilizer?
    var yoloDetector: YOLODetector?
    var cropRenderer: CropRenderer?
    var smoothTracker = SmoothTracker()
    var latestTrackOutput: SmoothTracker.TrackOutput?

    var previewTexture: MTLTexture? {
        if let cr = cropRenderer {
            return cr.outputTexture
        }
        return stabilizer?.outputTexture
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        camera.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        debug.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
}
