//
//  WalletTransaction.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import Foundation

struct WalletTransaction: Identifiable, Hashable {
    let id: String
    let type: TransactionType
    let amount: Int64  // in millisats
    let description: String?
    let createdAt: Int64
    let paymentHash: String?
    let preimage: String?
    let feesPaid: Int64?
    let settledAt: Int64?
    let expiresAt: Int64?

    enum TransactionType: String, CaseIterable {
        case incoming = "incoming"
        case outgoing = "outgoing"

        var displayName: String {
            switch self {
            case .incoming:
                return "Received"
            case .outgoing:
                return "Sent"
            }
        }

        var icon: String {
            switch self {
            case .incoming:
                return "arrow.down.left"
            case .outgoing:
                return "arrow.up.right"
            }
        }

        var color: String {
            switch self {
            case .incoming:
                return "green"
            case .outgoing:
                return "orange"
            }
        }
    }

    // MARK: - Computed Properties

    var isIncoming: Bool {
        return type == .incoming
    }

    var formattedAmount: String {
        let sats = amount / 1000  // Convert millisats to sats
        return formatSats(sats)
    }

    var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(createdAt))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var displayDescription: String {
        if let description = description, !description.isEmpty {
            return description
        }
        return isIncoming ? "Received" : "Sent"
    }
}

// MARK: - Mock Data for Preview

extension WalletTransaction {
    static let mockTransactions: [WalletTransaction] = [
        WalletTransaction(
            id: "1",
            type: .incoming,
            amount: 5_000_000,  // 5000 sats
            description: "Zap from @alice",
            createdAt: Int64(Date().timeIntervalSince1970 - 3600),  // 1 hour ago
            paymentHash: "abc123",
            preimage: "def456",
            feesPaid: 1000,
            settledAt: Int64(Date().timeIntervalSince1970 - 3600),
            expiresAt: nil
        ),
        WalletTransaction(
            id: "2",
            type: .outgoing,
            amount: 2_100_000,  // 2100 sats
            description: "Zap to @bob",
            createdAt: Int64(Date().timeIntervalSince1970 - 7200),  // 2 hours ago
            paymentHash: "ghi789",
            preimage: "jkl012",
            feesPaid: 500,
            settledAt: Int64(Date().timeIntervalSince1970 - 7200),
            expiresAt: nil
        ),
        WalletTransaction(
            id: "3",
            type: .incoming,
            amount: 10_000_000,  // 10000 sats
            description: "Lightning payment",
            createdAt: Int64(Date().timeIntervalSince1970 - 86400),  // 1 day ago
            paymentHash: "mno345",
            preimage: "pqr678",
            feesPaid: 2000,
            settledAt: Int64(Date().timeIntervalSince1970 - 86400),
            expiresAt: nil
        ),
        WalletTransaction(
            id: "4",
            type: .outgoing,
            amount: 1_500_000,  // 1500 sats
            description: "Payment for services",
            createdAt: Int64(Date().timeIntervalSince1970 - 172800),  // 2 days ago
            paymentHash: "stu901",
            preimage: "vwx234",
            feesPaid: 300,
            settledAt: Int64(Date().timeIntervalSince1970 - 172800),
            expiresAt: nil
        ),
    ]
}
