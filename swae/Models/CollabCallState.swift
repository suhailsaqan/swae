//
//  CollabCallState.swift
//  swae
//
//  Call state for WebRTC live collaborative streaming.
//

import Foundation

enum CollabCallState: Equatable {
    case idle
    case inviteSent(guestPubkey: String, callId: String)
    case inviteReceived(hostPubkey: String, callId: String, streamTitle: String)
    case connecting(callId: String)
    case connected(callId: String)
    case failed(reason: String)
    case ended(reason: String)

    var isActive: Bool {
        switch self {
        case .inviteSent, .inviteReceived, .connecting, .connected:
            return true
        case .idle, .failed, .ended:
            return false
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
