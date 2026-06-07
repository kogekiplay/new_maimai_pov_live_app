import SwiftUI
import AVFoundation
import Metal
import UIKit
import PhotosUI

private enum ControlTab: String, CaseIterable {
    case camera = "拍摄"
    case effects = "效果"
    case stream = "推流"
    case blivechat = "弹幕"

    var icon: String {
        switch self {
        case .camera: return "camera"
        case .effects: return "wand.and.stars"
        case .stream: return "arrow.up.circle"
        case .blivechat: return "message.fill"
        }
    }
}

struct Phase2View: View {
    @StateObject private var pipeline = LivePipelineManager()
    @State private var selectedTab: ControlTab = .camera
    @State private var panelExpanded: Bool = true
    @State private var isAntiTouchMode: Bool = false
    @State private var antiTouchTimer: Timer?
    @State private var volumeObservation: NSKeyValueObservation?
    @State private var previewOverride: Bool = false
    @State private var advancedExpanded: Bool = false
    @State private var presets: [StreamPreset] = Config.streamPresets
    @State private var showAddPresetSheet = false
    @State private var newPresetName = ""
    @State private var newPresetUrl = ""
    @State private var newPresetKey = ""
    @State private var gestureStartYaw: Float = 0
    @State private var gestureStartPitch: Float = 0
    @State private var gestureStartRoll: Float = 0
    @State private var dragStarted = false
    @State private var rotationStarted = false
    @AppStorage("rtmpUrl") private var rtmpUrl: String = ""
    @AppStorage("streamKey") private var streamKey: String = ""
    @State private var showImagePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showRestoreAlert = false

