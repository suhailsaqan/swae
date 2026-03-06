//
//  ZapFeedView.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct ZapFeedView: View {
    @ObservedObject var appState: AppState
    @StateObject private var zapFeedService = ZapFeedService()
    @State private var selectedFilter: ZapFilter = .all
    @State private var showZapComposer = false

    enum ZapFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case received = "Received"
        case recent = "Recent"
    }

    var filteredZaps: [NostrEvent] {
        let currentTime = Int64(Date().timeIntervalSince1970)
        let oneHourAgo = currentTime - 3600

        switch selectedFilter {
        case .all:
            return zapFeedService.zapFeed
        case .sent:
            return zapFeedService.zapFeed.filter { $0 is LightningZapsReceiptEvent }
        case .received:
            return zapFeedService.zapFeed.filter { $0 is LightningZapRequestEvent }
        case .recent:
            return zapFeedService.zapFeed.filter { $0.createdAt > oneHourAgo }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ZapFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                isSelected: selectedFilter == filter,
                                action: { selectedFilter = filter }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)

                // Zap feed
                if zapFeedService.zapFeed.isEmpty && !zapFeedService.isLoading {
                    EmptyZapFeedView()
                } else {
                    ZapFeedListView(
                        zaps: filteredZaps,
                        appState: appState,
                        isLoading: zapFeedService.isLoading
                    )
                }
            }
            .navigationTitle("Zap Feed")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showZapComposer = true
                    }) {
                        Image(systemName: "bolt.badge.plus")
                    }
                }
            }
            .onAppear {
                zapFeedService.startListening(appState: appState)
            }
            .onDisappear {
                zapFeedService.stopListening()
            }
            .sheet(isPresented: $showZapComposer) {
                ZapComposerView(appState: appState)
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.orange : Color.orange.opacity(0.15))
                )
        }
    }
}

struct EmptyZapFeedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.circle.dashed")
                .font(.system(size: 64))
                .foregroundColor(.orange.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Zaps Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Start zapping to see Lightning payments in your feed!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ZapFeedListView: View {
    let zaps: [NostrEvent]
    let appState: AppState
    let isLoading: Bool

    var body: some View {
        List {
            if isLoading && zaps.isEmpty {
                LoadingRowView()
            } else {
                ForEach(zaps, id: \.id) { zap in
                    ZapFeedRowView(zap: zap, appState: appState)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            // Trigger refresh of zap feed
            await refreshZapFeed()
        }
    }

    private func refreshZapFeed() async {
        // This would trigger a refresh of the zap feed
        // Implementation depends on how the ZapFeedService works
    }
}

struct LoadingRowView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Loading zaps...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }
}

struct ZapFeedRowView: View {
    let zap: NostrEvent
    let appState: AppState
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

    var senderPubkey: String {
        return zap.pubkey
    }

    var recipientPubkey: String {
        if let zapReceipt = zap as? LightningZapsReceiptEvent {
            return zapReceipt.recipientPubkey ?? ""
        } else if let zapRequest = zap as? LightningZapRequestEvent {
            return zapRequest.recipientPubkey ?? ""
        }
        return ""
    }

    var body: some View {
        Button(action: {
            showZapDetails = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with amount and timestamp
                HStack {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isSentZap
                                ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
                        )
                        .font(.system(size: 16))
                        .foregroundColor(isSentZap ? .red : .green)

                        Text("\(amount / 1000) sats")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(isSentZap ? .red : .green)
                    }

                    Spacer()

                    Text(formatTimestamp(zap.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Content
                if !content.isEmpty {
                    Text(content)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }

                // Action buttons
                HStack(spacing: 16) {
                    if !isSentZap {
                        // Show zap back button for received zaps
                        ZapBackButton(
                            targetPubkey: senderPubkey,
                            amount: amount,
                            appState: appState
                        )
                    }

                    Spacer()

                    // Copy transaction ID
                    Button(action: {
                        UIPasteboard.general.string = zap.id
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                            Text("Copy ID")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showZapDetails) {
            ZapDetailsView(zap: zap)
        }
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ZapBackButton: View {
    let targetPubkey: String
    let amount: Int64
    let appState: AppState

    @StateObject private var zapService: ZapService
    @State private var showAmountSelector = false
    @State private var selectedAmount: Int64

    init(targetPubkey: String, amount: Int64, appState: AppState) {
        self.targetPubkey = targetPubkey
        self.amount = amount
        self.appState = appState
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
        self._selectedAmount = State(initialValue: amount)
    }

    var body: some View {
        Button(action: {
            showAmountSelector = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                Text("Zap Back")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .disabled(zapService.isProcessingZap)
        .sheet(isPresented: $showAmountSelector) {
            ZapAmountSelectorView(
                selectedAmount: $selectedAmount,
                zapAmounts: [amount, amount * 2, amount * 5],
                onConfirm: { amount in
                    Task {
                        await sendZap(amount: amount)
                    }
                    showAmountSelector = false
                },
                onCancel: {
                    showAmountSelector = false
                }
            )
        }
    }

    private func sendZap(amount: Int64) async {
        let success = await zapService.sendZap(
            amount: amount,
            targetPubkey: targetPubkey,
            content: "Thanks for the zap! ⚡"
        )

        if !success {
            return
        }
    }
}

struct ZapComposerView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var targetPubkey: String = ""
    @State private var amount: Int64 = 1_000_000
    @State private var content: String = ""
    @State private var showQRScanner = false

    @StateObject private var zapService: ZapService

    init(appState: AppState) {
        self.appState = appState
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Target pubkey input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipient Pubkey")
                        .font(.headline)

                    HStack {
                        TextField("npub1...", text: $targetPubkey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: {
                            showQRScanner = true
                        }) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                        }
                    }
                }

                // Amount selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount")
                        .font(.headline)

                    HStack {
                        TextField("Amount in sats", value: $amount, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)

                        Text("sats")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message (Optional)")
                        .font(.headline)

                    TextField("Zap message...", text: $content, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                }

                Spacer()

                // Send button
                Button(action: sendZap) {
                    HStack {
                        if zapService.isProcessingZap {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "bolt.fill")
                        }

                        Text("Send Zap")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(targetPubkey.isEmpty || amount <= 0 ? Color.gray : Color.orange)
                    )
                }
                .disabled(targetPubkey.isEmpty || amount <= 0 || zapService.isProcessingZap)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Send Zap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRCodeScannerView { result in
                    if let pubkey = parsePubkeyFromQR(result) {
                        targetPubkey = pubkey
                    }
                    showQRScanner = false
                }
            }
            .onChange(of: zapService.zapSuccess) { success in
                if success {
                    dismiss()
                }
            }
        }
    }

    private func sendZap() {
        Task {
            let success = await zapService.sendZap(
                amount: amount * 1000,  // Convert to millisats
                targetPubkey: targetPubkey,
                content: content.isEmpty ? "Zap! ⚡" : content
            )

            if success {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }

    private func parsePubkeyFromQR(_ result: String) -> String? {
        // Parse QR code result to extract pubkey
        // This would depend on the QR code format
        return result
    }
}

#Preview {
    ZapFeedView(
        appState: AppState(modelContext: ModelContext(try! ModelContainer(for: AppSettings.self))))
}
