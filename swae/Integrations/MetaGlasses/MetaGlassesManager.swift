import AVFoundation
import Combine
import MWDATCamera
import MWDATCore
import UIKit

@MainActor
final class MetaGlassesManager: ObservableObject {
    @Published var isRegistered = false
    @Published var isRegistering = false
    @Published var devices: [DeviceIdentifier] = []
    @Published var hasActiveDevice = false
    @Published var isStreaming = false
    @Published var streamingStatus: String = "Stopped"
    @Published var previewFrame: UIImage?
    @Published var error: String?
    @Published var frameCount: UInt64 = 0
    @Published var capturedPhoto: UIImage?
    @Published var showPhotoPreview = false

    /// Callback for feeding raw CMSampleBuffers into Swae's video pipeline.
    var onVideoFrame: ((CMSampleBuffer) -> Void)?

    /// Callback when stream stops unexpectedly (disconnect, error, hinges closed).
    var onStreamStopped: (() -> Void)?

    /// Stable camera ID used by the buffered video system.
    let cameraId = UUID()

    private let deviceSelector: AutoDeviceSelector
    private var streamSession: StreamSession?
    private var stateToken: AnyListenerToken?
    private var videoToken: AnyListenerToken?
    private var errorToken: AnyListenerToken?
    private var photoToken: AnyListenerToken?
    private var registrationTask: Task<Void, Never>?
    private var deviceTask: Task<Void, Never>?
    private var activeDeviceTask: Task<Void, Never>?
    private var autoReconnectTask: Task<Void, Never>?
    private var lastResolution: StreamingResolution = .high
    private var wasStreamingBeforeBackground = false

    init() {
        deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        let currentState = Wearables.shared.registrationState
        isRegistered = currentState == .registered
        isRegistering = currentState == .registering
        startMonitoring()
    }

    private func startMonitoring() {
        registrationTask = Task {
            for await state in Wearables.shared.registrationStateStream() {
                self.isRegistered = state == .registered
                self.isRegistering = state == .registering
            }
        }
        deviceTask = Task {
            for await devices in Wearables.shared.devicesStream() {
                self.devices = devices
            }
        }
        activeDeviceTask = Task {
            for await device in deviceSelector.activeDeviceStream() {
                let hadDevice = self.hasActiveDevice
                self.hasActiveDevice = device != nil
                // Auto-reconnect: device came back while we were waiting
                if device != nil, !hadDevice, self.streamingStatus == "Waiting for reconnect..." {
                    self.scheduleAutoReconnect()
                }
            }
        }
    }

    // MARK: - Registration

    func connect() async {
        error = nil
        do {
            try await Wearables.shared.startRegistration()
        } catch let regError as RegistrationError {
            self.error = "Connection failed: \(regError.description)"
        } catch {
            self.error = "Connection failed: \(error.localizedDescription)"
        }
    }

    func disconnect() async {
        do {
            try await Wearables.shared.startUnregistration()
        } catch {
            self.error = "Disconnect failed: \(error.localizedDescription)"
        }
    }

    func handleUrl(_ url: URL) async {
        do {
            _ = try await Wearables.shared.handleUrl(url)
        } catch {
            self.error = "Registration callback failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Streaming

    func startStream(resolution: StreamingResolution = .high) async {
        error = nil
        lastResolution = resolution
        frameCount = 0
        streamingStatus = "Checking permissions..."

        // Permission flow matching official CameraAccess sample exactly
        let permission = Permission.camera
        do {
            let status = try await Wearables.shared.checkPermissionStatus(permission)
            if status == .granted {
                await beginStreamSession(resolution: resolution)
                return
            }
            streamingStatus = "Requesting permission..."
            let requestStatus = try await Wearables.shared.requestPermission(permission)
            if requestStatus == .granted {
                await beginStreamSession(resolution: resolution)
                return
            }
            error = "Camera permission denied. Grant permission in the Meta AI app."
            streamingStatus = "Permission denied"
        } catch let permError as PermissionError {
            self.error = "Permission error: \(permError.description)"
            streamingStatus = "Permission error"
        } catch {
            self.error = "Permission error: \(error.localizedDescription)"
            streamingStatus = "Permission error"
        }
    }

    private func beginStreamSession(resolution: StreamingResolution) async {
        streamingStatus = "Starting..."
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: resolution,
            frameRate: 24
        )
        let session = StreamSession(
            streamSessionConfig: config,
            deviceSelector: deviceSelector
        )
        self.streamSession = session

        stateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasStreaming = self.isStreaming
                switch state {
                case .stopped:
                    self.streamingStatus = "Stopped"
                    self.isStreaming = false
                    if wasStreaming {
                        self.onStreamStopped?()
                    }
                case .waitingForDevice:
                    self.streamingStatus = "Waiting for glasses..."
                case .starting:
                    self.streamingStatus = "Starting..."
                case .streaming:
                    self.streamingStatus = "Streaming"
                    self.isStreaming = true
                    self.error = nil
                case .stopping:
                    self.streamingStatus = "Stopping..."
                case .paused:
                    self.streamingStatus = "Paused"
                    self.isStreaming = false
                @unknown default:
                    self.streamingStatus = "Unknown"
                }
            }
        }

