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
        if let wallet = appState.wallet,
           case .existing = wallet.connect_state {
            return true
        }
        return false
    }

    private var hasServerNwc: Bool { model.zapStreamCoreHasNwc }

    /// Minimum balance required: enough for at least 1 minute of streaming.
    private var isBalanceTooLow: Bool {
        guard let balance, rate > 0 else { return false }
        return Double(balance) < rate
    }

    /// Streaming runway in minutes (nil if unknown).
    private var minutesLeft: Double? {
        guard let balance, rate > 0 else { return nil }
        return Double(balance) / rate
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
                            .fill(isBalanceTooLow ? Color.gray.opacity(0.4) : Color.red)
                    )
                    .foregroundColor(.white)
                }
                .disabled(isBalanceTooLow && !hasServerNwc)

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
        .navigationTitle("Going Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            model.startBalancePolling()
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

    private var lowBalanceBanner: some View {
        VStack(spacing: 14) {
            if hasServerNwc {
                // Server-side auto-topup is active
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.title3)
                        .foregroundColor(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto top-up is active")
                            .font(.subheadline.weight(.semibold))
                        Text("Your balance will be topped up automatically when you start streaming.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not enough credits")
                            .font(.subheadline.weight(.semibold))
                        Text("You need at least \(Int(rate)) sats to start streaming.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if walletConnected {
                    // Quick one-tap wallet top-up
                    Button {
                        quickTopUpFromWallet()
                    } label: {
                        HStack(spacing: 6) {
                            if isQuickTopUpInProgress {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.subheadline)
                            }
                            Text("Top Up \(quickTopUpAmount) sats from Wallet")
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
                    .disabled(isQuickTopUpInProgress)

                    if let error = quickTopUpError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Button {
                    showTopUpSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: walletConnected ? "qrcode" : "bolt.fill")
                            .font(.subheadline)
                        Text(walletConnected ? "Manual Top Up" : "Top Up Balance")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(walletConnected ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(walletConnected ? Color.clear : Color.orange)
                    )
                    .overlay(
                        walletConnected ?
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1) : nil
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(hasServerNwc ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(hasServerNwc ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    /// Amount for quick top-up: enough for ~30 minutes of streaming
    private var quickTopUpAmount: Int {
        max(Int(rate * 30), Int(rate))
    }

    private func quickTopUpFromWallet() {
        guard let wallet = appState.wallet,
              case .existing = wallet.connect_state else { return }

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

        dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onGoLive()
        }
    }
}
