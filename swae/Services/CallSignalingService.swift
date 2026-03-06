//
//  CallSignalingService.swift
//  swae
//
//  Nostr DM-based signaling for WebRTC collaborative streaming.
//  Encrypts/decrypts signaling messages (SDP offers, answers, ICE candidates,
//  invites) using NIP-04 and publishes them as kind 4 events.
//

import Foundation
import NostrSDK
import WebRTC

// MARK: - Signaling Message Types

struct WebRTCSignalMessage: Codable {
    let type: String  // Always "webrtc-signal"
    let version: Int
    let callId: String
    let signalType: SignalType
    let payload: SignalPayload

    enum SignalType: String, Codable {
        case invite
        case accept
        case reject
        case offer
        case answer
        case iceCandidate = "ice-candidate"
        case hangup
    }

    enum CodingKeys: String, CodingKey {
        case type, version
        case callId = "call_id"
        case signalType = "signal_type"
        case payload
    }
}

struct SignalPayload: Codable {
    // For invite
    var streamTitle: String?
    var streamId: String?

    // For offer/answer
    var sdp: String?
    var sdpType: String?  // "offer" or "answer"

    // For ice-candidate
    var candidate: String?
    var sdpMid: String?
    var sdpMLineIndex: Int32?

    enum CodingKeys: String, CodingKey {
        case streamTitle = "stream_title"
        case streamId = "stream_id"
        case sdp
        case sdpType = "sdp_type"
        case candidate
        case sdpMid
        case sdpMLineIndex
    }
}

// MARK: - Delegate

protocol CallSignalingServiceDelegate: AnyObject {
    func signalingService(_ service: CallSignalingService, didReceiveInvite message: WebRTCSignalMessage, from pubkey: String)
    func signalingService(_ service: CallSignalingService, didReceiveAccept message: WebRTCSignalMessage, from pubkey: String)
    func signalingService(_ service: CallSignalingService, didReceiveReject message: WebRTCSignalMessage, from pubkey: String)
    func signalingService(_ service: CallSignalingService, didReceiveOffer sdp: RTCSessionDescription, callId: String, from pubkey: String)
    func signalingService(_ service: CallSignalingService, didReceiveAnswer sdp: RTCSessionDescription, callId: String, from pubkey: String)
    func signalingService(_ service: CallSignalingService, didReceiveIceCandidate candidate: RTCIceCandidate, callId: String, from pubkey: String)
    func signalingService(_ service: CallSignalingService, didReceiveHangup callId: String, from pubkey: String)
}

// MARK: - CallSignalingService

final class CallSignalingService: EventCreating {
    weak var delegate: CallSignalingServiceDelegate?
    private weak var appState: AppState?

    /// Cache successful y-coordinate prefix per peer to avoid double-decrypt (P10)
    private var peerYPrefixCache: [String: Bool] = [:]

    /// Dedup: skip events we've already processed (from polling overlap or multiple relays)
    private var processedEventIds: Set<String> = []
    private static let maxProcessedEventIds = 1000

    /// Active subscription ID for kind 4 events
    private var signalingSubscriptionId: String?

    init(appState: AppState) {
        self.appState = appState
    }

    deinit {
        stopListening()
    }

    // MARK: - Subscription Management

    /// Start listening for kind 4 events addressed to the local user.
    func startListening() {
        guard let appState, let publicKey = appState.publicKey else {
            logger.error("call-signaling: Cannot start listening — no public key")
            return
        }
        // Don't double-subscribe
        guard signalingSubscriptionId == nil else { return }

        guard let filter = Filter(
            kinds: [EventKind.legacyEncryptedDirectMessage.rawValue],
            pubkeys: [publicKey.hex],
            since: Int(Date().addingTimeInterval(-30).timeIntervalSince1970)
        ) else {
            logger.error("call-signaling: Failed to create filter")
            return
        }
        signalingSubscriptionId = appState.relayReadPool.subscribe(with: filter)
        logger.info("call-signaling: Subscribed for kind 4 events, subId=\(signalingSubscriptionId ?? "nil")")
    }

    /// Stop listening for signaling events.
    func stopListening() {
        if let subId = signalingSubscriptionId {
            appState?.relayReadPool.closeSubscription(with: subId)
            signalingSubscriptionId = nil
            logger.info("call-signaling: Unsubscribed from kind 4 events")
        }
        peerYPrefixCache.removeAll()
    }

