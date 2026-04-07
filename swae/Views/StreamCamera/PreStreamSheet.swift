//
//  PreStreamSheet.swift
//  swae
//
//  Pre-stream review sheet shown before going live.
//  Lets the user review and quick-edit metadata before the countdown starts.
//

import Combine
import SwiftUI

struct PreStreamSheet: View {
    @EnvironmentObject private var model: Model
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var summary: String
    @State private var image: String
    @State private var selectedCategory: StreamCategory?
    @State private var selectedGameId: String?
    @State private var selectedGameName: String?
    @State private var additionalTags: String
    @State private var skipReview: Bool
    @State private var showTopUpSheet = false
    @State private var isQuickTopUpInProgress = false
    @State private var quickTopUpError: String?

    var onGoLive: () -> Void

    /// Reads live balance from the shared model.
    private var balance: Int? { model.zapStreamCoreBalance }
    private var rate: Double { model.zapStreamCoreRate }

    private var walletConnected: Bool {
        if let wallet = appState.wallet {
            switch wallet.connect_state {
            case .existing, .spark: return true
            default: return false
            }
        }
        return false
    }

    private var hasServerNwc: Bool { model.zapStreamCoreHasNwc }

    /// Wallet balance in sats (what auto top-up draws from)
    private var walletBalanceSats: Int {
        Int((appState.wallet?.balance ?? 0) / 1000)
    }

    /// The balance that matters for streaming: wallet balance when auto top-up is active,
    /// zap.stream balance otherwise.
    private var effectiveBalance: Int {
        if hasServerNwc { return walletBalanceSats }
        return balance ?? 0
    }

    /// Minimum balance required: enough for at least 1 minute of streaming.
    private var isBalanceTooLow: Bool {
        guard rate > 0 else { return false }
        return Double(effectiveBalance) < rate
    }

    /// Is the wallet empty when auto top-up is active?
    private var isWalletEmpty: Bool {
        hasServerNwc && walletBalanceSats == 0
    }

    /// Streaming runway in minutes (nil if unknown).
    private var minutesLeft: Double? {
        guard rate > 0 else { return nil }
        let bal = Double(effectiveBalance)
        guard bal > 0 else { return nil }
        return bal / rate
    }

    /// Whether the user has enough balance to actually start streaming.
    /// Only applies to Zap Stream Core streams that require payment.
    private var canGoLive: Bool {
        guard model.stream.zapStreamCoreEnabled else { return true }
        return !isBalanceTooLow
    }

