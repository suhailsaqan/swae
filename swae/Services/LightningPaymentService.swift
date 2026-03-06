//
//  LightningPaymentService.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import Combine
import Foundation
import NostrSDK

/// Service for handling Lightning payments through Nostr Wallet Connect
class LightningPaymentService: ObservableObject {
    @Published var isProcessing = false
    @Published var error: String?
    @Published var paymentStatus: PaymentStatus = .idle

    enum PaymentStatus {
        case idle
        case processing
        case success
        case failed
    }

    private let appState: AppState
    private let lnurlService = LNURLService()

    init(appState: AppState) {
        self.appState = appState
    }

    /// Processes a Lightning payment for a zap
    /// - Parameters:
    ///   - amount: Amount in millisats
    ///   - lightningAddress: Recipient's Lightning address
    ///   - zapRequest: The zap request event
    /// - Returns: True if payment was successful, false otherwise
    func processPayment(
        amount: Int64,
        lightningAddress: String,
        zapRequest: LightningZapRequestEvent
    ) async -> Bool {
        await MainActor.run {
            isProcessing = true
            error = nil
            paymentStatus = .processing
        }

        do {
            // Step 1: Get LNURL pay request
            guard let payRequest = await lnurlService.fetchLNURLPayRequest(from: lightningAddress)
            else {
                await MainActor.run {
                    error = "Failed to fetch LNURL pay request"
                    isProcessing = false
                    paymentStatus = .failed
                }
                return false
            }

            // Step 2: Create invoice
            let zapRequestJSON = try JSONEncoder().encode(zapRequest)
            let zapRequestString = String(data: zapRequestJSON, encoding: .utf8) ?? ""

            guard
                let payResponse = await lnurlService.createInvoice(
                    from: payRequest,
                    amount: amount,
                    comment: zapRequest.content.isEmpty ? nil : zapRequest.content,
                    zapRequest: zapRequestString
                )
            else {
                await MainActor.run {
                    error = "Failed to create Lightning invoice"
                    isProcessing = false
                    paymentStatus = .failed
                }
                return false
            }

            // Step 3: Pay the invoice through Nostr Wallet Connect
            let paymentSuccess = await payInvoice(payResponse.pr)

            await MainActor.run {
                isProcessing = false
                paymentStatus = paymentSuccess ? .success : .failed
            }

            return paymentSuccess

        } catch let paymentError {
            await MainActor.run {
                error = "Payment failed: \(paymentError.localizedDescription)"
                isProcessing = false
                paymentStatus = .failed
            }
            return false
        }
    }

    /// Pays a Lightning invoice through Nostr Wallet Connect
    /// - Parameter bolt11: The bolt11 invoice string
    /// - Returns: True if payment was successful, false otherwise
    func payInvoice(_ bolt11: String) async -> Bool {
        guard let wallet = appState.wallet else {
            await MainActor.run {
                error = "No wallet connected"
            }
            return false
        }

        do {
            // Use WalletModel's payInvoice method which uses NWCClient
            let preimage = try await wallet.payInvoice(bolt11)
            
            if let preimage = preimage {
                print("✅ LightningPaymentService: Payment successful with preimage: \(preimage)")
            } else {
                print("✅ LightningPaymentService: Payment successful (no preimage returned)")
            }
            
            return true
        } catch {
            await MainActor.run {
                self.error = "Payment failed: \(error.localizedDescription)"
            }
            print("❌ LightningPaymentService: Payment failed: \(error)")
            return false
        }
    }

    /// Resets the payment status
    func reset() {
        paymentStatus = .idle
        error = nil
        isProcessing = false
    }
}