    // MARK: - Receiving

    /// Called by AppState when a kind 4 event arrives. Decrypts and routes.
    func didReceiveEncryptedDM(_ event: NostrEvent) {
        // Dedup: skip events we've already processed
        guard !processedEventIds.contains(event.id) else { return }
        processedEventIds.insert(event.id)
        if processedEventIds.count > Self.maxProcessedEventIds {
            // Evict oldest entries by clearing half the set
            processedEventIds.removeAll()
        }

        // Skip self-sent events — we never send collab signals to ourselves
        guard event.pubkey != appState?.publicKey?.hex else { return }

        print("🔔 [COLLAB] didReceiveEncryptedDM called — eventId=\(event.id.prefix(8)), sender=\(event.pubkey.prefix(8))")
        guard let appState, let keypair = appState.keypair else {
            print("🔔 [COLLAB] ⚠️ No appState or keypair — cannot decrypt")
            return
        }
        let senderPubkey = event.pubkey

        // Decrypt using NIP04DecryptionHelper (handles y-coordinate prefix fallback)
        guard let senderPublicKey = PublicKey(hex: senderPubkey) else {
            print("🔔 [COLLAB] ⚠️ Invalid sender pubkey: \(senderPubkey.prefix(16))")
            return
        }

        let decrypted: String
        do {
            decrypted = try NIP04DecryptionHelper.decryptWithFallback(
                encryptedMessage: event.content,
                senderPublicKey: senderPublicKey,
                recipientPrivateKey: keypair.privateKey
            )
            print("🔔 [COLLAB] ✅ Decrypted content (first 100 chars): \(String(decrypted.prefix(100)))")
        } catch {
            // Not a message we can decrypt — likely not for us or not NIP-04
            print("🔔 [COLLAB] ⚠️ Decryption failed: \(error.localizedDescription)")
            return
        }

        // Parse JSON
        guard let data = decrypted.data(using: .utf8) else {
            print("🔔 [COLLAB] ⚠️ Could not convert decrypted string to Data")
            return
        }

        let message: WebRTCSignalMessage
        do {
            message = try JSONDecoder().decode(WebRTCSignalMessage.self, from: data)
        } catch {
            // Not a webrtc-signal message — ignore silently
            print("🔔 [COLLAB] Not a webrtc-signal message (decode failed: \(error.localizedDescription)). Raw: \(String(decrypted.prefix(200)))")
            return
        }

        // Verify it's our protocol
        guard message.type == "webrtc-signal", message.version == 1 else {
            print("🔔 [COLLAB] ⚠️ Wrong type/version: type=\(message.type), version=\(message.version)")
            return
        }

        print("🔔 [COLLAB] ✅ Valid signal: \(message.signalType.rawValue) callId=\(message.callId.prefix(8)) from=\(senderPubkey.prefix(8)), delegate=\(delegate != nil ? "SET" : "NIL")")

        // Route to delegate
        switch message.signalType {
        case .invite:
            delegate?.signalingService(self, didReceiveInvite: message, from: senderPubkey)
        case .accept:
            delegate?.signalingService(self, didReceiveAccept: message, from: senderPubkey)
        case .reject:
            delegate?.signalingService(self, didReceiveReject: message, from: senderPubkey)
        case .offer:
            if let sdpString = message.payload.sdp {
                let sdp = RTCSessionDescription(type: .offer, sdp: sdpString)
                delegate?.signalingService(self, didReceiveOffer: sdp, callId: message.callId, from: senderPubkey)
            }
        case .answer:
            if let sdpString = message.payload.sdp {
                let sdp = RTCSessionDescription(type: .answer, sdp: sdpString)
                delegate?.signalingService(self, didReceiveAnswer: sdp, callId: message.callId, from: senderPubkey)
            }
        case .iceCandidate:
            if let candidateString = message.payload.candidate {
                let candidate = RTCIceCandidate(
                    sdp: candidateString,
                    sdpMLineIndex: message.payload.sdpMLineIndex ?? 0,
                    sdpMid: message.payload.sdpMid
                )
                delegate?.signalingService(self, didReceiveIceCandidate: candidate, callId: message.callId, from: senderPubkey)
            }
        case .hangup:
            delegate?.signalingService(self, didReceiveHangup: message.callId, from: senderPubkey)
        }
    }

