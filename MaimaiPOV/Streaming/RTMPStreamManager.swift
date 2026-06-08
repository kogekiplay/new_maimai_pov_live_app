import SwiftUI
@preconcurrency import HaishinKit
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

final class RTMPStreamManager: ObservableObject, @unchecked Sendable {
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
    private var publishTask: Task<Void, Never>?
    private var publishGeneration: Int = 0

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

    // 音频PTS漂移补偿
    private var audioCumulativeSamples: Int64 = 0   // 实际累积音频样本数
    private var audioFirstAlignedTime: Double = 0    // 第一帧的alignedTime（起始参考点）
    private var audioHasFirstFrame: Bool = false     // 是否已收到第一帧

    // 视频PTS漂移补偿（补偿音频设备时钟与主机时钟的偏差）
    private var videoDriftCompensationSec: Double = 0.0

    // 视频PTS初始偏移（补偿AAC编码延迟~46ms，推流开始后50帧内渐进施加）
    private var videoInitialOffsetSec: Double = 0.0
    private var videoFrameCount: Int = 0

    // 视频PTS间隙检测
    private var lastConsumedVideoPts: Double = 0
    private var hasFirstConsumedVideoFrame: Bool = false

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
            guard self.isStreaming else { return }
            if attempt > 0 {
                self.streamStatus = "Reconnecting(\(attempt)/\(Config.maxReconnectAttempts))..."
            } else {
                self.streamStatus = "Connecting"
            }
            DebugInfoManager.shared.rtmpStatus = self.streamStatus
            DebugInfoManager.shared.log("RTMP: \(self.streamStatus)")
        }

        setupStatusMonitoring(connection: connection, stream: stream)

        let publishURL = rtmpUrl
        let publishKey = streamKey
        publishTask?.cancel()
        publishGeneration += 1
        let generation = publishGeneration
        publishTask = Task { [weak self] in
            defer {
                Task { [weak self] in
                    await self?.clearPublishTask(generation: generation)
                }
            }

            guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }
            await stream.setAudioSettings(AudioCodecSettings(bitRate: Config.audioBitrate))
            guard let self, !Task.isCancelled else { return }
            guard await self.shouldContinuePublishing(generation: generation) else { return }

            do {
                _ = try await connection.connect(publishURL)
                guard !Task.isCancelled else { return }
                guard await self.shouldContinuePublishing(generation: generation) else { return }
                _ = try await stream.publish(publishKey)
                guard !Task.isCancelled else { return }
                await self.handlePublishStarted(generation: generation)
            } catch {
                guard !Task.isCancelled else { return }
                guard await self.shouldContinuePublishing(generation: generation) else { return }
                await self.attemptReconnect(reason: error.localizedDescription)
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
                // PTS间隙检测
                self?.detectVideoPtsGap(buffer)
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
                let currentStream = self.lock.withLock { self.stream }
                guard let currentStream else { break }
                let info = await currentStream.info
                let fps = await currentStream.currentFPS
                let bitrateKbps = info.currentBytesPerSecond * 8 / 1000
                let fpsValue = Int(fps)
                await MainActor.run {
                    DebugInfoManager.shared.rtmpBitrate = bitrateKbps
                    DebugInfoManager.shared.rtmpFPS = fpsValue
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @MainActor
    private func handlePublishStarted(generation: Int) {
        guard isStreaming, publishGeneration == generation else { return }
        reconnectAttempt = 0
        streamStatus = "Publishing"
        DebugInfoManager.shared.rtmpStatus = "Publishing"
        DebugInfoManager.shared.log("RTMP: Publishing")
    }

    @MainActor
    private func shouldContinuePublishing(generation: Int) -> Bool {
        isStreaming && publishGeneration == generation
    }

    @MainActor
    private func clearPublishTask(generation: Int) {
        guard publishGeneration == generation else { return }
        publishTask = nil
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

        // 渐进式初始偏移：前50帧内每帧加1ms，累积到+50ms后固定（补偿AAC编码延迟，让视频延后）
        videoFrameCount += 1
        if videoFrameCount <= 50 {
            videoInitialOffsetSec = Double(videoFrameCount) / 1000.0
            if videoFrameCount % 10 == 0 {
                Task { @MainActor in
                    DebugInfoManager.shared.videoInitialOffsetMs = videoInitialOffsetSec * 1000.0
                }
            }
        }

        let totalOffsetSec = videoInitialOffsetSec + videoDriftCompensationSec

        var timingInfo = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: 60),
            presentationTimeStamp: CMTimeAdd(
                timestamp,
                CMTime(seconds: totalOffsetSec, preferredTimescale: 1000000000)
            ),
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

        // 更新浮窗buffer计数（每10帧更新一次，避免频繁UI刷新）
        if count % 10 == 0 {
            Task { @MainActor in
                DebugInfoManager.shared.videoBufferCount = count
            }
        }

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
        if cachedAudioFormat.map({
            $0.sampleRate != newFormat.sampleRate ||
            $0.channelCount != newFormat.channelCount ||
            $0.isInterleaved != newFormat.isInterleaved ||
            $0.commonFormat != newFormat.commonFormat
        }) ?? true {
            DebugInfoManager.logAsync("Audio: input fmt changed sr=\(newFormat.sampleRate) ch=\(newFormat.channelCount) il=\(newFormat.isInterleaved) cf=\(newFormat.commonFormat.rawValue)")
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
            DebugInfoManager.logAsync("Audio: out fmt changed \(oldDesc) -> sr=\(outFmt.sampleRate) ch=\(outFmt.channelCount) il=\(outFmt.isInterleaved) cf=\(outFmt.commonFormat.rawValue)")
            outputAudioFormat = outFmt
        }

        guard let outFormat = outputAudioFormat else { return }

        // 音频PTS漂移补偿：用实际累积样本数计算PTS，消除音频设备时钟与主机时钟的漂移
        let frameLength = bufferToQueue.frameLength
        if !audioHasFirstFrame {
            audioFirstAlignedTime = alignedTime
            audioHasFirstFrame = true
        }
        // 基于实际样本数计算预期时间（消除时钟漂移）
        let correctedTime = audioFirstAlignedTime + Double(audioCumulativeSamples) / outFormat.sampleRate
        audioCumulativeSamples += Int64(frameLength)

        // 漂移量诊断 & 视频PTS补偿
        let driftMs = (alignedTime - correctedTime) * 1000.0
        // 反向补偿视频PTS：driftMs<0(音频快) → 补偿量>0(视频PTS加大)
        videoDriftCompensationSec = -driftMs / 1000.0
        if audioBufferCount % 100 == 0 {
            Task { @MainActor in
                DebugInfoManager.shared.audioDriftMs = driftMs
                DebugInfoManager.shared.videoDriftCompensationMs = -driftMs
            }
        }

        let sampleTime = AVAudioFramePosition(correctedTime * outFormat.sampleRate)
        let audioTime = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: correctedTime), sampleTime: sampleTime, atRate: outFormat.sampleRate)

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
                    DebugInfoManager.shared.audioFrameLen = Int(bufferToQueue.frameLength)
                }
                // 跳变检测：err 相比上一轮变化超过 0.5ms
                if audioBufferCount > 200 && abs(errMs - prevErr) > 0.5 {
                    let mode = isStereo ? "S" : "M"
                    DebugInfoManager.logAsync(String(format: "ADiag[JUMP %@]: err %.3f→%.3fms acc=%.1fms ptsD=%.4f exp=%.4f frames=%u", mode, prevErr, errMs, audioTimeAccumError * 1000, ptsDelta * 1000, expectedDuration * 1000, bufferToQueue.frameLength))
                }
            }
            // 每 1000 帧输出一条紧凑滚动日志
            if audioBufferCount % 1000 == 0 {
                let mode = isStereo ? "S" : "M"
                DebugInfoManager.logAsync(String(format: "ADiag[%@]: err=%.3f acc=%.1fms ptsD=%.4f buf=%d", mode, error * 1000, audioTimeAccumError * 1000, ptsDelta * 1000, audioBufferCount))
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

        // 更新浮窗buffer计数（每20帧更新一次）
        if count % 20 == 0 {
            Task { @MainActor in
                DebugInfoManager.shared.audioBufferCount = count
            }
        }

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
        // 重置漂移补偿状态
        audioCumulativeSamples = 0
        audioFirstAlignedTime = 0
        audioHasFirstFrame = false
        videoDriftCompensationSec = 0.0
        // 重置初始偏移状态
        videoInitialOffsetSec = 0.0
        videoFrameCount = 0
        // 重置PTS间隙检测状态
        hasFirstConsumedVideoFrame = false
        lastConsumedVideoPts = 0
        DebugInfoManager.logAsync("Audio: state fully reset")
    }

    @MainActor
    private func attemptReconnect(reason: String? = nil) {
        guard isStreaming else { return }
        reconnectAttempt += 1
        if reconnectAttempt > Config.maxReconnectAttempts {
            streamStatus = "Reconnect failed, retry manually"
            DebugInfoManager.shared.rtmpStatus = "Reconnect failed"
            DebugInfoManager.shared.log("RTMP: 重连失败 - \(reason ?? "unknown")")
            isStreaming = false
            cleanup()
            return
        }

        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), Config.maxReconnectDelaySeconds)
        streamStatus = "Reconnecting(\(reconnectAttempt)/\(Config.maxReconnectAttempts))..."
        DebugInfoManager.shared.rtmpStatus = streamStatus
        DebugInfoManager.shared.log("RTMP: \(streamStatus) \(String(format: "%.0fs后重试", delay))")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                guard let self, self.isStreaming else { return }
                self.resetStreams()
                self.connectAndPublish()
            }
        }
    }

    @MainActor
    private func handleConnectionStatus(_ code: String) {
        guard isStreaming else { return }
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
        guard isStreaming else { return }
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

    private func detectVideoPtsGap(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMTimeGetSeconds(sampleBuffer.presentationTimeStamp)
        if !hasFirstConsumedVideoFrame {
            hasFirstConsumedVideoFrame = true
            lastConsumedVideoPts = pts
            return
        }
        let gapMs = (pts - lastConsumedVideoPts) * 1000.0
        // 正常60fps帧间隔约16.7ms，超过20ms视为异常间隙
        if gapMs > 20.0 {
            let estimatedFrames = Int(gapMs / 16.67)
            let skipInfo = String(format: "%.0fms (~%d fr)", gapMs, estimatedFrames)
            DebugInfoManager.logAsync("[VSKIP] gap=\(skipInfo) vBuf=\(videoBufferCount) aBuf=\(audioBufferCount)")
            Task { @MainActor in
                DebugInfoManager.shared.videoPtsGapCount += 1
                if gapMs > DebugInfoManager.shared.videoMaxPtsGapMs {
                    DebugInfoManager.shared.videoMaxPtsGapMs = gapMs
                }
                DebugInfoManager.shared.lastSkipInfo = skipInfo
            }
        }
        lastConsumedVideoPts = pts
    }

    private func forceClearBuffers() {
        bufferCountLock.lock()
        let vBuf = videoBufferCount
        let aBuf = audioBufferCount
        videoBufferCount = 0
        audioBufferCount = 0
        bufferCountLock.unlock()
        prevAudioAlignedTime = 0
        audioTimeAccumError = 0
        prevDisplayedErr = 0
        // 重置漂移补偿状态
        audioCumulativeSamples = 0
        videoDriftCompensationSec = 0.0
        videoInitialOffsetSec = 0.0
        videoFrameCount = 0
        // 重置PTS间隙检测状态
        hasFirstConsumedVideoFrame = false
        lastConsumedVideoPts = 0
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
            DebugInfoManager.shared.log("RTMP: 缓冲区强制清空 (vBuf=\(vBuf) aBuf=\(aBuf) encoded=\(videoFrameCount))")
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
        // 重置漂移补偿和初始偏移状态
        audioCumulativeSamples = 0
        audioFirstAlignedTime = 0
        audioHasFirstFrame = false
        videoDriftCompensationSec = 0.0
        videoInitialOffsetSec = 0.0
        videoFrameCount = 0
        prevAudioAlignedTime = 0
        audioTimeAccumError = 0
        hasFirstConsumedVideoFrame = false
        lastConsumedVideoPts = 0
        prevDisplayedErr = 0
    }

    private func cleanup() {
        reconnectTask?.cancel()
        reconnectTask = nil
        publishTask?.cancel()
        publishTask = nil
        publishGeneration += 1
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
