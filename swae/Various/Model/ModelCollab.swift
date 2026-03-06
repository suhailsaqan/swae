//
//  ModelCollab.swift
//  swae
//
//  Extension on Model that orchestrates the WebRTC collaborative streaming
//  lifecycle: invite → accept → connect → composite → end.
//  Ties together WebRTCService, CallSignalingService, GuestVideoCompositor,
//  and AudioMixerService.
//

import Foundation
import WebRTC

extension Model {

    // MARK: - Always-On Invite Listener

    /// Start the background signaling listener so the app can receive collab invites.
    /// Call this once after AppState is set and relays are connected.
    func startCollabSignalingListener() {
        guard let appState else {
            print("🔔 [COLLAB] ⚠️ startCollabSignalingListener — no appState")
            return
        }
        guard callSignalingService == nil else {
            print("🔔 [COLLAB] startCollabSignalingListener — already running")
            return
        }

        // Start the kind 4 relay subscription
        appState.startCollabSignalingSubscription()

        // Create a signaling service that routes invites to us
        let signaling = CallSignalingService(appState: appState)
        signaling.delegate = self
        callSignalingService = signaling
        appState.callSignalingService = signaling
        print("🔔 [COLLAB] ✅ Background invite listener started — delegate=\(signaling.delegate != nil ? "SET" : "NIL")")
    }

    // MARK: - Start Collab Call (Host)

    /// Host initiates a collab call by inviting a guest.
    func startCollabCall(guestPubkey: String, streamTitle: String, streamId: String?) {
        guard collabCallState == .idle else {
            logger.warning("collab: Cannot start call — state is \(String(describing: collabCallState))")
            return
        }
        guard let appState else {
            logger.error("collab: No appState available")
            return
        }

        let callId = UUID().uuidString
        logger.info("collab: Starting call \(callId) with guest \(guestPubkey.prefix(8))...")

        // Configure WebRTC audio session before anything else
        WebRTCService.configureAudioSession()

        // Sync the current stream mic to WebRTC so the VPIO uses the right input
        syncMicToRTCAudioSession()

        // Ensure signaling service exists (may already be running from background listener)
        if callSignalingService == nil {
            let signaling = CallSignalingService(appState: appState)
            signaling.delegate = self
            callSignalingService = signaling
            appState.callSignalingService = signaling
        }

        // Send invite
        callSignalingService?.sendInvite(
            to: guestPubkey,
            callId: callId,
            streamTitle: streamTitle,
            streamId: streamId
        )

        collabCallState = .inviteSent(guestPubkey: guestPubkey, callId: callId)
        startInviteTimeout()

        // Fast poll while waiting for accept/reject (3s instead of 15s)
        appState.setCollabSignalingPollInterval(3)
    }

    // MARK: - Accept Collab Call (Guest)

    /// Guest accepts an incoming invite.
    func acceptCollabCall(hostPubkey: String, callId: String) {
        guard case .inviteReceived = collabCallState else { return }
        guard let appState else { return }

        print("🔔 [COLLAB] Accepting call \(callId) from host \(hostPubkey.prefix(8))...")

        WebRTCService.configureAudioSession()

        // Sync the current stream mic to WebRTC so the VPIO uses the right input
        syncMicToRTCAudioSession()

        // Create signaling if not already created
        if callSignalingService == nil {
            let signaling = CallSignalingService(appState: appState)
            signaling.delegate = self
            callSignalingService = signaling
            appState.callSignalingService = signaling
        }

        // Send accept
        print("🔔 [COLLAB] Sending accept to host...")
        callSignalingService?.sendAccept(to: hostPubkey, callId: callId)

        // Create WebRTC service as guest (uses RTCCameraVideoCapturer)
        let rtc = WebRTCService(isHost: false)
        rtc.delegate = self
        rtc.connect()
        webRTCService = rtc
        print("🔔 [COLLAB] WebRTC peer connection created (guest), waiting for SDP offer from host...")

        collabCallState = .connecting(callId: callId)

        // Fast poll for SDP offer (2s) + immediate poll to catch it now
        appState.setCollabSignalingPollInterval(2)
        appState.pollCollabSignalingNow()
    }

