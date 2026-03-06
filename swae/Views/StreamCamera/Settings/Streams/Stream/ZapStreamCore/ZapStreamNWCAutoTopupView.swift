import Combine
import SwiftUI

/// Reusable auto-topup settings card for enabling/disabling server-side NWC auto-topup.
/// Embed this in StreamSettingsView and StreamZapStreamCoreSettingsView.
struct ZapStreamNWCAutoTopupView: View {
    @EnvironmentObject private var model: Model
    @EnvironmentObject private var appState: AppState

    let stream: SettingsStream

    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()

    private var hasNwc: Bool { model.zapStreamCoreHasNwc }

    private var walletConnected: Bool {
        if let wallet = appState.wallet,
           case .existing = wallet.connect_state {
            return true
        }
        return false
    }

    private var apiClient: ZapStreamCoreApiClient {
        ZapStreamCoreApiClient(config: ZapStreamCoreConfig(
            baseUrl: stream.zapStreamCoreBaseUrl
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasNwc {
                configuredView
            } else if walletConnected {
                enableView
            } else {
                noWalletView
            }
        }
    }

    // MARK: - Configured (has_nwc = true)

    private var configuredView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
                Text("Auto top-up active")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.green)
                Spacer()

                Button {
                    disableAutoTopup()
                } label: {
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Disable")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
                .disabled(isUpdating)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Enable (wallet connected, not configured)

    private var enableView: some View {
        VStack(spacing: 10) {
            Button {
                enableAutoTopup()
            } label: {
                HStack(spacing: 6) {
                    if isUpdating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                    }
                    Text("Enable Auto Top-Up")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green)
                )
            }
            .disabled(isUpdating)

            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - No Wallet

    private var noWalletView: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.circle")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Connect a wallet for auto top-ups")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func enableAutoTopup() {
        guard let wallet = appState.wallet,
              case .existing(let nwc) = wallet.connect_state else { return }

        let nwcUri = nwc.to_url().absoluteString
        isUpdating = true
        errorMessage = nil

        apiClient.updateAccount(appState: appState, nwcUri: nwcUri)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [self] completion in
                    isUpdating = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { _ in
                    model.refreshZapStreamCoreBalance()
                }
            )
            .store(in: &cancellables)
    }

    private func disableAutoTopup() {
        isUpdating = true
        errorMessage = nil

        apiClient.updateAccount(appState: appState, removeNwc: true)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [self] completion in
                    isUpdating = false
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { _ in
                    model.refreshZapStreamCoreBalance()
                }
            )
            .store(in: &cancellables)
    }
}
