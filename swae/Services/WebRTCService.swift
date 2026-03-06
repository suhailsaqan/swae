//
//  WebRTCService.swift
//  swae
//
//  WebRTC peer connection management for live collaborative streaming.
//  Handles RTCPeerConnection lifecycle, ICE, media tracks, and the
//  VideoUnit bridge capturer for host-side camera sharing.
//

import AVFoundation
import Foundation
import WebRTC

// MARK: - Delegate

protocol WebRTCServiceDelegate: AnyObject {
    func webRTCService(_ service: WebRTCService, didChangeState state: RTCPeerConnectionState)
    func webRTCService(_ service: WebRTCService, didChangeIceState state: RTCIceConnectionState)
    func webRTCService(_ service: WebRTCService, didGenerateCandidate candidate: RTCIceCandidate)
    func webRTCService(_ service: WebRTCService, didReceiveRemoteVideoTrack track: RTCVideoTrack)
    func webRTCService(_ service: WebRTCService, didCreateLocalSDP sdp: RTCSessionDescription)
    func webRTCServiceDidLoseHeartbeat(_ service: WebRTCService)
    func webRTCServiceDidReceiveHangup(_ service: WebRTCService)
}

// MARK: - WebRTCService

final class WebRTCService: NSObject {
    weak var delegate: WebRTCServiceDelegate?

    // WebRTC core objects
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?

    // Media tracks
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var localVideoSource: RTCVideoSource?

    // Host-side bridge: feeds VideoUnit frames into WebRTC without opening a second camera
    private(set) var bridgeCapturer: VideoUnitBridgeCapturer?

    // Remote video capture for compositor
    let remoteVideoRenderer = PixelBufferVideoRenderer()

    // Remote video track — stored for direct RTCMTLVideoView rendering
    private(set) var remoteVideoTrack: RTCVideoTrack?

    // Remote audio track — stored for volume control
    private(set) var remoteAudioTrack: RTCAudioTrack?

    // Whether this device is the host (composites + broadcasts) or guest (standard call)
    let isHost: Bool

    // Data channel for heartbeat pings
    private var dataChannel: RTCDataChannel?
    private var heartbeatTimer: Timer?
    private var missedHeartbeats: Int = 0
    private static let heartbeatInterval: TimeInterval = 5
    private static let maxMissedHeartbeats = 2

    // ICE restart tracking
    private(set) var iceRestartCount: Int = 0
    static let maxIceRestarts = 1

    // ICE candidate queue — candidates that arrive before remote description is set
    private var pendingIceCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false

    // MARK: - ICE Configuration