    // MARK: - Reject Collab Call (Guest)

    func rejectCollabCall() {
        guard case let .inviteReceived(hostPubkey, callId, _) = collabCallState else { return }
        callSignalingService?.sendReject(to: hostPubkey, callId: callId)
        collabCallState = .idle
        cleanupCollabServices()
    }

    // MARK: - End Collab Call (Either Side)

    func endCollabCall(reason: String = "User ended call") {
        // Re-entry guard — disconnect() triggers .closed which would call this again
        guard !isEndingCollabCall else { return }
        isEndingCollabCall = true

        logger.info("collab: Ending call — \(reason)")

        // Cancel timers and monitoring
        cancelCollabTimers()
        collabDisconnectTimer?.invalidate()
        collabDisconnectTimer = nil
        stopThermalMonitoring()
        stopAppLifecycleObservers()
        endCollabBackgroundTask()

        // Send hangup via data channel first (instant, <100ms)
        webRTCService?.sendDataChannelHangup()

        // Send hangup via Nostr DM as backup (1-15s relay delivery)
        if let peerPubkey = collabPeerPubkey, let callId = collabCallId {
            callSignalingService?.sendHangup(to: peerPubkey, callId: callId)
        }

        // Tear down collab video widget
        if let widgetId = collabVideoWidgetId {
            // Remove from all scenes
            for scene in database.scenes {
                scene.widgets.removeAll { $0.widgetId == widgetId }
            }
            // Remove from global widgets
            database.widgets.removeAll { $0.id == widgetId }
            // Remove from effects dictionary
            collabVideoEffects.removeAll()
            collabVideoWidgetId = nil
        }

        // Tear down compositor reference
        if let compositor = guestCompositor {
            media.unregisterEffect(compositor)
            guestCompositor = nil
        }

        // Refresh the pipeline
        sceneUpdated()

        // Tear down audio mixer
        audioMixerService?.stopCapturing()
        audioMixerService = nil

        // Tear down WebRTC bridge
        media.setOnRawFrameCaptured(nil)

        // Delay WebRTC disconnect to let the data channel hangup message flush.
        // The message is queued but needs ~100-200ms to actually send over the wire.
        // Without this delay, dataChannel.close() kills it before delivery.
        let rtcToDisconnect = webRTCService
        webRTCService = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            rtcToDisconnect?.disconnect()
        }

        // Tear down signaling
        cleanupCollabServices()

        collabCallState = .ended(reason: reason)

        // Reset send-widgets toggle to default for next call
        collabSendWidgets = true
        collabSkipPipForWebRTC = true
        guestAudioVolume = 1.0
        isEndingCollabCall = false

