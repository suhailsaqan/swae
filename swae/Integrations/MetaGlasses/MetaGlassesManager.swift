import AVFoundation
import Combine
import MWDATCamera
import MWDATCore
import UIKit

/// Represents the high-level streaming lifecycle so the model layer
/// can guard against duplicate starts without fragile string comparisons.
enum MetaGlassesStreamingStatus: Equatable {
    case stopped
    case checkingPermissions
    case requestingPermission
    case permissionDenied
    case permissionError
    case starting
    case streaming
    case stopping
    case paused
    case waitingForDevice
    case waitingForReconnect
    case reconnecting
    case unknown

    var displayString: String {
        switch self {
        case .stopped: return "Stopped"
        case .checkingPermissions: return "Checking permissions..."
        case .requestingPermission: return "Requesting permission..."
        case .permissionDenied: return "Permission denied"
        case .permissionError: return "Permission error"
        case .starting: return "Starting..."
        case .streaming: return "Streaming"
        case .stopping: return "Stopping..."
        case .paused: return "Paused"
        case .waitingForDevice: return "Waiting for glasses..."
        case .waitingForReconnect: return "Waiting for reconnect..."
        case .reconnecting: return "Reconnecting..."
        case .unknown: return "Unknown"
        }
    }

    /// Whether the manager is in the middle of starting up.
    var isTransitioning: Bool {
        switch self {
        case .checkingPermissions, .requestingPermission, .starting, .reconnecting:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class MetaGlassesManager: ObservableObject {
    @Published var isRegistered = false
    @Published var isRegistering = false
    @Published var devices: [DeviceIdentifier] = []
    @Published var hasActiveDevice = false
    @Published var isStreaming = false
    @Published var streamingStatus: MetaGlassesStreamingStatus = .stopped
    @Published var previewFrame: UIImage?
    @Published var error: String?
    @Published var frameCount: UInt64 = 0
    @Published var capturedPhoto: UIImage?
    @Published var showPhotoPreview = false
    @Published var selectedResolution: StreamingResolution = .high

    /// Callback for feeding raw CMSampleBuffers into Swae's video pipeline.
    var onVideoFrame: ((CMSampleBuffer) -> Void)?

    /// Callback when stream stops unexpectedly (disconnect, error, hinges closed).
    var onStreamStopped: (() -> Void)?

    /// Callback when auto-reconnect or foreground reconnect wants to restart.
    /// The model layer should call updateMetaGlassesStreamState() to decide
    /// whether to actually restart based on reference counting.
    var onReconnectRequested: (() -> Void)?

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
    var wasStreamingBeforeBackground = false

    /// Reusable CIContext for preview frame rendering — creating one per frame is expensive.
    private let previewCIContext = CIContext()

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
                if device != nil, !hadDevice, self.streamingStatus == .waitingForReconnect {
                    self.requestReconnect()
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
        // Stop the stream cleanly before unregistering to avoid relying
        // on SDK teardown behavior for cleanup.
        if isStreaming || streamingStatus.isTransitioning {
            await stopStream()
        }
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
        streamingStatus = .checkingPermissions

        // Permission flow matching official CameraAccess sample exactly
        let permission = Permission.camera
        do {
            let status = try await Wearables.shared.checkPermissionStatus(permission)
            if status == .granted {
                await beginStreamSession(resolution: resolution)
                return
            }
            streamingStatus = .requestingPermission
            let requestStatus = try await Wearables.shared.requestPermission(permission)
            if requestStatus == .granted {
                await beginStreamSession(resolution: resolution)
                return
            }
            error = "Camera permission denied. Grant permission in the Meta AI app."
            streamingStatus = .permissionDenied
        } catch let permError as PermissionError {
            self.error = "Permission error: \(permError.description)"
            streamingStatus = .permissionError
        } catch {
            self.error = "Permission error: \(error.localizedDescription)"
            streamingStatus = .permissionError
        }
    }

    private func beginStreamSession(resolution: StreamingResolution) async {
        streamingStatus = .starting
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
                    self.streamingStatus = .stopped
                    self.isStreaming = false
                    if wasStreaming {
                        self.onStreamStopped?()
                    }
                case .waitingForDevice:
                    self.streamingStatus = .waitingForDevice
                case .starting:
                    self.streamingStatus = .starting
                case .streaming:
                    self.streamingStatus = .streaming
                    self.isStreaming = true
                    self.error = nil
                case .stopping:
                    self.streamingStatus = .stopping
                case .paused:
                    self.streamingStatus = .paused
                    self.isStreaming = false
                @unknown default:
                    self.streamingStatus = .unknown
                }
            }
        }

        // Capture callback outside the Sendable closure to avoid main-actor isolation issue
        let frameCallback = self.onVideoFrame
        let ciContext = self.previewCIContext
        videoToken = session.videoFramePublisher.listen { [weak self] frame in
            frameCallback?(frame.sampleBuffer)
            // Build a higher-quality preview from the raw CMSampleBuffer
            let buffer = frame.sampleBuffer
            if let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
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
                    self.requestReconnect()
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
        cleanupSession()
    }

    /// Tears down session state and tokens without stopping the session itself.
    /// Used after stopStream() and during reconnection cleanup.
    private func cleanupSession() {
        streamSession = nil
        stateToken = nil
        videoToken = nil
        errorToken = nil
        photoToken = nil
        isStreaming = false
        streamingStatus = .stopped
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
            cleanupSession()
            streamingStatus = .reconnecting
            // Delay to let glasses BLE state settle after background teardown,
            // then ask the model layer to re-evaluate via callback.
            autoReconnectTask?.cancel()
            autoReconnectTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard !Task.isCancelled else { return }
                guard self.hasActiveDevice else {
                    self.streamingStatus = .stopped
                    return
                }
                self.onReconnectRequested?()
            }
        }
    }

    // MARK: - Reconnection

    /// Asks the model layer to re-evaluate whether the stream should restart.
    /// This keeps the model's reference counting in control instead of
    /// the manager restarting the stream on its own.
    private func requestReconnect() {
        autoReconnectTask?.cancel()
        streamingStatus = .waitingForReconnect
        autoReconnectTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second delay
            guard !Task.isCancelled else { return }
            guard self.hasActiveDevice else {
                self.streamingStatus = .waitingForDevice
                return
            }
            // Clean up old session before requesting restart
            await self.streamSession?.stop()
            self.cleanupSession()
            self.streamingStatus = .reconnecting
            // Let the model layer decide whether to restart
            self.onReconnectRequested?()
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
