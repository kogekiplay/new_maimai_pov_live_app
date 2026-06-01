import AVFoundation
import Combine

class AudioDeviceManager: ObservableObject {
    enum AudioSource: String, CaseIterable {
        case builtInMic = "内置麦"
        case externalMono = "DJI 单声道"
        case externalStereo = "DJI 立体声"
    }

    @Published var availableSources: [AudioSource] = [.builtInMic]
    @Published var selectedSource: AudioSource = .builtInMic
    @Published var externalDeviceName: String?
    @Published var isExternalDeviceConnected: Bool = false
    @Published var isStereoMixEnabled: Bool = false

    var onSourceChanged: ((AudioSource) -> Void)?

    private var routeChangeObserver: Any?
    private let audioSession = AVAudioSession.sharedInstance()

    init() {
        detectCurrentDevices()
        observeRouteChanges()
    }

    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func isExternalPort(_ portType: AVAudioSession.Port) -> Bool {
        return portType == AVAudioSession.Port.usbAudio || portType == .headsetMic
    }

    func detectCurrentDevices() {
        availableSources = [.builtInMic]
        isExternalDeviceConnected = false
        externalDeviceName = nil

        guard let inputs = audioSession.availableInputs else { return }
        for input in inputs {
            if isExternalPort(input.portType) {
                availableSources.append(.externalMono)
                availableSources.append(.externalStereo)
                externalDeviceName = input.portName
                isExternalDeviceConnected = true
                break
            }
        }

        if !availableSources.contains(selectedSource) {
            selectedSource = .builtInMic
            isStereoMixEnabled = false
        }
    }

    func switchToSource(_ source: AudioSource) {
        guard source != selectedSource else { return }
        selectedSource = source
        isStereoMixEnabled = (source == .externalStereo)

        switch source {
        case .builtInMic:
            configureBuiltInMic()
        case .externalMono, .externalStereo:
            configureExternalDevice()
        }

        onSourceChanged?(source)
    }

    func configureBuiltInMic() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)

            guard let inputs = audioSession.availableInputs else { return }
            let builtInMicInput = inputs.first(where: { $0.portType == .builtInMic })
            guard let builtInMicInput else { return }
            try audioSession.setPreferredInput(builtInMicInput)

            let dataSources = builtInMicInput.dataSources
            let backMic = dataSources?.first(where: { $0.orientation == .back })
            if let backMic {
                let supportedPatterns = backMic.supportedPolarPatterns
                if let supportedPatterns, supportedPatterns.contains(.cardioid) {
                    try? backMic.setPreferredPolarPattern(.cardioid)
                }
                try? builtInMicInput.setPreferredDataSource(backMic)
            }
            try? audioSession.setPreferredInputOrientation(.portrait)
        } catch {
            print("AudioDeviceManager: Built-in mic config failed: \(error)")
        }
    }

    func configureExternalDevice() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)

            let inputs = audioSession.availableInputs
            let externalInput = inputs?.first(where: { isExternalPort($0.portType) })
            if let externalInput {
                try audioSession.setPreferredInput(externalInput)
                externalDeviceName = externalInput.portName
            }
        } catch {
            print("AudioDeviceManager: External device config failed: \(error)")
        }
    }

    private func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.detectCurrentDevices()

            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt {
                let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason)
                if changeReason == .oldDeviceUnavailable {
                    if self.selectedSource != .builtInMic {
                        self.selectedSource = .builtInMic
                        self.isStereoMixEnabled = false
                        self.configureBuiltInMic()
                        self.onSourceChanged?(.builtInMic)
                    }
                }
            }
        }
    }
}
