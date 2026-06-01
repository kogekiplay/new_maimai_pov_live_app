import AVFoundation
import Accelerate

class AudioMixer: ObservableObject {
    @Published var leftGain: Float = 1.0
    @Published var rightGain: Float = 1.0
    @Published var leftLevel: Float = 0.0
    @Published var rightLevel: Float = 0.0
    @Published var mixedLevel: Float = 0.0
    @Published var audioFormatInfo: String = "--"

    var isStereoMixEnabled: Bool = false

    private var monoFormat: AVAudioFormat?
    private var monoBuffer: AVAudioPCMBuffer?
    private let levelSmoothing: Float = 0.3
    private var smoothedLeftLevel: Float = 0
    private var smoothedRightLevel: Float = 0
    private var smoothedMixedLevel: Float = 0
    private var levelUpdateCounter: Int = 0
    private let levelUpdateInterval: Int = 3

    private var standardFormat: AVAudioFormat?
    private var standardBuffer: AVAudioPCMBuffer?
    private var audioConverter: AVAudioConverter?

    func process(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        if isStereoMixEnabled && input.format.channelCount >= 2 {
            return processStereo(input)
        } else {
            return processMono(input)
        }
    }

    func calculateLevel(_ input: AVAudioPCMBuffer) {
        let frameLength = Int(input.frameLength)
        guard frameLength > 0 else { return }

        if let floatData = input.floatChannelData?[0] {
            calculateLevelFromFloat(floatData, frameLength: frameLength)
        } else {
            calculateLevelViaConversion(input)
        }
    }

    private func calculateLevelFromFloat(_ data: UnsafePointer<Float>, frameLength: Int) {
        var sum: Float = 0
        vDSP_svesq(data, 1, &sum, vDSP_Length(frameLength))
        let rawLevel = sqrt(sum / Float(frameLength)) * 5.0
        smoothedLeftLevel = smoothedLeftLevel * (1 - levelSmoothing) + min(rawLevel, 1.0) * levelSmoothing
        smoothedRightLevel = smoothedLeftLevel
        smoothedMixedLevel = smoothedLeftLevel
        updateLevelsOnMain()
    }

    private func calculateLevelViaConversion(_ input: AVAudioPCMBuffer) {
        let sampleRate = input.format.sampleRate
        let channels = input.format.channelCount
        let frameLength = Int(input.frameLength)

        if standardFormat == nil || standardFormat!.sampleRate != sampleRate || standardFormat!.channelCount != channels {
            standardFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
            audioConverter = AVAudioConverter(from: input.format, to: standardFormat!)
            standardBuffer = nil
        }

        guard let format = standardFormat, let converter = audioConverter else { return }

        if standardBuffer == nil || standardBuffer!.frameCapacity < AVAudioFrameCount(frameLength) {
            standardBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength))
        }

        guard let buffer = standardBuffer else { return }

        var error: NSError?
        let convertedFrames = converter.convert(to: buffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return input
        }

        guard convertedFrames > 0, let floatData = buffer.floatChannelData?[0] else { return }

        let convertedLength = Int(buffer.frameLength)
        var sum: Float = 0
        vDSP_svesq(floatData, 1, &sum, vDSP_Length(convertedLength))
        let rawLevel = sqrt(sum / Float(convertedLength)) * 5.0
        smoothedLeftLevel = smoothedLeftLevel * (1 - levelSmoothing) + min(rawLevel, 1.0) * levelSmoothing
        smoothedRightLevel = smoothedLeftLevel
        smoothedMixedLevel = smoothedLeftLevel
        updateLevelsOnMain()
    }

    private func processStereo(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let frameLength = Int(input.frameLength)
        guard frameLength > 0 else { return input }

        guard let leftChannel = input.floatChannelData?[0],
              let rightChannel = input.floatChannelData?[1] else {
            return input
        }

        var leftSum: Float = 0
        var rightSum: Float = 0
        vDSP_svesq(leftChannel, 1, &leftSum, vDSP_Length(frameLength))
        vDSP_svesq(rightChannel, 1, &rightSum, vDSP_Length(frameLength))
        let rawLeft = sqrt(leftSum / Float(frameLength)) * 5.0
        let rawRight = sqrt(rightSum / Float(frameLength)) * 5.0

        smoothedLeftLevel = smoothedLeftLevel * (1 - levelSmoothing) + min(rawLeft, 1.0) * levelSmoothing
        smoothedRightLevel = smoothedRightLevel * (1 - levelSmoothing) + min(rawRight, 1.0) * levelSmoothing

        ensureMonoBuffer(frameLength: frameLength, sampleRate: input.format.sampleRate)
        guard let outputData = monoBuffer?.floatChannelData?[0] else { return input }

        var mixedSum: Float = 0
        for i in 0..<frameLength {
            let mixed = leftChannel[i] * leftGain + rightChannel[i] * rightGain
            outputData[i] = mixed * 0.5
            mixedSum += outputData[i] * outputData[i]
        }
        let rawMixed = sqrt(mixedSum / Float(frameLength)) * 5.0
        smoothedMixedLevel = smoothedMixedLevel * (1 - levelSmoothing) + min(rawMixed, 1.0) * levelSmoothing

        monoBuffer?.frameLength = AVAudioFrameCount(frameLength)

        updateLevelsOnMain()

        return monoBuffer ?? input
    }

    private func processMono(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let frameLength = Int(input.frameLength)
        guard frameLength > 0 else { return input }

        guard let channelData = input.floatChannelData?[0] else {
            return input
        }

        var sum: Float = 0
        vDSP_svesq(channelData, 1, &sum, vDSP_Length(frameLength))
        let rawLevel = sqrt(sum / Float(frameLength)) * 5.0
        smoothedLeftLevel = smoothedLeftLevel * (1 - levelSmoothing) + min(rawLevel, 1.0) * levelSmoothing
        smoothedRightLevel = smoothedLeftLevel
        smoothedMixedLevel = smoothedLeftLevel

        updateLevelsOnMain()

        return input
    }

    private func updateLevelsOnMain() {
        levelUpdateCounter += 1
        guard levelUpdateCounter >= levelUpdateInterval else { return }
        levelUpdateCounter = 0

        let ll = smoothedLeftLevel
        let rl = smoothedRightLevel
        let ml = smoothedMixedLevel

        DispatchQueue.main.async { [weak self] in
            self?.leftLevel = ll
            self?.rightLevel = rl
            self?.mixedLevel = ml
        }
    }

    private func ensureMonoBuffer(frameLength: Int, sampleRate: Float64) {
        if monoFormat == nil || monoFormat!.sampleRate != sampleRate {
            monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        }
        if monoBuffer == nil || monoBuffer!.frameCapacity < AVAudioFrameCount(frameLength) {
            if let format = monoFormat {
                monoBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength))
            }
        }
    }
}