    // MARK: - Sending

    /// Send an invite to a guest.
    func sendInvite(to guestPubkey: String, callId: String, streamTitle: String, streamId: String?) {
        let message = WebRTCSignalMessage(
            type: "webrtc-signal",
            version: 1,
            callId: callId,
            signalType: .invite,
            payload: SignalPayload(streamTitle: streamTitle, streamId: streamId)
        )
        send(message, to: guestPubkey)
    }

    /// Send accept response.
    func sendAccept(to hostPubkey: String, callId: String) {
        let message = WebRTCSignalMessage(
            type: "webrtc-signal",
            version: 1,
            callId: callId,
            signalType: .accept,
            payload: SignalPayload()
        )
        send(message, to: hostPubkey)
    }

    /// Send reject response.
    func sendReject(to hostPubkey: String, callId: String) {
        let message = WebRTCSignalMessage(
            type: "webrtc-signal",
            version: 1,
            callId: callId,
            signalType: .reject,
            payload: SignalPayload()
        )
        send(message, to: hostPubkey)
    }

    /// Send SDP offer.
    func sendOffer(_ sdp: RTCSessionDescription, to peerPubkey: String, callId: String) {
        let message = WebRTCSignalMessage(
            type: "webrtc-signal",
            version: 1,
            callId: callId,
            signalType: .offer,
            payload: SignalPayload(sdp: sdp.sdp, sdpType: "offer")
        )
        send(message, to: peerPubkey)
    }

    /// Send SDP answer.
    func sendAnswer(_ sdp: RTCSessionDescription, to peerPubkey: String, callId: String) {
        let message = WebRTCSignalMessage(
            type: "webrtc-signal",
            version: 1,
            callId: callId,
            signalType: .answer,
            payload: SignalPayload(sdp: sdp.sdp, sdpType: "answer")
        )
        send(message, to: peerPubkey)
    }

    /// Send ICE candidate.
    func sendIceCandidate(_ candidate: RTCIceCandidate, to peerPubkey: String, callId: String) {
        let message = WebRTCSignalMessage(
            type: "webrtc-signal",
            version: 1,
            callId: callId,
            signalType: .iceCandidate,
            payload: SignalPayload(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex
            )
        )
        send(message, to: peerPubkey)
    }

    /// Send hangup.
    func sendHangup(to peerPubkey: String, callId: String) {
        let message = WebRTCSignalMessage(
            type: "webrtc-signal",
            version: 1,
            callId: callId,
            signalType: .hangup,
            payload: SignalPayload()
        )
        send(message, to: peerPubkey)
    }

    // MARK: - Private: Encrypt + Publish

    private func send(_ message: WebRTCSignalMessage, to recipientPubkey: String) {
        guard let appState, let keypair = appState.keypair else {
            logger.error("call-signaling: Cannot send — no keypair")
            return
        }
        guard let recipientPublicKey = PublicKey(hex: recipientPubkey) else {
            logger.error("call-signaling: Invalid recipient pubkey")
            return
        }

        // Serialize to JSON
        guard let jsonData = try? JSONEncoder().encode(message),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            logger.error("call-signaling: Failed to serialize message")
            return
        }

        // Create kind 4 event using the SDK's EventCreating factory.
        // This handles NIP-04 encryption + event signing in one call.
        do {
            let event = try legacyEncryptedDirectMessage(
                withContent: jsonString,
                toRecipient: recipientPublicKey,
                signedBy: keypair
            )
            // Publish to user's write relays
            appState.relayWritePool.publishEvent(event)
            // Also publish to dedicated signaling relays (many user relays block kind 4)
            for relay in appState.collabSignalingRelays where relay.state == .connected {
                try? relay.publishEvent(event)
            }
            print("🔔 [COLLAB] Sent \(message.signalType.rawValue) to \(recipientPubkey.prefix(8))... (write pool + \(appState.collabSignalingRelays.filter { $0.state == .connected }.count) signaling relays)")
        } catch {
            print("🔔 [COLLAB] ⚠️ Failed to create/sign event: \(error.localizedDescription)")
        }
    }
}
