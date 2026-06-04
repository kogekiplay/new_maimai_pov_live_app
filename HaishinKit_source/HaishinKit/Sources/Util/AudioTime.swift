import AVFoundation
import Foundation

/// A helper class for interoperating between AVAudioTime and CMTime.
/// Conversion fails without hostTime on the AVAudioTime side, and cannot be saved with AVAssetWriter.
final class AudioTime {
    var at: AVAudioTime {
        let now = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
        guard let anchorTime else {
            return now
        }
        return now.extrapolateTime(fromAnchor: anchorTime) ?? now
    }

    var hasAnchor: Bool {
        return anchorTime != nil
    }

    private var sampleRate: Double = 0.0
    private var anchorTime: AVAudioTime?
    private var sampleTime: AVAudioFramePosition = 0
    private var framesSinceAnchor: Int = 0

    func advanced(_ count: AVAudioFramePosition) {
        sampleTime += count
        framesSinceAnchor += Int(count)
    }

    func anchor(_ time: CMTime, sampleRate: Double) {
        self.sampleRate = sampleRate
        guard anchorTime == nil || framesSinceAnchor >= 100 else {
            return
        }
        if anchorTime == nil {
            // First anchor: use input sampleTime
            if time.timescale == Int32(sampleRate) {
                sampleTime = time.value
            } else {
                // ReplayKit .appAudio
                sampleTime = Int64(Double(time.value) * sampleRate / Double(time.timescale))
            }
        }
        // Re-anchor: keep current sampleTime (continuity), update hostTime from input
        anchorTime = .init(
            hostTime: AVAudioTime.hostTime(forSeconds: time.seconds),
            sampleTime: sampleTime,
            atRate: sampleRate
        )
        framesSinceAnchor = 0
    }

    func anchor(_ time: AVAudioTime) {
        sampleRate = time.sampleRate
        guard anchorTime == nil || framesSinceAnchor >= 100 else {
            return
        }
        if anchorTime == nil {
            // First anchor: use input sampleTime
            sampleTime = time.sampleTime
        }
        // Re-anchor: keep current sampleTime (continuity), update hostTime from input
        anchorTime = .init(
            hostTime: time.hostTime,
            sampleTime: sampleTime,
            atRate: time.sampleRate
        )
        framesSinceAnchor = 0
    }

    func reset() {
        sampleRate = 0.0
        sampleTime = 0
        anchorTime = nil
        framesSinceAnchor = 0
    }
}
