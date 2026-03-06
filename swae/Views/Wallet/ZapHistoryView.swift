//
//  ZapHistoryView.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct ZapHistoryView: View {
    @ObservedObject var appState: AppState
    @State private var zapHistory: [NostrEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading zap history...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if zapHistory.isEmpty {
                    EmptyZapHistoryView()
                } else {
                    ZapHistoryListView(zapHistory: zapHistory)
                }
            }
            .navigationTitle("Zap History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshZapHistory) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                loadZapHistory()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func loadZapHistory() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Get zap receipts that we've sent
                let sentZaps = appState.zapReceipts.filter { zapReceipt in
                    // Filter for zaps sent by us (check if we're the sender)
                    zapReceipt.pubkey == appState.keypair?.publicKey.hex
                }

                // Get zap requests that we've received
                let receivedZaps = appState.zapRequests.filter { zapRequest in
                    // Filter for zaps received by us (check if we're the recipient)
                    zapRequest.recipientPubkey == appState.keypair?.publicKey.hex
                }

                // Combine and sort by timestamp
                let allZaps = (sentZaps + receivedZaps).sorted { $0.createdAt > $1.createdAt }

                await MainActor.run {
                    self.zapHistory = allZaps
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load zap history: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func refreshZapHistory() {
        loadZapHistory()
    }
}

struct EmptyZapHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 64))
                .foregroundColor(.orange.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Zaps Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(
                    "Your zap history will appear here once you start sending or receiving Lightning payments."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ZapHistoryListView: View {
    let zapHistory: [NostrEvent]

    var body: some View {
        List(zapHistory, id: \.id) { zap in
            ZapHistoryRowView(zap: zap)
        }
        .listStyle(PlainListStyle())
    }
}

struct ZapHistoryRowView: View {
    let zap: NostrEvent
    @State private var showZapDetails = false

    var isSentZap: Bool {
        zap is LightningZapsReceiptEvent
    }

    var amount: Int64 {
        if let zapReceipt = zap as? LightningZapsReceiptEvent {
            return Int64(zapReceipt.description?.amount ?? 0)
        } else if let zapRequest = zap as? LightningZapRequestEvent {
            return Int64(zapRequest.amount ?? 0)
        }
        return 0
    }

    var content: String {
        return zap.content
    }

    var recipientPubkey: String {
        if let zapReceipt = zap as? LightningZapsReceiptEvent {
            return zapReceipt.recipientPubkey ?? ""
        } else if let zapRequest = zap as? LightningZapRequestEvent {
            return zapRequest.recipientPubkey ?? ""
        }
        return ""
    }

    var senderPubkey: String {
        return zap.pubkey
    }

    var body: some View {
        Button(action: {
            showZapDetails = true
        }) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: isSentZap ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isSentZap ? .red : .green)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(isSentZap ? "Sent Zap" : "Received Zap")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(amount / 1000) sats")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(isSentZap ? .red : .green)
                    }

                    if !content.isEmpty {
                        Text(content)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Text(formatTimestamp(zap.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showZapDetails) {
            ZapDetailsView(zap: zap)
        }
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ZapDetailsView: View {
    let zap: NostrEvent
    @Environment(\.dismiss) private var dismiss

    var isSentZap: Bool {
        zap is LightningZapsReceiptEvent
    }

    var amount: Int64 {
        if let zapReceipt = zap as? LightningZapsReceiptEvent {
            return Int64(zapReceipt.description?.amount ?? 0)
        } else if let zapRequest = zap as? LightningZapRequestEvent {
            return Int64(zapRequest.amount ?? 0)
        }
        return 0
    }

    var content: String {
        return zap.content
    }

    var recipientPubkey: String {
        if let zapReceipt = zap as? LightningZapsReceiptEvent {
            return zapReceipt.recipientPubkey ?? ""
        } else if let zapRequest = zap as? LightningZapRequestEvent {
            return zapRequest.recipientPubkey ?? ""
        }
        return ""
    }

    var senderPubkey: String {
        return zap.pubkey
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 16) {
                        Image(
                            systemName: isSentZap
                                ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                        )
                        .font(.system(size: 48))
                        .foregroundColor(isSentZap ? .red : .green)

                        VStack(spacing: 8) {
                            Text(isSentZap ? "Sent Zap" : "Received Zap")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("\(amount / 1000) sats")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(isSentZap ? .red : .green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        ZapDetailRow(title: "Type", value: isSentZap ? "Outgoing" : "Incoming")
                        ZapDetailRow(
                            title: "Amount",
                            value: "\(amount / 1000) sats (\(formatAmountInUSD(amount)))")
                        ZapDetailRow(title: "Date", value: formatTimestamp(zap.createdAt))

                        if !content.isEmpty {
                            ZapDetailRow(title: "Message", value: content)
                        }

                        ZapDetailRow(title: "Transaction ID", value: zap.id.prefix(16) + "...")

                        if isSentZap {
                            ZapDetailRow(
                                title: "Recipient", value: recipientPubkey.prefix(16) + "...")
                        } else {
                            ZapDetailRow(title: "Sender", value: senderPubkey.prefix(16) + "...")
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Zap Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatAmountInUSD(_ amountInMillisats: Int64) -> String {
        // This is a placeholder - in a real app you'd fetch the current BTC price
        let sats = Double(amountInMillisats) / 1000.0
        let btcPrice = 50000.0  // Placeholder BTC price
        let usdAmount = sats / 100_000_000.0 * btcPrice
        return String(format: "$%.2f", usdAmount)
    }
}

struct ZapDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.body)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    ZapHistoryView(
        appState: AppState(modelContext: ModelContext(try! ModelContainer(for: AppSettings.self))))
}
