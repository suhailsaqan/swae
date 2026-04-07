import Combine
import SwiftUI

// MARK: - Zap Stream Core Wizard View

struct ZapStreamCoreWizardView: View {
    @EnvironmentObject private var model: Model
    @StateObject private var viewModel = ZapStreamCoreWizardViewModel()
    @State private var showingPaymentView = false
    @State private var showingAccountInfo = false

    var body: some View {
        VStack(spacing: 20) {
            // Account Information Section
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Text("Account Information")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: {
                        if let appState = model.appState {
                            viewModel.loadAccountInfo(appState: appState)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                    .disabled(viewModel.isLoadingAccount)
                }

                if viewModel.isLoadingAccount {
                    ProgressView("Loading account info...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let accountInfo = viewModel.accountInfo {
                    AccountInfoCard(accountInfo: accountInfo)
                } else if let error = viewModel.accountError {
                    ErrorCard(message: error)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Payment Section
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .font(.title2)
                        .foregroundColor(.yellow)

                    Text("Account Balance")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()

                    if let balance = model.zapStreamCoreBalance ?? viewModel.accountBalance.map({ Int($0) }) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(balance)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("sats")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let balance = model.zapStreamCoreBalance.map({ Double($0) }) ?? viewModel.accountBalance {
                    BalanceIndicator(balance: balance)
                }

                // Auto top-up prompt
                WizardAutoTopupPrompt()

                Button(action: {
                    showingPaymentView = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Top Up Account")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Streaming Information
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundColor(.green)

                    Text("Streaming Ready")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Spacer()
                }

                if let accountInfo = viewModel.accountInfo {
                    StreamingDetailsCard(accountInfo: accountInfo)
                } else {
                    Text("Account information will be loaded to show streaming details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Spacer()
        }
        .padding()
        .onAppear {
            if let appState = model.appState {
                viewModel.loadAccountInfo(appState: appState)
            }
            model.startBalancePolling()
        }
        .onDisappear {
            model.stopBalancePolling()
        }
        .sheet(isPresented: $showingPaymentView, onDismiss: {
            model.refreshZapStreamCoreBalance()
        }) {
            ZapStreamCorePaymentView()
                .environmentObject(model)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

// MARK: - Account Info Card

struct AccountInfoCard: View {
    let accountInfo: ZapStreamCoreAccountResponse

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Balance:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(accountInfo.balance) sats")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack {
                Text("Endpoints:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(accountInfo.endpoints.count) available")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack {
                Text("Terms Accepted:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(accountInfo.tos?.accepted == true ? "Yes" : "No")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(accountInfo.tos?.accepted == true ? .green : .red)
            }
        }
    }
}

// MARK: - Balance Indicator

struct BalanceIndicator: View {
    let balance: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Current Balance")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(balance)) sats")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            // Balance status indicator
            HStack {
                Image(systemName: balanceStatusIcon)
                    .foregroundColor(balanceStatusColor)

                Text(balanceStatusText)
                    .font(.caption)
                    .foregroundColor(balanceStatusColor)

                Spacer()
            }
        }
    }

    private var balanceStatusIcon: String {
        if balance >= 10000 {
            return "checkmark.circle.fill"
        } else if balance >= 1000 {
            return "exclamationmark.triangle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }

    private var balanceStatusColor: Color {
        if balance >= 10000 {
            return .green
        } else if balance >= 1000 {
            return .orange
        } else {
            return .red
        }
    }

    private var balanceStatusText: String {
        if balance >= 10000 {
            return "Good balance for streaming"
        } else if balance >= 1000 {
            return "Low balance - consider topping up"
        } else {
            return "Very low balance - top up needed"
        }
    }
}

// MARK: - Streaming Details Card

struct StreamingDetailsCard: View {
    let accountInfo: ZapStreamCoreAccountResponse

    var body: some View {
        VStack(spacing: 8) {
            if let rtmpEndpoint = accountInfo.endpoints.first(where: {
                $0.name.lowercased().contains("rtmp")
            }) {
                HStack {
                    Text("RTMP URL:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(rtmpEndpoint.url)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }

                HStack {
                    Text("Stream Key:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(rtmpEndpoint.key.prefix(8)) + "...")
                        .font(.system(.caption, design: .monospaced))
                }
            }

            HStack {
                Text("Balance:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(accountInfo.balance) sats")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Error Card

struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)

            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Zap Stream Core Wizard ViewModel

@MainActor
class ZapStreamCoreWizardViewModel: ObservableObject {
    @Published var isLoadingAccount = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var accountInfo: ZapStreamCoreAccountResponse?
    @Published var accountBalance: Double?
    @Published var accountError: String?

    private var apiClient: ZapStreamCoreApiClient?
    private var cancellables = Set<AnyCancellable>()

    func loadAccountInfo(appState: AppState) {
        guard let apiClient = apiClient else {
            setupApiClient()
            return
        }

        isLoadingAccount = true
        accountError = nil

        apiClient.getAccountInfo(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoadingAccount = false
                    if case .failure(let error) = completion {
                        self?.accountError = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] accountInfo in
                    self?.accountInfo = accountInfo
                    self?.accountBalance = Double(accountInfo.balance)
                }
            )
            .store(in: &cancellables)
    }

    private func setupApiClient() {
        let config = ZapStreamCoreConfig()
        apiClient = ZapStreamCoreApiClient(config: config)
    }

    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Wizard Auto Top-Up Prompt

/// Lightweight auto-topup prompt for the wizard's Account Balance section.
struct WizardAutoTopupPrompt: View {
    @EnvironmentObject private var model: Model
    @EnvironmentObject private var appState: AppState

    private var hasNwc: Bool { model.zapStreamCoreHasNwc }

    private var walletConnected: Bool {
        if let wallet = appState.wallet {
            switch wallet.connect_state {
            case .existing, .spark: return true
            default: return false
            }
        }
        return false
    }

    var body: some View {
        if hasNwc {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Auto-paying from your wallet")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        } else if walletConnected {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable wallet auto-payment")
                        .font(.subheadline.weight(.medium))
                    Text("Automatically maintain your balance from your wallet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect a wallet")
                        .font(.subheadline.weight(.medium))
                    Text("Enable automatic balance top-ups")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.systemGray5))
            .cornerRadius(8)
        }
    }
}

#Preview {
    ZapStreamCoreWizardView()
        .environmentObject(Model())
}
