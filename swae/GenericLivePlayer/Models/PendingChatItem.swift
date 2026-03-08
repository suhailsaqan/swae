//
//  PendingChatItem.swift
//  swae
//
//  Models for optimistic chat display with pending states
//

import Foundation

enum PendingChatStatus: Equatable {
    case sending
    case confirmed   // Relay accepted (OK received), waiting for echo-back
    case failed(error: String)
}

struct PendingChatMessage: Equatable {
    let localId: String          // UUID for tracking
    var eventId: String?         // Nostr event ID (var — updated on retry with new ID after re-signing)
    let pubkey: String           // Sender's pubkey
    let content: String          // Message text
    let createdAt: Int64         // Timestamp
    var status: PendingChatStatus
}

struct PendingChatZap: Equatable {
    let localId: String          // UUID for tracking
    let senderPubkey: String     // Sender's pubkey
    let recipientPubkey: String  // Recipient's pubkey
    let amount: Int64            // Amount in millisats
    let content: String?         // Optional zap message
    let createdAt: Int64         // Timestamp
    let eventCoordinate: String? // Stream coordinate
    var status: PendingChatStatus
}