    private static let defaultIceServers: [RTCIceServer] = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
    ]

    // MARK: - Init

    init(isHost: Bool) {
        self.isHost = isHost
        // Initialize WebRTC. RTCPeerConnectionFactory must be created after
        // RTCInitializeSSL() — the factory handles this internally.
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
        super.init()
    }

    deinit {
        disconnect()
    }

    // MARK: - Connection Setup

    func connect() {
        let config = RTCConfiguration()
        config.iceServers = Self.defaultIceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        guard let pc = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            logger.error("webrtc: Failed to create RTCPeerConnection")
            return
        }
        peerConnection = pc

        setupDataChannel()
        setupAudioTrack()
        setupVideoTrack()
    }

    func disconnect() {
        stopHeartbeat()
        dataChannel?.close()
        dataChannel = nil
        bridgeCapturer = nil
        localAudioTrack = nil
        localVideoTrack = nil
        localVideoSource = nil
        remoteAudioTrack = nil
        hasRemoteDescription = false
        pendingIceCandidates.removeAll()
        peerConnection?.close()
        peerConnection = nil
    }

    // MARK: - Audio Track

    private func setupAudioTrack() {
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": "true",
                "googNoiseSuppression": "true",
                "googAutoGainControl": "true",
            ]
        )
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        peerConnection?.add(audioTrack, streamIds: ["stream0"])
        localAudioTrack = audioTrack
    }

    // MARK: - Video Track

    private func setupVideoTrack() {
        let videoSource = factory.videoSource()
        localVideoSource = videoSource

        // Both host and guest: bridge from VideoUnit's existing camera.
        let capturer = VideoUnitBridgeCapturer(videoSource: videoSource)
        bridgeCapturer = capturer

        // adaptOutputFormat MUST be called for custom capturers to activate the
        // internal frame adapter. Without it, the encoder silently drops all frames.
        // Use a reasonable target resolution — the adapter will scale incoming frames.
        // Per SO: https://stackoverflow.com/questions/73600303
        videoSource.adaptOutputFormat(toWidth: 1280, height: 720, fps: 30)

        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        peerConnection?.add(videoTrack, streamIds: ["stream0"])
        localVideoTrack = videoTrack
    }

    // MARK: - SDP Offer / Answer

    func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true",
            ],
            optionalConstraints: nil
        )
        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp, error == nil else {
                logger.error("webrtc: Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                return
            }
            self.peerConnection?.setLocalDescription(sdp) { error in
                if let error {
                    logger.error("webrtc: Failed to set local description: \(error.localizedDescription)")
                    return
                }
                self.delegate?.webRTCService(self, didCreateLocalSDP: sdp)
            }
        }
    }

    func createAnswer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true",
            ],
            optionalConstraints: nil
        )
        peerConnection?.answer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp, error == nil else {
                logger.error("webrtc: Failed to create answer: \(error?.localizedDescription ?? "unknown")")
                return
            }
            self.peerConnection?.setLocalDescription(sdp) { error in
                if let error {
                    logger.error("webrtc: Failed to set local description: \(error.localizedDescription)")
                    return
                }
                self.delegate?.webRTCService(self, didCreateLocalSDP: sdp)
            }
        }
    }

    func setRemoteDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        peerConnection?.setRemoteDescription(sdp) { [weak self] error in
            guard let self else {
                completion(error)
                return
            }
            if error == nil {
                self.hasRemoteDescription = true
                // Flush any ICE candidates that arrived before the remote description
                let pending = self.pendingIceCandidates
                self.pendingIceCandidates.removeAll()
                if !pending.isEmpty {
                    print("🔔 [PIP] Flushing \(pending.count) queued ICE candidates")
                }
                for candidate in pending {
                    self.peerConnection?.add(candidate) { error in
                        if let error {
                            print("🔔 [PIP] ⚠️ Failed to add queued ICE candidate: \(error.localizedDescription)")
                        }
                    }
                }
            }
            completion(error)
        }
    }

    func addIceCandidate(_ candidate: RTCIceCandidate, completion: @escaping (Error?) -> Void) {
        if hasRemoteDescription {
            peerConnection?.add(candidate, completionHandler: completion)
        } else {
            // Queue until remote description is set
            pendingIceCandidates.append(candidate)
            print("🔔 [PIP] Queued ICE candidate (no remote description yet), queue size=\(pendingIceCandidates.count)")
            completion(nil)
        }
    }

    // MARK: - Mute / Camera Controls

    func setAudioEnabled(_ enabled: Bool) {
        localAudioTrack?.isEnabled = enabled
    }

    func setVideoEnabled(_ enabled: Bool) {
        localVideoTrack?.isEnabled = enabled
    }

    /// Set the remote audio playback volume (0.0–10.0, where 1.0 is unity).
    /// This controls what the streamer hears through the speaker.
    func setRemoteAudioVolume(_ volume: Double) {
        remoteAudioTrack?.source.volume = volume
    }

    // MARK: - WebRTC Bitrate Control

    func setMaxBitrate(_ bps: Int) {
        guard let sender = peerConnection?.senders
            .first(where: { $0.track?.kind == "video" })
        else { return }
        let params = sender.parameters
        if let encoding = params.encodings.first {
            encoding.maxBitrateBps = NSNumber(value: bps)
        }
        sender.parameters = params
    }

    // MARK: - Data Channel (Heartbeat)

    private func setupDataChannel() {
        let config = RTCDataChannelConfiguration()
        config.isOrdered = true
        config.isNegotiated = false
        guard let dc = peerConnection?.dataChannel(forLabel: "heartbeat", configuration: config) else {
            logger.warning("webrtc: Failed to create data channel")
            return
        }
        dc.delegate = self
        dataChannel = dc
    }

    func startHeartbeat() {
        stopHeartbeat()
        missedHeartbeats = 0
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeatPing()
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        missedHeartbeats = 0
    }

    private func sendHeartbeatPing() {
        guard let dc = dataChannel, dc.readyState == .open else {
            missedHeartbeats += 1
            checkHeartbeatTimeout()
            return
        }
        let data = "ping".data(using: .utf8)!
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        dc.sendData(buffer)
        missedHeartbeats += 1
        checkHeartbeatTimeout()
    }

    private func didReceiveHeartbeatPong() {
        missedHeartbeats = 0
    }

    private func checkHeartbeatTimeout() {
        if missedHeartbeats >= Self.maxMissedHeartbeats {
            logger.warning("webrtc: Missed \(missedHeartbeats) heartbeats — peer unresponsive")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.webRTCServiceDidLoseHeartbeat(self)
            }
        }
    }

    // MARK: - ICE Restart

    /// Send a hangup message via the WebRTC data channel for instant delivery (<100ms).
    /// Falls back silently if the data channel isn't open — Nostr DM hangup is the backup.
    func sendDataChannelHangup() {
        guard let dc = dataChannel, dc.readyState == .open else { return }
        let data = "hangup".data(using: .utf8)!
        dc.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    /// Attempt an ICE restart to recover from a transient network change.
    /// Returns false if max restarts exceeded.
    func attemptIceRestart() -> Bool {
        guard iceRestartCount < Self.maxIceRestarts else {
            logger.warning("webrtc: Max ICE restarts (\(Self.maxIceRestarts)) exceeded")
            return false
        }
        guard let pc = peerConnection else { return false }

        iceRestartCount += 1
        logger.info("webrtc: Attempting ICE restart #\(iceRestartCount)")

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "IceRestart": "true",
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true",
            ],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp, error == nil else {
                logger.error("webrtc: ICE restart offer failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            self.peerConnection?.setLocalDescription(sdp) { error in
                if let error {
                    logger.error("webrtc: ICE restart set local desc failed: \(error.localizedDescription)")
                    return
                }
                self.delegate?.webRTCService(self, didCreateLocalSDP: sdp)
            }
        }
        return true
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        logger.info("webrtc: Signaling state changed: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("🔔 [PIP] peerConnection didAdd stream — videoTracks=\(stream.videoTracks.count), audioTracks=\(stream.audioTracks.count)")

        // Store remote audio track for volume control
        if let audioTrack = stream.audioTracks.first {
            remoteAudioTrack = audioTrack
            print("🔔 [PIP] Remote audio track stored: enabled=\(audioTrack.isEnabled), id=\(audioTrack.trackId)")
        }

        if let videoTrack = stream.videoTracks.first {
            print("🔔 [PIP] Remote video track: enabled=\(videoTrack.isEnabled), state=\(videoTrack.readyState.rawValue), id=\(videoTrack.trackId)")
            print("🔔 [PIP] Attaching remoteVideoRenderer to remote video track")
            videoTrack.add(remoteVideoRenderer)
            remoteVideoTrack = videoTrack

            // Log all transceivers
            for (i, t) in peerConnection.transceivers.enumerated() {
                let kind = t.mediaType == .video ? "video" : "audio"
                print("🔔 [PIP] Transceiver[\(i)] \(kind): direction=\(t.direction.rawValue), sender.track=\(t.sender.track?.trackId ?? "nil"), receiver.track=\(t.receiver.track?.trackId ?? "nil")")
            }

            // Log local video track state
            if let localVT = localVideoTrack {
                print("🔔 [PIP] Local video track: enabled=\(localVT.isEnabled), state=\(localVT.readyState.rawValue), source=\(localVT.source)")
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.webRTCService(self, didReceiveRemoteVideoTrack: videoTrack)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        logger.info("webrtc: Remote stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        logger.info("webrtc: Negotiation needed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        logger.info("webrtc: ICE connection state: \(newState.rawValue)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.webRTCService(self, didChangeIceState: newState)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        logger.info("webrtc: ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.webRTCService(self, didGenerateCandidate: candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.info("webrtc: ICE candidates removed: \(candidates.count)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.info("webrtc: Data channel opened: \(dataChannel.label)")
        // Remote peer's data channel — set delegate to receive heartbeat pings
        if dataChannel.label == "heartbeat" {
            dataChannel.delegate = self
            self.dataChannel = dataChannel
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        logger.info("webrtc: Connection state: \(stateChanged.rawValue)")

        if stateChanged == .connected {
            // Log stats after connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let pc = self.peerConnection else { return }
                pc.statistics { report in
                    for (key, stats) in report.statistics {
                        if key.contains("RTCOutboundRTP") || key.contains("RTCInboundRTP") {
                            print("🔔 [PIP] Stats: \(key) = \(stats.values)")
                        }
                    }
                    // Also check sender/receiver
                    for sender in pc.senders {
                        print("🔔 [PIP] Sender: kind=\(sender.track?.kind ?? "nil"), enabled=\(sender.track?.isEnabled ?? false), trackId=\(sender.track?.trackId ?? "nil")")
                    }
                    for receiver in pc.receivers {
                        print("🔔 [PIP] Receiver: kind=\(receiver.track?.kind ?? "nil"), enabled=\(receiver.track?.isEnabled ?? false), trackId=\(receiver.track?.trackId ?? "nil")")
                    }
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.webRTCService(self, didChangeState: stateChanged)
        }
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCService: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        logger.info("webrtc: Data channel state: \(dataChannel.readyState.rawValue)")
        if dataChannel.readyState == .open {
            startHeartbeat()
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let message = String(data: buffer.data, encoding: .utf8) else { return }
        if message == "ping" {
            // Respond with pong
            let pong = RTCDataBuffer(data: "pong".data(using: .utf8)!, isBinary: false)
            dataChannel.sendData(pong)
        } else if message == "pong" {
            didReceiveHeartbeatPong()
        } else if message == "hangup" {
            // Peer sent hangup via data channel — instant delivery
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.webRTCServiceDidReceiveHangup(self)
            }
        }
    }
}

// MARK: - VideoUnitBridgeCapturer

/// Bridges Swae's existing camera pipeline (VideoUnit) into WebRTC without opening
/// a second camera session. The host's VideoUnit calls pushFrame() each frame via
/// the onRawFrameCaptured callback. This is dispatched off the pipeline queue to
/// avoid blocking — see Performance Analysis P1.
final class VideoUnitBridgeCapturer: RTCVideoCapturer {
    private let videoSource: RTCVideoSource
    private var frameCount: UInt64 = 0
    private var hasLoggedFirstFrame = false
    private var lastWidth: Int = 0
    private var lastHeight: Int = 0

    /// Max FPS to send to the guest. Defaults to 15 to reduce encoder contention (P8).
    var maxFps: Int = 15
    private var frameSkip: UInt64 { UInt64(max(1, 30 / maxFps)) }

    /// When true, the buffer is post-effects (already in correct orientation) — use ._0.
    /// When false, the buffer is raw camera (sensor landscape) — use ._90 for portrait.
    var postEffectsMode: Bool = true

    init(videoSource: RTCVideoSource) {
        self.videoSource = videoSource
        super.init(delegate: videoSource)
    }

    /// Reset frame counter after camera reattach so the first frames aren't
    /// skipped by frameSkip logic. Called before reattachCamera() during collab.
    func resetForReattach() {
        frameCount = 0
        hasLoggedFirstFrame = false
        // Clear tracked dimensions so the next frame triggers adaptOutputFormat
        lastWidth = 0
        lastHeight = 0
    }

    /// Called from webrtcBridgeQueue (NOT processorPipelineQueue) with the raw camera buffer.
    /// The CVPixelBuffer is IOSurface-backed — zero-copy across queues.
    func pushFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        frameCount += 1
        guard frameCount % frameSkip == 0 else { return }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)

        // Detect dimension change and re-adapt the video source.
        // Without this, WebRTC's H264 encoder permanently stalls when frame
        // dimensions change (orientation switch, resolution change, etc.)
        // because the internal frame adapter was configured for the old size.
        // Always use 1280x720 target — adaptOutputFormat is orientation-agnostic
        // and will adjust to maintain the input orientation automatically.
        if w != lastWidth || h != lastHeight {
            lastWidth = w
            lastHeight = h
            videoSource.adaptOutputFormat(toWidth: 1280, height: 720, fps: 30)
            print("🔔 [PIP] Frame dimensions changed to \(w)x\(h) — re-adapted to 1280x720")
        }

        // Log first few frames and periodically for diagnostics
        if frameCount <= 5 * frameSkip || frameCount % (50 * frameSkip) == 0 {
            print("🔔 [PIP] BridgeCapturer.pushFrame #\(frameCount) — \(w)x\(h), ts=\(String(format: "%.3f", timestamp.seconds))")
        }

        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = Int64(timestamp.seconds * 1_000_000_000)
        // Post-effects buffer is already in correct orientation → ._0
        // Raw camera buffer: check if the buffer is portrait (height > width).
        // If so, it's already been rotated by AVCaptureConnection → ._0.
        // If landscape (width >= height), it's in the correct orientation → ._0.
        // In all cases the buffer we receive is already correctly oriented
        // (either by the effects pipeline or by AVCaptureConnection.videoOrientation).
        let rotation: RTCVideoRotation = ._0
        let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: rotation, timeStampNs: timeStampNs)
        delegate?.capturer(self, didCapture: frame)
    }
}

// MARK: - PixelBufferVideoRenderer

/// Captures remote WebRTC video frames as CVPixelBuffer for the GuestVideoCompositor.
/// WebRTC's decoder thread writes via renderFrame(), the processorPipelineQueue reads
/// via getLatestBuffer(). Protected by os_unfair_lock (hold time ~10ns, contention negligible).
final class PixelBufferVideoRenderer: NSObject, RTCVideoRenderer {
    private var _latestPixelBuffer: CVPixelBuffer?
    private var _lock = os_unfair_lock()

    func setSize(_ size: CGSize) {
        // Required by protocol. No-op — we don't need to resize.
    }

    private var _frameCount: Int = 0

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        _frameCount += 1
        if _frameCount <= 5 || _frameCount % 30 == 0 {
            print("🎥🎥🎥 REMOTE FRAME #\(_frameCount) — \(frame.width)x\(frame.height) type=\(type(of: frame.buffer))")
        }
        if let cvBuffer = frame.buffer as? RTCCVPixelBuffer {
            os_unfair_lock_lock(&_lock)
            _latestPixelBuffer = cvBuffer.pixelBuffer
            os_unfair_lock_unlock(&_lock)
        } else {
            if _frameCount <= 5 {
                print("🎥🎥🎥 REMOTE FRAME is NOT RTCCVPixelBuffer — type=\(type(of: frame.buffer)), DROPPED")
            }
        }
    }

    func getLatestBuffer() -> CVPixelBuffer? {
        os_unfair_lock_lock(&_lock)
        let buffer = _latestPixelBuffer
        os_unfair_lock_unlock(&_lock)
        return buffer
    }
}

// MARK: - RTCAudioSession Configuration

extension WebRTCService {
    /// Configure RTCAudioSession for manual audio management.
    /// Call this BEFORE connect() to prevent WebRTC from reconfiguring AVAudioSession.
    static func configureAudioSession() {
        // Override WebRTC's default audio session config.
        // WebRTC defaults to .voiceChat mode which routes audio to the earpiece.
        // .videoChat mode routes to the loud speaker, which is correct for a
        // streaming app where the user is not holding the phone to their ear.
        let config = RTCAudioSessionConfiguration()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.categoryOptions = [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
        config.mode = AVAudioSession.Mode.videoChat.rawValue
        RTCAudioSessionConfiguration.setWebRTC(config)

        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.lockForConfiguration()
        rtcAudioSession.useManualAudio = true
        rtcAudioSession.isAudioEnabled = true
        // Belt-and-suspenders: explicitly override output to speaker in case
        // the VPIO still tries to route to the earpiece after initialization.
        try? rtcAudioSession.overrideOutputAudioPort(.speaker)
        rtcAudioSession.unlockForConfiguration()
    }
}
