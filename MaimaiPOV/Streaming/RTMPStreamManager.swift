import SwiftUI
import HaishinKit
import CoreMedia
import VideoToolbox
import AVFAudio

enum StreamResolution: String, CaseIterable {
    case r720p = "720p"
    case r1080p = "1080p"

    var size: CGSize {
        switch self {
        case .r720p: return CGSize(width: 1280, height: 720)
        case .r1080p: return CGSize(width: 1920, height: 1080)
        }
    }
}

class RTMPStreamManager: ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var streamStatus: String = "Idle"
    @Published var streamResolution: StreamResolution = .r1080p
    @Published var videoBitrate: Int = Config.streamBitrate

    var audioMixer: AudioMixer?

    var audioSyncQueueDepth: Int {
        bufferCountLock.lock()
        defer { bufferCountLock.unlock() }
        return audioBufferCount
    }

    private var connection: RTMPConnection?
    private var stream: RTMPStream?

    private var statusTask: Task<Void, Never>?
    private var streamStatusTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?

    private var videoIngestTask: Task<Void, Never>?
    private var audioIngestTask: Task<Void, Never>?
    private var videoContinuation: AsyncStream<CMSampleBuffer>.Continuation?
    private var audioContinuation: AsyncStream<(AVAudioBuffer, AVAudioTime)>.Continuation?

    private var videoFormatDescription: CMVideoFormatDescription?
    private var cachedAudioFormat: AVAudioFormat?
    /// 处理后的音频格式（可能与输入格式不同，如立体声降混为单声道后）
    /// 用于创建 AVAudioTime 和静音 buffer
    private var outputAudioFormat: AVAudioFormat?
    private let lock = NSLock()

    private var rtmpUrl: String = ""
    private var streamKey: String = ""
    private var reconnectAttempt: Int = 0
    private var reconnectTask: Task<Void, Never>?

    private var streamingStartTime: Date?
    private var durationUpdateTask: Task<Void, Never>?

    private var videoBufferCount: Int = 0
    private var audioBufferCount: Int = 0
    private let bufferCountLock = NSLock()
    // 音频时间戳诊断
    private var prevAudioAlignedTime: Double = 0
    private var prevAudioFrameLength: AVAudioFrameCount = 0
    private var audioTimeAccumError: Double = 0  // 累积时间戳误差
    private var prevDisplayedErr: Double = 0       // 上一轮显示的 err 值（用于跳变检测）

    @MainActor
    func startPublish(url: String, streamKey: String) {
        guard !isStreaming else { return }
        guard !url.isEmpty, !streamKey.isEmpty else {
            streamStatus = "Error: URL/Key empty"
            return
        }
        self.rtmpUrl = url
        self.streamKey = streamKey
        self.reconnectAttempt = 0
        self.streamingStartTime = Date()
        isStreaming = true
        startDurationTimer()
        connectAndPublish()
    }

    private func connectAndPublish() {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)

        let resolution = streamResolution
        let bitrate = videoBitrate

        let bitrateBps = bitrate * 1000

        lock.lock()
        self.connection = connection
        self.stream = stream
        lock.unlock()

        setupStreamPipelines(stream)

        let attempt = reconnectAttempt
        Task { @MainActor in
            if attempt > 0 {
                self.streamStatus = "重连中(\(attempt)/\(Config.maxReconnectAttempts))..."
            } else {
                self.streamStatus = "Connecting"
            }
            DebugInfoManager.shared.rtmpStatus = self.streamStatus
            DebugInfoManager.shared.log("RTMP: \(self.streamStatus)")
        }

        setupStatusMonitoring(connection: connection, stream: stream)

        Task { [weak self] in
            var videoSettings = VideoCodecSettings(
                videoSize: resolution.size,
                bitRate: bitrateBps,
                maxKeyFrameIntervalDuration: 2
            )
            videoSettings.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String
            videoSettings.bitRateMode = .constant
            videoSettings.allowFrameReordering = false
            videoSettings.dataRateLimits = [Double(bitrateBps) / 8.0 * 2.0, 1.0]
            await stream.setVideoSettings(videoSettings)
            await stream.setAudioSettings(AudioCodecSettings(bitRate: Config.audioBitrate))

            do {
                _ = try await connection.connect(rtmpUrl)
                _ = try await stream.publish(streamKey)
                await MainActor.run {
                    self?.reconnectAttempt = 0
                    self?.streamStatus = "Publishing"
                    DebugInfoManager.shared.rtmpStatus = "Publishing"
                    DebugInfoManager.shared.log("RTMP: Publishing")
                }
            } catch {
                await MainActor.run {
                    self?.attemptReconnect(reason: error.localizedDescription)
                }
            }
        }
    }

    private func setupStreamPipelines(_ stream: RTMPStream) {
        let (vStream, vContinuation) = AsyncStream<CMSampleBuffer>.makeStream(
            of: CMSampleBuffer.self,
            bufferingPolicy: .bufferingNewest(Config.streamVideoBufferFrames)
        )
        videoContinuation = vContinuation
        videoIngestTask = Task { [weak self, weak stream] in
            for await buffer in vStream {
                self?.decrementVideoBufferCount()
                await stream?.append(buffer)
            }
        }

        let (aStream, aContinuation) = AsyncStream<(AVAudioBuffer, AVAudioTime)>.makeStream(
            of: (AVAudioBuffer, AVAudioTime).self,
            bufferingPolicy: .bufferingNewest(Config.streamAudioBufferFrames)
        )
        audioContinuation = aContinuation
        audioIngestTask = Task { [weak self, weak stream] in
            for await (buffer, when) in aStream {
                self?.decrementAudioBufferCount()
                await stream?.append(buffer, when: when)
            }
        }
    }

    private func setupStatusMonitoring(connection: RTMPConnection, stream: RTMPStream) {
        statusTask = Task { [weak self] in
            for await status in await connection.status {
                let code = status.code
                Task { @MainActor in
                    self?.handleConnectionStatus(code)
                }
            }
        }

        streamStatusTask = Task { [weak self] in
            for await status in await stream.status {
                let code = status.code
                Task { @MainActor in
                    self?.handleStreamStatus(code)
                }
            }
        }

        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let currentStream: RTMPStream?
                self.lock.lock()
                currentStream = self.stream
                self.lock.unlock()
                guard let currentStream else { break }
                let info = await currentStream.info
                let fps = await currentStream.currentFPS
                DispatchQueue.main.async {
                    DebugInfoManager.shared.rtmpBitrate = info.currentBytesPerSecond * 8 / 1000
                    DebugInfoManager.shared.rtmpFPS = Int(fps)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @MainActor
    func stopPublish() {
        guard isStreaming else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        durationUpdateTask?.cancel()
        durationUpdateTask = nil
        streamingStartTime = nil
        DebugInfoManager.shared.streamingDuration = "--"

        let stream: RTMPStream?
        let connection: RTMPConnection?
        lock.lock()
        stream = self.stream
        connection = self.connection
        lock.unlock()

        Task {
            if let stream { _ = try? await stream.close() }
            if let connection { try? await connection.close() }
        }

        isStreaming = false
        streamStatus = "Idle"
        DebugInfoManager.shared.rtmpStatus = "Idle"
        DebugInfoManager.shared.rtmpBitrate = 0
        DebugInfoManager.shared.rtmpFPS = 0
        DebugInfoManager.shared.log("RTMP: Stopped")
        cleanup()
    }

    func appendVideo(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isStreaming else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        var needsNewFormat = false
        if let desc = videoFormatDescription {
            let descDimensions = CMVideoFormatDescriptionGetDimensions(desc)
            let descCodec = CMFormatDescriptionGetMediaSubType(desc)
            if descDimensions.width != width || descDimensions.height != height || descCodec != pixelFormat {
                needsNewFormat = true
            }
        } else {
            needsNewFormat = true
        }

        if needsNewFormat {
            var newDesc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &newDesc
            )
            guard status == noErr, let newDesc else { return }
            videoFormatDescription = newDesc
        }

        guard let formatDescription = videoFormatDescription else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: 60),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard result == noErr, let finalSampleBuffer = sampleBuffer else { return }

        bufferCountLock.lock()
        videoBufferCount += 1
        let count = videoBufferCount
        bufferCountLock.unlock()

        if count > Int(Double(Config.streamVideoBufferFrames) * 1.5) {
            forceClearBuffers()
            return
        }

        videoContinuation?.yield(finalSampleBuffer)
    }

    func appendAudio(sampleBuffer: CMSampleBuffer, alignedTime: Double) {
        guard isStreaming else { return }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        // cachedAudioFormat 始终与 CMSampleBuffer 格式一致（用于创建 pcmBuffer）
        let newFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        if cachedAudioFormat == nil ||
           cachedAudioFormat!.sampleRate != newFormat.sampleRate ||
           cachedAudioFormat!.channelCount != newFormat.channelCount ||
           cachedAudioFormat!.isInterleaved != newFormat.isInterleaved ||
           cachedAudioFormat!.commonFormat != newFormat.commonFormat {
            DebugInfoManager.shared.logAsync("Audio: input fmt changed sr=\(newFormat.sampleRate) ch=\(newFormat.channelCount) il=\(newFormat.isInterleaved) cf=\(newFormat.commonFormat.rawValue)")
            cachedAudioFormat = newFormat
        }
        guard let audioFormat = cachedAudioFormat else { return }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard copyStatus == noErr else { return }

        var bufferToQueue = pcmBuffer
        if let mixer = audioMixer {
            if mixer.isStereoMixEnabled && audioFormat.channelCount >= 2 {
                bufferToQueue = mixer.process(pcmBuffer)
            } else {
                mixer.calculateLevel(pcmBuffer)
            }
        }

        // outputAudioFormat 与处理后的 buffer 格式一致（用于 AVAudioTime 和静音 buffer）
        let outFmt = bufferToQueue.format
        if outputAudioFormat == nil || outputAudioFormat != outFmt {
            let oldDesc = outputAudioFormat.map { "sr=\($0.sampleRate) ch=\($0.channelCount) il=\($0.isInterleaved) cf=\($0.commonFormat.rawValue)" } ?? "nil"
            DebugInfoManager.shared.logAsync("Audio: out fmt changed \(oldDesc) -> sr=\(outFmt.sampleRate) ch=\(outFmt.channelCount) il=\(outFmt.isInterleaved) cf=\(outFmt.commonFormat.rawValue)")
            outputAudioFormat = outFmt
        }

        guard let outFormat = outputAudioFormat else { return }
        let sampleTime = AVAudioFramePosition(alignedTime * outFormat.sampleRate)
        let audioTime = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: alignedTime), sampleTime: sampleTime, atRate: outFormat.sampleRate)

        // 诊断：检测音频 PTS 与帧数的一致性
        let isStereo = audioMixer?.isStereoMixEnabled ?? false
        if prevAudioAlignedTime > 0 {
            let ptsDelta = alignedTime - prevAudioAlignedTime
            let expectedDuration = Double(bufferToQueue.frameLength) / outFormat.sampleRate
            let error = ptsDelta - expectedDuration
            audioTimeAccumError += error
            // 更新浮窗固定显示字段
            if audioBufferCount % 100 == 0 {
                let prevErr = prevDisplayedErr  // 上一轮 err（局部变量，线程安全）
                let errMs = error * 1000
                prevDisplayedErr = errMs
                Task { @MainActor in
                    DebugInfoManager.shared.audioDiagErr = errMs
                    DebugInfoManager.shared.audioDiagAccum = audioTimeAccumError * 1000
                    DebugInfoManager.shared.audioPtsDelta = ptsDelta * 1000
                }
                // 跳变检测：err 相比上一轮变化超过 0.05ms
                if audioBufferCount > 200 && abs(errMs - prevErr) > 0.05 {
                    let mode = isStereo ? "S" : "M"
                    DebugInfoManager.shared.logAsync(String(format: "ADiag[JUMP %@]: err %.3f→%.3fms acc=%.1fms ptsD=%.4f exp=%.4f frames=%u", mode, prevErr, errMs, audioTimeAccumError * 1000, ptsDelta * 1000, expectedDuration * 1000, bufferToQueue.frameLength))
                }
            }
            // 每 300 帧输出一条紧凑滚动日志
            if audioBufferCount % 300 == 0 {
                let mode = isStereo ? "S" : "M"
                DebugInfoManager.shared.logAsync(String(format: "ADiag[%@]: err=%.3f acc=%.1fms ptsD=%.4f buf=%d", mode, error * 1000, audioTimeAccumError * 1000, ptsDelta * 1000, audioBufferCount))
            }
        }
        prevAudioAlignedTime = alignedTime
        prevAudioFrameLength = bufferToQueue.frameLength

        // 更新浮窗固定字段
        let inFmt = audioFormat
        let fmtStr = { (f: AVAudioFormat) in "\(Int(f.sampleRate)) \(f.channelCount)ch \(f.isInterleaved ? "I" : "N") \(f.commonFormat.rawValue)" }
        let inStr = fmtStr(inFmt)
        let outStr = fmtStr(outFormat)
        let modeStr = isStereo ? "STEREO" : "MONO"
        Task { @MainActor in
            DebugInfoManager.shared.audioMode = modeStr
            DebugInfoManager.shared.audioInFmt = inStr
            DebugInfoManager.shared.audioOutFmt = outStr
        }

        // 直接 yield 到编码管线，无 sync queue
        bufferCountLock.lock()
        audioBufferCount += 1
        let count = audioBufferCount
        bufferCountLock.unlock()

        if count > Int(Double(Config.streamAudioBufferFrames) * 1.5) {
            forceClearBuffers()
            return
        }

        audioContinuation?.yield((bufferToQueue, audioTime))
    }

    func resetAudioState() {
        bufferCountLock.lock()
        audioBufferCount = 0
        bufferCountLock.unlock()
        prevAudioAlignedTime = 0
        prevAudioFrameLength = 0
        audioTimeAccumError = 0
        prevDisplayedErr = 0
        cachedAudioFormat = nil
        outputAudioFormat = nil
        DebugInfoManager.shared.logAsync("Audio: state fully reset")
    }

    @MainActor
    private func attemptReconnect(reason: String? = nil) {
        reconnectAttempt += 1
        if reconnectAttempt > Config.maxReconnectAttempts {
            streamStatus = "重连失败，请手动重试"
            DebugInfoManager.shared.rtmpStatus = "重连失败"
            DebugInfoManager.shared.log("RTMP: 重连失败 - \(reason ?? "unknown")")
            isStreaming = false
            cleanup()
            return
        }

        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), Config.maxReconnectDelaySeconds)
        streamStatus = "重连中(\(reconnectAttempt)/\(Config.maxReconnectAttempts))..."
        DebugInfoManager.shared.rtmpStatus = streamStatus
        DebugInfoManager.shared.log("RTMP: \(streamStatus) \(String(format: "%.0fs后重试", delay))")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.isStreaming else { return }
            self.resetStreams()
            await MainActor.run {
                self.connectAndPublish()
            }
        }
    }

    @MainActor
    private func handleConnectionStatus(_ code: String) {
        switch code {
        case "NetConnection.Connect.Success":
            streamStatus = "Connected"
            DebugInfoManager.shared.rtmpStatus = "Connected"
            DebugInfoManager.shared.log("RTMP: Connected")
        case "NetConnection.Connect.Closed":
            attemptReconnect(reason: "连接关闭")
        case "NetConnection.Connect.Failed":
            attemptReconnect(reason: "连接失败")
        case "NetConnection.Connect.Rejected":
            streamStatus = "Rejected"
            DebugInfoManager.shared.rtmpStatus = "Rejected"
            DebugInfoManager.shared.log("RTMP: Rejected - 不重连")
            isStreaming = false
            cleanup()
        default: break
        }
    }

    @MainActor
    private func handleStreamStatus(_ code: String) {
        switch code {
        case "NetStream.Publish.Start":
            if reconnectAttempt == 0 {
                streamStatus = "Publishing"
                DebugInfoManager.shared.rtmpStatus = "Publishing"
                DebugInfoManager.shared.log("RTMP: Publishing")
            }
        case "NetStream.Publish.BadName":
            streamStatus = "BadName"
            DebugInfoManager.shared.rtmpStatus = "BadName"
            DebugInfoManager.shared.log("RTMP: BadName")
        case "NetStream.Connect.Closed", "NetStream.Unpublish.Success":
            if isStreaming {
                attemptReconnect(reason: "流关闭")
            }
        default: break
        }
    }

    private func decrementVideoBufferCount() {
        bufferCountLock.lock()
        videoBufferCount = max(0, videoBufferCount - 1)
        bufferCountLock.unlock()
    }

    private func decrementAudioBufferCount() {
        bufferCountLock.lock()
        audioBufferCount = max(0, audioBufferCount - 1)
        bufferCountLock.unlock()
    }

    private func forceClearBuffers() {
        bufferCountLock.lock()
        videoBufferCount = 0
        audioBufferCount = 0
        bufferCountLock.unlock()
        prevAudioAlignedTime = 0
        audioTimeAccumError = 0
        prevDisplayedErr = 0
        videoContinuation?.finish()
        audioContinuation?.finish()
        lock.lock()
        if let s = stream {
            videoContinuation = nil
            audioContinuation = nil
            lock.unlock()
            setupStreamPipelines(s)
        } else {
            lock.unlock()
        }
        videoFormatDescription = nil
        cachedAudioFormat = nil
        outputAudioFormat = nil
        Task { @MainActor in
            DebugInfoManager.shared.log("RTMP: 缓冲区强制清空")
        }
    }

    private func resetStreams() {
        statusTask?.cancel(); statusTask = nil
        streamStatusTask?.cancel(); streamStatusTask = nil
        statsTask?.cancel(); statsTask = nil
        videoContinuation?.finish(); videoContinuation = nil
        audioContinuation?.finish(); audioContinuation = nil
        videoIngestTask?.cancel(); videoIngestTask = nil
        audioIngestTask?.cancel(); audioIngestTask = nil
        lock.lock()
        let oldStream = stream
        let oldConnection = connection
        stream = nil
        connection = nil
        lock.unlock()
        Task {
            if let s = oldStream { _ = try? await s.close() }
            if let c = oldConnection { _ = try? await c.close() }
        }
        videoFormatDescription = nil
        bufferCountLock.lock()
        videoBufferCount = 0
        audioBufferCount = 0
        bufferCountLock.unlock()
    }

    private func cleanup() {
        reconnectTask?.cancel()
        reconnectTask = nil
        resetStreams()
    }

    private func startDurationTimer() {
        durationUpdateTask = Task { @MainActor in
            while !Task.isCancelled {
                if let startTime = streamingStartTime {
                    let duration = Date().timeIntervalSince(startTime)
                    let hours = Int(duration) / 3600
                    let minutes = (Int(duration) % 3600) / 60
                    let seconds = Int(duration) % 60
                    if hours > 0 {
                        DebugInfoManager.shared.streamingDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                    } else {
                        DebugInfoManager.shared.streamingDuration = String(format: "%02d:%02d", minutes, seconds)
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
