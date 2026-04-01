import AVFoundation
import MWDATCore

let metaGlassesCameraId = UUID(uuidString: "00000000-ae7a-91a5-5e5c-000000000000")!

extension Model {
    @MainActor
    func setupMetaGlasses() {
        let manager = MetaGlassesManager()
        manager.onVideoFrame = { [weak self] sampleBuffer in
            self?.media.appendBufferedVideoSampleBuffer(
                cameraId: metaGlassesCameraId,
                sampleBuffer: sampleBuffer
            )
            self?.metaGlassesPipCompositor?.updateFrame(sampleBuffer)
        }
        manager.onStreamStopped = { [weak self] in
            self?.media.removeBufferedVideo(cameraId: metaGlassesCameraId)
        }
        metaGlassesManager = manager
    }

    // MARK: - Stream Lifecycle (reference counted)

    /// Whether the current scene requires Meta Glasses video.
    var isMetaGlassesNeededByScene: Bool {
        return getSelectedScene()?.cameraPosition == .metaGlasses
    }

    /// Whether the settings preview is active.
    var isMetaGlassesPreviewActive: Bool {
        get { metaGlassesPreviewRequested }
        set { metaGlassesPreviewRequested = newValue }
    }

    /// Whether anything needs the glasses stream running.
    private var isMetaGlassesStreamNeeded: Bool {
        return isMetaGlassesNeededByScene || metaGlassesPreviewRequested || isMetaGlassesPipEnabled
    }

    /// Call this to ensure the stream is running if anything needs it,
    /// or stopped if nothing does.
    func updateMetaGlassesStreamState() {
        if isMetaGlassesStreamNeeded {
            ensureMetaGlassesStreamStarted()
        } else {
            ensureMetaGlassesStreamStopped()
        }
    }

    private func ensureMetaGlassesStreamStarted() {
        Task { @MainActor in
            guard let manager = metaGlassesManager else { return }
            // Don't start if already streaming or in the middle of reconnecting
            guard !manager.isStreaming,
                  manager.streamingStatus != "Reconnecting...",
                  manager.streamingStatus != "Starting...",
                  manager.streamingStatus != "Checking permissions...",
                  manager.streamingStatus != "Requesting permission..."
            else { return }
            media.addBufferedVideo(
                cameraId: metaGlassesCameraId,
                name: "Meta Glasses",
                latency: 0.15
            )
            await manager.startStream(resolution: manager.selectedResolution)
        }
    }

    private func ensureMetaGlassesStreamStopped() {
        Task { @MainActor in
            guard metaGlassesManager?.isStreaming == true else { return }
            await metaGlassesManager?.stopStream()
        }
        media.removeBufferedVideo(cameraId: metaGlassesCameraId)
    }

    // MARK: - Settings Preview

    func startMetaGlassesPreview() {
        metaGlassesPreviewRequested = true
        updateMetaGlassesStreamState()
    }

    func stopMetaGlassesPreview() {
        metaGlassesPreviewRequested = false
        updateMetaGlassesStreamState()
    }

    // MARK: - Scene Camera

    func attachMetaGlassesCamera(scene: SettingsScene) {
        attachBufferedCamera(cameraId: metaGlassesCameraId, scene: scene)
        updateMetaGlassesStreamState()
    }

    /// Called when scene switches AWAY from Meta Glasses.
    /// The stream will stop only if no other consumer needs it.
    func detachMetaGlassesCamera() {
        updateMetaGlassesStreamState()
    }

    // MARK: - PiP Mode

    func enableMetaGlassesPip() {
        guard metaGlassesPipCompositor == nil else { return }
        let compositor = MetaGlassesCompositor()
        metaGlassesPipCompositor = compositor
        media.registerEffect(compositor)
        updateMetaGlassesStreamState()
    }

    func disableMetaGlassesPip() {
        guard let compositor = metaGlassesPipCompositor else { return }
        media.unregisterEffect(compositor)
        metaGlassesPipCompositor = nil
        updateMetaGlassesStreamState()
    }

    var isMetaGlassesPipEnabled: Bool {
        return metaGlassesPipCompositor != nil
    }

    // MARK: - Full Stop (for stopAll / background teardown)

    func stopMetaGlassesCompletely() {
        metaGlassesPreviewRequested = false
        disableMetaGlassesPip()
        Task { @MainActor in
            await metaGlassesManager?.stopStream()
        }
        media.removeBufferedVideo(cameraId: metaGlassesCameraId)
    }

    // MARK: - Background Lifecycle

    func metaGlassesDidEnterBackground() {
        Task { @MainActor in
            metaGlassesManager?.handleDidEnterBackground()
        }
    }

    func metaGlassesWillEnterForeground() {
        // The manager handles its own foreground reconnection with a delay.
        // Don't call updateMetaGlassesStreamState() here — let the manager's
        // delayed reconnect handle it to avoid racing with scene reattachment.
        Task { @MainActor in
            metaGlassesManager?.handleWillEnterForeground()
        }
    }

    func isMetaGlassesCamera(cameraId: String) -> Bool {
        return cameraId == metaGlassesCamera
    }
}
