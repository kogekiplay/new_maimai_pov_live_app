import SwiftUI

struct DebugOverlayView: View {
    enum DebugTab: CaseIterable {
        case stream
        case yolo
        case track
        case log

        var title: String {
            switch self {
            case .stream: return L10n.string("Stream")
            case .yolo: return "YOLO"
            case .track: return L10n.string("Track")
            case .log: return L10n.string("Log")
            }
        }
    }

    @ObservedObject var debug: DebugInfoManager
    @Binding var isAntiTouchMode: Bool
    @Binding var antiTouchTimer: Timer?
    @Binding var selectedTab: DebugTab

    private var isCollapsed: Bool { !debug.isDetailVisible }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlassPanelBackground(cornerRadius: 10, tint: Color.black.opacity(isCollapsed ? 0.28 : 0.42))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        Button(action: toggleDetailVisibility) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))

                    Text("Debug")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.cyan)
                .padding(.trailing, 8)

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
                    Text(debug.rtmpStatus == "Publishing" ? "PUB" : L10n.streamStatus(debug.rtmpStatus))
                        .foregroundColor(rtmpStatusColor(debug.rtmpStatus))
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityIdentifier("debug-toggle")
        .accessibilityLabel("Debug")
        .accessibilityHint(L10n.string(isCollapsed ? "Expand debug details" : "Collapse debug details"))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        DraggableGlassSegmentedControl(
            selection: $selectedTab,
            segments: DebugTab.allCases.map { .init(value: $0, title: $0.title) },
            accent: .cyan
        )
        .frame(width: 188, height: 28)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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
            infoRow("Status", L10n.streamStatus(debug.rtmpStatus),
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
            infoRow("Detect", L10n.string(debug.yoloDetected ? "Yes" : "No"),
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
            infoRow("Stab", L10n.string(debug.stabEnabled ? "On" : "Off"),
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
                .onChange(of: debug.logMessages.count) { _, count in
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
        Text(L10n.string(title))
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.cyan)
    }

    private func infoRow(_ label: String, _ value: String, color: Color = .white) -> some View {
        HStack(spacing: 4) {
            Text("\(L10n.string(label)):")
                .foregroundColor(.gray)
            Text(value)
                .foregroundColor(color)
            Spacer()
        }
    }

    private func rtmpStatusColor(_ status: String) -> Color {
        if status.hasPrefix("Reconnecting(") {
            return .yellow
        }

        switch status {
        case "Publishing": return .green
        case "Connecting", "Connected": return .yellow
        case "Idle": return .gray
        default: return .red
        }
    }

    private func magneticAccuracyString(_ accuracy: Int32) -> String {
        switch accuracy {
        case 2: return L10n.string("High")
        case 1: return L10n.string("Medium")
        case 0: return L10n.string("Low")
        default: return L10n.string("Uncalibrated")
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

    private func toggleDetailVisibility() {
        antiTouchTimer?.invalidate()
        antiTouchTimer = nil
        isAntiTouchMode = false
        withAnimation(.easeInOut(duration: 0.15)) {
            debug.isDetailVisible.toggle()
        }
    }
}

private struct DraggableGlassSegmentedControl<Selection: Hashable>: View {
    struct Segment: Identifiable {
        let value: Selection
        let title: String

        var id: Selection { value }
    }

    @Binding var selection: Selection
    let segments: [Segment]
    let accent: Color

    @State private var pressedIndex: Int?
    @State private var dragCenterX: CGFloat?
    @Namespace private var glassNamespace

    private let height: CGFloat = 28
    private let horizontalInset: CGFloat = 4
    private let thumbInset: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segmentWidth = SegmentedDragMetrics.segmentWidth(
                totalWidth: width,
                horizontalInset: horizontalInset,
                count: segments.count
            )
            let isDragging = dragCenterX != nil
            let currentIndex = pressedIndex ?? selectedIndex
            let thumbWidth = SegmentedDragMetrics.thumbWidth(
                segmentWidth: segmentWidth,
                thumbInset: thumbInset,
                isDragging: isDragging
            )
            let thumbHeight = isDragging ? height : height - 2
            let thumbCenterX = dragCenterX ?? SegmentedDragMetrics.centerX(
                for: currentIndex,
                totalWidth: width,
                horizontalInset: horizontalInset,
                count: segments.count
            )
            let thumbOffset = SegmentedDragMetrics.offset(
                forCenterX: thumbCenterX,
                totalWidth: width,
                thumbWidth: thumbWidth
            )

            controlBody(
                segmentWidth: segmentWidth,
                thumbWidth: thumbWidth,
                thumbHeight: thumbHeight,
                thumbOffset: thumbOffset,
                isDragging: isDragging
            )
            .contentShape(Capsule())
            .simultaneousGesture(dragGesture(width: width))
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func controlBody(
        segmentWidth: CGFloat,
        thumbWidth: CGFloat,
        thumbHeight: CGFloat,
        thumbOffset: CGFloat,
        isDragging: Bool
    ) -> some View {
        if #available(iOS 26.0, *) {
            nativeGlassBody(
                segmentWidth: segmentWidth,
                thumbWidth: thumbWidth,
                thumbHeight: thumbHeight,
                thumbOffset: thumbOffset,
                isDragging: isDragging
            )
        } else {
            fallbackBody(
                segmentWidth: segmentWidth,
                thumbWidth: thumbWidth,
                thumbHeight: thumbHeight,
                thumbOffset: thumbOffset,
                isDragging: isDragging
            )
        }
    }

    @available(iOS 26.0, *)
    private func nativeGlassBody(
        segmentWidth: CGFloat,
        thumbWidth: CGFloat,
        thumbHeight: CGFloat,
        thumbOffset: CGFloat,
        isDragging: Bool
    ) -> some View {
        GlassEffectContainer(spacing: 6) {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        Button {
                            selectSegment(at: index)
                        } label: {
                            nativeGlassSegment(
                                title: segment.title,
                                isSelected: selectedIndex == index
                            )
                            .frame(width: segmentWidth, height: height - 2)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .glassEffectUnion(id: "debug-segment-track", namespace: glassNamespace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(segment.title)
                        .accessibilityValue(selectedIndex == index ? L10n.string("Selected") : "")
                    }
                }
                .padding(.horizontal, horizontalInset)

                selectedGlassSegment(isDragging: isDragging)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .offset(x: thumbOffset, y: (height - thumbHeight) / 2)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID("debug-segment-selection", in: glassNamespace)
                    .animation(dragCenterX == nil ? .interactiveSpring(response: 0.26, dampingFraction: 0.82) : nil, value: thumbOffset)
                    .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.78), value: isDragging)
                    .allowsHitTesting(false)
            }
        }
    }

    private func fallbackBody(
        segmentWidth: CGFloat,
        thumbWidth: CGFloat,
        thumbHeight: CGFloat,
        thumbOffset: CGFloat,
        isDragging: Bool
    ) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                }

            selectedGlassSegment(isDragging: isDragging)
                .frame(width: thumbWidth, height: thumbHeight)
                .background(accent.opacity(isDragging ? 0.24 : 0.16), in: Capsule())
                .offset(x: thumbOffset, y: (height - thumbHeight) / 2)
                .animation(dragCenterX == nil ? .interactiveSpring(response: 0.26, dampingFraction: 0.82) : nil, value: thumbOffset)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.78), value: isDragging)
                .allowsHitTesting(false)

            segmentButtonsRow(segmentWidth: segmentWidth, selectedTextIsHidden: true)
        }
    }

    @available(iOS 26.0, *)
    private func nativeGlassSegment(title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.system(size: 9, weight: isSelected ? .bold : .semibold, design: .monospaced))
            .foregroundColor(isSelected ? .clear : .white.opacity(0.58))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
    }

    private func segmentButtonsRow(segmentWidth: CGFloat, selectedTextIsHidden: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                Button {
                    selectSegment(at: index)
                } label: {
                    segmentText(segment.title, isSelected: selectedIndex == index, selectedTextIsHidden: selectedTextIsHidden)
                        .frame(width: segmentWidth, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.title)
                .accessibilityValue(selectedIndex == index ? L10n.string("Selected") : "")
            }
        }
        .padding(.horizontal, horizontalInset)
    }

    private func segmentText(_ title: String, isSelected: Bool, selectedTextIsHidden: Bool) -> some View {
        Text(title)
            .font(.system(size: 9, weight: isSelected ? .bold : .semibold, design: .monospaced))
            .foregroundColor(isSelected && selectedTextIsHidden ? .clear : .white.opacity(0.58))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func selectedGlassSegment(isDragging: Bool) -> some View {
        Text(selectedTitle)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .scaleEffect(isDragging ? 1.03 : 1)
            .animation(.easeOut(duration: 0.12), value: isDragging)
    }

    private var selectedIndex: Int {
        segments.firstIndex { $0.value == selection } ?? 0
    }

    private var selectedTitle: String {
        guard segments.indices.contains(selectedIndex) else { return "" }
        return segments[selectedIndex].title
    }

    private func selectSegment(at index: Int) {
        guard segments.indices.contains(index) else { return }
        guard segments[index].value != selection else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.82)) {
            selection = segments[index].value
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !segments.isEmpty else { return }

                let segmentWidth = SegmentedDragMetrics.segmentWidth(
                    totalWidth: width,
                    horizontalInset: horizontalInset,
                    count: segments.count
                )
                let thumbWidth = SegmentedDragMetrics.thumbWidth(
                    segmentWidth: segmentWidth,
                    thumbInset: thumbInset,
                    isDragging: true
                )
                dragCenterX = SegmentedDragMetrics.clampedCenterX(
                    value.location.x,
                    totalWidth: width,
                    thumbWidth: thumbWidth
                )

                let nextIndex = SegmentedDragMetrics.index(
                    at: value.location.x,
                    totalWidth: width,
                    horizontalInset: horizontalInset,
                    count: segments.count
                )
                pressedIndex = nextIndex

                guard segments[nextIndex].value != selection else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selection = segments[nextIndex].value
            }
            .onEnded { _ in
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.82)) {
                    pressedIndex = nil
                    dragCenterX = nil
                }
            }
    }
}

