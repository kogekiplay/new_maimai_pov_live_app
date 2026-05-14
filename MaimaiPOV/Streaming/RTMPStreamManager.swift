import SwiftUI
import HaishinKit
import CoreMedia
import VideoToolbox

enum StreamResolution: String, CaseIterable {
    case r720p = "720p"
    case r1080p = "1080p"

    var size: CGSize {
        switch self {
        case .r720p: return CGSize(width: Config.outputWidth, height: Config.outputHeight)
        case .r1080p: return CGSize(width: 1080, height: 1920)
        }
    }
}

class RTMPStreamManager: ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var streamStatus: String = "Idle"
    @Published var streamResolution: StreamResolution = .r720p
    @Published var videoBitrate: Int = Config.videoBitrate / 1000

    private var connection: RTMPConnection?
    private var stream: RTMPStream?

    private var statusTask: Task<Void, Never>?
    private var streamStatusTask: Task<Void, Never>?

    private var videoIngestTask: Task<Void, Never>?
    private var audioIngestTask: Task<Void, Never>?
    private var videoContinuation: AsyncStream<CMSampleBuffer>.Continuation?
    private var audioContinuation: AsyncStream<CMSampleBuffer>.Continuation?

    private var videoFormatDescription: CMVideoFormatDescription?
    private let lock = NSLock()

    private var videoFrameCount: Int64 = 0
    private var audioFrameCount: Int64 = 0
    private var lastLogTime: CFAbsoluteTime = 0

    @MainActor
    func startPublish(url: String, streamKey: String) {
        guard !isStreaming else { return }
        guard !url.isEmpty, !streamKey.isEmpty else {
            streamStatus = "Error: URL/Key empty"
            return
        }

        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)

        let resolution = streamResolution
        let bitrate = videoBitrate

        Task {
            await stream.setVideoSettings(VideoCodecSettings(
                videoSize: resolution.size,
                bitRate: bitrate * 1000,
                profileLevel: kVTProfileLevel_H264_Main_3_1 as String
            ))
            await stream.setAudioSettings(AudioCodecSettings(bitRate: Config.audioBitrate))
        }

        lock.lock()
        self.connection = connection
        self.stream = stream
        lock.unlock()

        let vStream = AsyncStream<CMSampleBuffer> { continuation in
            self.videoContinuation = continuation
        }
        videoIngestTask = Task { [weak stream] in
            for await buffer in vStream {
                await stream?.append(buffer)
            }
        }

        let aStream = AsyncStream<CMSampleBuffer> { continuation in
            self.audioContinuation = continuation
        }
        audioIngestTask = Task { [weak stream] in
            for await buffer in aStream {
                await stream?.append(buffer)
            }
        }

        isStreaming = true
        streamStatus = "Connecting"
        DebugInfoManager.shared.rtmpStatus = "Connecting"
        DebugInfoManager.shared.log("RTMP: Connecting to \(url)")

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

        Task { [weak self] in
            do {
                _ = try await connection.connect(url)
                _ = try await stream.publish(streamKey)
                await MainActor.run {
                    self?.streamStatus = "Publishing"
                    DebugInfoManager.shared.rtmpStatus = "Publishing"
                    DebugInfoManager.shared.log("RTMP: Publishing started")
                }
            } catch {
                await MainActor.run {
                    self?.streamStatus = "Failed: \(error.localizedDescription)"
                    DebugInfoManager.shared.rtmpStatus = "Failed"
                    DebugInfoManager.shared.log("RTMP: Failed - \(error.localizedDescription)")
                    self?.isStreaming = false
                    self?.cleanup()
                }
            }
        }
    }

    @MainActor
    func stopPublish() {
        guard isStreaming else { return }

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
        DebugInfoManager.shared.log("RTMP: Stopped. Video frames sent: \(videoFrameCount), Audio frames sent: \(audioFrameCount)")
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

        videoFrameCount += 1
        videoContinuation?.yield(finalSampleBuffer)

        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLogTime >= 2.0 {
            lastLogTime = now
            DispatchQueue.main.async {
                DebugInfoManager.shared.rtmpVideoFrames = Int(self.videoFrameCount)
                DebugInfoManager.shared.rtmpAudioFrames = Int(self.audioFrameCount)
                DebugInfoManager.shared.log("RTMP: vFrames=\(self.videoFrameCount) aFrames=\(self.audioFrameCount) PTS=\(timestamp.seconds)")
            }
        }
    }

    func appendAudio(sampleBuffer: CMSampleBuffer) {
        guard isStreaming else { return }
        audioFrameCount += 1
        audioContinuation?.yield(sampleBuffer)
    }

    @MainActor
    private func handleConnectionStatus(_ code: String) {
        switch code {
        case "NetConnection.Connect.Success":
            streamStatus = "Connected"
            DebugInfoManager.shared.rtmpStatus = "Connected"
            DebugInfoManager.shared.log("RTMP: Connection success")
        case "NetConnection.Connect.Closed", "NetConnection.Connect.Failed", "NetConnection.Connect.Rejected":
            streamStatus = code.components(separatedBy: ".").last ?? "Error"
            DebugInfoManager.shared.rtmpStatus = streamStatus
            DebugInfoManager.shared.log("RTMP: Connection \(streamStatus)")
            isStreaming = false
            cleanup()
        default: break
        }
    }

    @MainActor
    private func handleStreamStatus(_ code: String) {
        switch code {
        case "NetStream.Publish.Start":
            streamStatus = "Publishing"
            DebugInfoManager.shared.rtmpStatus = "Publishing"
            DebugInfoManager.shared.log("RTMP: Publish started")
        case "NetStream.Publish.BadName":
            streamStatus = "BadName"
            DebugInfoManager.shared.rtmpStatus = "BadName"
            DebugInfoManager.shared.log("RTMP: Publish BadName")
        case "NetStream.Connect.Closed", "NetStream.Unpublish.Success":
            if isStreaming {
                streamStatus = "Stream Closed"
                DebugInfoManager.shared.rtmpStatus = "Stream Closed"
                DebugInfoManager.shared.log("RTMP: Stream closed")
                isStreaming = false
                cleanup()
            }
        default: break
        }
    }

    private func cleanup() {
        statusTask?.cancel()
        statusTask = nil
        streamStatusTask?.cancel()
        streamStatusTask = nil

        videoContinuation?.finish()
        videoContinuation = nil
        audioContinuation?.finish()
        audioContinuation = nil
        videoIngestTask?.cancel()
        videoIngestTask = nil
        audioIngestTask?.cancel()
        audioIngestTask = nil

        lock.lock()
        stream = nil
        connection = nil
        lock.unlock()
        videoFormatDescription = nil

        videoFrameCount = 0
        audioFrameCount = 0
    }
}
