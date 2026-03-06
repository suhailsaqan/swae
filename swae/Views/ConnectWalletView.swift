//
//  ConnectWalletView.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//

import SwiftUI

struct ConnectWalletView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: WalletModel
    @EnvironmentObject var appState: AppState

    @State var scanning: Bool = false
    @State private var showAlert = false
    @State var error: String? = nil
    @State var wallet_scan_result: WalletScanResult = .scanning
    @State private var showManualOptions = false
    @State private var isConnectingCoinos = false
    @State private var coinosAlertMessage = ""
    @State private var showCoinosAlert = false

    var body: some View {
        MainContent
            .navigationTitle(
                NSLocalizedString(
                    "Wallet",
                    comment: "Navigation title for attaching Nostr Wallet Connect lightning wallet."
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .padding()
            .onChange(of: wallet_scan_result) { res in
                scanning = false

                switch res {
                case .success(let url):
                    error = nil
                    self.model.connect(url)

                case .failed:
                    showAlert.toggle()

                case .scanning:
                    error = nil
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(
                        "Invalid Nostr wallet connection string",
                        comment:
                            "Error message when an invalid Nostr wallet connection string is provided."
                    ),
                    message: Text(
                        "Make sure the wallet you are connecting to supports NWC.",
                        comment:
                            "Hint message when an invalid Nostr wallet connection string is provided."
                    ),
                    dismissButton: .default(
                        Text("OK", comment: "Button label indicating user wants to proceed.")
                    ) {
                        wallet_scan_result = .scanning
                    }
                )
            }
            .alert("Connection Failed", isPresented: $showCoinosAlert) {
                Button("OK") { showCoinosAlert = false }
            } message: {
                Text(coinosAlertMessage)
            }
    }

    func AreYouSure(nwc: WalletConnectURL) -> some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 80, height: 80)

                    Image(systemName: "wallet.pass")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                }

                VStack(spacing: 8) {
                    Text("Confirm Wallet Connection")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("Are you sure you want to connect this wallet?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Wallet details
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relay URL")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(nwc.relay.url.absoluteString)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                        )
                }

                if let lud16 = nwc.lud16 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lightning Address")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Text(lud16)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.1))
                            )
                    }
                }
            }

            // Action buttons
            VStack(spacing: 12) {
                Button(action: {
                    model.connect(nwc)
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Connect Wallet")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                    )
                    .foregroundColor(.white)
                }

                Button(action: {
                    model.cancel()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Cancel")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                    )
                    .foregroundColor(.primary)
                }
            }
        }
        .padding(24)
    }

    var ConnectWallet: some View {
        VStack(spacing: 20) {
            // Wallet connection options — no redundant header needed
            VStack(spacing: 16) {
                // Coinos One-Click Setup (Featured / Recommended)
                Button(action: {
                    connectCoinosWallet()
                }) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 50, height: 50)

                            if isConnectingCoinos {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.orange)
                            } else {
                                Image(systemName: "bolt.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Coinos Wallet")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(isConnectingCoinos ? "Connecting..." : "One-click Lightning wallet setup")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !isConnectingCoinos {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orange.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isConnectingCoinos)

                // Manual connection toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showManualOptions.toggle()
                    }
                }) {
                    HStack {
                        Text("Manual Connections")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Spacer()

                        Image(systemName: showManualOptions ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.05))
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Manual connection options (expandable)
                if showManualOptions {
                    VStack(spacing: 12) {
                        // Paste NWC Address
                        Button(action: {
                            if let pasted_nwc = UIPasteboard.general.string {
                                guard let url = WalletConnectURL(str: pasted_nwc) else {
                                    wallet_scan_result = .failed
                                    return
                                }

                                wallet_scan_result = .success(url)
                            }
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.15))
                                        .frame(width: 50, height: 50)

                                    Image(systemName: "doc.text.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Paste Connection String")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text("Paste your NWC connection string from clipboard")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(spacing: 2) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("PASTE")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Scan QR Code
                        NavigationLink(destination: WalletScannerView(result: $wallet_scan_result))
                        {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.green.opacity(0.15))
                                        .frame(width: 50, height: 50)

                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.title2)
                                        .foregroundColor(.green)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scan QR Code")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text("Scan your wallet's QR code with camera")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(spacing: 2) {
                                    Image(systemName: "camera.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("SCAN")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.green.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }

            // Error message
            if let err = self.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 20)
    }

    var TopSection: some View {
        HStack(spacing: 0) {
            Button(
                action: {},
                label: {
                    Image("swae")
                        .resizable()
                        .frame(width: 30, height: 30)
                }
            )
            //            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15), cornerRadius: 9999))
            .disabled(true)
            .padding(.horizontal, 30)

            Image("chevron-double-right")
                .resizable()
                .frame(width: 25, height: 25)

            Button(
                action: {},
                label: {
                    Image("wallet")
                        .resizable()
                        .frame(width: 30, height: 30)
                    //                    .foregroundStyle(LINEAR_GRADIENT)
                }
            )
            //            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15), cornerRadius: 9999))
            .disabled(true)
            .padding(.horizontal, 30)
        }
    }

    var TitleSection: some View {
        VStack(spacing: 20) {
            // Bolt icon with orange glow
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.orange)
            }

            VStack(spacing: 8) {
                Text("Send Zaps, Support Creators")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Connect a Lightning wallet to tip streamers, receive zaps, and join the Bitcoin economy.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 20)
    }

    var MainContent: some View {
        VStack(spacing: 0) {
            switch model.connect_state {
            case .new(let nwc):
                AreYouSure(nwc: nwc)
            case .existing(let nwc):
                WalletMainView(walletModel: model)
            case .none:
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        TitleSection
                        ConnectWallet

                        Text("You can change your wallet anytime in settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 24)
                    }
                    .padding(.bottom, 100)  // Add padding to prevent tab bar overlap
                }
            }
        }
    }

    // MARK: - Coinos Connection

    private func connectCoinosWallet() {
        guard let keypair = appState.keypair else {
            coinosAlertMessage = "No keypair available"
            showCoinosAlert = true
            return
        }

        isConnectingCoinos = true

        Task {
            do {
                let coinosClient = CoinosClient(userKeypair: keypair)
                try await coinosClient.loginOrRegister()

                // Delete existing NWC connection, then create new one
                do {
                    try await coinosClient.deleteNWCConnection()
                } catch {
                    // Connection may not exist — continue
                }

                let nwcURL = try await coinosClient.createNWCConnection()

                await MainActor.run {
                    appState.wallet?.connect(nwcURL)
                    isConnectingCoinos = false
                }
            } catch {
                await MainActor.run {
                    isConnectingCoinos = false
                    if let clientError = error as? CoinosClient.ClientError {
                        switch clientError {
                        case .errorFormingRequest:
                            coinosAlertMessage = "Failed to form request - missing keypair or invalid data"
                        case .errorProcessingResponse:
                            coinosAlertMessage = "Failed to process server response"
                        case .unauthorized:
                            coinosAlertMessage = "Authentication failed - check credentials"
                        case .notLoggedIn:
                            coinosAlertMessage = "Not logged in to Coinos"
                        case .unexpectedHTTPResponse(let statusCode, let response):
                            coinosAlertMessage = "Server error (HTTP \(statusCode)): \(String(data: response, encoding: .utf8) ?? "Unknown error")"
                        }
                    } else {
                        coinosAlertMessage = "Failed to connect wallet: \(error.localizedDescription)"
                    }
                    showCoinosAlert = true
                }
            }
        }
    }
}