        // Capture callback outside the Sendable closure to avoid main-actor isolation issue
        let frameCallback = self.onVideoFrame
        videoToken = session.videoFramePublisher.listen { [weak self] frame in
            frameCallback?(frame.sampleBuffer)
            // Build a higher-quality preview from the raw CMSampleBuffer
            let buffer = frame.sampleBuffer
            if let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    Task { @MainActor in
                        self?.previewFrame = uiImage
                        self?.frameCount += 1
                    }
                }
            }
        }

        errorToken = session.errorPublisher.listen { [weak self] sessionError in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let message = self.formatError(sessionError)
                self.error = message
                if self.isRecoverableError(sessionError) {
                    self.scheduleAutoReconnect()
                }
            }
        }

        photoToken = session.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let uiImage = UIImage(data: photoData.data) {
                    self.capturedPhoto = uiImage
                    self.showPhotoPreview = true
                }
            }
        }

        await session.start()
    }

    func stopStream() async {
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
        await streamSession?.stop()
        streamSession = nil
        stateToken = nil
        videoToken = nil
        errorToken = nil
        photoToken = nil
        isStreaming = false
        streamingStatus = "Stopped"
        previewFrame = nil
        frameCount = 0
    }

    // MARK: - Background Handling

    func handleDidEnterBackground() {
        wasStreamingBeforeBackground = isStreaming
        // SDK supports background streaming with bluetooth-peripheral + external-accessory
        // background modes. Video decoding stops but the BLE connection stays alive.
        // We just stop updating the preview frame to save CPU.
        previewFrame = nil
    }

    func handleWillEnterForeground() {
        // The old session was destroyed by stopAll() during background.
        // We need to wait for the glasses BLE state to settle before
        // starting a new session, otherwise the glasses get confused
        // (old session teardown races with new session creation).
        if wasStreamingBeforeBackground {
            wasStreamingBeforeBackground = false
            // Clean up any stale session state
            streamSession = nil
            stateToken = nil
            videoToken = nil
            errorToken = nil
            photoToken = nil
            isStreaming = false
            streamingStatus = "Reconnecting..."
            // Delay to let glasses BLE state settle after background teardown
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard !Task.isCancelled, self.hasActiveDevice else {
                    self.streamingStatus = "Stopped"
                    return
                }
                await self.startStream(resolution: self.lastResolution)
            }
        }
    }

    // MARK: - Auto Reconnect

    private func scheduleAutoReconnect() {
        autoReconnectTask?.cancel()
        streamingStatus = "Waiting for reconnect..."
        autoReconnectTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second delay
            guard !Task.isCancelled else { return }
            guard self.hasActiveDevice else {
                self.streamingStatus = "Waiting for glasses..."
                return
            }
            // Clean up old session
            await self.streamSession?.stop()
            self.streamSession = nil
            self.stateToken = nil
            self.videoToken = nil
            self.errorToken = nil
            // Restart
            await self.startStream(resolution: self.lastResolution)
        }
    }

    private func isRecoverableError(_ error: StreamSessionError) -> Bool {
        switch error {
        case .deviceNotConnected, .deviceNotFound, .timeout, .hingesClosed:
            return true
        case .videoStreamingError, .audioStreamingError:
            return true
        case .permissionDenied, .internalError:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() {
        streamSession?.capturePhoto(format: .jpeg)
    }

    func dismissError() {
        error = nil
    }

    func dismissPhotoPreview() {
        showPhotoPreview = false
        capturedPhoto = nil
    }

    func savePhotoToLibrary() {
        guard let photo = capturedPhoto else { return }
        UIImageWriteToSavedPhotosAlbum(photo, nil, nil, nil)
    }

    // MARK: - Helpers

    private func formatError(_ error: StreamSessionError) -> String {
        switch error {
        case .deviceNotFound:
            return "Glasses not found"
        case .deviceNotConnected:
            return "Glasses disconnected"
        case .permissionDenied:
            return "Camera permission denied"
        case .timeout:
            return "Connection timed out"
        case .hingesClosed:
            return "Glasses hinges are closed — open them to resume"
        case .videoStreamingError:
            return "Video streaming error"
        case .audioStreamingError:
            return "Audio streaming error"
        case .internalError:
            return "Internal SDK error"
        @unknown default:
            return "Unknown error"
        }
    }

    deinit {
        registrationTask?.cancel()
        deviceTask?.cancel()
        activeDeviceTask?.cancel()
        autoReconnectTask?.cancel()
    }
}
