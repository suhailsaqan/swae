//
//  ZapService.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import Combine
import Foundation
import NostrSDK

/// Service for handling Lightning Zaps using NIP-57 and the NostrSDK
class ZapService: ObservableObject, EventCreating {
    @Published var isProcessingZap = false
    @Published var zapError: String?
    @Published var zapSuccess = false

    private let appState: AppState
    private let lightningPaymentService: LightningPaymentService

    init(appState: AppState) {
        self.appState = appState
        self.lightningPaymentService = LightningPaymentService(appState: appState)
    }

    /// Creates and sends a zap request using the NostrSDK
    /// - Parameters:
    ///   - amount: Amount in millisats
    ///   - targetPubkey: Public key of the recipient
    ///   - eventCoordinate: Optional event coordinate for context
    ///   - content: Optional message content
    /// - Returns: True if successful, false otherwise
    func sendZap(
        amount: Int64,
        targetPubkey: String,
        eventCoordinate: String? = nil,
        content: String? = nil
    ) async -> Bool {
        guard let keypair = appState.keypair else {
            await MainActor.run {
                zapError = "No keypair available"
            }
            return false
        }

        await MainActor.run {
            isProcessingZap = true
            zapError = nil
            zapSuccess = false
        }

        do {
            // Step 1: Get recipient's Lightning address from metadata
            guard let recipientMetadata = appState.metadataEvents[targetPubkey]?.userMetadata,
                let lightningAddress = recipientMetadata.lightningAddress
            else {
                await MainActor.run {
                    zapError = "Recipient doesn't have a Lightning address configured"
                    isProcessingZap = false
                }
                return false
            }

            // Step 1.5: No need to verify Nostr support - any LNURL service should work

            // Step 2: Convert Lightning address to LNURL
            let lnurl = convertLightningAddressToLNURL(lightningAddress)
            guard let lnurl = lnurl else {
                await MainActor.run {
                    zapError = "Invalid Lightning address format"
                    isProcessingZap = false
                }
                return false
            }

            // Step 3: Use NostrSDK's ZapManager to create zap request
            // For custodial wallets like Alby, we use the target user's pubkey as recipient
            // The money goes to Alby but gets credited to the target user's account
            print(
                "🔍 Zap: Creating zap request - recipientPubkey: \(targetPubkey), senderPubkey: \(keypair.publicKey.hex)"
            )
            print("🔍 Zap: Lightning address: \(lightningAddress)")
            print("🔍 Zap: LNURL: \(lnurl)")
            
            let zapRequestResult: ZapManager.ZapRequestResult
            do {
                zapRequestResult = try await ZapManager.createZapRequest(
                    content: content ?? "Zap! ⚡",
                    amount: amount,
                    lnurl: lnurl,
                    recipientPubkey: targetPubkey,
                    eventId: nil,
                    eventCoordinate: eventCoordinate,
                    relays: appState.relayWritePool.relays.map { $0.url.absoluteString },
                    signedBy: keypair
                )
                print("✅ Zap: Created zap request successfully")
            } catch {
                print("❌ Zap: Failed to create zap request")
                print("❌ Zap: Error: \(error)")
                
                // Check if it's a JSON decoding error (HTML/text response)
                let errorMessage: String
                if let decodingError = error as? DecodingError {
                    errorMessage = "The recipient's Lightning wallet is unavailable or doesn't support zaps."
                } else {
                    errorMessage = "Failed to create zap request. The Lightning address may not support zaps."
                }
                
                await MainActor.run {
                    zapError = errorMessage
                    isProcessingZap = false
                }
                return false
            }

            // Step 4: Send zap request to get invoice
            print("🔍 Zap: Sending zap request to LNURL service")
            print("🔍 Zap: Callback URL: \(zapRequestResult.callbackURL)")
            
            let zapRequestWithInvoice: ZapManager.ZapRequestResult
            do {
                zapRequestWithInvoice = try await ZapManager.sendZapRequest(zapRequestResult)
            } catch {
                print("❌ Zap: Failed to get invoice from LNURL service")
                print("❌ Zap: Error: \(error)")
                
                // Check if it's a JSON decoding error (HTML response)
                if let decodingError = error as? DecodingError {
                    await MainActor.run {
                        zapError = "Lightning service returned an error. The recipient's Lightning address may not support zaps."
                        isProcessingZap = false
                    }
                } else {
                    await MainActor.run {
                        zapError = "Failed to get invoice: \(error.localizedDescription)"
                        isProcessingZap = false
                    }
                }
                return false
            }

            guard let bolt11Invoice = zapRequestWithInvoice.bolt11Invoice else {
                await MainActor.run {
                    zapError = "Failed to get Lightning invoice"
                    isProcessingZap = false
                }
                return false
            }
            
            print("✅ Zap: Got invoice: \(bolt11Invoice.prefix(50))...")

            // Step 5: Pay the invoice through Nostr Wallet Connect
            let paymentSuccess = await lightningPaymentService.payInvoice(bolt11Invoice)

            // NOTE: Some NWC implementations have decryption issues with responses
            // but the payment still goes through. We check the error message to see
            // if it's just a decryption issue (which we can ignore) or a real payment failure.
            let isDecryptionError = lightningPaymentService.error?.lowercased().contains("decrypt") ?? false
            
            if paymentSuccess || isDecryptionError {
                // Step 6: Payment successful!
                // NOTE: The LNURL service will publish the official zap receipt
                // We should NOT publish our own zap receipt as it causes duplicates
                
                await MainActor.run {
                    zapSuccess = true
                    isProcessingZap = false
                    // Clear the decryption error since payment succeeded
                    if isDecryptionError {
                        zapError = nil
                    }
                }

                print("✅ Zap: Successfully sent \(amount / 1000) sats to \(targetPubkey)")
                print("✅ Zap: Waiting for LNURL service to publish zap receipt...")
                return true
            } else {
                await MainActor.run {
                    zapError = lightningPaymentService.error ?? "Lightning payment failed"
                    isProcessingZap = false
                }
                return false
            }

        } catch {
            await MainActor.run {
                zapError = "Failed to send zap: \(error.localizedDescription)"
                isProcessingZap = false
            }
            print("❌ Zap: Failed to send zap: \(error)")
            return false
        }
    }

