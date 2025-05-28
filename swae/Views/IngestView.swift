//
//  IngestView.swift
//  swae
//
//  Created by Suhail Saqan on 1/30/25.
//

import AVFoundation
import Photos
import SwiftUI
import VideoToolbox

struct IngestView: View {
    @StateObject private var viewModel = IngestViewModel()
    @State private var zoomFactor: CGFloat = 1.0
    @State private var isControlsVisible = true

    var body: some View {
        ZStack {
            VideoPreviewView(mixer: viewModel.mixer, zoomFactor: $zoomFactor) { zoom in
                viewModel.updateZoom(zoom)
            }
            .clipped()
            .onTapGesture(count: 2) {
                viewModel.rotateCamera()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isControlsVisible.toggle()
                }
            }

            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .opacity(isControlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.1), value: isControlsVisible)

            VStack {
                TopControlBar(viewModel: viewModel)
                    .padding(.top, ((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.top ?? 0) + 10)
                    .opacity(isControlsVisible ? 1 : 0)
                    .offset(y: isControlsVisible ? 0 : -100)
                
                Spacer()
                
                BottomControlBar(viewModel: viewModel, zoomFactor: $zoomFactor)
                    .padding(.bottom, ((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom ?? 0) + 10)
                    .opacity(isControlsVisible ? 1 : 0)
                    .offset(y: isControlsVisible ? 0 : 100)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isControlsVisible)

            ZoomIndicatorView(zoomFactor: zoomFactor)
                .opacity(zoomFactor > 1.1 ? 1 : 0)
                .animation(.easeInOut, value: zoomFactor)
            
            if viewModel.isPublishing {
                RecordingIndicatorView()
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .onAppear {
            notify(.display_tabbar(false))
            viewModel.setup()
        }
        .onDisappear {
            notify(.display_tabbar(true))
            viewModel.cleanup()
        }
        .statusBarHidden()
    }
}

struct TopControlBar: View {
    @ObservedObject var viewModel: IngestViewModel
    @SceneStorage("ContentView.selected_tab") var selected_tab: ScreenTabs = .home
    @State private var showSettings = false
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                GlassButton(systemName: "xmark") {
                    selected_tab = .home
                    notify(.display_tabbar(true))
                }
                
                GlassButton(systemName: "gearshape.fill") {
                    showSettings = true
                }
                
                GlassButton(systemName: "wand.and.stars") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            
            Spacer()
            
            if viewModel.isPublishing {
                LiveIndicatorView(duration: viewModel.streamDuration)
            } else {
                StreamStatusView(isConnected: viewModel.isConnected)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                GlassButton(systemName: "camera.rotate.fill") {
                    viewModel.rotateCamera()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                
                GlassButton(
                    systemName: "bolt.fill",
                    isActive: viewModel.isTorchEnabled,
                    activeColor: .yellow
                ) {
                    viewModel.toggleTorch()
                }
                
                GlassButton(systemName: "mic.slash.fill") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showSettings) {
            StreamSettingsView(viewModel: viewModel)
        }
    }
}

struct BottomControlBar: View {
    @ObservedObject var viewModel: IngestViewModel
    @Binding var zoomFactor: CGFloat
    @State private var showZoomWheel = false
    
    var body: some View {
        VStack(spacing: 20) {
            if !viewModel.isPublishing {
                HStack(spacing: 30) {
                    CircularButton(
                        systemName: "plus.magnifyingglass",
                        isActive: showZoomWheel
                    ) {
                        withAnimation(.spring()) {
                            showZoomWheel.toggle()
                        }
                    }
                    
                    QualityIndicatorButton(bitrate: viewModel.videoBitrate)
                    
                    CircularButton(systemName: "grid") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    
                    CircularButton(systemName: "timer") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                .opacity(showZoomWheel ? 0.3 : 1)
                .animation(.easeInOut, value: showZoomWheel)
            }
            
            if showZoomWheel {
                ZoomWheelView(zoomFactor: $zoomFactor) { zoom in
                    viewModel.updateZoom(zoom)
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            MainRecordButton(viewModel: viewModel)
        }
        .padding(.horizontal, 20)
    }
}

struct ZoomWheelView: View {
    @Binding var zoomFactor: CGFloat
    let onZoomChange: (CGFloat) -> Void
    
    private let zoomLevels: [CGFloat] = [1.0, 1.5, 2.0, 3.0, 5.0]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("\(zoomFactor, specifier: "%.1f")×")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            
            HStack(spacing: 8) {
                ForEach(zoomLevels, id: \.self) { level in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            zoomFactor = level
                            onZoomChange(level)
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text("\(level, specifier: level == 1.0 ? "%.0f" : "%.1f")×")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(abs(zoomFactor - level) < 0.1 ? .black : .white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(abs(zoomFactor - level) < 0.1 ? .white : .clear)
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct MainRecordButton: View {
    @ObservedObject var viewModel: IngestViewModel
    @State private var isPressed = false
    @State private var pulseAnimation = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                viewModel.togglePublish()
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .stroke(viewModel.isPublishing ? .red : .white, lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .opacity(pulseAnimation ? 0.3 : 0.8)
                
                Circle()
                    .fill(viewModel.isPublishing ? .red : .clear)
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isPressed ? 0.95 : 1)
                
                Group {
                    if viewModel.isPublishing {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 24, height: 24)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.isPublishing)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever()) {
                    pulseAnimation = true
                }
            }
        }
        .buttonStyle(PressedButtonStyle(isPressed: $isPressed))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isPublishing)
    }
}

struct GlassButton: View {
    let systemName: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    init(systemName: String, isActive: Bool = false, activeColor: Color = .white, action: @escaping () -> Void) {
        self.systemName = systemName
        self.isActive = isActive
        self.activeColor = activeColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isActive ? activeColor : .white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct CircularButton: View {
    let systemName: String
    let isActive: Bool
    let action: () -> Void
    
    init(systemName: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.isActive = isActive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? .white.opacity(0.2) : .black.opacity(0.3))
                    .stroke(.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 50, height: 50)
                
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct QualityIndicatorButton: View {
    let bitrate: Int
    
    var qualityText: String {
        switch bitrate {
        case 0..<1000: return "SD"
        case 1000..<3000: return "HD"
        case 3000..<6000: return "FHD"
        default: return "4K"
        }
    }
    
    var qualityColor: Color {
        switch bitrate {
        case 0..<1000: return .orange
        case 1000..<3000: return .blue
        case 3000..<6000: return .green
        default: return .purple
        }
    }
    
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 2) {
                Text(qualityText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(qualityColor)
                
                Text("\(bitrate)k")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 50, height: 50)
            .background(.black.opacity(0.3))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(qualityColor.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct LiveIndicatorView: View {
    let duration: TimeInterval
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(), value: pulse)
                .onAppear { pulse = true }
            
            Text("LIVE")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text(formatDuration(duration))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct StreamStatusView: View {
    let isConnected: Bool
    @State private var ringPulse: CGFloat = 1.0
    @State private var rotation: Double = 0.0
    
    var body: some View {
        ZStack {
            // Outer glowing ring for "Connecting..." state
            Circle()
                .stroke(
                    isConnected ? Color.clear : Color.orange.opacity(0.5),
                    lineWidth: 3
                )
                .frame(width: 38, height: 38)
                .scaleEffect(ringPulse)
                .opacity(isConnected ? 0 : 0.6)
                .animation(
                    isConnected ? .none : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: ringPulse
                )
            
            // Main badge
            Circle()
                .fill(.ultraThinMaterial.opacity(0.7))
                .frame(width: 28, height: 28)
                .overlay(
                    Group {
                        if isConnected {
                            Circle()
                                .fill(.green)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.orange)
                                .rotationEffect(.degrees(rotation))
                                .animation(
                                    .linear(duration: 2.0).repeatForever(autoreverses: false),
                                    value: rotation
                                )
                        }
                    }
                )
        }
        .onAppear {
            ringPulse = 1.2
            rotation = 360
        }
    }
}

struct ZoomIndicatorView: View {
    let zoomFactor: CGFloat
    
    var body: some View {
        VStack {
            Text("\(zoomFactor, specifier: "%.1f")×")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
            
            Spacer()
        }
        .padding(.top, 100)
    }
}

struct RecordingIndicatorView: View {
    @State private var blink = false
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                        .opacity(blink ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: blink)
                    
                    Text("REC")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.7), in: Capsule())
                .padding(.trailing, 20)
                .padding(.top, 60)
            }
            
            Spacer()
        }
        .onAppear { blink = true }
    }
}

struct StreamSettingsView: View {
    @ObservedObject var viewModel: IngestViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isStreamKeyVisible = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        
                        TextField("Stream URI", text: $viewModel.streamURI)
                    }
                    
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        
                        Group {
                            if isStreamKeyVisible {
                                TextField("Stream key", text: Binding(
                                    get: { viewModel.streamName ?? "" },
                                    set: { viewModel.streamName = $0 }
                                ))
                            } else {
                                SecureField("Stream key", text: Binding(
                                    get: { viewModel.streamName ?? "" },
                                    set: { viewModel.streamName = $0.isEmpty ? nil : $0 }
                                ))
                            }
                        }
                        
                        Button(action: { isStreamKeyVisible.toggle() }) {
                            Image(systemName: isStreamKeyVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Stream Configuration")
                }
                
                Section {
                    let presets = [
                        ("Low (720p)", 1500),
                        ("Medium (1080p)", 3000),
                        ("High (1080p)", 6000),
                        ("Ultra (4K)", 8000)
                    ]
                    ForEach(presets, id: \.0) { title, bitrate in
                        QualityPresetRow(
                            title: title,
                            bitrate: bitrate,
                            isSelected: viewModel.videoBitrate == bitrate,
                            onSelect: {
                                viewModel.updateVideoBitrate(bitrate: bitrate)
                            }
                        )
                    }
                } header: {
                    Text("Quality Presets")
                }
                
                Section {
                    let fpsOptions = [
                        ("15 FPS", 0),
                        ("30 FPS", 1),
                        ("60 FPS", 2)
                    ]
                    ForEach(fpsOptions, id: \.0) { title, index in
                        FPSPresetRow(
                            title: title,
                            index: index,
                            isSelected: viewModel.selectedFPS == index,
                            onSelect: {
                                viewModel.selectedFPS = index
                            }
                        )
                    }
                } header: {
                    Text("Frame Rate")
                }
            }
//            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.configureMixer()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct QualityPresetRow: View {
    let title: String
    let bitrate: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                
                Text("\(bitrate) kbps")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

struct FPSPresetRow: View {
    let title: String
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

struct VideoPreviewView: UIViewRepresentable {
    let mixer: MediaMixer
    @Binding var zoomFactor: CGFloat
    let onZoomChange: (CGFloat) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        let videoView = MTHKView(frame: .zero)
        videoView.videoGravity = .resizeAspectFill
        
        containerView.addSubview(videoView)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: containerView.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        containerView.addGestureRecognizer(pinchGesture)
        
        Task {
            await mixer.addOutput(videoView)
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.zoomFactor = zoomFactor
        context.coordinator.onZoomChange = onZoomChange
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(zoomFactor: zoomFactor, onZoomChange: onZoomChange)
    }
    
    class Coordinator: NSObject {
        var zoomFactor: CGFloat
        var onZoomChange: (CGFloat) -> Void
        private var initialZoom: CGFloat = 1.0
        
        init(zoomFactor: CGFloat, onZoomChange: @escaping (CGFloat) -> Void) {
            self.zoomFactor = zoomFactor
            self.onZoomChange = onZoomChange
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialZoom = zoomFactor
            case .changed:
                let newZoom = max(1.0, min(5.0, initialZoom * gesture.scale))
                if abs(newZoom - zoomFactor) > 0.05 {
                    zoomFactor = newZoom
                    onZoomChange(newZoom)
                }
            default:
                break
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PressedButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

@MainActor
final class IngestViewModel: ObservableObject {
    @Published var isPublishing: Bool = false
    @Published var audioDevices: [String] = []
    @Published var isTorchEnabled: Bool = false
    @Published var streamURI: String = "rtmp://in.zap.stream/live"
    @Published var streamName: String? = "live"
    @Published var isConnected: Bool = false
    @Published var streamDuration: TimeInterval = 0
    @Published var videoBitrate: Int = VideoCodecSettings.default.bitRate / 1000
    @Published var selectedFPS: Int = 1 {
        didSet {
            updateFPS()
        }
    }
    
    private var streamTimer: Timer?
    let mixer = MediaMixer(
        multiCamSessionEnabled: true,
        multiTrackAudioMixingEnabled: false,
        useManualCapture: true
    )
    private let netStreamSwitcher = HKStreamSwitcher()
    private var currentPosition: AVCaptureDevice.Position = .back

    func setup() {
        Task {
            await configureMixer()
            await attachDevices()
            setupNotifications()
            isConnected = true
        }
    }

    func configureMixer() async {
        if let orientation = DeviceUtil.videoOrientation(
            by: UIApplication.shared.statusBarOrientation)
        {
            await mixer.setVideoOrientation(orientation)
        }
        await mixer.setMonitoringEnabled(DeviceUtil.isHeadphoneConnected())
        var videoMixerSettings = await mixer.videoMixerSettings
        videoMixerSettings.mode = .offscreen
        await mixer.setVideoMixerSettings(videoMixerSettings)
        
        if !streamURI.isEmpty && streamName != nil {
            await netStreamSwitcher.setPreference(Preference(uri: streamURI, streamName: streamName))
        } else {
            await netStreamSwitcher.setPreference(Preference.default)
        }
        if let stream = await netStreamSwitcher.stream {
            await mixer.addOutput(stream)
        }
    }

    private func attachDevices() async {
        let back = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: currentPosition)
        let front = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front)

        try? await mixer.attachVideo(back, track: 0)
        try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
        try? await mixer.attachVideo(front, track: 1) { videoUnit in
            videoUnit.isVideoMirrored = true
        }
        await mixer.startRunning()
    }

    func cleanup() {
        streamTimer?.invalidate()
        Task {
            await netStreamSwitcher.close()
            await mixer.stopRunning()
            try? await mixer.attachAudio(nil)
            try? await mixer.attachVideo(nil, track: 0)
            try? await mixer.attachVideo(nil, track: 1)
        }
    }

    func togglePublish() {
        Task {
            if isPublishing {
                UIApplication.shared.isIdleTimerDisabled = false
                await netStreamSwitcher.close()
                stopStreamTimer()
            } else {
                UIApplication.shared.isIdleTimerDisabled = true
                await netStreamSwitcher.open(.ingest)
                startStreamTimer()
            }
            isPublishing.toggle()
        }
    }
    
    private func startStreamTimer() {
        streamDuration = 0
        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.streamDuration += 1
        }
    }
    
    private func stopStreamTimer() {
        streamTimer?.invalidate()
        streamTimer = nil
        streamDuration = 0
    }

    func rotateCamera() {
        Task {
            if await mixer.isMultiCamSessionEnabled {
                var videoMixerSettings = await mixer.videoMixerSettings
                videoMixerSettings.mainTrack = videoMixerSettings.mainTrack == 0 ? 1 : 0
                await mixer.setVideoMixerSettings(videoMixerSettings)
            } else {
                let position: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
                try? await mixer.attachVideo(
                    AVCaptureDevice.default(
                        .builtInWideAngleCamera, for: .video, position: position)
                ) { videoUnit in
                    videoUnit.isVideoMirrored = position == .front
                }
                currentPosition = position
            }
        }
    }

    func updateVideoBitrate(bitrate: Int) {
        Task {
            guard let stream = await netStreamSwitcher.stream else { return }
            var videoSettings = await stream.videoSettings
            videoSettings.bitRate = bitrate * 1000
            await stream.setVideoSettings(videoSettings)
            self.videoBitrate = bitrate
        }
    }

    func toggleTorch() {
        Task {
            let newState = !(await mixer.isTorchEnabled)
            await mixer.setTorchEnabled(newState)
            isTorchEnabled = newState
        }
    }

    func updateZoom(_ zoomFactor: CGFloat) {
        Task {
            try await mixer.configuration(video: 0) { unit in
                guard let device = unit.device else { return }
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: zoomFactor, withRate: 5.0)
                device.unlockForConfiguration()
            }
        }
    }

    func updateFPS() {
        Task {
            switch selectedFPS {
            case 0: await mixer.setFrameRate(15)
            case 1: await mixer.setFrameRate(30)
            case 2: await mixer.setFrameRate(60)
            default: break
            }
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.handleOrientationChange()
        }
    }

    private func handleOrientationChange() {
        guard let orientation = DeviceUtil.videoOrientation(
            by: UIApplication.shared.statusBarOrientation)
        else { return }
        Task {
            await mixer.setVideoOrientation(orientation)
        }
    }
}
