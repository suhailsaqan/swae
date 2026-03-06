//
//  ZapButton.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import NostrSDK
import SwiftData
import SwiftUI

/// A reusable zap button component that can be used throughout the app
struct ZapButton: View {
    let targetPubkey: String
    let eventCoordinate: String?
    let amount: Int64
    let content: String?

    @StateObject private var zapService: ZapService
    @State private var showAmountSelector = false
    @State private var selectedAmount: Int64

    // Predefined zap amounts in millisats
    private let zapAmounts: [Int64] = [
        100_000,  // 100 sats
        500_000,  // 500 sats
        1_000_000,  // 1,000 sats
        5_000_000,  // 5,000 sats
        10_000_000,  // 10,000 sats
        25_000_000,  // 25,000 sats
    ]

    init(
        targetPubkey: String,
        eventCoordinate: String? = nil,
        amount: Int64 = 1_000_000,
        content: String? = nil,
        appState: AppState
    ) {
        self.targetPubkey = targetPubkey
        self.eventCoordinate = eventCoordinate
        self.amount = amount
        self.content = content
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
        self._selectedAmount = State(initialValue: amount)
    }

    var body: some View {
        Button(action: {
            if showAmountSelector {
                Task {
                    await sendZap(amount: selectedAmount)
                }
                showAmountSelector = false
            } else {
                showAmountSelector = true
            }
        }) {
            HStack(spacing: 6) {
                if zapService.isProcessingZap {
                    ProgressView()
                        .scaleEffect(0.7)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                }

                Text("\(amount / 1000)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .disabled(zapService.isProcessingZap)
        .sheet(isPresented: $showAmountSelector) {
            ZapAmountSelectorView(
                selectedAmount: $selectedAmount,
                zapAmounts: zapAmounts,
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
        .onChange(of: zapService.zapSuccess) { success in
            if success {
                // Reset after showing success
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    zapService.reset()
                }
            }
        }
    }

    private func sendZap(amount: Int64) async {
        let success = await zapService.sendZap(
            amount: amount,
            targetPubkey: targetPubkey,
            eventCoordinate: eventCoordinate,
            content: content ?? "Zap! ⚡"
        )

        if !success {
            // Error handling is done through the service's published properties
            return
        }
    }
}

/// A compact zap button for chat messages
struct CompactZapButton: View {
    let targetPubkey: String
    let eventCoordinate: String?
    let amount: Int64
    let content: String?

    @StateObject private var zapService: ZapService
    @State private var showAmountSelector = false
    @State private var selectedAmount: Int64

    // Predefined zap amounts in millisats
    private let zapAmounts: [Int64] = [
        100_000,  // 100 sats
        500_000,  // 500 sats
        1_000_000,  // 1,000 sats
        5_000_000,  // 5,000 sats
        10_000_000,  // 10,000 sats
        25_000_000,  // 25,000 sats
    ]

    init(
        targetPubkey: String,
        eventCoordinate: String? = nil,
        amount: Int64 = 1_000_000,
        content: String? = nil,
        appState: AppState
    ) {
        self.targetPubkey = targetPubkey
        self.eventCoordinate = eventCoordinate
        self.amount = amount
        self.content = content
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
        self._selectedAmount = State(initialValue: amount)
    }

    var body: some View {
        Button(action: {
            if showAmountSelector {
                Task {
                    await sendZap(amount: selectedAmount)
                }
                showAmountSelector = false
            } else {
                showAmountSelector = true
            }
        }) {
            HStack(spacing: 2) {
                if zapService.isProcessingZap {
                    ProgressView()
                        .scaleEffect(0.4)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
                }

                Text("\(amount / 1000)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.0))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.2), lineWidth: 0.5)
                    )
            )
            .scaleEffect(zapService.isProcessingZap ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: zapService.isProcessingZap)
        }
        .disabled(zapService.isProcessingZap)
        .sheet(isPresented: $showAmountSelector) {
            ZapAmountSelectorView(
                selectedAmount: $selectedAmount,
                zapAmounts: zapAmounts,
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
        .onChange(of: zapService.zapSuccess) { success in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    zapService.reset()
                }
            }
        }
    }

    private func sendZap(amount: Int64) async {
        let success = await zapService.sendZap(
            amount: amount,
            targetPubkey: targetPubkey,
            eventCoordinate: eventCoordinate,
            content: content ?? "Zap! ⚡"
        )

        if !success {
            return
        }
    }
}

/// A quick zap button with predefined amounts
struct QuickZapButton: View {
    let targetPubkey: String
    let eventCoordinate: String?
    let amount: Int64
    let content: String?

    @StateObject private var zapService: ZapService

    init(
        targetPubkey: String,
        eventCoordinate: String? = nil,
        amount: Int64 = 1_000_000,
        content: String? = nil,
        appState: AppState
    ) {
        self.targetPubkey = targetPubkey
        self.eventCoordinate = eventCoordinate
        self.amount = amount
        self.content = content
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
    }

    var body: some View {
        Button(action: {
            Task {
                await sendZap()
            }
        }) {
            HStack(spacing: 4) {
                if zapService.isProcessingZap {
                    ProgressView()
                        .scaleEffect(0.6)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }

                Text("\(amount / 1000)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
        .onChange(of: zapService.zapSuccess) { success in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    zapService.reset()
                }
            }
        }
    }

    private func sendZap() async {
        let success = await zapService.sendZap(
            amount: amount,
            targetPubkey: targetPubkey,
            eventCoordinate: eventCoordinate,
            content: content ?? "Zap! ⚡"
        )

        if !success {
            return
        }
    }
}

/// A zap amount selector view for custom amounts
struct ZapAmountSelectorView: View {
    @Binding var selectedAmount: Int64
    let zapAmounts: [Int64]
    let onConfirm: (Int64) -> Void
    let onCancel: () -> Void

    @State private var customAmount: String = ""
    @State private var isCustomAmount = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Enhanced header with gradient background
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.8), Color.orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 4) {
                        Text("Send Zap")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        Text("Send a Lightning payment")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 20)

                // Enhanced amount selector
                VStack(spacing: 20) {
                    Text("Select Amount")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Predefined amounts with improved styling
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 3),
                        spacing: 12
                    ) {
                        ForEach(zapAmounts, id: \.self) { amount in
                            Button(action: {
                                selectedAmount = amount
                                isCustomAmount = false
                            }) {
                                VStack(spacing: 6) {
                                    Text("\(amount / 1000)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(
                                            selectedAmount == amount && !isCustomAmount
                                                ? .white : .orange
                                        )
                                    Text("sats")
                                        .font(.caption)
                                        .foregroundColor(
                                            selectedAmount == amount && !isCustomAmount
                                                ? .white.opacity(0.8) : .secondary
                                        )
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            selectedAmount == amount && !isCustomAmount
                                                ? LinearGradient(
                                                    colors: [
                                                        Color.orange, Color.orange.opacity(0.8),
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                : LinearGradient(
                                                    colors: [
                                                        Color(.systemGray6), Color(.systemGray5),
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    selectedAmount == amount && !isCustomAmount
                                                        ? Color.clear
                                                        : Color(.systemGray4),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    // Enhanced custom amount section
                    VStack(spacing: 12) {
                        Text("Custom Amount")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            TextField("Enter amount", text: $customAmount)
                                .keyboardType(.numberPad)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.systemGray6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color(.systemGray4), lineWidth: 1)
                                        )
                                )
                                .onChange(of: customAmount) { newValue in
                                    if let amount = Int64(newValue), amount > 0 {
                                        selectedAmount = amount * 1000  // Convert to millisats
                                        isCustomAmount = true
                                    }
                                }

                            Text("sats")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Enhanced action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onConfirm(selectedAmount)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Send \(selectedAmount / 1000) sats")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange, Color.orange.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    }
                    .disabled(selectedAmount <= 0)
                    .opacity(selectedAmount <= 0 ? 0.6 : 1.0)

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.systemGray6))
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ZapButton(
            targetPubkey: "test",
            appState: AppState(
                modelContext: ModelContext(try! ModelContainer(for: AppSettings.self)))
        )

        QuickZapButton(
            targetPubkey: "test",
            amount: 500_000,
            appState: AppState(
                modelContext: ModelContext(try! ModelContainer(for: AppSettings.self)))
        )
    }
    .padding()
}
