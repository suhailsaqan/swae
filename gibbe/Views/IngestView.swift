//
//  IngestView.swift
//  gibbe
//
//  Created by Suhail Saqan on 1/30/25.
//

import AVFoundation
import Photos
import SwiftUI
import VideoToolbox

struct IngestView: View {
    @StateObject private var viewModel = IngestViewModel()
    @State private var videoBitrate: Float = Float(VideoCodecSettings.default.bitRate) / 1000
    @State private var audioBitrate: Float = Float(AudioCodecSettings.default.bitRate) / 1000
    @State private var zoomFactor: Float = 1.0
    @State private var selectedEffect = 0
    @State private var selectedFPS = 1
    @State private var selectedAudioMode = 0
    @State private var selectedAudioDevice = 0
    @State private var showControls = true

    var body: some View {
        ZStack(alignment: .bottom) {
            VideoPreviewView(mixer: viewModel.mixer)
                .edgesIgnoringSafeArea(.all)

            if showControls {
                ControlPanelView(
                    viewModel: viewModel,
                    videoBitrate: $videoBitrate,
                    audioBitrate: $audioBitrate,
                    zoomFactor: $zoomFactor,
                    selectedEffect: $selectedEffect,
                    selectedFPS: $selectedFPS,
                    selectedAudioMode: $selectedAudioMode,
                    selectedAudioDevice: $selectedAudioDevice
                )
            }
        }
        .onAppear {
            viewModel.setup()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

struct ControlPanelView: View {
    @ObservedObject var viewModel: IngestViewModel
    @Binding var videoBitrate: Float
    @Binding var audioBitrate: Float
    @Binding var zoomFactor: Float
    @Binding var selectedEffect: Int
    @Binding var selectedFPS: Int
    @Binding var selectedAudioMode: Int
    @Binding var selectedAudioDevice: Int
    @State private var showOptions = false
    @State private var sheetPresented = false

    var fpsList = ["15", "30", "60"]

    var body: some View {
        VStack {
            HStack {
                if !viewModel.isPublishing {
                    Button(action: {
                        withAnimation(.spring()) {
                            showOptions.toggle()
                            sheetPresented = showOptions
                        }
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 28))
                    }

                    Spacer()

                    HStack {
                        Button(action: viewModel.rotateCamera) {
                            Image(systemName: "camera.rotate.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24))
                        }

                        Button(action: viewModel.toggleTorch) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(viewModel.isTorchEnabled ? .yellow : .gray)
                                .font(.system(size: 24))
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Spacer()

            LiveButton(viewModel: viewModel)
        }
        .padding()
        .onChange(of: selectedFPS) { _ in
            viewModel.updateFPS()
        }
        .sheet(isPresented: $sheetPresented) {
            VStack {
                Text("Stream Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 8)

                // Video Bitrate Control
                VStack(alignment: .leading, spacing: 12) {
                    Text("Video Bitrate")
                        .foregroundColor(.gray)
                        .font(.caption)
                    HStack {
                        Text("\(Int(videoBitrate)) kbps")
                            .foregroundColor(.white)
                        Slider(value: $videoBitrate, in: 100...8000, step: 100)
                    }

                    Text("Zoom")
                        .foregroundColor(.gray)
                        .font(.caption)
                    HStack {
                        Text("\(zoomFactor, specifier: "%.1f")x")
                            .foregroundColor(.white)
                        Slider(value: $zoomFactor, in: 1...5)
                    }

//                    Picker("FPS", selection: $selectedFPS) {
//                        ForEach(fpsList, id: \.self) {
//                            Text($0)
//                        }
//                    }
//                    .pickerStyle(SegmentedPickerStyle())
//                    .onChange(of: selectedFPS) { _ in
//                        viewModel.updateFPS()
//                    }
                }
                .padding(.horizontal)
            }
            .presentationDetents([.medium, .large])  // Customize the sheet size here
            .presentationDragIndicator(.visible)  // Make drag indicator visible
        }
    }
}

struct LiveButton: View {
    @ObservedObject var viewModel: IngestViewModel

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.2)) {
                viewModel.togglePublish()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.isPublishing ? .red : .black)
                    .frame(
                        width: viewModel.isPublishing ? 85 : 65,
                        height: viewModel.isPublishing ? 85 : 65, alignment: .center)

                Circle()
                    .stroke(viewModel.isPublishing ? .red : .white, lineWidth: 4)
                    .frame(
                        width: viewModel.isPublishing ? 95 : 75,
                        height: viewModel.isPublishing ? 95 : 75, alignment: .center)
            }
            .frame(alignment: .center)
        }
        .buttonStyle(.plain)
    }
}

struct VideoPreviewView: UIViewRepresentable {
    let mixer: MediaMixer

    func makeUIView(context: Context) -> some UIView {
        let view = MTHKView(frame: UIScreen.main.bounds)
        view.videoGravity = .resizeAspectFill
        Task {
            await mixer.addOutput(view)
        }
        return view
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {}
}

@MainActor
final class IngestViewModel: ObservableObject {
    @Published var isPublishing: Bool = false
    @Published var audioDevices: [String] = []
    @Published var isTorchEnabled: Bool = false

    let mixer = MediaMixer(
        multiCamSessionEnabled: true,
        multiTrackAudioMixingEnabled: false,
        useManualCapture: true
    )

    private let netStreamSwitcher = HKStreamSwitcher()
    private var currentPosition: AVCaptureDevice.Position = .back

    func setup() {
        Task {
            // Initial setup similar to viewDidLoad/viewWillAppear
            await configureMixer()
            await attachDevices()
            setupNotifications()
        }
    }

    @Published var selectedFPS = 1 {
        didSet {
            updateFPS()
        }
    }

    private func configureMixer() async {
        if let orientation = DeviceUtil.videoOrientation(
            by: UIApplication.shared.statusBarOrientation)
        {
            await mixer.setVideoOrientation(orientation)
        }

        await mixer.setMonitoringEnabled(DeviceUtil.isHeadphoneConnected())
        var videoMixerSettings = await mixer.videoMixerSettings
        videoMixerSettings.mode = .offscreen
        await mixer.setVideoMixerSettings(videoMixerSettings)

        await netStreamSwitcher.setPreference(Preference.default)
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
            } else {
                UIApplication.shared.isIdleTimerDisabled = true
                await netStreamSwitcher.open(.ingest)
            }
            isPublishing.toggle()
        }
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
            videoSettings.bitRate = bitrate
            await stream.setVideoSettings(videoSettings)
        }
    }

    func toggleTorch() {
        Task {
            isTorchEnabled = await mixer.isTorchEnabled
            await mixer.setTorchEnabled(!isTorchEnabled)
        }
    }

    func pauseStream() {
        Task {
            if let stream = await netStreamSwitcher.stream as? RTMPStream {
                _ = try? await stream.pause(true)
            }
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
            case 0:
                await mixer.setFrameRate(15)
            case 1:
                await mixer.setFrameRate(30)
            case 2:
                await mixer.setFrameRate(60)
            default:
                break
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
        guard
            let orientation = DeviceUtil.videoOrientation(
                by: UIApplication.shared.statusBarOrientation)
        else { return }
        Task {
            await mixer.setVideoOrientation(orientation)
        }
    }
}
