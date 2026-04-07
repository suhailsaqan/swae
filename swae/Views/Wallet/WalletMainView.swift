//
//  WalletMainView.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct WalletMainView: View {
    @ObservedObject var walletModel: WalletModel
    @State private var hideBalance: Bool = false
    @State private var showSettings: Bool = false
    @State private var showSendSheet: Bool = false
    @State private var showReceiveSheet: Bool = false
    @State private var showGetBitcoinSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Balance Section
                BalanceView(
                    balance: walletModel.balance,
                    hideBalance: $hideBalance,
                    onGetBitcoinTapped: { showGetBitcoinSheet = true }
                )

                // Action Buttons
                actionButtonsSection


                // Transactions Section
                TransactionsView(
                    transactions: walletModel.transactions,
                    hideBalance: $hideBalance
                )

                // Error Section
                if let error = walletModel.error {
                    errorSection(error)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)  // Space for tab bar
        }
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.accentPurple)
                }
            }
        }
        .refreshable {
            await walletModel.refreshWalletData()
        }
        .onAppear {
            if walletModel.balance == nil && !walletModel.isLoading {
                Task {
                    await walletModel.loadWalletData()
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            WalletSettingsView(walletModel: walletModel)
        }
        .sheet(isPresented: $showSendSheet) {
            SendPaymentView(walletModel: walletModel)
        }
        .sheet(isPresented: $showReceiveSheet) {
            ReceiveView(walletModel: walletModel)
        }
        .sheet(isPresented: $showGetBitcoinSheet) {
            GetBitcoinView(
                lud16: lightningAddress,
                onReceiveViaTapped: { showReceiveSheet = true }
            )
        }
    }

    // MARK: - Computed Properties

    private var lightningAddress: String? {
        switch walletModel.connect_state {
        case .spark(let lud16):
            return lud16
        case .existing(let nwc):
            return nwc.lud16
        default:
            return nil
        }
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Send Button
                Button(action: {
                    showSendSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .medium))
                        Text("Send")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentPurple)
                    )
                }

                // Receive Button
                Button(action: {
                    showReceiveSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 16, weight: .medium))
                        Text("Receive")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentPurple, lineWidth: 2)
                    )
                }
            }

            // Get Bitcoin Button
            Button(action: {
                showGetBitcoinSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                    Text("Get Bitcoin")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.red)

            Text("Error")
                .font(.headline)
                .foregroundColor(.red)

            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await walletModel.refreshWalletData()
                }
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Wallet Settings View

struct WalletSettingsView: View {
    @ObservedObject var walletModel: WalletModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDisconnectAlert: Bool = false
    @State private var copiedField: String? = nil
    @State private var showBackupSheet: Bool = false

    #if DEBUG
    enum NWCTestStatus { case idle, running, success, failed }
    @State private var nwcTestStatus: NWCTestStatus = .idle
    @State private var nwcTestMessage: String? = nil
    #endif
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Connection Status
                        connectionStatusSection
                        
                        // Wallet Details
                        switch walletModel.connect_state {
                        case .existing(let nwc):
                            walletDetailsSection(nwc: nwc)
                        case .spark(let lud16):
                            sparkDetailsSection(lud16: lud16)
                        default:
                            EmptyView()
                        }
                        
                        // Actions
                        actionsSection
                        
                        Spacer(minLength: 40)
                        