        // Reset to idle after a brief delay so UI can show "ended" state
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if case .ended = self?.collabCallState {
                self?.collabCallState = .idle
            }
        }
    }

    private func cleanupCollabServices() {
        // Don't destroy the signaling service — restart the background listener
        // so we can receive future invites.
        callSignalingService?.stopListening()
        callSignalingService = nil
        appState?.callSignalingService = nil
        // Restart the always-on listener
        startCollabSignalingListener()
        // Resume polling for new invites
        appState?.resumeCollabSignalingPoll()
    }

    // MARK: - Helpers

    /// The peer's pubkey for the current call (host sees guest, guest sees host).
    var collabPeerPubkey: String? {
        switch collabCallState {
        case .inviteSent(let guestPubkey, _): return guestPubkey
        case .inviteReceived(let hostPubkey, _, _): return hostPubkey
        case .connecting, .connected:
            // Stored during state transitions
            return _collabPeerPubkey
        default: return nil
        }
    }

    var collabCallId: String? {
        switch collabCallState {
        case .inviteSent(_, let callId): return callId
        case .inviteReceived(_, let callId, _): return callId
        case .connecting(let callId): return callId
        case .connected(let callId): return callId
        default: return nil
        }
    }

    /// Start the compositor and frame bridge after WebRTC connects. Runs on BOTH sides.
    fileprivate func activateCompositing() {
        guard let rtc = webRTCService else {
            print("🔔 [PIP] ⚠️ activateCompositing — webRTCService is nil!")
            return
        }

        // Create the GuestVideoCompositor — we hold a reference for the widget system
        let compositor = GuestVideoCompositor(remoteVideoRenderer: rtc.remoteVideoRenderer)
        guestCompositor = compositor
        print("🔔 [PIP] Created GuestVideoCompositor, renderer=\(rtc.remoteVideoRenderer)")

        // Create a .collabVideo widget so the PiP is draggable/resizable like any other widget
        let widget = SettingsWidget(name: "Collab Video")
        widget.type = .collabVideo
        database.widgets.append(widget)
        collabVideoWidgetId = widget.id

        // Add to ALL scenes so the PiP survives scene switches
        for scene in database.scenes {
            let sceneWidget = SettingsSceneWidget(widgetId: widget.id)
            sceneWidget.x = 70
            sceneWidget.y = 5
            sceneWidget.width = 25
            sceneWidget.height = 35
            scene.widgets.append(sceneWidget)
        }

        // Register through the widget system
        addSingleWidgetEffect(widget: widget)

        // Bridge local VideoUnit frames to WebRTC
        let bridgeCapturer = rtc.bridgeCapturer
        print("🔔 [PIP] Setting onRawFrameCaptured bridge, bridgeCapturer=\(bridgeCapturer != nil ? "SET" : "NIL")")
        media.setOnRawFrameCaptured { [weak bridgeCapturer] pixelBuffer, timestamp in
            bridgeCapturer?.pushFrame(pixelBuffer, timestamp: timestamp)
        }

        print("🔔 [PIP] ✅ Compositing activated — collab video widget created + frame bridge set")

        // Start audio mixer — captures WebRTC remote audio and mixes into RTMP stream
        if let audioUnit = media.audioUnit {
            let mixer = AudioMixerService(audioUnit: audioUnit)
            mixer.startCapturing()
            audioMixerService = mixer
            print("🔔 [COLLAB] ✅ AudioMixerService started — guest audio will be mixed into stream")
        } else {
            print("🔔 [COLLAB] ⚠️ Could not start AudioMixerService — audioUnit is nil")
        }

        // Slow poll during connected call (5s) — backup for hangup detection
        // via Nostr DM in case WebRTC data channel/state changes don't fire
        appState?.setCollabSignalingPollInterval(5)
    }

    /// Sync the collabSendWidgets toggle to VideoUnit and BridgeCapturer.
    /// Call this whenever the user toggles the setting during a call.
    func updateCollabSendWidgets() {
        let sendWidgets = collabSendWidgets
        media.setCollabSendWidgets(sendWidgets)
        webRTCService?.bridgeCapturer?.postEffectsMode = sendWidgets
    }

    /// Sync the collabSkipPipForWebRTC toggle to VideoUnit.
    func updateCollabSkipPip() {
        media.setCollabSkipPipForWebRTC(collabSkipPipForWebRTC)
    }

    /// Reattach camera during an active collab call.
    /// Resets the WebRTC bridge frame counter and bypasses the ignore-frames
    /// window so frames flow immediately after reattach, keeping WebRTC alive.
    func reattachCameraForCollab() {
        webRTCService?.bridgeCapturer?.resetForReattach()
        // Bypass the ignore-frames-after-attach window so the post-effects
        // WebRTC tap fires immediately. Without this, the ~0.3-0.5s ignore
        // window blocks ALL frames (including the WebRTC tap) and the
        // encoder stalls permanently.
        media.setIgnoreFramesAfterAttachSeconds(0)
        reattachCamera()
    }

    /// Re-establish the WebRTC frame bridge after the Processor is recreated.
    /// Called from reloadStream() which creates a new Processor, replacing the
    /// VideoUnit that had onRawFrameCaptured set. Without this, the WebRTC
    /// video freezes permanently after any stream reload (resolution change,
    /// orientation change, codec change, etc.).
    func reestablishCollabBridgeIfNeeded() {
        guard collabCallState.isConnected, let bridgeCapturer = webRTCService?.bridgeCapturer else {
            return
        }
        media.setOnRawFrameCaptured { [weak bridgeCapturer] pixelBuffer, timestamp in
            bridgeCapturer?.pushFrame(pixelBuffer, timestamp: timestamp)
        }
        bridgeCapturer.resetForReattach()
        // Also re-sync collab video settings to the new VideoUnit
        media.setCollabSendWidgets(collabSendWidgets)
        media.setCollabSkipPipForWebRTC(collabSkipPipForWebRTC)
        print("🔔 [COLLAB] ✅ Re-established WebRTC frame bridge after stream reload")
    }

    /// Sync the current stream mic to RTCAudioSession so WebRTC's VPIO
    /// AudioUnit uses the same mic as the RTMP stream.
    /// Call this before WebRTC connect() and after any mic change during a call.
    func syncMicToRTCAudioSession() {
        let currentMic = mic.current
        guard currentMic != noMic, currentMic.isAudioSession() else { return }
        processorControlQueue.async {
            let session = AVAudioSession.sharedInstance()
            guard let inputPort = session.availableInputs?.first(where: { $0.uid == currentMic.inputUid })
            else { return }
            let rtcSession = RTCAudioSession.sharedInstance()
            rtcSession.lockForConfiguration()
            try? rtcSession.setPreferredInput(inputPort)
            if let dataSourceId = currentMic.dataSourceId as? NSNumber,
               let dataSource = inputPort.dataSources?.first(where: { $0.dataSourceID == dataSourceId }) {
                try? rtcSession.setInputDataSource(dataSource)
            }
            rtcSession.unlockForConfiguration()
            print("🔔 [COLLAB] Synced RTCAudioSession to mic: \(currentMic.name)")
        }
    }

    /// Sync the guest audio volume to AudioUnit's mixing pipeline and WebRTC playback.
    func updateGuestAudioVolume() {
        // Control what goes into the RTMP stream (mixing pipeline)
        media.setGuestAudioVolume(guestAudioVolume)
        // Control what the streamer hears locally (WebRTC speaker playback)
        // RTCAudioSource.volume range is 0–10, our slider is 0–2.
        // Map: slider 0.0 → WebRTC 0.0, slider 1.0 → WebRTC 1.0, slider 2.0 → WebRTC 2.0
        webRTCService?.setRemoteAudioVolume(Double(guestAudioVolume))
    }

    // MARK: - Phase 6: Timeout Handling

    /// Start a 60-second invite timeout. Auto-cancels if guest doesn't respond.
    func startInviteTimeout() {
        collabInviteTimer?.invalidate()
        collabInviteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            if case .inviteSent = self.collabCallState {
                logger.info("collab: Invite timed out after 60 seconds")
                self.endCollabCall(reason: "Invite timed out — guest didn't respond")
                self.makeToast(title: "Guest didn't respond")
            }
        }
    }

    /// Start a 30-second ICE connection timeout.
    func startIceTimeout() {
        collabIceTimer?.invalidate()
        collabIceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self else { return }
            if case .connecting = self.collabCallState {
                logger.info("collab: ICE connection timed out after 30 seconds")
                self.endCollabCall(reason: "Connection failed — guest may be behind a strict firewall")
                self.makeToast(title: "Connection failed")
            }
        }
    }

    func cancelCollabTimers() {
        collabInviteTimer?.invalidate()
        collabInviteTimer = nil
        collabIceTimer?.invalidate()
        collabIceTimer = nil
    }

    // MARK: - Phase 6: Thermal Monitoring

    /// Start monitoring thermal state. Degrades WebRTC quality first, never RTMP.
    func startThermalMonitoring() {
        stopThermalMonitoring()
        collabThermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
        // Check current state immediately
        handleThermalStateChange()
    }

    func stopThermalMonitoring() {
        if let observer = collabThermalObserver {
            NotificationCenter.default.removeObserver(observer)
            collabThermalObserver = nil
        }
    }

    private func handleThermalStateChange() {
        guard collabCallState.isConnected, let rtc = webRTCService else { return }

        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair:
            // Full quality
            rtc.setMaxBitrate(1_500_000)
            rtc.bridgeCapturer?.maxFps = 15
        case .serious:
            // Reduce WebRTC quality — guest sees lower quality, RTMP stream unaffected
            logger.warning("collab: Thermal state SERIOUS — reducing WebRTC quality")
            rtc.setMaxBitrate(500_000)
            rtc.bridgeCapturer?.maxFps = 10
            makeToast(title: "Device warming up — reducing guest video quality")
        case .critical:
            // End the call to protect the stream
            logger.error("collab: Thermal state CRITICAL — ending collab call")
            endCollabCall(reason: "Device overheating — ending guest call to protect stream quality")
            makeToast(title: "Call ended — device too hot")
        @unknown default:
            break
        }
    }

    // MARK: - Phase 6: Background Task Handling

    /// Begin a background task when the app is backgrounded during a call.
    func beginCollabBackgroundTask() {
        guard collabBackgroundTask == .invalid else { return }
        collabBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CollabCall") { [weak self] in
            // Expiration handler — end the call if we run out of background time
            logger.warning("collab: Background task expiring — ending call")
            self?.endCollabCall(reason: "App moved to background")
            self?.endCollabBackgroundTask()
        }
    }

    func endCollabBackgroundTask() {
        guard collabBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(collabBackgroundTask)
        collabBackgroundTask = .invalid
    }

    // MARK: - Phase 6: App Lifecycle Observers

    /// Observe app foreground/background transitions to manage the call during backgrounding.
    func startAppLifecycleObservers() {
        stopAppLifecycleObservers()
        collabBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.collabCallState.isActive else { return }
            logger.info("collab: App entered background — starting background task")
            self.beginCollabBackgroundTask()
        }
        collabForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            logger.info("collab: App returning to foreground")
            self.endCollabBackgroundTask()
        }
    }

    func stopAppLifecycleObservers() {
        if let observer = collabBackgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            collabBackgroundObserver = nil
        }
        if let observer = collabForegroundObserver {
            NotificationCenter.default.removeObserver(observer)
            collabForegroundObserver = nil
        }
    }
}

