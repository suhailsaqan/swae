//
//  ZapAttachment.swift
//  swae
//
//  Model representing a pending zap attachment in the chat input bar
//

import Foundation

/// Represents a pending zap attachment in the input bar
struct ZapAttachment {
    let amount: Int64           // In millisats
    let targetPubkey: String
    let eventCoordinate: String?
    
    var satsAmount: Int64 { amount / 1000 }
    
    var displayText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: satsAmount)) ?? "\(satsAmount)"
        return "⚡ \(formatted) sats"
    }
    
    /// Format amount for display (without the bolt emoji)
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: satsAmount)) ?? "\(satsAmount)"
    }
}
