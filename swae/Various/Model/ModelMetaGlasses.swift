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
            guard let self else { return }
            self.media.removeBufferedVideo(cameraId: metaGlassesCameraId)
            // Reset preview flag so the UI doesn't show a stale "Stop" button
            // for a stream that died unexpectedly.
            self.metaGlassesPreviewRequested = false
        }
        manager.onReconnectRequested = { [weak self] in
            guard let self else { return }
            // The manager wants to reconnect (auto-reconnect or foreground resume).
            // Let the reference counting system decide whether to actually restart.
            self.updateMetaGlassesStreamState()
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
            // Always register the buffered video on the current Processor.
            // This is critical because reloadStream() creates a new Processor,
            // destroying the old one's bufferedVideos dictionary. Without this,
            // a resolution change while Meta Glasses is active causes frames
            // to be silently dropped (the SDK session is still running but the
            // new Processor has no entry for the camera ID).
            media.addBufferedVideo(
                cameraId: metaGlassesCameraId,
                name: "Meta Glasses",
                latency: 0.15
            )
            // Only start the SDK stream if it's not already running or transitioning.
            guard !manager.isStreaming, !manager.streamingStatus.isTransitioning else { return }
            await manager.startStream(resolution: manager.selectedResolution)
        }
    }

    private func ensureMetaGlassesStreamStopped() {
        Task { @MainActor in
            guard let manager = metaGlassesManager else { return }
            guard manager.isStreaming || manager.streamingStatus.isTransitioning else { return }
            await manager.stopStream()
            // Remove buffered video AFTER the stream has actually stopped
            // to avoid the pipeline receiving frames for a removed camera ID.
            media.removeBufferedVideo(cameraId: metaGlassesCameraId)
        }
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
            // Remove buffered video AFTER the stream has actually stopped.
            media.removeBufferedVideo(cameraId: metaGlassesCameraId)
        }
    }

    // MARK: - Background Lifecycle

    func metaGlassesDidEnterBackground() {
        Task { @MainActor in
            metaGlassesManager?.handleDidEnterBackground()
        }
    }

    func metaGlassesWillEnterForeground() {
        // The manager handles its own foreground reconnection with a delay.
        // It will call onReconnectRequested which triggers updateMetaGlassesStreamState()
        // so the reference counting system stays in control.
        Task { @MainActor in
            metaGlassesManager?.handleWillEnterForeground()
        }
    }

    func isMetaGlassesCamera(cameraId: String) -> Bool {
        return cameraId == metaGlassesCamera
    }
}