// MARK: - CallSignalingServiceDelegate

extension Model: CallSignalingServiceDelegate {
    func signalingService(_ service: CallSignalingService, didReceiveInvite message: WebRTCSignalMessage, from pubkey: String) {
        print("🔔 [COLLAB] signalingService didReceiveInvite — callId=\(message.callId.prefix(8)), from=\(pubkey.prefix(8)), currentState=\(String(describing: collabCallState))")
        // Accept invites when idle OR when in the brief .ended/.failed display states
        switch collabCallState {
        case .idle, .ended, .failed:
            break
        default:
            // Actually in a call — reject
            print("🔔 [COLLAB] ⚠️ Not idle — auto-rejecting invite")
            service.sendReject(to: pubkey, callId: message.callId)
            return
        }
        let title = message.payload.streamTitle ?? "Live Stream"
        collabCallState = .inviteReceived(hostPubkey: pubkey, callId: message.callId, streamTitle: title)
        _collabPeerPubkey = pubkey
        print("🔔 [COLLAB] ✅ State set to .inviteReceived — title='\(title)', UI should show banner now")
    }

    func signalingService(_ service: CallSignalingService, didReceiveAccept message: WebRTCSignalMessage, from pubkey: String) {
        guard case let .inviteSent(guestPubkey, callId) = collabCallState,
              pubkey == guestPubkey, message.callId == callId
        else {
            print("🔔 [COLLAB] Received accept but state mismatch — currentState=\(String(describing: collabCallState)), from=\(pubkey.prefix(8)), callId=\(message.callId.prefix(8))")
            return
        }

        print("🔔 [COLLAB] Guest accepted — creating WebRTC connection as host")
        _collabPeerPubkey = pubkey

        // Create WebRTC service as host (uses VideoUnitBridgeCapturer)
        let rtc = WebRTCService(isHost: true)
        rtc.delegate = self
        rtc.connect()
        webRTCService = rtc

        // Create and send SDP offer
        print("🔔 [COLLAB] Creating SDP offer...")
        rtc.createOffer()

        collabCallState = .connecting(callId: callId)
        cancelCollabTimers()  // Cancel invite timeout
        startIceTimeout()     // Start ICE connection timeout

        // Fast poll for SDP answer (2s) + immediate poll
        appState?.setCollabSignalingPollInterval(2)
        appState?.pollCollabSignalingNow()
    }

