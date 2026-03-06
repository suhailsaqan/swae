import Combine
import NostrSDK
import SwiftUI

struct StreamZapStreamCoreSettingsView: View {
    @EnvironmentObject private var model: Model
    @EnvironmentObject private var appState: AppState
    @ObservedObject var stream: SettingsStream

    // MARK: - State
    @State private var isLoading = false
    @State private var accountInfo: ZapStreamCoreAccountResponse?
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showTopUpSheet = false

    // MARK: - API Client
    private var apiClient: ZapStreamCoreApiClient {
        let config = ZapStreamCoreConfig(
            baseUrl: stream.zapStreamCoreBaseUrl,
            streamTitle: stream.zapStreamCoreStreamTitle.isEmpty
                ? stream.name : stream.zapStreamCoreStreamTitle,
            streamDescription: stream.zapStreamCoreStreamDescription,
            isPublic: stream.zapStreamCoreIsPublic
        )
        return ZapStreamCoreApiClient(config: config)
    }

    private var displayName: String? {
        if let pubkey = appState.publicKey?.hex,
           let metadata = appState.metadataEvents[pubkey] {
            return metadata.userMetadata?.displayName ?? metadata.userMetadata?.name
        }
        return nil
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerView
                connectionStatusView
                
                if stream.zapStreamCoreEnabled {
                    streamSettingsCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Zap Stream Core")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if stream.zapStreamCoreEnabled {
                connectToZapStreamCore()
                model.startBalancePolling()
            }
        }
        .onDisappear {
            model.stopBalancePolling()
        }
        .onChange(of: stream.zapStreamCoreEnabled) { enabled in
            if enabled {
                connectToZapStreamCore()
                model.startBalancePolling()
            } else {
                model.stopBalancePolling()
            }
        }
        .sheet(isPresented: $showTopUpSheet, onDismiss: {
            model.refreshZapStreamCoreBalance()
        }) {
            ZapStreamCorePaymentView()
                .environmentObject(model)
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.yellow)
            }
            
            Text("Zap Stream Core")
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            Text("Stream to Nostr with your identity")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Enable Toggle
            Toggle("Enable Zap Stream Core", isOn: $stream.zapStreamCoreEnabled)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }

    // MARK: - Connection Status View
    @ViewBuilder
    private var connectionStatusView: some View {
        if stream.zapStreamCoreEnabled {
            if appState.keypair == nil {
                noIdentityView
            } else if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let account = accountInfo {
                connectedView(account)
            }
        }
    }


    // MARK: - No Identity View
    private var noIdentityView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "key.slash")
                    .foregroundColor(.orange)
                Text("Nostr Identity Required")
                    .fontWeight(.medium)
                Spacer()
            }
            
            Text("Create or import a Nostr identity to stream with Zap Stream Core.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Loading View
    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Connecting...")
                    .font(.subheadline.weight(.medium))
                Text("Setting up your stream")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Connection Failed")
                    .fontWeight(.medium)
                Spacer()
            }
            
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button {
                connectToZapStreamCore()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.subheadline.weight(.medium))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Connected View
    private func connectedView(_ account: ZapStreamCoreAccountResponse) -> some View {
        let balance = model.zapStreamCoreBalance ?? account.balance
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let name = displayName {
                        Text("@\(name)")
                            .font(.subheadline.weight(.medium))
                    } else if let npub = appState.publicKey?.npub {
                        Text(String(npub.prefix(16)) + "...")
                            .font(.caption.monospaced())
                    }
                    
                    Text("Balance: \(balance) sats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let cost = account.endpoints.first?.cost {
                        Text("\(Int(cost.rate)) \(cost.unit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Top Up") {
                        showTopUpSheet = true
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.yellow)
                }
            }

            // Auto Top-Up section
            ZapStreamNWCAutoTopupView(stream: stream)
                .environmentObject(model)
                .environmentObject(appState)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }


    // MARK: - Stream Settings Card
    private var streamSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            Text("STREAM SETTINGS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 16) {
                // Title field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stream Title")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    TextField("My Stream", text: $stream.zapStreamCoreStreamTitle)
                        .font(.body)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        )
                }
                
                // Description field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Stream Description", text: $stream.zapStreamCoreStreamDescription, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...4)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        )
                }
                
                // Public toggle
                HStack {
                    Text("Public Stream")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $stream.zapStreamCoreIsPublic)
                        .labelsHidden()
                }
                
                // Protocol picker
                HStack {
                    Text("Protocol")
                        .font(.body)
                    Spacer()
                    Picker("Protocol", selection: $stream.zapStreamCorePreferredProtocol) {
                        Text("RTMP").tag(ZapStreamCoreProtocol.rtmp)
                        Text("SRT").tag(ZapStreamCoreProtocol.srt)
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    // MARK: - Methods
    private func connectToZapStreamCore() {
        guard appState.keypair != nil else {
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // First test the connection
        apiClient.testConnection()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        self.isLoading = false
                        self.errorMessage = "Connection test failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { _ in
                    // Now get account info
                    self.getAccountInfo()
                }
            )
            .store(in: &cancellables)
    }

    private func getAccountInfo() {
        apiClient.getAccountInfo(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        self.errorMessage = "Failed to get account info: \(error.localizedDescription)"
                    }
                },
                receiveValue: { accountResponse in
                    self.accountInfo = accountResponse
                    self.errorMessage = nil

                    // Seed the shared model balance
                    self.model.zapStreamCoreBalance = accountResponse.balance
                    self.model.zapStreamCoreHasNwc = accountResponse.hasNwc
                    if let cost = accountResponse.endpoints.first?.cost {
                        self.model.zapStreamCoreRate = cost.rate
                    }
                    
                    // Update stream URL if needed
                    if let endpoint = accountResponse.endpoints.first {
                        let fullUrl = "\(endpoint.url)/\(endpoint.key)"
                        if stream.url == defaultStreamUrl || stream.url.isEmpty {
                            stream.url = fullUrl
                        }
                        stream.zapStreamCoreStreamKey = endpoint.key
                    }
                }
            )
            .store(in: &cancellables)
    }
}