                        // Disconnect Button
                        disconnectButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Wallet Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .alert("Disconnect Wallet", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    walletModel.disconnect()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to disconnect your wallet? You can reconnect anytime.")
            }
            .sheet(isPresented: $showBackupSheet) {
                BackupWalletView(walletModel: walletModel)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Connection Status
    
    private var isConnected: Bool {
        switch walletModel.connect_state {
        case .existing, .spark:
            return true
        default:
            return false
        }
    }
    
    private var connectionStatusSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((isConnected ? Color.accentPurple : Color.gray).opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isConnected ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isConnected ? .orange : .gray)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isConnected ? "Connected" : "Not Connected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text({
                    switch walletModel.connect_state {
                    case .spark: return "Spark Wallet"
                    case .existing: return "Nostr Wallet Connect"
                    default: return "Not Connected"
                    }
                }())
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Circle()
                .fill(isConnected ? Color.accentPurple : Color.gray)
                .frame(width: 10, height: 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Wallet Details
    
    private func walletDetailsSection(nwc: WalletConnectURL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONNECTION DETAILS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                // Relay
                settingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Relay",
                    value: nwc.relay.url.host ?? nwc.relay.url.absoluteString,
                    fullValue: nwc.relay.url.absoluteString
                )
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Lightning Address
                if let lud16 = nwc.lud16 {
                    settingsRow(
                        icon: "at",
                        title: "Lightning Address",
                        value: lud16,
                        fullValue: lud16
                    )
                    
                    Divider().background(Color.gray.opacity(0.3))
                }
                
                // Wallet Pubkey
                settingsRow(
                    icon: "key.fill",
                    title: "Wallet Pubkey",
                    value: String(nwc.pubkey.hex.prefix(8)) + "..." + String(nwc.pubkey.hex.suffix(8)),
                    fullValue: nwc.pubkey.hex
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
    
    private func sparkDetailsSection(lud16: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WALLET DETAILS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                settingsRow(
                    icon: "bolt.shield.fill",
                    title: "Wallet Type",
                    value: "Self-custodial (Spark)",
                    fullValue: "Self-custodial Spark wallet via Breez SDK"
                )
                
                Divider().background(Color.gray.opacity(0.3))
                
                if let lud16 {
                    settingsRow(
                        icon: "at",
                        title: "Lightning Address",
                        value: lud16,
                        fullValue: lud16
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private func settingsRow(icon: String, title: String, value: String, fullValue: String) -> some View {
        Button(action: {
            UIPasteboard.general.string = fullValue
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedField = title
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    copiedField = nil
                }
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    
                    Text(copiedField == title ? "Copied!" : value)
                        .font(.system(size: 15))
                        .foregroundColor(copiedField == title ? .green : .white)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: copiedField == title ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundColor(copiedField == title ? .green : .gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACTIONS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                Button(action: {
                    Task {
                        await walletModel.refreshWalletData()
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        
                        Text("Refresh Wallet Data")
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if walletModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(walletModel.isLoading)

                // Backup recovery phrase (Spark wallets only)
                if case .spark = walletModel.connect_state {
                    Divider().background(Color.gray.opacity(0.3))

                    Button(action: { showBackupSheet = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                                .frame(width: 24)

                            Text("Backup Recovery Phrase")
                                .font(.system(size: 15))
                                .foregroundColor(.white)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Debug: Test NWC Responder (Spark wallets only)
                #if DEBUG
                Divider().background(Color.gray.opacity(0.3))

                Button(action: { runNWCResponderTest() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16))
                            .foregroundColor(nwcTestStatus == .success ? .green : nwcTestStatus == .failed ? .red : .purple)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test NWC Responder")
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                            if let msg = nwcTestMessage {
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundColor(nwcTestStatus == .success ? .green : nwcTestStatus == .failed ? .red : .gray)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        if nwcTestStatus == .running {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: nwcTestStatus == .success ? "checkmark.circle.fill" : nwcTestStatus == .failed ? "xmark.circle.fill" : "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(nwcTestStatus == .success ? .green : nwcTestStatus == .failed ? .red : .gray)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(nwcTestStatus == .running)
                #endif
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
    
    // MARK: - Debug NWC Responder Test

    #if DEBUG
    private func runNWCResponderTest() {
        guard case .spark = walletModel.connect_state,
              let spark = walletModel.sparkService else {
            nwcTestStatus = .failed
            nwcTestMessage = "Spark wallet not connected"
            return
        }

        nwcTestStatus = .running
        nwcTestMessage = "Starting responder..."

        Task {
            do {
                let responder = NWCResponder()
                await MainActor.run { nwcTestMessage = "Connecting to relay..." }

                let nwcURL = try await responder.start(sparkService: spark)
                await MainActor.run { nwcTestMessage = "Responder running. Sending test request..." }

                let result = try await responder.selfTest()
                responder.stop()

                await MainActor.run {
                    nwcTestStatus = .success
                    // Parse to show a clean message
                    if result.contains("alias") || result.contains("methods") {
                        nwcTestMessage = "Round-trip OK. get_info responded."
                    } else {
                        nwcTestMessage = "Response: \(String(result.prefix(80)))"
                    }
                }
            } catch {
                await MainActor.run {
                    nwcTestStatus = .failed
                    nwcTestMessage = error.localizedDescription
                }
            }
        }
    }
    #endif

    // MARK: - Disconnect Button
    
    private var disconnectButton: some View {
        Button(action: {
            showDisconnectAlert = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                Text("Disconnect Wallet")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
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
}

#Preview {
    WalletMainView(
        walletModel: WalletModel(
            publicKey: PublicKey(hex: "test")!,
            appState: AppState(
                modelContext: ModelContext(try! ModelContainer(for: AppSettings.self))))
    )
    .preferredColorScheme(.dark)
}