    func signalingService(_ service: CallSignalingService, didReceiveReject message: WebRTCSignalMessage, from pubkey: String) {
        guard case let .inviteSent(guestPubkey, callId) = collabCallState,
              pubkey == guestPubkey, message.callId == callId
        else { return }

        logger.info("collab: Guest rejected the invite")
        cancelCollabTimers()
        collabCallState = .ended(reason: "Guest declined")
        cleanupCollabServices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if case .ended = self?.collabCallState {
                self?.collabCallState = .idle
            }
        }
    }

    func signalingService(_ service: CallSignalingService, didReceiveOffer sdp: RTCSessionDescription, callId: String, from pubkey: String) {
        guard case .connecting(let currentCallId) = collabCallState, callId == currentCallId else {
            print("🔔 [COLLAB] Received offer but state/callId mismatch — state=\(String(describing: collabCallState)), callId=\(callId.prefix(8))")
            return
        }
        guard let rtc = webRTCService else {
            print("🔔 [COLLAB] ⚠️ Received offer but webRTCService is nil!")
            return
        }

        print("🔔 [COLLAB] Received SDP offer — setting remote description and creating answer")
        rtc.setRemoteDescription(sdp) { [weak self] error in
            if let error {
                print("🔔 [COLLAB] ⚠️ Failed to set remote description: \(error.localizedDescription)")
                return
            }
            print("🔔 [COLLAB] Remote description set, creating answer...")
            self?.webRTCService?.createAnswer()
            // Immediate poll to catch ICE candidates that may already be on the relay
            self?.appState?.pollCollabSignalingNow()
        }
    }

    func signalingService(_ service: CallSignalingService, didReceiveAnswer sdp: RTCSessionDescription, callId: String, from pubkey: String) {
        guard case .connecting(let currentCallId) = collabCallState, callId == currentCallId else {
            print("🔔 [COLLAB] Received answer but state/callId mismatch")
            return
        }

        print("🔔 [COLLAB] Received SDP answer — setting remote description")
        webRTCService?.setRemoteDescription(sdp) { [weak self] error in
            if let error {
                print("🔔 [COLLAB] ⚠️ Failed to set remote description (answer): \(error.localizedDescription)")
            } else {
                print("🔔 [COLLAB] ✅ Remote description (answer) set successfully")
                // Immediate poll to catch ICE candidates
                self?.appState?.pollCollabSignalingNow()
            }
        }
    }

    func signalingService(_ service: CallSignalingService, didReceiveIceCandidate candidate: RTCIceCandidate, callId: String, from pubkey: String) {
        print("🔔 [COLLAB] Received ICE candidate from \(pubkey.prefix(8))")
        webRTCService?.addIceCandidate(candidate) { error in
            if let error {
                print("🔔 [COLLAB] ⚠️ Failed to add ICE candidate: \(error.localizedDescription)")
            }
        }
    }

    func signalingService(_ service: CallSignalingService, didReceiveHangup callId: String, from pubkey: String) {
        logger.info("collab: Peer hung up")
        endCollabCall(reason: "Peer ended call")
    }
}

