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
    @State private var showWalletReceiveSheet = false

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
            VStack(spacing: 20) {
                // Enable toggle
                enableToggle
                
                if stream.zapStreamCoreEnabled {
                    connectionStatusView
                    
                    streamSettingsCard
                    
                    // TOS acceptance for new users (shown at end of flow)
                    if let account = accountInfo,
                       account.tos?.accepted == false,
                       !model.zapStreamCoreTosAccepted {
                        ZapStreamCoreTosView(stream: stream)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Zap Stream Core")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if stream.zapStreamCoreEnabled {
                connectToZapStreamCore()
                model.startBalancePolling()
                if model.zapStreamCoreHasNwc, appState.wallet?.balance == nil {
                    Task { await appState.wallet?.refreshBalanceOnly() }
                }
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
        .sheet(isPresented: $showWalletReceiveSheet) {
            if let wallet = appState.wallet {
                ReceiveView(walletModel: wallet)
            }
        }
    }

    // MARK: - Enable Toggle
    private var enableToggle: some View {
        Toggle("Enable Zap Stream Core", isOn: $stream.zapStreamCoreEnabled)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    // MARK: - Connection Status View
    @ViewBuilder
    private var connectionStatusView: some View {
        if appState.keypair == nil {
            noIdentityView
        } else if isLoading {
            loadingView
        } else if let error = errorMessage {
            errorView(error)
        } else if let account = accountInfo {
            balanceCard(account)
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

    // MARK: - Loading View (Skeleton)
    private var loadingView: some View {
        VStack(spacing: 10) {
            HStack {
                Capsule().fill(Color(.systemGray4)).frame(width: 100, height: 18)
                Capsule().fill(Color(.systemGray5)).frame(width: 30, height: 14)
                Spacer()
                Capsule().fill(Color(.systemGray5)).frame(width: 60, height: 14)
            }
            Capsule().fill(Color(.systemGray5)).frame(height: 4)
            HStack {
                Capsule().fill(Color(.systemGray5)).frame(width: 100, height: 12)
                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shimmer()
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

    // MARK: - Balance Card
    
    private var walletConnected: Bool {
        if let wallet = appState.wallet {
            switch wallet.connect_state {
            case .existing, .spark: return true
            default: return false
            }
        }
        return false
        return false
    }

    private func balanceCard(_ account: ZapStreamCoreAccountResponse) -> some View {
        let cost = account.endpoints.first?.cost
        let rate = cost?.rate ?? 0

        return Group {
            if model.zapStreamCoreHasNwc {
                let walletMillisats = appState.wallet?.balance
                let walletSats = walletMillisats != nil ? Int(walletMillisats! / 1000) : nil
                let minutesLeft = (walletSats != nil && rate > 0) ? Double(walletSats!) / rate : Double.infinity
                let hoursLeft = minutesLeft / 60.0

                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(walletSats == nil ? .secondary : (walletSats! > 0 ? .green : .orange))
                        if let sats = walletSats {
                            Text(formatBalance(sats))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                            Text("sats in wallet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("0,000")
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .redacted(reason: .placeholder)
                            Text("sats in wallet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .redacted(reason: .placeholder)
                        }
                        Spacer()
                        Button { showWalletReceiveSheet = true } label: {
                            HStack(spacing: 4) {
                                Text("Fund Wallet")
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.green)
                        }
                    }

                    if walletSats == nil {
                        Capsule().fill(Color(.systemGray5)).frame(height: 4).shimmer()
                    } else if walletSats == 0 {
                        Text("Fund your wallet to stream")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if rate > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                                Capsule().fill(balanceColor(hoursLeft: hoursLeft))
                                    .frame(width: min(geo.size.width,
                                        geo.size.width * CGFloat(min(hoursLeft / 10.0, 1.0))),
                                        height: 4)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text(runwayText(minutesLeft: minutesLeft))
                                .font(.caption)
                                .foregroundColor(balanceColor(hoursLeft: hoursLeft))
                            Text("•").font(.caption).foregroundColor(.secondary)
                            Text("\(formatSatsRate(rate)) sats/min")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                        }
                    }

                    // Auto top-up controls (enable/disable)
                    Divider()
                    ZapStreamNWCAutoTopupView(stream: stream)
                        .environmentObject(model)
                        .environmentObject(appState)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            } else {
                let balance = model.zapStreamCoreBalance ?? account.balance
                let minutesLeft = rate > 0 ? Double(balance) / rate : Double.infinity
                let hoursLeft = minutesLeft / 60.0

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(balanceColor(hoursLeft: hoursLeft))
                        Text(formatBalance(balance))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Text("sats")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button { showTopUpSheet = true } label: {
                            HStack(spacing: 4) {
                                Text("Top Up")
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(balanceColor(hoursLeft: hoursLeft))
                        }
                    }

                    if rate > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                                Capsule().fill(balanceColor(hoursLeft: hoursLeft))
                                    .frame(width: min(geo.size.width,
                                        geo.size.width * CGFloat(min(hoursLeft / 10.0, 1.0))),
                                        height: 4)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text(runwayText(minutesLeft: minutesLeft))
                                .font(.caption)
                                .foregroundColor(balanceColor(hoursLeft: hoursLeft))
                            if let cost {
                                Text("•").font(.caption).foregroundColor(.secondary)
                                Text("\(cost.formattedRate) sats/\(cost.unit)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }

                    if walletConnected {
                        Divider()
                        ZapStreamNWCAutoTopupView(stream: stream)
                            .environmentObject(model)
                            .environmentObject(appState)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Balance Helpers

    private func balanceColor(hoursLeft: Double) -> Color {
        if hoursLeft < 1 { return .red }
        if hoursLeft < 2 { return .orange }
        return .green
    }

    private func runwayText(minutesLeft: Double) -> String {
        if minutesLeft == .infinity { return "Unlimited" }
        let hours = Int(minutesLeft) / 60
        let mins = Int(minutesLeft) % 60
        if hours > 0 {
            return "~\(hours)h \(mins)m of streaming"
        }
        return "~\(mins)m of streaming"
    }

    private func formatBalance(_ sats: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
    }


    // MARK: - Stream Settings Card
    private var streamSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SETTINGS")
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
                    self.model.zapStreamCoreTosAccepted = accountResponse.tos?.accepted ?? false
                    self.model.zapStreamCoreTosLink = accountResponse.tos?.link
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
