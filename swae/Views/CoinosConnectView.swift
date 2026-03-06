//
//  CoinosConnectView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct CoinosConnectView: View {
    @EnvironmentObject var appState: AppState
    @State private var isConnecting = false
    @State private var error: String?
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 72, height: 72)

                            Image(systemName: "bolt.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.orange)
                        }

                        Text("One-Tap Wallet Setup")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Your wallet will be ready in seconds")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    // Features — user benefits
                    VStack(spacing: 0) {
                        FeatureRow(
                            icon: "bolt.fill",
                            title: "Zap Your Favorite Streamers",
                            description: "Send instant Bitcoin tips during live streams"
                        )
                        Divider().padding(.leading, 44)
                        FeatureRow(
                            icon: "arrow.down.circle",
                            title: "Receive Zaps on Your Streams",
                            description: "Get paid directly when viewers support you"
                        )
                        Divider().padding(.leading, 44)
                        FeatureRow(
                            icon: "checkmark.shield",
                            title: "No Downloads Needed",
                            description: "Created from your Nostr key — nothing extra to install"
                        )
                    }
                    .padding(.horizontal, 20)
                }
            }

            // CTA pinned at bottom
            VStack(spacing: 10) {
                Button(action: connectCoinosWallet) {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isConnecting ? "Connecting..." : "Connect Coinos Wallet")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange)
                    )
                }
                .disabled(isConnecting)

                Text("Powered by Coinos")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 12)
        }
        .alert("Connection Status", isPresented: $showAlert) {
            Button("OK") {
                showAlert = false
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func connectCoinosWallet() {
        guard let keypair = appState.keypair else {
            alertMessage = "No keypair available"
            showAlert = true
            return
        }

        isConnecting = true
        error = nil

        Task {
            do {
                let coinosClient = CoinosClient(userKeypair: keypair)

                print(
                    "🔧 CoinosConnectView: Creating CoinosClient with user keypair: \(keypair.publicKey.hex.prefix(8))..."
                )

                // Login or register with Coinos
                try await coinosClient.loginOrRegister()

                print("🔧 CoinosConnectView: Successfully logged in to Coinos")

                // Check what NWC connection currently exists
                print("🔧 CoinosConnectView: Checking existing NWC connection...")
                do {
                    if let existingConfig = try await coinosClient.getNWCAppConnectionConfig() {
                        print("🔧 CoinosConnectView: Found existing NWC config:")
                        print("🔧 CoinosConnectView: - Name: \(existingConfig.name)")
                        print("🔧 CoinosConnectView: - Pubkey: \(existingConfig.pubkey)")

                        // Check if the existing config matches our current keypair
                        let currentNWCPubkey =
                            coinosClient.publicNWCKeypair?.publicKey.hex ?? "unknown"
                        if let existingPubkey = existingConfig.pubkey,
                            existingPubkey != currentNWCPubkey
                        {
                            print("🔧 CoinosConnectView: ⚠️  KEYPAIR MISMATCH DETECTED!")
                            print("🔧 CoinosConnectView: - Existing NWC pubkey: \(existingPubkey)")
                            print("🔧 CoinosConnectView: - Current NWC pubkey: \(currentNWCPubkey)")
                            print(
                                "🔧 CoinosConnectView: - This means the existing connection was created with a different user keypair"
                            )
                            print(
                                "🔧 CoinosConnectView: - We need to delete and recreate the connection"
                            )
                        } else {
                            print("🔧 CoinosConnectView: ✅ NWC pubkey matches current keypair")
                        }

                        if let existingNWC = existingConfig.nwc {
                            print(
                                "🔧 CoinosConnectView: - Existing NWC URL present"
                            )
                        }
                    } else {
                        print("🔧 CoinosConnectView: No existing NWC connection found")
                    }
                } catch {
                    print("🔧 CoinosConnectView: Error checking existing NWC connection: \(error)")
                    // Continue anyway - this is just for debugging
                }

                // Delete existing NWC connection first, then create new one
                let nwcURL: WalletConnectURL
                do {
                    print("🔧 CoinosConnectView: Attempting to delete existing NWC connection...")
                    try await coinosClient.deleteNWCConnection()
                    print("🔧 CoinosConnectView: Successfully deleted existing NWC connection")
                } catch {
                    print("🔧 CoinosConnectView: Delete failed (may not exist): \(error)")
                    // Continue - the connection may not exist
                }

                do {
                    print("🔧 CoinosConnectView: Creating new NWC connection")
                    nwcURL = try await coinosClient.createNWCConnection()
                    print("🔧 CoinosConnectView: Successfully created new NWC connection")
                } catch {
                    print("🔧 CoinosConnectView: Create failed: \(error)")
                    throw error
                }

                print("🔧 CoinosConnectView: Final NWC URL configured")
                print("🔧 CoinosConnectView: NWC pubkey: \(nwcURL.pubkey.hex.prefix(8))...")
                // NWC secret logged redacted for security

                // Connect the wallet
                await MainActor.run {
                    appState.wallet?.connect(nwcURL)
                    isConnecting = false
                }

            } catch {
                await MainActor.run {
                    isConnecting = false
                    let errorMessage: String
                    if let clientError = error as? CoinosClient.ClientError {
                        switch clientError {
                        case .errorFormingRequest:
                            errorMessage =
                                "Failed to form request - missing keypair or invalid data"
                        case .errorProcessingResponse:
                            errorMessage = "Failed to process server response"
                        case .unauthorized:
                            errorMessage = "Authentication failed - check credentials"
                        case .notLoggedIn:
                            errorMessage = "Not logged in to Coinos"
                        case .unexpectedHTTPResponse(let statusCode, let response):
                            errorMessage =
                                "Server error (HTTP \(statusCode)): \(String(data: response, encoding: .utf8) ?? "Unknown error")"
                        }
                    } else {
                        errorMessage =
                            "Failed to connect Coinos wallet: \(error.localizedDescription)"
                    }
                    alertMessage = errorMessage
                    showAlert = true
                    print("❌ CoinosConnectView: Error details: \(error)")
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    CoinosConnectView()
        .environmentObject(
            AppState(modelContext: ModelContext(try! ModelContainer(for: AppSettings.self))))
}
