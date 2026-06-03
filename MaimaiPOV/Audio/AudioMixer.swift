import AVFoundation
import Accelerate
import QuartzCore

class AudioMixer: ObservableObject {
    @Published var leftGain: Float = 1.0
    @Published var rightGain: Float = 1.0
    @Published var leftLevel: Float = 0.0
    @Published var rightLevel: Float = 0.0
    @Published var mixedLevel: Float = 0.0
    @Published var audioFormatInfo: String = "--"

    var isStereoMixEnabled: Bool = false

    private var monoFormat: AVAudioFormat?
    /// 立体声输出格式（用于 processStereo 输出，保持与输入相同的通道数以避免 HaishinKit 格式切换）
    private var stereoOutputFormat: AVAudioFormat?
    private let levelSmoothing: Float = 0.3
    private var smoothedLeftLevel: Float = 0
    private var smoothedRightLevel: Float = 0
    private var smoothedMixedLevel: Float = 0
    private var levelUpdateCounter: Int = 0
    private let levelUpdateInterval: Int = 3

    private var standardFormat: AVAudioFormat?
    private var standardBuffer: AVAudioPCMBuffer?
    private var audioConverter: AVAudioConverter?

    /// 立体声处理诊断计数器
    private var stereoDiagCounter: Int = 0
    /// 格式转换路径计数器
    private var conversionDiagCounter: Int = 0

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
        guard let converted = convertToStandardFormat(input) else { return }
        let convertedLength = Int(converted.frameLength)
        guard convertedLength > 0, let floatData = converted.floatChannelData?[0] else { return }

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

        stereoDiagCounter += 1

        if let leftChannel = input.floatChannelData?[0],
           let rightChannel = input.floatChannelData?[1] {
            return processStereoFromFloat(leftChannel: leftChannel, rightChannel: rightChannel, frameLength: frameLength, sampleRate: input.format.sampleRate, fallback: input)
        }

        // 非 Float32 格式需要先转换（如 interleaved Int16）
        conversionDiagCounter += 1
        if conversionDiagCounter % 100 == 0 {
            DebugInfoManager.shared.logAsync("MixerCvt: non-float sr=\(Int(input.format.sampleRate)) ch=\(input.format.channelCount) il=\(input.format.isInterleaved) cf=\(input.format.commonFormat.rawValue) inFL=\(frameLength) cnt=\(conversionDiagCounter)")
        }
        guard let converted = convertToStandardFormat(input),
              let leftChannel = converted.floatChannelData?[0],
              let rightChannel = converted.floatChannelData?[1] else {
            calculateLevelViaConversion(input)
            return input
        }

        let convertedLength = Int(converted.frameLength)
        return processStereoFromFloat(leftChannel: leftChannel, rightChannel: rightChannel, frameLength: convertedLength, sampleRate: input.format.sampleRate, fallback: input)
    }

    private func processStereoFromFloat(leftChannel: UnsafePointer<Float>, rightChannel: UnsafePointer<Float>, frameLength: Int, sampleRate: Float64, fallback: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let t0 = CACurrentMediaTime()

        var leftSum: Float = 0
        var rightSum: Float = 0
        vDSP_svesq(leftChannel, 1, &leftSum, vDSP_Length(frameLength))
        vDSP_svesq(rightChannel, 1, &rightSum, vDSP_Length(frameLength))
        let rawLeft = sqrt(leftSum / Float(frameLength)) * 5.0
        let rawRight = sqrt(rightSum / Float(frameLength)) * 5.0

        smoothedLeftLevel = smoothedLeftLevel * (1 - levelSmoothing) + min(rawLeft, 1.0) * levelSmoothing
        smoothedRightLevel = smoothedRightLevel * (1 - levelSmoothing) + min(rawRight, 1.0) * levelSmoothing

        // 使用立体声输出格式（2通道），避免 HaishinKit 因格式切换导致时间戳漂移
        // 两个声道都填充混合后的音频
        if stereoOutputFormat == nil || stereoOutputFormat!.sampleRate != sampleRate {
            stereoOutputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        }
        guard let stereoFmt = stereoOutputFormat,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: stereoFmt, frameCapacity: AVAudioFrameCount(frameLength)) else {
            return fallback
        }
        outputBuffer.frameLength = AVAudioFrameCount(frameLength)

        guard let outputLeft = outputBuffer.floatChannelData?[0],
              let outputRight = outputBuffer.floatChannelData?[1] else { return fallback }

        var mixedSum: Float = 0
        for i in 0..<frameLength {
            let mixed = leftChannel[i] * leftGain + rightChannel[i] * rightGain
            let sample = mixed * 0.5
            outputLeft[i] = sample
            outputRight[i] = sample
            mixedSum += sample * sample
        }
        let rawMixed = sqrt(mixedSum / Float(frameLength)) * 5.0
        smoothedMixedLevel = smoothedMixedLevel * (1 - levelSmoothing) + min(rawMixed, 1.0) * levelSmoothing

        updateLevelsOnMain()

        // 更新混音耗时字段（浮窗固定显示）
        if stereoDiagCounter % 20 == 0 {
            let elapsed = (CACurrentMediaTime() - t0) * 1000
            Task { @MainActor in
                DebugInfoManager.shared.audioMixTime = elapsed
            }
        }

        return outputBuffer
    }

    private func processMono(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let frameLength = Int(input.frameLength)
        guard frameLength > 0 else { return input }

        if let channelData = input.floatChannelData?[0] {
            var sum: Float = 0
            vDSP_svesq(channelData, 1, &sum, vDSP_Length(frameLength))
            let rawLevel = sqrt(sum / Float(frameLength)) * 5.0
            smoothedLeftLevel = smoothedLeftLevel * (1 - levelSmoothing) + min(rawLevel, 1.0) * levelSmoothing
            smoothedRightLevel = smoothedLeftLevel
            smoothedMixedLevel = smoothedLeftLevel
            updateLevelsOnMain()
            return input
        }

        calculateLevelViaConversion(input)
        return input
    }

    private func convertToStandardFormat(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let sampleRate = input.format.sampleRate
        let channels = input.format.channelCount
        let frameLength = Int(input.frameLength)

        if standardFormat == nil || standardFormat!.sampleRate != sampleRate || standardFormat!.channelCount != channels {
            standardFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)
            audioConverter = AVAudioConverter(from: input.format, to: standardFormat!)
            standardBuffer = nil
        }

        guard let format = standardFormat, let converter = audioConverter else { return nil }

        if standardBuffer == nil || standardBuffer!.frameCapacity < AVAudioFrameCount(frameLength) {
            standardBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength))
        }

        guard let buffer = standardBuffer else { return nil }

        // 重置 converter 避免跨帧累积状态导致 frameLength 漂移
        converter.reset()
        var error: NSError?
        let status = converter.convert(to: buffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return input
        }

        guard status != .error else { return nil }
        // 防御性裁剪：确保输出帧数不超过输入帧数
        if buffer.frameLength > AVAudioFrameCount(frameLength) {
            DebugInfoManager.shared.logAsync("MixerCvt: trimmed fl from \(buffer.frameLength) to \(frameLength)")
            buffer.frameLength = AVAudioFrameCount(frameLength)
        }
        return buffer
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
}