private enum SegmentedDragMetrics {
    static func segmentWidth(totalWidth: CGFloat, horizontalInset: CGFloat, count: Int) -> CGFloat {
        let availableWidth = max(totalWidth - horizontalInset * 2, 1)
        return availableWidth / CGFloat(max(count, 1))
    }

    static func thumbWidth(segmentWidth: CGFloat, thumbInset: CGFloat, isDragging: Bool) -> CGFloat {
        max(segmentWidth - thumbInset * (isDragging ? 0.5 : 2), 1)
    }

    static func centerX(
        for index: Int,
        totalWidth: CGFloat,
        horizontalInset: CGFloat,
        count: Int
    ) -> CGFloat {
        let segmentWidth = segmentWidth(
            totalWidth: totalWidth,
            horizontalInset: horizontalInset,
            count: count
        )
        let clampedIndex = min(max(index, 0), max(count - 1, 0))
        return horizontalInset + segmentWidth * (CGFloat(clampedIndex) + 0.5)
    }

    static func offset(forCenterX centerX: CGFloat, totalWidth: CGFloat, thumbWidth: CGFloat) -> CGFloat {
        let maxOffset = max(totalWidth - thumbWidth, 0)
        return min(max(centerX - thumbWidth / 2, 0), maxOffset)
    }

    static func clampedCenterX(_ centerX: CGFloat, totalWidth: CGFloat, thumbWidth: CGFloat) -> CGFloat {
        let minCenter = thumbWidth / 2
        let maxCenter = max(totalWidth - thumbWidth / 2, minCenter)
        return min(max(centerX, minCenter), maxCenter)
    }

    static func index(at locationX: CGFloat, totalWidth: CGFloat, horizontalInset: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }

        let segmentWidth = segmentWidth(
            totalWidth: totalWidth,
            horizontalInset: horizontalInset,
            count: count
        )
        let maxInnerX = segmentWidth * CGFloat(count) - 0.01
        let clampedX = min(max(locationX - horizontalInset, 0), maxInnerX)
        return min(max(Int(clampedX / segmentWidth), 0), count - 1)
    }
}