// MARK: - WebRTCServiceDelegate

extension Model: WebRTCServiceDelegate {
    func webRTCService(_ service: WebRTCService, didChangeState state: RTCPeerConnectionState) {
        switch state {
        case .connected:
            if case .connecting(let callId) = collabCallState {
                collabCallState = .connected(callId: callId)
                cancelCollabTimers()
                collabDisconnectTimer?.invalidate()
                collabDisconnectTimer = nil
                print("🔔 [COLLAB] ✅ WebRTC connected — activating compositing on both sides")
                activateCompositing()
                startThermalMonitoring()
                startAppLifecycleObservers()
            } else if collabCallState.isConnected {
                // Reconnected after ICE restart — cancel disconnect timeout
                collabDisconnectTimer?.invalidate()
                collabDisconnectTimer = nil
                makeToast(title: "Reconnected")
            }
        case .disconnected:
            // Transient disconnection — attempt ICE restart before giving up
            guard collabCallState.isConnected else {
                // Not yet connected — treat as failure
                endCollabCall(reason: "Connection failed during setup")
                return
            }
            logger.warning("collab: WebRTC disconnected — attempting ICE restart")
            if service.attemptIceRestart() {
                makeToast(title: "Reconnecting to guest...")
                startDisconnectTimeout()
            } else {
                endCollabCall(reason: "Connection lost — could not reconnect")
            }
        case .failed:
            logger.warning("collab: WebRTC connection failed")
            endCollabCall(reason: "Connection failed")
        case .closed:
            // Peer properly closed the connection — end the call
            if collabCallState.isActive {
                endCollabCall(reason: "Peer disconnected")
            }
        default:
            break
        }
    }