    var body: some View {
        VStack(spacing: 0) {
            previewSection
                .frame(maxHeight: .infinity)

            controlPanel
        }
        .preferredColorScheme(.dark)
        .background(Color.black)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            pipeline.start()

            if pipeline.hasRestorableSnapshot {
                showRestoreAlert = true
            }

            let session = AVAudioSession.sharedInstance()
            volumeObservation = session.observe(\.outputVolume) { [weak session] _, _ in
                guard session != nil else { return }
                DispatchQueue.main.async {
                    if isAntiTouchMode {
                        antiTouchTimer?.invalidate()
                        antiTouchTimer = nil
                        isAntiTouchMode = false
                    }
                }
            }
        }
        .alert("恢复点歌队列", isPresented: $showRestoreAlert) {
            Button("恢复队列") {
                pipeline.restoreQueueFromSnapshot()
            }
            Button("保留未演奏礼物值") {
                pipeline.restoreGiftValuesOnlyFromSnapshot()
            }
            Button("保留所有礼物值") {
                pipeline.restoreAllGiftValuesFromSnapshot()
            }
            Button("不恢复", role: .destructive) {
                pipeline.discardSnapshot()
            }
        } message: {
            let songGiftCount = pipeline.preservableGiftValueUserCount
            let allGiftCount = pipeline.allPreservableGiftValueUserCount
            if allGiftCount > 0 {
                Text("检测到\(pipeline.snapshotAgeString)有点歌队列数据，是否恢复？\n（未演奏\(songGiftCount)位 / 全部\(allGiftCount)位用户可继承礼物值）")
            } else {
                Text("检测到\(pipeline.snapshotAgeString)有点歌队列数据，是否恢复？")
            }
        }
        .phase2ChangeHandlers(
            pipeline: pipeline,
            panelExpanded: $panelExpanded,
            isAntiTouchMode: $isAntiTouchMode,
            antiTouchTimer: $antiTouchTimer
        )
        .onDisappear {
            antiTouchTimer?.invalidate()
            antiTouchTimer = nil
            volumeObservation?.invalidate()
            volumeObservation = nil
            pipeline.stop()
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if pipeline.stabEnabled, pipeline.camera.cameraAuthorized {
                    if let texture = pipeline.previewTexture {
                        MetalView(device: pipeline.device, texture: texture, previewEnabled: pipeline.previewEnabled, commandQueue: pipeline.sharedCommandQueue)
                            .aspectRatio(pipeline.isCropActive ? CGFloat(Config.outputWidth) / CGFloat(Config.outputHeight) : 3.0 / 4.0, contentMode: .fit)
                    }
                } else if pipeline.camera.cameraAuthorized {
                    CameraPreviewView(session: pipeline.camera.session)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .overlay(Text("Camera not authorized").foregroundColor(.gray))
                }

                if pipeline.stabEnabled, pipeline.previewEnabled {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    if !dragStarted {
                                        dragStarted = true
                                        gestureStartYaw = pipeline.yaw
                                        gestureStartPitch = pipeline.pitch
                                    }
                                    let dx = Float(value.translation.width)
                                    let dy = Float(value.translation.height)
                                    let sensitivity: Float = 0.3
                                    pipeline.yaw = clamp(gestureStartYaw - dx * sensitivity, -90, 90)
                                    pipeline.pitch = clamp(gestureStartPitch + dy * sensitivity, -90, 90)
                                }
                                .onEnded { _ in
                                    dragStarted = false
                                }
                        )
                        .simultaneousGesture(
                            RotationGesture()
                                .onChanged { angle in
                                    if !rotationStarted {
                                        rotationStarted = true
                                        gestureStartRoll = pipeline.roll
                                    }
                                    pipeline.roll = clamp(gestureStartRoll - Float(angle.degrees), -45, 45)
                                }
                                .onEnded { _ in
                                    rotationStarted = false
                                }
                        )
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        pipeline.yaw = 0
                                        pipeline.pitch = 0
                                        pipeline.roll = 0
                                    }
                                }
                        )
                }
            }

            DebugOverlayView(debug: pipeline.debug, isAntiTouchMode: $isAntiTouchMode)
                .padding(.leading, 4)
                .padding(.top, 4)

            if pipeline.yoloOverlayEnabled, pipeline.yoloEnabled {
                VStack {
                    Spacer()
                    HStack {
                        YOLOOverlayView(
                            debug: pipeline.debug,
                            device: pipeline.device,
                            texture: pipeline.stabTexture
                        )
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.7, maxHeight: UIScreen.main.bounds.height * 0.5)
                        .padding(4)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 0) {
            Button {
                if isAntiTouchMode { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    panelExpanded.toggle()
                    previewOverride = false
                    pipeline.previewEnabled = panelExpanded
                }
            } label: {
                HStack {
                    if panelExpanded {
                        Text(selectedTab.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .fill(statusColor(pipeline.streamManager.streamStatus))
                            .frame(width: 8, height: 8)
                        Text(pipeline.streamManager.streamStatus)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(statusColor(pipeline.streamManager.streamStatus))
                    }
                    Spacer()
                    Image(systemName: panelExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .adaptiveGlassPanel(cornerRadius: 8, tint: Color.white.opacity(0.04), interactive: true)
            }
            .buttonStyle(.plain)

            if panelExpanded {
                ScrollView(.vertical, showsIndicators: false) {
                    switch selectedTab {
                    case .camera: cameraTabContent
                    case .effects: effectsTabContent
                    case .stream: streamTabContent
                    case .blivechat: blivechatTabContent
                    }
                }
                .frame(maxHeight: 240)

                ControlTabRail(selection: $selectedTab)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .padding(.bottom, bottomSafeArea)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .adaptiveGlassPanel(cornerRadius: 14, tint: Color.black.opacity(0.18))
    }

    // MARK: - Camera Tab

    private var cameraTabContent: some View {
        VStack(spacing: 8) {
            lensPicker
            isoRow
            autoFocusRow
            if !pipeline.autoFocusEnabled {
                focusRow
            }
            stabilizerToggleRow
        }
        .padding(12)
    }

    // MARK: - Effects Tab

    private var effectsTabContent: some View {
        VStack(spacing: 8) {
            fovRow
            distRatioRow
            yoloToggleRow
            if pipeline.yoloEnabled {
                yoloOverlayToggleRow
            }
            overlayToggleRow
            if pipeline.overlayEnabled {
                overlayPosXRow
                overlayPosYRow
                overlayScaleRow
                overlayOpacityRow
                overlayRotationRow
            }

            Button {
                withAnimation {
                    advancedExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("高级设置").font(.caption).foregroundColor(.gray)
                    Spacer()
                    Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundColor(.gray)
                }
            }

            if advancedExpanded {
                VStack(spacing: 8) {
                    activitySmoothFactorRow
                    syncRow
                    yoloPaddingRow
                    trackTargetRatioRow
                    trackRecenterSpeedRow
                    recenterGraceMsRow
                    acquireSpeedRow
                    cropVerticalOffsetRow
                    smoothingToggleRow
                    if pipeline.smoothingEnabled {
                        smoothingBaseAlphaRow
                        smoothingDeviationRow
                        smoothingCenterFloorRow
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Stream Tab

    private var streamTabContent: some View {
        VStack(spacing: 8) {
            if !presets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button {
                                rtmpUrl = preset.url
                                streamKey = preset.streamKey
                            } label: {
                                HStack(spacing: 4) {
                                    Text(preset.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Button {
                                        presets.removeAll { $0.id == preset.id }
                                        Config.streamPresets = presets
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .adaptiveGlassPanel(cornerRadius: 8, tint: Color.white.opacity(0.06), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                showAddPresetSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("添加预设")
                }
                .font(.caption)
            }
            .sheet(isPresented: $showAddPresetSheet) {
                NavigationView {
                    Form {
                        TextField("名称", text: $newPresetName)
                        TextField("RTMP URL", text: $newPresetUrl)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("Stream Key", text: $newPresetKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .navigationTitle("添加预设")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showAddPresetSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                let preset = StreamPreset(name: newPresetName, url: newPresetUrl, streamKey: newPresetKey)
                                presets.append(preset)
                                Config.streamPresets = presets
                                newPresetName = ""
                                newPresetUrl = ""
                                newPresetKey = ""
                                showAddPresetSheet = false
                            }
                            .disabled(newPresetName.isEmpty || newPresetUrl.isEmpty)
                        }
                    }
                }
            }
            .adaptiveGlassButton()

            rtmpUrlRow
            streamKeyRow
            resolutionRow
            bitrateRow
            audioSourceRow
            audioMixerSection
            audioMeterRow
            streamButtonRow
        }
        .padding(12)
    }

    // MARK: - Blivechat Tab

    private var blivechatTabContent: some View {
        VStack(spacing: 8) {
            HStack {
                Text("服务器").font(.caption).frame(width: 55, alignment: .leading)
                Picker("", selection: $pipeline.blivechatServer) {
                    ForEach(BlivechatServer.allCases) { server in
                        Text(server.displayName).tag(server)
                    }
                }
                .pickerStyle(.menu)
                .disabled(isBlivechatConnected)
            }

            HStack {
                Text("身份码").font(.caption).frame(width: 55, alignment: .leading)
                TextField("输入身份码", text: $pipeline.blivechatIdentityCode)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(isBlivechatConnected)
            }

            HStack {
                if isBlivechatConnected {
                    Button {
                        pipeline.disconnectBlivechat()
                    } label: {
                        HStack {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("断开").font(.caption).fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButton(prominent: true)
                    .tint(.red)
                    .controlSize(.small)
                } else if isBlivechatReconnecting {
                    Button {
                        pipeline.disconnectBlivechat()
                    } label: {
                        HStack {
                            ProgressView().scaleEffect(0.6)
                            Text("强制断开").font(.caption).fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButton(prominent: true)
                    .tint(.red)
                    .controlSize(.small)
                } else {
                    Button {
                        pipeline.connectBlivechat()
                    } label: {
                        HStack {
                            Image(systemName: "link").font(.caption)
                            Text("连接").font(.caption).fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButton(prominent: true)
                    .tint(.green)
                    .controlSize(.small)
                    .disabled(pipeline.blivechatIdentityCode.isEmpty)
                }

                Text(blivechatStateText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(blivechatStateColor)
                    .lineLimit(1)
            }

            if isBlivechatConnected {
                Divider().background(Color.gray.opacity(0.3))

                if !pipeline.webServerURL.isEmpty {
                    HStack {
                        Text("LAN").font(.caption).frame(width: 55, alignment: .leading)
                        Text(pipeline.webServerURL)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.cyan)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .onTapGesture {
                                UIPasteboard.general.string = pipeline.webServerURL
                            }
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .onTapGesture {
                                UIPasteboard.general.string = pipeline.webServerURL
                            }
                    }
                }

                Divider().background(Color.gray.opacity(0.3))

                HStack {
                    Text("弹幕").font(.caption).frame(width: 55, alignment: .leading)
                    Text(pipeline.latestDanmaku)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text("\(pipeline.danmakuCount)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Divider().background(Color.gray.opacity(0.3))
            }
        }
        .padding(12)
    }

    private var isBlivechatConnected: Bool {
        if case .connected = pipeline.blivechatConnectionState { return true }
        return false
    }

    private var isBlivechatReconnecting: Bool {
        if case .reconnecting = pipeline.blivechatConnectionState { return true }
        return false
    }

    private var blivechatStateText: String {
        switch pipeline.blivechatConnectionState {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .reconnecting(let msg): return "重连中: \(msg)"
        case .error(let msg):
            let display = msg.count > 15 ? String(msg.prefix(15)) + "..." : msg
            return "错误: \(display)"
        }
    }

    private var blivechatStateColor: Color {
        switch pipeline.blivechatConnectionState {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .reconnecting: return .yellow
        case .error: return .red
        }
    }

    // MARK: - Control Rows

    private var lensPicker: some View {
        Picker("Lens", selection: $pipeline.selectedLens) {
            ForEach(LensType.allCases, id: \.self) { lens in
                Text(lens.rawValue).tag(lens)
            }
        }
        .pickerStyle(.segmented)
    }

    private var isoRow: some View {
        labeledRow("ISO") {
            Slider(value: $pipeline.isoValue, in: pipeline.minISO...pipeline.maxISO, step: 1)
        } valueLabel: {
            Text("\(Int(pipeline.isoValue))").font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .onChange(of: pipeline.camera.isRunning) { _, running in
            if running { pipeline.updateISORange() }
        }
    }

    private var autoFocusRow: some View {
        HStack {
            Text("Focus").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.autoFocusEnabled).labelsHidden()
            Spacer()
            Text(pipeline.autoFocusEnabled ? "AUTO" : "LOCK")
                .font(.caption2)
                .foregroundColor(pipeline.autoFocusEnabled ? .green : .orange)
        }
    }

    private var focusRow: some View {
        labeledRow("Focus") {
            Slider(value: $pipeline.focusValue, in: 0...1)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.focusValue)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var stabilizerToggleRow: some View {
        HStack(spacing: 6) {
            Text("Stabilizer").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.stabEnabled).labelsHidden().controlSize(.small)
            Spacer(minLength: 2)
            Image(systemName: "figure.run")
                .font(.caption2)
                .foregroundColor(pipeline.activityMode ? .green : .gray)
                .frame(width: 12)
            Toggle("", isOn: $pipeline.activityMode).labelsHidden().controlSize(.small)
            Spacer(minLength: 2)
            Image(systemName: "eye")
                .font(.caption2)
                .foregroundColor(.gray)
                .frame(width: 12)
            Toggle("", isOn: Binding(
                get: { pipeline.previewEnabled },
                set: { newValue in
                    previewOverride = true
                    pipeline.previewEnabled = newValue
                }
            )).labelsHidden().controlSize(.small)
            Spacer(minLength: 2)
            Text("\(String(format: "%.1f", pipeline.lagMs))ms")
                .font(.caption2).foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var fovRow: some View {
        labeledRow("FOV") {
            Slider(value: Binding(get: { Double(pipeline.fov) }, set: { pipeline.fov = Float($0) }), in: 30...160, step: 1)
        } valueLabel: {
            Text("\(Int(pipeline.fov))°").font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var distRatioRow: some View {
        labeledRow("Dist") {
            Slider(value: Binding(get: { Double(pipeline.distRatio) }, set: { pipeline.distRatio = Float($0) }), in: 0...1)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.distRatio)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var activitySmoothFactorRow: some View {
        labeledRow("Follow") {
            Slider(value: Binding(get: { Double(pipeline.activitySmoothFactor) }, set: { pipeline.activitySmoothFactor = Float($0) }), in: 0.01...0.2)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.activitySmoothFactor)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var syncRow: some View {
        Group {
            labeledRow("Sync") {
                Slider(value: $pipeline.syncOffsetMs, in: -50...50)
            } valueLabel: {
                Text(String(format: "%.0f", pipeline.syncOffsetMs)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
            }
            labeledRow("Readout") {
                Slider(value: $pipeline.readoutTimeMs, in: 5...15)
            } valueLabel: {
                Text(String(format: "%.1f", pipeline.readoutTimeMs)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
            }
        }
    }

    private var yoloToggleRow: some View {
        HStack {
            Text("YOLO").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.yoloEnabled).labelsHidden()
            Spacer()
            Text(pipeline.yoloEnabled ? "ON" : "OFF")
                .font(.caption2)
                .foregroundColor(pipeline.yoloEnabled ? .green : .red)
        }
    }

    private var yoloPaddingRow: some View {
        labeledRow("YOLOPad") {
            Slider(value: $pipeline.yoloPadding, in: 0...100, step: 1)
        } valueLabel: {
            Text("\(Int(pipeline.yoloPadding))px").font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var yoloOverlayToggleRow: some View {
        HStack {
            Text("YOLOOverlay").font(.caption).frame(width: 80, alignment: .leading)
            Toggle("", isOn: $pipeline.yoloOverlayEnabled)
                .labelsHidden()
                .onChange(of: pipeline.yoloOverlayEnabled) { _, _ in
                    pipeline.updateYoloOverlayEnabled()
                }
            Spacer()
            Text(pipeline.yoloOverlayEnabled ? "ON" : "OFF")
                .font(.caption2)
                .foregroundColor(pipeline.yoloOverlayEnabled ? .green : .red)
        }
    }

    private var overlayToggleRow: some View {
        HStack {
            let overlayEnabled = pipeline.overlayEnabled
            Text("Overlay").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.overlayEnabled).labelsHidden()
            Spacer()
            PhotosPicker(selection: $selectedPhotoItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundColor(overlayEnabled ? .cyan : .gray)
            }
            .disabled(!overlayEnabled)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem = newItem else { return }
                let pipeline = pipeline
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            pipeline.loadOverlayImage(image)
                        }
                    }
                }
            }
            Spacer()
            Text(pipeline.overlayEnabled ? "ON" : "OFF")
                .font(.caption2)
                .foregroundColor(pipeline.overlayEnabled ? .green : .red)
        }
    }

    private func slotTuningRow(label: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float) -> some View {
        HStack {
            Text(label).font(.system(size: 9, design: .monospaced)).frame(width: 22, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.3f", value.wrappedValue)).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray).frame(width: 38, alignment: .trailing)
        }
    }

    private var overlayPosXRow: some View {
        labeledRow("OX") {
            Slider(value: $pipeline.overlayPosX, in: -0.5...1.5, step: 0.01)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.overlayPosX)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .disabled(!pipeline.overlayEnabled)
    }

    private var overlayPosYRow: some View {
        labeledRow("OY") {
            Slider(value: $pipeline.overlayPosY, in: -0.5...1.5, step: 0.01)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.overlayPosY)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .disabled(!pipeline.overlayEnabled)
    }

    private var overlayScaleRow: some View {
        labeledRow("OScale") {
            Slider(value: $pipeline.overlayScale, in: 0.05...3.0, step: 0.01)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.overlayScale)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .disabled(!pipeline.overlayEnabled)
    }

    private var overlayOpacityRow: some View {
        labeledRow("OAlpha") {
            Slider(value: $pipeline.overlayOpacity, in: 0...1, step: 0.01)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.overlayOpacity)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .disabled(!pipeline.overlayEnabled)
    }

    private var overlayRotationRow: some View {
        labeledRow("ORot") {
            Slider(value: $pipeline.overlayRotation, in: 0...360, step: 1)
        } valueLabel: {
            Text("\(Int(pipeline.overlayRotation))°").font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .disabled(!pipeline.overlayEnabled)
    }

    private var trackTargetRatioRow: some View {
        labeledRow("TargetRatio") {
            Slider(value: $pipeline.trackTargetRatio, in: 0.1...1.0, step: 0.05)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.trackTargetRatio)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var trackRecenterSpeedRow: some View {
        labeledRow("Recenter") {
            Slider(value: $pipeline.trackRecenterSpeed, in: 0.05...0.5, step: 0.01)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.trackRecenterSpeed)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var recenterGraceMsRow: some View {
        labeledRow("Grace") {
            Slider(value: $pipeline.recenterGraceMs, in: 0...2000, step: 50)
        } valueLabel: {
            Text("\(Int(pipeline.recenterGraceMs))ms").font(.caption).foregroundColor(.gray).frame(width: 50, alignment: .trailing)
        }
    }

    private var acquireSpeedRow: some View {
        labeledRow("Acquire") {
            Slider(value: $pipeline.acquireSpeed, in: 0.05...0.5, step: 0.01)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.acquireSpeed)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
    }

    private var cropVerticalOffsetRow: some View {
        labeledRow("HOffset") {
            Slider(value: $pipeline.cropHorizontalOffset, in: -500...500, step: 10)
        } valueLabel: {
            Text("\(Int(pipeline.cropHorizontalOffset))px").font(.caption).foregroundColor(.gray).frame(width: 50, alignment: .trailing)
        }
        .onChange(of: pipeline.cropHorizontalOffset) { _, _ in
            pipeline.updateCropHorizontalOffset()
        }
    }

    private var smoothingToggleRow: some View {
        HStack {
            Text("Smooth").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.smoothingEnabled).labelsHidden()
            Spacer()
            Text(pipeline.smoothingEnabled ? "ON" : "OFF")
                .font(.caption2)
                .foregroundColor(pipeline.smoothingEnabled ? .green : .red)
        }
    }

    private var smoothingBaseAlphaRow: some View {
        labeledRow("Alpha") {
            Slider(value: $pipeline.smoothingBaseAlpha, in: 0.05...1.0, step: 0.05)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.smoothingBaseAlpha)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .disabled(!pipeline.smoothingEnabled)
    }

    private var smoothingDeviationRow: some View {
        Group {
            labeledRow("MinDev") {
                Slider(value: $pipeline.smoothingMinDeviation, in: 0.0...0.1, step: 0.005)
            } valueLabel: {
                Text(String(format: "%.3f", pipeline.smoothingMinDeviation)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
            }
            labeledRow("MaxDev") {
                Slider(value: $pipeline.smoothingMaxDeviation, in: 0.0...0.15, step: 0.005)
            } valueLabel: {
                Text(String(format: "%.3f", pipeline.smoothingMaxDeviation)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
            }
        }
        .disabled(!pipeline.smoothingEnabled)
    }

    private var smoothingCenterFloorRow: some View {
        labeledRow("CFloor") {
            Slider(value: $pipeline.smoothingCenterFloor, in: 0.0...1.0, step: 0.05)
        } valueLabel: {
            Text(String(format: "%.2f", pipeline.smoothingCenterFloor)).font(.caption).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
        }
        .disabled(!pipeline.smoothingEnabled)
    }

    private var rtmpUrlRow: some View {
        HStack {
            Text("URL").font(.caption).frame(width: 55, alignment: .leading)
            TextField("rtmp://...", text: $rtmpUrl)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(pipeline.streamManager.isStreaming)
        }
    }

    private var streamKeyRow: some View {
        HStack {
            Text("Key").font(.caption).frame(width: 55, alignment: .leading)
            SecureField("stream-key", text: $streamKey)
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(pipeline.streamManager.isStreaming)
        }
    }

    private var resolutionRow: some View {
        HStack {
            Text("Res").font(.caption).frame(width: 55, alignment: .leading)
            Picker("", selection: Binding(
                get: { pipeline.streamManager.streamResolution },
                set: { pipeline.streamManager.streamResolution = $0 }
            )) {
                ForEach(StreamResolution.allCases, id: \.self) { res in
                    Text(res.rawValue).tag(res)
                }
            }
            .pickerStyle(.segmented)
            .disabled(pipeline.streamManager.isStreaming)
            Spacer()
            if pipeline.streamManager.isStreaming {
                Text("断开后可切换")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
        }
    }

    private var bitrateRow: some View {
        labeledRow("Bitrate") {
            Slider(value: Binding(
                get: { Double(pipeline.streamManager.videoBitrate) },
                set: { pipeline.streamManager.videoBitrate = Int($0); Config.streamBitrate = Int($0) }
            ), in: 1000...10000, step: 500)
        } valueLabel: {
            Text("\(pipeline.streamManager.videoBitrate)kbps")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var audioSourceRow: some View {
        HStack(spacing: 4) {
            Text("音频源").font(.caption).frame(width: 55, alignment: .leading)
            Picker("", selection: Binding(
                get: { pipeline.audioDeviceManager.selectedSource },
                set: { pipeline.audioDeviceManager.switchToSource($0) }
            )) {
                ForEach(pipeline.audioDeviceManager.availableSources, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            if pipeline.audioDeviceManager.isExternalDeviceConnected {
                Image(systemName: "mic.fill")
                    .foregroundColor(.green)
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private var audioMixerSection: some View {
        if pipeline.audioDeviceManager.selectedSource == .externalStereo {
            labeledRow("机台") {
                Slider(value: Binding(
                    get: { pipeline.audioMixer.leftGain },
                    set: { pipeline.audioMixer.leftGain = $0 }
                ), in: 0...2, step: 0.05)
            } valueLabel: {
                Text(String(format: "%.0f%%", pipeline.audioMixer.leftGain * 100))
                    .font(.caption2).monospacedDigit().frame(width: 38)
            }

            labeledRow("领夹") {
                Slider(value: Binding(
                    get: { pipeline.audioMixer.rightGain },
                    set: { pipeline.audioMixer.rightGain = $0 }
                ), in: 0...2, step: 0.05)
            } valueLabel: {
                Text(String(format: "%.0f%%", pipeline.audioMixer.rightGain * 100))
                    .font(.caption2).monospacedDigit().frame(width: 38)
            }
        }
    }

    private var audioMeterRow: some View {
        HStack(spacing: 4) {
            Text("电平").font(.caption).frame(width: 55, alignment: .leading)

            if pipeline.audioDeviceManager.selectedSource == .externalStereo {
                VStack(alignment: .leading, spacing: 2) {
                    Text("L").font(.system(size: 8)).foregroundColor(.green)
                    LevelBar(level: pipeline.audioMixer.leftLevel, color: .green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("R").font(.system(size: 8)).foregroundColor(.blue)
                    LevelBar(level: pipeline.audioMixer.rightLevel, color: .blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mix").font(.system(size: 8)).foregroundColor(.orange)
                    LevelBar(level: pipeline.audioMixer.mixedLevel, color: .orange)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level").font(.system(size: 8)).foregroundColor(.green)
                    LevelBar(level: pipeline.audioMixer.mixedLevel, color: .green)
                }
            }
        }
    }

    private var streamButtonRow: some View {
        HStack {
            if pipeline.streamManager.isStreaming {
                Button {
                    pipeline.streamManager.stopPublish()
                } label: {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("停止推流")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .adaptiveGlassButton(prominent: true)
                .tint(.red)
                .controlSize(.small)
            } else {
                Button {
                    pipeline.streamManager.startPublish(url: rtmpUrl, streamKey: streamKey)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.circle")
                            .font(.caption)
                        Text("开始推流")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .adaptiveGlassButton(prominent: true)
                .tint(.green)
                .controlSize(.small)
                .disabled(rtmpUrl.isEmpty || streamKey.isEmpty)
            }

            Text(pipeline.streamManager.streamStatus)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(statusColor(pipeline.streamManager.streamStatus))
                .lineLimit(1)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Publishing": return .green
        case "Connecting", "Connected": return .yellow
        case "Idle": return .gray
        default: return .red
        }
    }

    // MARK: - Helpers

    private var bottomSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.safeAreaInsets.bottom ?? 0
    }

    private func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
        Swift.min(Swift.max(value, min), max)
    }

    private func labeledRow<C: View, V: View>(
        _ label: String,
        @ViewBuilder content: () -> C,
        @ViewBuilder valueLabel: () -> V
    ) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).frame(width: 55, alignment: .leading)
            content()
            valueLabel()
        }
    }
}

private struct ControlTabRail: View {
    @Binding var selection: ControlTab
    @State private var pressedIndex: Int?
    @State private var dragCenterX: CGFloat?

    private let tabs = Array(ControlTab.allCases)
    private let horizontalInset: CGFloat = 8
    private let railHeight: CGFloat = 78
    private let railBodyHeight: CGFloat = 66
    private let restingBubbleHeight: CGFloat = 62
    private let activeBubbleHeight: CGFloat = 76
    private let accent = Color(red: 1.0, green: 0.25, blue: 0.42)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segmentWidth = segmentWidth(for: width)
            let visualIndex = pressedIndex ?? selectedIndex
            let isPressing = pressedIndex != nil
            let bubbleWidth = bubbleWidth(for: segmentWidth, isPressing: isPressing)
            let bubbleHeight = bubbleHeight(isPressing: isPressing)
            let bubbleCenterX = dragCenterX ?? tabCenterX(for: visualIndex, width: width)
            let bubbleOffset = bubbleOffset(forCenter: bubbleCenterX, width: width, bubbleWidth: bubbleWidth)

            ZStack(alignment: .leading) {
                glassContainer {
                    ZStack(alignment: .leading) {
                        railBackground
                            .frame(height: railBodyHeight)
                            .padding(.vertical, (railHeight - railBodyHeight) / 2)

                        selectionBubble(isPressing: isPressing, height: bubbleHeight)
                            .frame(width: bubbleWidth, height: bubbleHeight)
                            .offset(x: bubbleOffset)
                            .scaleEffect(isPressing ? 1.06 : 1.0)
                            .animation(dragCenterX == nil ? .interactiveSpring(response: 0.28, dampingFraction: 0.78) : nil, value: visualIndex)
                            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.74), value: isPressing)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                        tabLabel(tab, isSelected: selectedIndex == index, isPressed: pressedIndex == index)
                            .frame(width: segmentWidth, height: railHeight)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            .contentShape(RoundedRectangle(cornerRadius: railBodyHeight / 2, style: .continuous))
            .gesture(tabDragGesture(width: width))
        }
        .frame(height: railHeight)
    }

    @ViewBuilder
    private func glassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                content()
            }
        } else {
            content()
        }
    }

    private var railBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: railBodyHeight / 2, style: .continuous)
                .fill(Color.black.opacity(0.28))
            RoundedRectangle(cornerRadius: railBodyHeight / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .adaptiveGlassPanel(cornerRadius: railBodyHeight / 2, tint: Color.black.opacity(0.26), interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: railBodyHeight / 2, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.42), radius: 14, x: 0, y: 8)
    }

    private func selectionBubble(isPressing: Bool, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isPressing ? 0.30 : 0.18),
                            Color.white.opacity(isPressing ? 0.10 : 0.04),
                            Color.black.opacity(0.18)
                        ],
                        center: .topLeading,
                        startRadius: 6,
                        endRadius: 112
                    )
                )

            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isPressing ? 0.18 : 0.10),
                            Color.clear,
                            Color.white.opacity(isPressing ? 0.08 : 0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .adaptiveGlassPanel(cornerRadius: height / 2, tint: Color.white.opacity(isPressing ? 0.08 : 0.03), interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(isPressing ? 0.22 : 0.10),
                            Color.white.opacity(isPressing ? 0.18 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isPressing ? 1.4 : 1
                )
        }
        .shadow(color: Color.black.opacity(0.46), radius: 16, x: 0, y: 8)
    }

    private var selectedIndex: Int {
        tabs.firstIndex(of: selection) ?? 0
    }

    private func tabLabel(_ tab: ControlTab, isSelected: Bool, isPressed: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: tab.icon)
                .font(.system(size: isSelected ? 25 : 23, weight: isSelected ? .bold : .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
        }
        .foregroundColor(isSelected ? accent : .white.opacity(0.88))
        .scaleEffect(isPressed ? 1.10 : (isSelected ? 1.03 : 1))
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }

    private func segmentWidth(for width: CGFloat) -> CGFloat {
        let innerWidth = max(width - horizontalInset * 2, 1)
        return innerWidth / CGFloat(max(tabs.count, 1))
    }

    private func bubbleWidth(for segmentWidth: CGFloat, isPressing: Bool) -> CGFloat {
        if isPressing {
            return max(segmentWidth + 56, 120)
        }
        return max(segmentWidth - 12, 64)
    }

    private func bubbleHeight(isPressing: Bool) -> CGFloat {
        isPressing ? activeBubbleHeight : restingBubbleHeight
    }

    private func tabCenterX(for index: Int, width: CGFloat) -> CGFloat {
        let segmentWidth = segmentWidth(for: width)
        return horizontalInset + segmentWidth * (CGFloat(index) + 0.5)
    }

    private func bubbleOffset(forCenter centerX: CGFloat, width: CGFloat, bubbleWidth: CGFloat) -> CGFloat {
        let minX: CGFloat = 0
        let maxX = max(width - bubbleWidth, 0)
        return min(max(centerX - bubbleWidth / 2, minX), maxX)
    }

    private func clampedBubbleCenter(_ centerX: CGFloat, width: CGFloat, bubbleWidth: CGFloat) -> CGFloat {
        let minCenter = bubbleWidth / 2
        let maxCenter = max(width - bubbleWidth / 2, minCenter)
        return min(max(centerX, minCenter), maxCenter)
    }

    private func tabIndex(at locationX: CGFloat, width: CGFloat) -> Int {
        let segmentWidth = segmentWidth(for: width)
        let clampedX = min(max(locationX - horizontalInset, 0), segmentWidth * CGFloat(tabs.count) - 0.01)
        return min(max(Int(clampedX / segmentWidth), 0), tabs.count - 1)
    }

    private func tabDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let activeBubbleWidth = bubbleWidth(for: segmentWidth(for: width), isPressing: true)
                dragCenterX = clampedBubbleCenter(value.location.x, width: width, bubbleWidth: activeBubbleWidth)

                let nextIndex = tabIndex(at: value.location.x, width: width)
                pressedIndex = nextIndex
                guard tabs[nextIndex] != selection else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.82)) {
                    selection = tabs[nextIndex]
                }
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    pressedIndex = nil
                    dragCenterX = nil
                }
            }
    }
}

// MARK: - Top-level change handlers

private extension View {
    func phase2ChangeHandlers(
        pipeline: LivePipelineManager,
        panelExpanded: Binding<Bool>,
        isAntiTouchMode: Binding<Bool>,
        antiTouchTimer: Binding<Timer?>
    ) -> some View {
        self
            .modifier(CameraChangeHandlers(pipeline: pipeline))
            .modifier(StabilizerChangeHandlers(pipeline: pipeline))
            .modifier(YoloPreviewChangeHandlers(pipeline: pipeline))
            .modifier(TrackingChangeHandlers(pipeline: pipeline))
            .modifier(OverlayChangeHandlers(pipeline: pipeline))
            .modifier(SessionChangeHandlers(
                pipeline: pipeline,
                panelExpanded: panelExpanded,
                isAntiTouchMode: isAntiTouchMode,
                antiTouchTimer: antiTouchTimer
            ))
    }
}

private struct CameraChangeHandlers: ViewModifier {
    @ObservedObject var pipeline: LivePipelineManager

    func body(content: Content) -> some View {
        content
            .onChange(of: pipeline.selectedLens) { _, newValue in
                pipeline.handleLensChange(newValue)
            }
            .onChange(of: pipeline.focusValue) { _, _ in
                pipeline.applyExposure()
            }
            .onChange(of: pipeline.autoFocusEnabled) { _, _ in
                Config.autoFocusEnabled = pipeline.autoFocusEnabled
                pipeline.camera.setAutoFocus(pipeline.autoFocusEnabled)
            }
            .onChange(of: pipeline.shutterTimescale) { _, _ in
                pipeline.applyExposure()
            }
            .onChange(of: pipeline.isoValue) { _, _ in
                pipeline.applyExposure()
            }
            .onChange(of: pipeline.syncOffsetMs) { _, newValue in
                Config.syncOffsetMs = newValue
            }
            .onChange(of: pipeline.readoutTimeMs) { _, newValue in
                Config.readoutTimeMs = newValue
                pipeline.updateReadoutTime()
            }
    }
}

private struct StabilizerChangeHandlers: ViewModifier {
    @ObservedObject var pipeline: LivePipelineManager

    func body(content: Content) -> some View {
        content
            .onChange(of: pipeline.stabEnabled) { _, _ in
                pipeline.updateStabilizerEnabled()
            }
            .onChange(of: pipeline.activityMode) { _, _ in
                pipeline.updateActivityMode()
            }
            .onChange(of: pipeline.activitySmoothFactor) { _, _ in
                pipeline.updateActivitySmoothFactor()
            }
            .onChange(of: pipeline.fov) { _, _ in
                pipeline.updateFov()
            }
            .onChange(of: pipeline.distRatio) { _, _ in
                pipeline.updateDistRatio()
            }
            .onChange(of: pipeline.yaw) { _, _ in
                pipeline.updateYaw()
            }
            .onChange(of: pipeline.pitch) { _, _ in
                pipeline.updatePitch()
            }
            .onChange(of: pipeline.roll) { _, _ in
                pipeline.updateRoll()
            }
    }
}

private struct YoloPreviewChangeHandlers: ViewModifier {
    @ObservedObject var pipeline: LivePipelineManager

    func body(content: Content) -> some View {
        content
            .onChange(of: pipeline.yoloPadding) { _, _ in
                pipeline.updateYoloPadding()
            }
            .onChange(of: pipeline.yoloEnabled) { _, newValue in
                Config.yoloEnabled = newValue
            }
            .onChange(of: pipeline.previewEnabled) { _, newValue in
                Config.previewEnabled = newValue
            }
    }
}

private struct TrackingChangeHandlers: ViewModifier {
    @ObservedObject var pipeline: LivePipelineManager

    func body(content: Content) -> some View {
        content
            .onChange(of: pipeline.trackTargetRatio) { _, _ in
                pipeline.updateTrackTargetRatio()
            }
            .onChange(of: pipeline.trackRecenterSpeed) { _, _ in
                pipeline.updateTrackRecenterSpeed()
            }
            .onChange(of: pipeline.recenterGraceMs) { _, _ in
                pipeline.updateRecenterGraceMs()
            }
            .onChange(of: pipeline.acquireSpeed) { _, _ in
                pipeline.updateAcquireSpeed()
            }
            .onChange(of: pipeline.smoothingEnabled) { _, _ in
                pipeline.updateSmoothingEnabled()
            }
            .onChange(of: pipeline.smoothingBaseAlpha) { _, _ in
                pipeline.updateSmoothingBaseAlpha()
            }
            .onChange(of: pipeline.smoothingMinDeviation) { _, _ in
                pipeline.updateSmoothingMinDeviation()
            }
            .onChange(of: pipeline.smoothingMaxDeviation) { _, _ in
                pipeline.updateSmoothingMaxDeviation()
            }
            .onChange(of: pipeline.smoothingCenterFloor) { _, _ in
                pipeline.updateSmoothingCenterFloor()
            }
    }
}

private struct OverlayChangeHandlers: ViewModifier {
    @ObservedObject var pipeline: LivePipelineManager

    func body(content: Content) -> some View {
        content
            .onChange(of: pipeline.overlayEnabled) { _, _ in
                pipeline.updateOverlayEnabled()
            }
            .onChange(of: pipeline.overlayPosX) { _, _ in
                pipeline.updateOverlayPosition()
            }
            .onChange(of: pipeline.overlayPosY) { _, _ in
                pipeline.updateOverlayPosition()
            }
            .onChange(of: pipeline.overlayScale) { _, _ in
                pipeline.updateOverlayScale()
            }
            .onChange(of: pipeline.overlayOpacity) { _, _ in
                pipeline.updateOverlayOpacity()
            }
            .onChange(of: pipeline.overlayRotation) { _, _ in
                pipeline.updateOverlayRotation()
            }
    }
}

private struct SessionChangeHandlers: ViewModifier {
    @ObservedObject var pipeline: LivePipelineManager
    @Binding var panelExpanded: Bool
    @Binding var isAntiTouchMode: Bool
    @Binding var antiTouchTimer: Timer?

    func body(content: Content) -> some View {
        content
            .onChange(of: pipeline.streamManager.isStreaming) { _, streaming in
                if streaming {
                    pipeline.debug.isDetailVisible = false
                }
            }
            .onChange(of: panelExpanded) { _, expanded in
                if expanded {
                    antiTouchTimer?.invalidate()
                    antiTouchTimer = nil
                    isAntiTouchMode = false
                } else {
                    antiTouchTimer?.invalidate()
                    antiTouchTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                        DispatchQueue.main.async {
                            isAntiTouchMode = true
                        }
                    }
                }
            }
    }
}

struct LevelBar: View {
    let level: Float
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, level))))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Camera preview (fallback)

private final class PreviewView2: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView2 {
        let v = PreviewView2()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        if let connection = v.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ uiView: PreviewView2, context: Context) {}
}

// MARK: - Corner radius helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let p = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(p.cgPath)
    }
}
