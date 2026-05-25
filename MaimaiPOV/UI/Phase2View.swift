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
        }
        .onChange(of: pipeline.selectedLens) { pipeline.handleLensChange($0) }
        .onChange(of: pipeline.focusValue) { _ in pipeline.applyExposure() }
        .onChange(of: pipeline.autoFocusEnabled) { _ in
            Config.autoFocusEnabled = pipeline.autoFocusEnabled
            pipeline.camera.setAutoFocus(pipeline.autoFocusEnabled)
        }
        .onChange(of: pipeline.shutterTimescale) { _ in pipeline.applyExposure() }
        .onChange(of: pipeline.isoValue) { _ in pipeline.applyExposure() }
        .onChange(of: pipeline.syncOffsetMs) { Config.syncOffsetMs = $0 }
        .onChange(of: pipeline.readoutTimeMs) {
            Config.readoutTimeMs = $0
            pipeline.updateReadoutTime()
        }
        .onChange(of: pipeline.stabEnabled) { _ in pipeline.updateStabilizerEnabled() }
        .onChange(of: pipeline.fov) { _ in pipeline.updateFov() }
        .onChange(of: pipeline.distRatio) { _ in pipeline.updateDistRatio() }
        .onChange(of: pipeline.yaw) { _ in pipeline.updateYaw() }
        .onChange(of: pipeline.pitch) { _ in pipeline.updatePitch() }
        .onChange(of: pipeline.roll) { _ in pipeline.updateRoll() }
        .onChange(of: pipeline.yoloPadding) { _ in pipeline.updateYoloPadding() }
        .onChange(of: pipeline.yoloEnabled) { newValue in
            Config.yoloEnabled = newValue
        }
        .onChange(of: pipeline.previewEnabled) { newValue in
            Config.previewEnabled = newValue
        }
        .onChange(of: pipeline.trackTargetRatio) { _ in pipeline.updateTrackTargetRatio() }
        .onChange(of: pipeline.trackRecenterSpeed) { _ in pipeline.updateTrackRecenterSpeed() }
        .onChange(of: pipeline.recenterGraceMs) { _ in pipeline.updateRecenterGraceMs() }
        .onChange(of: pipeline.acquireSpeed) { _ in pipeline.updateAcquireSpeed() }
        .onChange(of: pipeline.smoothingEnabled) { _ in pipeline.updateSmoothingEnabled() }
        .onChange(of: pipeline.smoothingBaseAlpha) { _ in pipeline.updateSmoothingBaseAlpha() }
        .onChange(of: pipeline.smoothingMinDeviation) { _ in pipeline.updateSmoothingMinDeviation() }
        .onChange(of: pipeline.smoothingMaxDeviation) { _ in pipeline.updateSmoothingMaxDeviation() }
        .onChange(of: pipeline.smoothingCenterFloor) { _ in pipeline.updateSmoothingCenterFloor() }
        .onChange(of: pipeline.overlayEnabled) { _ in pipeline.updateOverlayEnabled() }
        .onChange(of: pipeline.overlayPosX) { _ in pipeline.updateOverlayPosition() }
        .onChange(of: pipeline.overlayPosY) { _ in pipeline.updateOverlayPosition() }
        .onChange(of: pipeline.overlayScale) { _ in pipeline.updateOverlayScale() }
        .onChange(of: pipeline.overlayOpacity) { _ in pipeline.updateOverlayOpacity() }
        .onChange(of: pipeline.overlayRotation) { _ in pipeline.updateOverlayRotation() }
        .onChange(of: pipeline.songCardEnabled) { _ in pipeline.updateSongCardEnabled() }
        .onChange(of: pipeline.streamManager.isStreaming) { streaming in
            if streaming {
                pipeline.debug.isDetailVisible = false
            }
        }
        .onDisappear {
            pipeline.stop()
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if pipeline.stabEnabled, pipeline.camera.cameraAuthorized {
                    if let texture = pipeline.previewTexture {
                        MetalView(device: pipeline.device, texture: texture, previewEnabled: pipeline.previewEnabled)
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

            DebugOverlayView(debug: pipeline.debug)
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
                .background(Color.gray.opacity(0.2))
            }

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

                HStack {
                    ForEach(ControlTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: tab.icon)
                                Text(tab.rawValue)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(selectedTab == tab ? .white : .gray)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, bottomSafeArea)
                .background(Color.black.opacity(0.3))
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(10, corners: [.topLeft, .topRight])
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
            songCardToggleRow
            if pipeline.songCardEnabled {
                songCardSlotTuningSection
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
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
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

            rtmpUrlRow
            streamKeyRow
            resolutionRow
            bitrateRow
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
                    .buttonStyle(.borderedProminent)
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
                    .buttonStyle(.borderedProminent)
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

                HStack {
                    Text("点歌权限").font(.caption).frame(width: 55, alignment: .leading)
                    Text("\(pipeline.giftPermissionManager.activePermissionCount) 人")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Spacer()
                }

                HStack {
                    Text("测试模式").font(.caption).frame(width: 55, alignment: .leading)
                    Toggle("", isOn: $pipeline.songRequestTestMode)
                        .labelsHidden()
                        .scaleEffect(0.7)
                    Spacer()
                }

                if pipeline.songRequestTestMode {
                    HStack {
                        Text("插队测试").font(.caption).frame(width: 55, alignment: .leading)
                        Toggle("", isOn: $pipeline.songRequestTestPriorityMode)
                            .labelsHidden()
                            .scaleEffect(0.7)
                        Spacer()
                    }
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

    private var blivechatStateText: String {
        switch pipeline.blivechatConnectionState {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .error(let msg): return "错误: \(msg)"
        }
    }

    private var blivechatStateColor: Color {
        switch pipeline.blivechatConnectionState {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
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
        .onChange(of: pipeline.camera.isRunning) { running in
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
        HStack {
            Text("Stabilizer").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.stabEnabled).labelsHidden()
            Spacer()
            Text("Preview").font(.caption2).foregroundColor(.gray)
            Toggle("", isOn: Binding(
                get: { pipeline.previewEnabled },
                set: { newValue in
                    previewOverride = true
                    pipeline.previewEnabled = newValue
                }
            )).labelsHidden()
            Spacer()
            Text("Lag: \(String(format: "%.1f", pipeline.lagMs))ms")
                .font(.caption2).foregroundColor(.gray)
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
                .onChange(of: pipeline.yoloOverlayEnabled) { _ in
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
            Text("Overlay").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.overlayEnabled).labelsHidden()
            Spacer()
            PhotosPicker(selection: $selectedPhotoItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundColor(pipeline.overlayEnabled ? .cyan : .gray)
            }
            .disabled(!pipeline.overlayEnabled)
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem = newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pipeline.loadOverlayImage(image)
                    }
                }
            }
            Spacer()
            Text(pipeline.overlayEnabled ? "ON" : "OFF")
                .font(.caption2)
                .foregroundColor(pipeline.overlayEnabled ? .green : .red)
        }
    }

    private var songCardToggleRow: some View {
        HStack {
            Text("SongCard").font(.caption).frame(width: 55, alignment: .leading)
            Toggle("", isOn: $pipeline.songCardEnabled).labelsHidden()
            Spacer()
            if pipeline.songCardEnabled {
                Button {
                    pipeline.addSongToQueue(SongCardData(
                        songName: "Song \(pipeline.songCardManager.queue.count + 1)",
                        artist: "Artist",
                        difficulty: ["BASIC", "ADVANCED", "EXPERT", "MASTER"][pipeline.songCardManager.queue.count % 4],
                        level: "\(7 + pipeline.songCardManager.queue.count)",
                        requester: "User\(pipeline.songCardManager.queue.count + 1)"
                    ))
                } label: {
                    Image(systemName: "plus").font(.caption2).foregroundColor(.green)
                }
                Button {
                    pipeline.triggerSongCardSwitch()
                } label: {
                    Image(systemName: "forward.fill").font(.caption2).foregroundColor(.yellow)
                }
            }
            Text(pipeline.songCardEnabled ? "ON" : "OFF")
                .font(.caption2)
                .foregroundColor(pipeline.songCardEnabled ? .green : .red)
        }
    }

    private var songCardSlotTuningSection: some View {
        VStack(spacing: 4) {
            slotTuningRow(label: "S0X", value: $pipeline.slot0PosX, range: 0.0...1.0, step: 0.01)
            slotTuningRow(label: "S0Y", value: $pipeline.slot0PosY, range: 0.0...0.5, step: 0.005)
            slotTuningRow(label: "S0S", value: $pipeline.slot0Scale, range: 0.05...1.0, step: 0.01)
            slotTuningRow(label: "S1X", value: $pipeline.slot1PosX, range: 0.0...1.0, step: 0.01)
            slotTuningRow(label: "S1Y", value: $pipeline.slot1PosY, range: 0.0...0.5, step: 0.005)
            slotTuningRow(label: "S1S", value: $pipeline.slot1Scale, range: 0.05...1.0, step: 0.01)
            slotTuningRow(label: "S2X", value: $pipeline.slot2PosX, range: 0.0...1.0, step: 0.01)
            slotTuningRow(label: "S2Y", value: $pipeline.slot2PosY, range: 0.0...0.5, step: 0.005)
            slotTuningRow(label: "S2S", value: $pipeline.slot2Scale, range: 0.05...1.0, step: 0.01)
        }
        .onChange(of: pipeline.slot0PosX) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot0PosY) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot0Scale) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot1PosX) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot1PosY) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot1Scale) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot2PosX) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot2PosY) { _ in pipeline.updateSongCardSlots() }
        .onChange(of: pipeline.slot2Scale) { _ in pipeline.updateSongCardSlots() }
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
        .onChange(of: pipeline.cropHorizontalOffset) { _ in
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
                .buttonStyle(.borderedProminent)
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
                .buttonStyle(.borderedProminent)
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
        v.previewLayer.connection?.videoOrientation = .portrait
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