    func webRTCService(_ service: WebRTCService, didChangeIceState state: RTCIceConnectionState) {
        // ICE state is informational — connection state delegate handles the actual transitions
    }

    func webRTCService(_ service: WebRTCService, didGenerateCandidate candidate: RTCIceCandidate) {
        guard let peerPubkey = collabPeerPubkey, let callId = collabCallId else {
            print("🔔 [COLLAB] ⚠️ ICE candidate generated but no peer pubkey or callId")
            return
        }
        print("🔔 [COLLAB] Sending ICE candidate to \(peerPubkey.prefix(8))")
        callSignalingService?.sendIceCandidate(candidate, to: peerPubkey, callId: callId)
    }

    func webRTCService(_ service: WebRTCService, didReceiveRemoteVideoTrack track: RTCVideoTrack) {
        print("🔔 [COLLAB] ✅ Remote video track received")
    }

    func webRTCService(_ service: WebRTCService, didCreateLocalSDP sdp: RTCSessionDescription) {
        guard let peerPubkey = collabPeerPubkey, let callId = collabCallId else {
            print("🔔 [COLLAB] ⚠️ SDP created but no peer pubkey or callId")
            return
        }
        if sdp.type == .offer {
            print("🔔 [COLLAB] Sending SDP offer to \(peerPubkey.prefix(8))")
            callSignalingService?.sendOffer(sdp, to: peerPubkey, callId: callId)
        } else if sdp.type == .answer {
            print("🔔 [COLLAB] Sending SDP answer to \(peerPubkey.prefix(8))")
            callSignalingService?.sendAnswer(sdp, to: peerPubkey, callId: callId)
        }
    }

    func webRTCServiceDidLoseHeartbeat(_ service: WebRTCService) {
        guard collabCallState.isConnected else { return }
        logger.warning("collab: Heartbeat lost — peer unresponsive")
        // Try ICE restart first, then give up
        if !service.attemptIceRestart() {
            endCollabCall(reason: "Guest became unresponsive")
            makeToast(title: "Call ended — guest unresponsive")
        } else {
            startDisconnectTimeout()
        }
    }

    func webRTCServiceDidReceiveHangup(_ service: WebRTCService) {
        logger.info("collab: Received hangup via data channel — ending call instantly")
        endCollabCall(reason: "Peer ended call")
    }
}

// MARK: - Disconnect Timeout

extension Model {
    /// Start a 10-second safety net after ICE restart. If the connection doesn't
    /// recover within 10 seconds, end the call to prevent "stuck reconnecting" state.
    fileprivate func startDisconnectTimeout() {
        collabDisconnectTimer?.invalidate()
        collabDisconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self, self.collabCallState.isConnected else { return }
            logger.warning("collab: Disconnect timeout — ending call")
            self.endCollabCall(reason: "Connection lost")
        }
    }
}
