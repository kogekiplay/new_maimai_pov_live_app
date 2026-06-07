import SwiftUI

struct DebugOverlayView: View {
    @ObservedObject var debug: DebugInfoManager
    @Binding var isAntiTouchMode: Bool
    @State private var dragOffset: CGSize = .zero
    @State private var selectedTab: DebugTab = .stream

    private var isCollapsed: Bool { !debug.isDetailVisible }

    enum DebugTab: String, CaseIterable {
        case stream = "STREAM"
        case yolo = "YOLO"
        case track = "TRACK"
        case log = "LOG"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar

            if !isCollapsed {
                tabBar
                tabContent
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.white)
        .background(Color.black.opacity(isCollapsed ? 0.6 : 0.75))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .offset(dragOffset)
        .gesture(dragGesture)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.cyan)

            Text("DEBUG")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.cyan)

            Spacer()

            Text("\(Int(debug.fps))fps")
                .foregroundColor(debug.fps >= 55 ? .green : .orange)

            Text(String(format: "%.1fms", debug.pipelineLagMs))
                .foregroundColor(debug.pipelineLagMs < 10 ? .green :
                                   debug.pipelineLagMs < 20 ? .yellow : .red)

            if isCollapsed && debug.isStreaming {
                Text(debug.rtmpBitrate > 0 ? "\(debug.rtmpBitrate)kbps" : "")
                    .foregroundColor(.gray)
            }

            if isCollapsed && debug.isStreaming {
                Text(debug.rtmpStatus == "Publishing" ? "PUB" : debug.rtmpStatus)
                    .foregroundColor(rtmpStatusColor(debug.rtmpStatus))
                    .font(.system(size: 8, weight: .bold))
            }

            Button {
                if isAntiTouchMode { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    debug.isDetailVisible.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "arrow.up.right.and.arrow.down.left" : "minus")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DebugTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 9, weight: selectedTab == tab ? .bold : .regular))
                        .foregroundColor(selectedTab == tab ? .cyan : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedTab == tab ? Color.cyan.opacity(0.15) : Color.clear)
                }
            }
        }
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .stream:
            ScrollView {
                streamContent
            }
            .frame(maxHeight: 280)
        case .yolo:
            ScrollView {
                yoloContent
            }
            .frame(maxHeight: 280)
        case .track:
            ScrollView {
                trackContent
            }
            .frame(maxHeight: 280)
        case .log:
            logContent
        }
    }

    // MARK: - STREAM Tab

    private var streamContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader("RTMP")
            infoRow("Status", debug.rtmpStatus,
                    color: rtmpStatusColor(debug.rtmpStatus))
            infoRow("Duration", debug.streamingDuration)
            infoRow("Bitrate", "\(debug.rtmpBitrate)kbps")
            infoRow("FPS", "\(debug.rtmpFPS)")

            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 2)

            sectionHeader("VIDEO")
            infoRow("Readback", debug.streamInfo,
                    color: debug.streamInfo != "--" ? .green : .gray)
            infoRow("VBuf", "\(debug.videoBufferCount) bufs",
                    color: debug.videoBufferCount > 60 ? .red :
                           debug.videoBufferCount > 30 ? .yellow : .green)
            infoRow("Lag", String(format: "%.1fms", debug.pipelineLagMs),
                    color: debug.pipelineLagMs < 10 ? .green :
                           debug.pipelineLagMs < 20 ? .yellow : .red)

            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 2)

            sectionHeader("SKIP DIAG")
            infoRow("SkipCnt", "\(debug.videoPtsGapCount)",
                    color: debug.videoPtsGapCount > 0 ? .red : .green)
            infoRow("MaxGap", String(format: "%.1fms", debug.videoMaxPtsGapMs),
                    color: debug.videoMaxPtsGapMs > 50 ? .red :
                           debug.videoMaxPtsGapMs > 20 ? .yellow : .green)
            infoRow("LastSkip", debug.lastSkipInfo,
                    color: debug.lastSkipInfo != "--" ? .yellow : .gray)

            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 2)

            sectionHeader("AUDIO SYNC")
            infoRow("ABuf", "\(debug.audioBufferCount) bufs",
                    color: debug.audioBufferCount > 100 ? .red :
                           debug.audioBufferCount > 50 ? .yellow : .green)
            infoRow("ADrift", String(format: "%.1fms", debug.audioDriftMs),
                    color: abs(debug.audioDriftMs) < 5 ? .green : .yellow)
            infoRow("VComp", String(format: "%.1fms", debug.videoDriftCompensationMs),
                    color: abs(debug.videoDriftCompensationMs) < 5 ? .green : .yellow)
            infoRow("VInit", String(format: "%.1fms", debug.videoInitialOffsetMs),
                    color: debug.videoInitialOffsetMs < 55 ? .green : .yellow)
            infoRow("AErr", String(format: "%.3fms", debug.audioDiagErr),
                    color: abs(debug.audioDiagErr) < 0.1 ? .green : (debug.audioDiagErr < 0 ? .red : .yellow))
            infoRow("AAccum", String(format: "%.1fms", debug.audioDiagAccum),
                    color: abs(debug.audioDiagAccum) < 5 ? .green : .red)
            infoRow("AMode", debug.audioMode,
                    color: debug.audioMode == "STEREO" ? .cyan : .white)
            infoRow("AMix", String(format: "%.3fms", debug.audioMixTime),
                    color: debug.audioMixTime < 1.0 ? .green : .yellow)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - YOLO Tab

    private var yoloContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader("DETECTION")
            infoRow("Detect", debug.yoloDetected ? "YES" : "NO",
                    color: debug.yoloDetected ? .green : .red)
            infoRow("Conf", String(format: "%.2f", debug.yoloConfidence))
            infoRow("Infer", String(format: "%.1fms", debug.yoloInferenceMs))
            infoRow("Prep", String(format: "%.1fms", debug.yoloPreprocessMs))
            infoRow("Total", String(format: "%.1fms", debug.yoloInferenceMs + debug.yoloPreprocessMs))

            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 2)

            sectionHeader("DETAIL")
            infoRow("Boxes", debug.yoloBoxesInfo)
            infoRow("Top3", debug.yoloTopBoxes)
            infoRow("Rank", "\(debug.yoloBestRank)", color: debug.yoloBestRank == 1 ? .green : .orange)
            infoRow("YFPS", String(format: "%.0f/%.0f", debug.yoloActualFPS, debug.yoloTargetFPS),
                    color: debug.yoloActualFPS >= debug.yoloTargetFPS * 0.8 ? .green : .orange)
            infoRow("Pad", "\(debug.yoloPadding)px")
            infoRow("U", debug.yoloUniforms)

            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 2)

            sectionHeader("COORDS")
            infoRow("Raw", debug.yoloRawCoord)
            infoRow("Stab", debug.yoloStabCoord)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - TRACK Tab

    private var trackContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader("TRACKING")
            infoRow("State", debug.trackState == "tracking" && debug.trackTrust < 1.0 ? "tracking*" : debug.trackState,
                    color: debug.trackState == "tracking" ? (debug.trackTrust < 1.0 ? .yellow : .green) :
                           debug.trackState == "acquiring" ? .cyan :
                           debug.trackState == "grace" ? .yellow :
                           debug.trackState == "recenter" ? .yellow : .orange)
            infoRow("Crop", String(format: "%.0f×%.0f @%.0f,%.0f",
                debug.trackCropW, debug.trackCropH,
                debug.trackCx, debug.trackCy))
            infoRow("AR", String(format: "%.3f", debug.trackAspectRatio),
                    color: abs(debug.trackAspectRatio - 1.0) < 0.02 ? .green :
                           abs(debug.trackAspectRatio - 1.0) < 0.05 ? .yellow : .red)
            infoRow("Trust", String(format: "%.2f", debug.trackTrust),
                    color: debug.trackTrust > 0.8 ? .green :
                           debug.trackTrust > 0.3 ? .yellow : .red)
            infoRow("Raw", String(format: "%.0f×%.0f", debug.trackRawW, debug.trackRawH))
            infoRow("Smooth", String(format: "%.0f", debug.trackSmoothSize))
            infoRow("Ratio", String(format: "%.2f", debug.trackTargetRatio))
            infoRow("Recenter", String(format: "%.2f", debug.trackRecenterSpeed))
            infoRow("HOff", String(format: "%+.0fpx", debug.cropHorizontalOffset))

            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 2)

            sectionHeader("STABILIZER")
            infoRow("FOV", String(format: "%.0f°", debug.fov))
            infoRow("Dist", String(format: "%.2f", debug.distRatio))
            infoRow("Lens", debug.lensType)
            infoRow("Stab", debug.stabEnabled ? "ON" : "OFF",
                    color: debug.stabEnabled ? .green : .red)
            infoRow("Frame", "\(debug.frameCount)")

            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 2)

            sectionHeader("MAGNETOMETER")
            infoRow("Accuracy", magneticAccuracyString(debug.magneticAccuracy),
                    color: magneticAccuracyColor(debug.magneticAccuracy))
            infoRow("RawYaw", String(format: "%.1f°", debug.rawYawDeg))
            infoRow("FltYaw", String(format: "%.1f°", debug.filteredYawDeg))
            infoRow("YawDelta", String(format: "%.2f°", debug.yawDeltaDeg),
                    color: abs(debug.yawDeltaDeg) > 2.0 ? .red :
                           abs(debug.yawDeltaDeg) > 0.5 ? .yellow : .green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - LOG Tab

    private var logContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(debug.logMessages.indices, id: \.self) { i in
                            Text(debug.logMessages[i])
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.green.opacity(0.8))
                                .id(i)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: debug.logMessages.count) { count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.cyan)
    }

    private func infoRow(_ label: String, _ value: String, color: Color = .white) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .foregroundColor(.gray)
            Text(value)
                .foregroundColor(color)
            Spacer()
        }
    }

    private func rtmpStatusColor(_ status: String) -> Color {
        switch status {
        case "Publishing": return .green
        case "Connecting", "Connected": return .yellow
        case "Idle": return .gray
        default: return .red
        }
    }

    private func magneticAccuracyString(_ accuracy: Int32) -> String {
        switch accuracy {
        case 2: return "HIGH"
        case 1: return "MEDIUM"
        case 0: return "LOW"
        default: return "UNCALIBRATED"
        }
    }

    private func magneticAccuracyColor(_ accuracy: Int32) -> Color {
        switch accuracy {
        case 2: return .green
        case 1: return .yellow
        case 0: return .orange
        default: return .red
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { _ in
                dragOffset = .zero
            }
    }
}
