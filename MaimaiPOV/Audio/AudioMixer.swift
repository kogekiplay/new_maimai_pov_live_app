import AVFoundation

class AudioMixer: ObservableObject {
    @Published var leftGain: Float = 1.0
    @Published var rightGain: Float = 1.0
    @Published var leftLevel: Float = 0.0
    @Published var rightLevel: Float = 0.0
    @Published var mixedLevel: Float = 0.0

    var isStereoMixEnabled: Bool = false

    private var monoFormat: AVAudioFormat?
    private var monoBuffer: AVAudioPCMBuffer?
    private let levelSmoothing: Float = 0.3
    private var smoothedLeftLevel: Float = 0
    private var smoothedRightLevel: Float = 0
    private var smoothedMixedLevel: Float = 0

    func process(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        if isStereoMixEnabled && input.format.channelCount >= 2 {
            return processStereo(input)
        } else {
            return processMono(input)
        }
    }

    private func processStereo(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let frameLength = Int(input.frameLength)
        guard frameLength > 0 else { return input }

        let leftChannel = input.floatChannelData![0]
        let rightChannel = input.floatChannelData![1]

        var leftSum: Float = 0
        var rightSum: Float = 0
        for i in 0..<frameLength {
            leftSum += leftChannel[i] * leftChannel[i]
            rightSum += rightChannel[i] * rightChannel[i]
        }
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.leftLevel = self.smoothedLeftLevel
            self.rightLevel = self.smoothedRightLevel
            self.mixedLevel = self.smoothedMixedLevel
        }

        return monoBuffer ?? input
    }

    private func processMono(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let frameLength = Int(input.frameLength)
        guard frameLength > 0 else { return input }

        let channelData = input.floatChannelData![0]

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rawLevel = sqrt(sum / Float(frameLength)) * 5.0
        smoothedLeftLevel = smoothedLeftLevel * (1 - levelSmoothing) + min(rawLevel, 1.0) * levelSmoothing
        smoothedRightLevel = smoothedLeftLevel
        smoothedMixedLevel = smoothedLeftLevel

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.leftLevel = self.smoothedLeftLevel
            self.rightLevel = self.smoothedRightLevel
            self.mixedLevel = self.smoothedMixedLevel
        }

        return input
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