    init(stream: SettingsStream, skipReview: Bool, onGoLive: @escaping () -> Void) {
        _title = State(initialValue: stream.zapStreamCoreStreamTitle.isEmpty
            ? stream.name : stream.zapStreamCoreStreamTitle)
        _summary = State(initialValue: stream.zapStreamCoreStreamDescription)
        _image = State(initialValue: stream.zapStreamCoreStreamImage)

        let parsed = CategoryTagsHelper.parse(tags: stream.zapStreamCoreStreamTags)
        _selectedCategory = State(initialValue: parsed.category)
        _selectedGameId = State(initialValue: parsed.gameId)
        _selectedGameName = State(initialValue: parsed.gameName)
        _additionalTags = State(initialValue: parsed.additionalTags)

        _skipReview = State(initialValue: skipReview)
        self.onGoLive = onGoLive
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    TextField("Stream title", text: $title)
                        .font(.body)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                }

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    TextField("What are you streaming?", text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.body)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                }

                // Cover Image
                StreamCoverImageView(imageURL: $image)

                // Category & Tags
                CategoryPickerView(
                    selectedCategory: $selectedCategory,
                    selectedGameId: $selectedGameId,
                    selectedGameName: $selectedGameName,
                    additionalTags: $additionalTags
                )

                // Low balance warning or runway pill
                if isBalanceTooLow {
                    lowBalanceBanner
                } else if let mins = minutesLeft {
                    balancePill(minutes: mins)
                }

                // Go Live button
                Button {
                    saveAndGoLive()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("GO LIVE")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canGoLive ? Color.red : Color.gray.opacity(0.4))
                    )
                    .foregroundColor(.white)
                }
                .disabled(!canGoLive)

                // Skip toggle
                Toggle("Skip review next time", isOn: $skipReview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .onChange(of: skipReview) { newValue in
                        model.database.skipPreStreamReview = newValue
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .navigationTitle("Going Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            model.startBalancePolling()
            if model.zapStreamCoreHasNwc, appState.wallet?.balance == nil {
                Task { await appState.wallet?.refreshBalanceOnly() }
            }
        }
        .onDisappear {
            model.stopBalancePolling()
        }
        .sheet(isPresented: $showTopUpSheet, onDismiss: {
            model.refreshZapStreamCoreBalance()
        }) {
            ZapStreamCorePaymentView()
                .environmentObject(model)
        }
    }

    // MARK: - Low Balance Banner

    @State private var isEnablingAutoTopup = false

    private var lowBalanceBanner: some View {
        VStack(spacing: 14) {
            if hasServerNwc && !isWalletEmpty && !isBalanceTooLow {
                // Auto top-up active and wallet has enough funds
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-paying from your wallet")
                            .font(.subheadline.weight(.semibold))
                        Text("\(walletBalanceSats) sats in wallet • Charged as you stream")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            } else if hasServerNwc && !isWalletEmpty && isBalanceTooLow {
                // Auto top-up active but wallet balance too low for even 1 minute
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wallet balance too low")
                            .font(.subheadline.weight(.semibold))
                        Text("You need at least \(formatSatsRate(rate)) sats to start. You have \(walletBalanceSats) sats.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Button {
                    showTopUpSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.subheadline)
                        Text("Fund Wallet")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange)
                    )
                }
            } else if hasServerNwc && isWalletEmpty {
                // Auto top-up active but wallet is empty
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wallet is empty")
                            .font(.subheadline.weight(.semibold))
                        Text("Fund your wallet to stream. It will charge it as you go.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            } else if walletConnected {
                // Wallet connected but NWC not enabled — offer combined action
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable wallet auto-payment to go live")
                            .font(.subheadline.weight(.semibold))
                        Text("Your wallet will be charged \(formatSatsRate(rate)) sats/min while streaming.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Enable & Go Live combined button
                Button {
                    enableAutoTopupAndGoLive()
                } label: {
                    HStack(spacing: 6) {
                        if isEnablingAutoTopup {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.subheadline)
                        }
                        Text("Enable & Go Live")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green)
                    )
                }
                .disabled(isEnablingAutoTopup)

                // Fallback manual top-up
                Button {
                    showTopUpSheet = true
                } label: {
                    Text("Top up manually instead")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // No wallet — manual top-up only
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not enough credits")
                            .font(.subheadline.weight(.semibold))
                        Text("You need at least \(formatSatsRate(rate)) sats to start streaming.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Button {
                    showTopUpSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.subheadline)
                        Text("Top Up Balance")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange)
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(bannerBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(bannerBorderColor, lineWidth: 1)
        )
    }

    private var bannerBackgroundColor: Color {
        if hasServerNwc && !isBalanceTooLow { return Color.green.opacity(0.1) }
        if hasServerNwc { return Color.orange.opacity(0.08) }
        if walletConnected { return Color.orange.opacity(0.08) }
        return Color.red.opacity(0.1)
    }

    private var bannerBorderColor: Color {
        if hasServerNwc && !isBalanceTooLow { return Color.green.opacity(0.3) }
        if hasServerNwc { return Color.orange.opacity(0.2) }
        if walletConnected { return Color.orange.opacity(0.2) }
        return Color.red.opacity(0.3)
    }

    /// Enables auto top-up on the server then triggers go-live
    private func enableAutoTopupAndGoLive() {
        guard let wallet = appState.wallet else { return }

        switch wallet.connect_state {
        case .existing(let nwc):
            // Coinos path — use NWC URL directly
            isEnablingAutoTopup = true
            let nwcUri = nwc.to_url().absoluteString
            sendNwcUriAndGoLive(nwcUri)

        case .spark:
            // Spark path — start on-device NWC responder
            guard let spark = wallet.sparkService else { return }
            isEnablingAutoTopup = true
            Task { @MainActor in
                do {
                    let responder = NWCResponder()
                    let nwcURL = try await responder.start(sparkService: spark)
                    model.nwcResponder = responder
                    sendNwcUriAndGoLive(nwcURL.to_url().absoluteString)
                } catch {
                    print("❌ NWCResponder start failed: \(error)")
                    isEnablingAutoTopup = false
                    quickTopUpFromWallet()
                }
            }

        default:
            return
        }
    }

    private func sendNwcUriAndGoLive(_ nwcUri: String) {
        let config = ZapStreamCoreConfig(baseUrl: model.stream.zapStreamCoreBaseUrl)
        let client = ZapStreamCoreApiClient(config: config)

        var cancellable: AnyCancellable?
        cancellable = client.updateAccount(appState: appState, nwcUri: nwcUri)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [self] completion in
                    isEnablingAutoTopup = false
                    if case .failure = completion {
                        model.nwcResponder?.stop()
                        model.nwcResponder = nil
                        quickTopUpFromWallet()
                    }
                    _ = cancellable
                },
                receiveValue: { [self] _ in
                    model.zapStreamCoreHasNwc = true
                    model.refreshZapStreamCoreBalance()
                    saveAndGoLive()
                }
            )
    }

    /// Amount for quick top-up: enough for ~30 minutes of streaming
    private var quickTopUpAmount: Int {
        max(Int(rate * 30), Int(rate))
    }

    private func quickTopUpFromWallet() {
        guard let wallet = appState.wallet else { return }
        switch wallet.connect_state {
        case .existing, .spark: break
        default: return
        }

        isQuickTopUpInProgress = true
        quickTopUpError = nil

        let config = ZapStreamCoreConfig(baseUrl: model.stream.zapStreamCoreBaseUrl)
        let client = ZapStreamCoreApiClient(config: config)

        // Create invoice then pay it
        var cancellable: AnyCancellable?
        cancellable = client.createInvoice(
            appState: appState,
            amount: Double(quickTopUpAmount),
            currency: "sats",
            description: "Pre-stream top-up"
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [self] completion in
                if case .failure(let error) = completion {
                    isQuickTopUpInProgress = false
                    quickTopUpError = error.localizedDescription
                }
                _ = cancellable // prevent dealloc
            },
            receiveValue: { [self] invoice in
                Task {
                    do {
                        let _ = try await wallet.payInvoice(invoice.paymentRequest)
                        await MainActor.run {
                            isQuickTopUpInProgress = false
                            model.refreshZapStreamCoreBalance()
                        }
                    } catch {
                        await MainActor.run {
                            isQuickTopUpInProgress = false
                            quickTopUpError = error.localizedDescription
                        }
                    }
                }
            }
        )
    }

    // MARK: - Balance Pill

    private func balancePill(minutes: Double) -> some View {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        let text = hours > 0 ? "~\(hours)h \(mins)m left" : "~\(mins)m left"
        let color: Color = minutes < 60 ? .orange : .green

        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundColor(color)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveAndGoLive() {
        model.stream.zapStreamCoreStreamTitle = title.trimmingCharacters(in: .whitespaces)
        model.stream.zapStreamCoreStreamDescription = summary.trimmingCharacters(in: .whitespaces)
        model.stream.zapStreamCoreStreamImage = image
        model.stream.zapStreamCoreStreamTags = CategoryTagsHelper.combine(
            category: selectedCategory,
            gameId: selectedGameId,
            additionalTags: additionalTags
        )

        // Persist settings to disk immediately so they survive app lifecycle events
        model.store()

        dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onGoLive()
        }
    }
}
