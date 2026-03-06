//
//  ZapServiceView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct ZapServiceView: View {
    let targetPubkey: String
    let eventCoordinate: String?
    let amount: Int64

    @StateObject private var zapService: ZapService
    @State private var showAmountSelector = false
    @State private var selectedAmount: Int64 = 1_000_000  // Default 1000 sats in millisats
    @State private var showAlert = false
    @State private var alertMessage = ""

    // Predefined zap amounts in millisats
    private let zapAmounts: [Int64] = [
        100000, 500000, 1_000_000, 5_000_000, 10_000_000, 25_000_000,
    ]

    init(
        targetPubkey: String, eventCoordinate: String? = nil, amount: Int64 = 1_000_000,
        appState: AppState
    ) {
        self.targetPubkey = targetPubkey
        self.eventCoordinate = eventCoordinate
        self.amount = amount
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Clean zap button
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
                HStack(spacing: 4) {
                    if zapService.isProcessingZap {
                        ProgressView()
                            .scaleEffect(0.6)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text("Zap")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.6, blue: 0.0),
                                    Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.8),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.3),
                                    lineWidth: 0.5)
                        )
                )
                .scaleEffect(zapService.isProcessingZap ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: zapService.isProcessingZap)
            }
            .disabled(zapService.isProcessingZap)

            // Status messages with better styling
            if let error = zapService.zapError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )
            }

            if zapService.zapSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Zap sent!")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
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
        .alert("Zap Status", isPresented: $showAlert) {
            Button("OK") {
                showAlert = false
            }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: zapService.zapSuccess) { success in
            if success {
                alertMessage = "Zap sent successfully! ⚡"
                showAlert = true
                // Reset after showing success
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    zapService.reset()
                }
            }
        }
        .onChange(of: zapService.zapError) { error in
            if let error = error {
                alertMessage = error
                showAlert = true
            }
        }
    }

    private func sendZap(amount: Int64) async {
        let success = await zapService.sendZap(
            amount: amount,
            targetPubkey: targetPubkey,
            eventCoordinate: eventCoordinate,
            content: "Zap! ⚡"
        )

        if !success {
            // Error handling is done through the service's published properties
            return
        }
    }
}

#Preview {
    ZapServiceView(
        targetPubkey: "test",
        appState: AppState(modelContext: ModelContext(try! ModelContainer(for: AppSettings.self))))
}