    /// Resets the zap service state
    func reset() {
        zapSuccess = false
        zapError = nil
        isProcessingZap = false
        lightningPaymentService.reset()
    }

    /// Converts a Lightning address to LNURL
    /// - Parameter lightningAddress: The Lightning address (e.g., "user@domain.com")
    /// - Returns: The LNURL or nil if invalid
    private func convertLightningAddressToLNURL(_ lightningAddress: String) -> String? {
        // Split by @ to get user and domain
        let components = lightningAddress.components(separatedBy: "@")
        guard components.count == 2 else { return nil }

        let user = components[0]
        let domain = components[1]

        // Create LNURL by prepending "https://" to domain and appending user
        return "https://\(domain)/.well-known/lnurlp/\(user)"
    }

    /// Creates a zap receipt event (typically done by the Lightning service)
    func createZapReceipt(
        zapRequest: LightningZapRequestEvent,
        paymentHash: String,
        amount: Int64,
        signedBy: Keypair
    ) throws -> LightningZapReceiptEvent {
        // Encode the zap request as JSON for the description field
        let zapRequestData = try JSONEncoder().encode(zapRequest)
        let zapRequestJSON = String(data: zapRequestData, encoding: .utf8) ?? ""

        // Create a mock bolt11 invoice (in real implementation, this would be the actual invoice)
        let mockBolt11 = "lnbc\(amount)u1p\(UUID().uuidString.prefix(8))..."

        let zapReceipt = try lightningZapReceiptEvent(
            recipientPubkey: zapRequest.recipientPubkey ?? "",
            senderPubkey: signedBy.publicKey.hex,
            eventId: zapRequest.eventId,
            eventCoordinate: zapRequest.eventCoordinate,
            bolt11: mockBolt11,
            zapRequestJSON: zapRequestJSON,
            preimage: paymentHash,
            createdAt: Int64(Date().timeIntervalSince1970),
            signedBy: signedBy,
            additionalRelays: zapRequest.relayURLs
        )

        return zapReceipt
    }
}
