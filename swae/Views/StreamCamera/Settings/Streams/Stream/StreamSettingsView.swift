import Combine
import SwiftUI

struct PlatformLogoAndNameView: View {
    let logo: String
    let name: String

    var body: some View {
        HStack {
            Image(logo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 25)
            Text(name)
        }
    }
}

struct TwitchLogoAndNameView: View {
    var body: some View {
        PlatformLogoAndNameView(logo: "TwitchLogo", name: String(localized: "Twitch"))
    }
}

struct KickLogoAndNameView: View {
    var body: some View {
        PlatformLogoAndNameView(logo: "KickLogo", name: String(localized: "Kick"))
    }
}

struct YouTubeLogoAndNameView: View {
    var body: some View {
        PlatformLogoAndNameView(logo: "YouTubeLogo", name: String(localized: "YouTube"))
    }
}

struct StreamPlatformsSettingsView: View {
    let stream: SettingsStream

    var body: some View {
        // Placeholder for streaming platforms
    }
}

struct StreamSettingsView: View {
    @EnvironmentObject private var model: Model
    @EnvironmentObject private var appState: AppState
    @ObservedObject var database: Database
    @ObservedObject var stream: SettingsStream
    
    // MARK: - Zap Stream State
    @State private var isLoading = false
    @State private var accountInfo: ZapStreamCoreAccountResponse?
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showTopUpSheet = false
    @State private var showWalletReceiveSheet = false
    /// Persists the selected game name across renders. CategoryTagsHelper.parse()
    /// cannot derive the name from the tag string alone, so we keep it in @State.
    @State private var selectedGameName: String?

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

    /// Converts between [String] array and structured category/game/tags for the picker.
    private var categoryBinding: Binding<StreamCategory?> {
        Binding(
            get: { CategoryTagsHelper.parse(tags: stream.zapStreamCoreStreamTags).category },
            set: { newCat in
                let parsed = CategoryTagsHelper.parse(tags: stream.zapStreamCoreStreamTags)
                stream.zapStreamCoreStreamTags = CategoryTagsHelper.combine(
                    category: newCat,
                    gameId: newCat?.id == "gaming" ? parsed.gameId : nil,
                    additionalTags: parsed.additionalTags
                )
            }
        )
    }

    private var gameIdBinding: Binding<String?> {
        Binding(
            get: { CategoryTagsHelper.parse(tags: stream.zapStreamCoreStreamTags).gameId },
            set: { newId in
                let parsed = CategoryTagsHelper.parse(tags: stream.zapStreamCoreStreamTags)
                stream.zapStreamCoreStreamTags = CategoryTagsHelper.combine(
                    category: parsed.category,
                    gameId: newId,
                    additionalTags: parsed.additionalTags
                )
            }
        )
    }

    private var gameNameBinding: Binding<String?> {
        Binding(
            get: { selectedGameName },
            set: { selectedGameName = $0 }
        )
    }

    private var additionalTagsBinding: Binding<String> {
        Binding(
            get: { CategoryTagsHelper.parse(tags: stream.zapStreamCoreStreamTags).additionalTags },
            set: { newValue in
                let parsed = CategoryTagsHelper.parse(tags: stream.zapStreamCoreStreamTags)
                stream.zapStreamCoreStreamTags = CategoryTagsHelper.combine(
                    category: parsed.category,
                    gameId: parsed.gameId,
                    additionalTags: newValue
                )
            }
        )
    }

    /// Converts between String content warning and Bool toggle.
    private var contentWarningBinding: Binding<Bool> {
        Binding(
            get: { !stream.zapStreamCoreContentWarning.isEmpty },
            set: { newValue in
                stream.zapStreamCoreContentWarning = newValue ? "nsfw" : ""
            }
        )
    }

    var body: some View {
        // Use ScrollView for Zap Streams, Form for custom streams
        if stream.zapStreamCoreEnabled {
            zapStreamBody
        } else {
            customStreamBody
        }
    }
    
    // MARK: - Zap Stream Body (Card-based layout)
    private var zapStreamBody: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Balance / skeleton / error / no-identity
                connectionStatusView
                
                // Stream settings (includes name)
                streamSettingsCard
                
                // Media section
                mediaSection
                
                // Advanced settings
                advancedSection
                
                // TOS acceptance for new users (shown at end of flow)
                if let account = accountInfo,
                   account.tos?.accepted == false,
                   !model.zapStreamCoreTosAccepted {
                    ZapStreamCoreTosView(stream: stream)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Stream")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            connectToZapStreamCore()
            model.startBalancePolling()
            // Load wallet balance if auto top-up is active and balance not yet loaded
            if model.zapStreamCoreHasNwc, appState.wallet?.balance == nil {
                Task { await appState.wallet?.refreshBalanceOnly() }
            }
        }
        .onDisappear {
            model.stopBalancePolling()
            // Persist any stream setting changes to disk
            model.store()
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

    
    // MARK: - Custom Stream Body (Form-based layout)
    private var customStreamBody: some View {
        Form {
            Section {
                NameEditView(name: $stream.name, existingNames: database.streams)
            }
            Section {
                NavigationLink {
                    StreamUrlSettingsView(stream: stream)
                } label: {
                    TextItemView(
                        name: String(localized: "URL"), value: schemeAndAddress(url: stream.url))
                }
                .disabled(stream.enabled && model.isLive)
                NavigationLink {
                    StreamZapStreamCoreSettingsView(stream: stream)
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("Zap Stream Core")
                        Spacer()
                        Text("OFF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                NavigationLink {
                    StreamVideoSettingsView(database: database, stream: stream)
                } label: {
                    Text("Video")
                }
                NavigationLink {
                    StreamAudioSettingsView(
                        stream: stream,
                        bitrate: Float(stream.audioBitrate / 1000)
                    )
                } label: {
                    Text("Audio")
                }
                if database.showAllSettings {
                    NavigationLink {
                        StreamAudioSettingsView(
                            stream: stream,
                            bitrate: Float(stream.audioBitrate / 1000)
                        )
                    } label: {
                        Text("Audio")
                    }
                    NavigationLink {
                        StreamRecordingSettingsView(stream: stream, recording: stream.recording)
                    } label: {
                        Text("Recording")
                    }
                    NavigationLink {
                        StreamReplaySettingsView(stream: stream, replay: stream.replay)
                    } label: {
                        Text("Replay")
                    }
                    NavigationLink {
                        StreamSnapshotSettingsView(stream: stream, recording: stream.recording)
                    } label: {
                        Text("Snapshot")
                    }
                }
                if isPhone() || isPad() {
                    Toggle(isOn: $stream.portrait) {
                        Text("Portrait")
                    }
                    .disabled(stream.enabled && (model.isLive || model.isRecording))
                    .onChange(of: stream.portrait) { _ in
                        if stream.enabled {
                            model.setCurrentStream(stream: stream)
                            model.reloadStream()
                            model.resetSelectedScene(changeScene: false)
                            model.updateOrientation()
                        }
                    }
                }
                if database.showAllSettings {
                    switch stream.getProtocol() {
                    case .srt:
                        NavigationLink {
                            StreamSrtSettingsView(
                                debug: database.debug,
                                stream: stream,
                                dnsLookupStrategy: stream.srt.dnsLookupStrategy!.rawValue
                            )
                        } label: {
                            Text("SRT(LA)")
                        }
                    case .rtmp:
                        NavigationLink {
                            StreamRtmpSettingsView(stream: stream)
                        } label: {
                            Text("RTMP")
                        }
                        StreamMultiStreamingSettingsView(
                            stream: stream, multiStreaming: stream.multiStreaming)
                    case .rist:
                        NavigationLink {
                            StreamRistSettingsView(stream: stream)
                        } label: {
                            Text("RIST")
                        }
                    }
                }
            } header: {
                Text("Media")
            }
            Section {
                StreamPlatformsSettingsView(stream: stream)
            } header: {
                Text("Streaming platforms")
            }
            Section {
                NavigationLink {
                    StreamObsRemoteControlSettingsView(stream: stream)
                } label: {
                    Toggle("OBS remote control", isOn: $stream.obsWebSocketEnabled)
                        .onChange(of: stream.obsWebSocketEnabled) { _ in
                            if stream.enabled {
                                model.obsWebSocketEnabledUpdated()
                            }
                        }
                }
                if database.showAllSettings {
                    NavigationLink {
                        GoLiveNotificationSettingsView(stream: stream)
                    } label: {
                        Text("Go live notification")
                    }
                    NavigationLink {
                        StreamRealtimeIrlSettingsView(stream: stream)
                    } label: {
                        Toggle(
                            "RealtimeIRL",
                            isOn: Binding(
                                get: {
                                    stream.realtimeIrlEnabled
                                },
                                set: { value in
                                    stream.realtimeIrlEnabled = value
                                    if stream.enabled {
                                        model.reloadLocation()
                                    }
                                }))
                    }
                }
            }
            if database.showAllSettings {
                if !isMac() {
                    Section {
                        Toggle("Background streaming", isOn: $stream.backgroundStreaming)
                    } footer: {
                        Text("Live stream and record when the app is in background mode.")
                    }
                }
                Section {
                    NavigationLink {
                        TextEditView(
                            title: String(localized: "Estimated viewer delay"),
                            value: formatOneDecimal(stream.estimatedViewerDelay),
                            keyboardType: .numbersAndPunctuation
                        ) {
                            guard let latency = Float($0), latency >= 0.0, latency <= 15.0 else {
                                return
                            }
                            stream.estimatedViewerDelay = latency
                        }
                    } label: {
                        TextItemView(
                            name: String(localized: "Estimated viewer delay"),
                            value: "\(formatOneDecimal(stream.estimatedViewerDelay)) s"
                        )
                    }
                } footer: {
                    Text(
                        """
                        Estimated viewer delay, for example used to make it easier to take \
                        snapshots using the chat bot. It does not delay the stream.
                        """)
                }
            }
        }
        .navigationTitle("Stream")
    }


    // MARK: - Zap Stream Components

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
                // Auto top-up active — show wallet balance (what the server charges)
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
                // Show balance + auto top-up prompt
                let balance = model.zapStreamCoreBalance ?? account.balance
                let minutesLeft = rate > 0 ? Double(balance) / rate : Double.infinity
                let hoursLeft = minutesLeft / 60.0

                VStack(spacing: 12) {
                    // Balance row
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

                    // Runway bar
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

                    // Auto top-up prompt when wallet is connected
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
            Text("STREAM INFO")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 16) {
                // Name field (internal identifier)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Stream Name", text: $stream.name)
                        .font(.body)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemGroupedBackground))
                        )
                }

                // Title field (what viewers see)
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

                // Cover Image
                StreamCoverImageView(imageURL: $stream.zapStreamCoreStreamImage)

                // Category & Tags
                CategoryPickerView(
                    selectedCategory: categoryBinding,
                    selectedGameId: gameIdBinding,
                    selectedGameName: gameNameBinding,
                    additionalTags: additionalTagsBinding
                )

                // Public toggle
                HStack {
                    Text("Public Stream")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: $stream.zapStreamCoreIsPublic)
                        .labelsHidden()
                }

                // Content Warning toggle
                HStack {
                    Text("NSFW Content Warning")
                        .font(.body)
                    Spacer()
                    Toggle("", isOn: contentWarningBinding)
                        .labelsHidden()
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - Media Section
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MEDIA")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                NavigationLink {
                    StreamVideoSettingsView(database: database, stream: stream)
                } label: {
                    HStack {
                        Text("Video")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(16)
                }

                Divider()
                    .padding(.leading, 16)

                NavigationLink {
                    StreamAudioSettingsView(
                        stream: stream,
                        bitrate: Float(stream.audioBitrate / 1000)
                    )
                } label: {
                    HStack {
                        Text("Audio")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(16)
                }

                Divider()
                    .padding(.leading, 16)

                NavigationLink {
                    StreamRecordingSettingsView(stream: stream, recording: stream.recording)
                } label: {
                    HStack {
                        Text("Recording")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(16)
                }
                
                Divider()
                    .padding(.leading, 16)
                
                HStack {
                    Text("Adaptive Resolution")
                        .foregroundColor(.primary)
                    Spacer()
                    Toggle("", isOn: $stream.adaptiveEncoderResolution)
                        .labelsHidden()
                        .disabled(stream.enabled && model.isLive)
                        .onChange(of: stream.adaptiveEncoderResolution) { _ in
                            model.reloadStreamIfEnabled(stream: stream)
                        }
                }
                .padding(16)

                Divider()
                    .padding(.leading, 16)
                
                if isPhone() || isPad() {
                    HStack {
                        Text("Portrait")
                            .foregroundColor(.primary)
                        Spacer()
                        Toggle("", isOn: $stream.portrait)
                            .labelsHidden()
                            .disabled(stream.enabled && (model.isLive || model.isRecording))
                            .onChange(of: stream.portrait) { _ in
                                if stream.enabled {
                                    model.setCurrentStream(stream: stream)
                                    model.reloadStream()
                                    model.resetSelectedScene(changeScene: false)
                                    model.updateOrientation()
                                }
                            }
                    }
                    .padding(16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }
    
    // MARK: - Advanced Section
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADVANCED")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                // Protocol picker
                HStack {
                    Text("Protocol")
                        .foregroundColor(.primary)
                    Spacer()
                    Picker("Protocol", selection: $stream.zapStreamCorePreferredProtocol) {
                        Text("RTMP").tag(ZapStreamCoreProtocol.rtmp)
                        Text("SRT").tag(ZapStreamCoreProtocol.srt)
                    }
                    .pickerStyle(.menu)
                }
                .padding(16)

                Divider()
                    .padding(.leading, 16)

                // Skip pre-stream review
                HStack {
                    Text("Skip Pre-Stream Review")
                        .foregroundColor(.primary)
                    Spacer()
                    Toggle("", isOn: $database.skipPreStreamReview)
                        .labelsHidden()
                }
                .padding(16)

                Divider()
                    .padding(.leading, 16)

                // OBS remote control
                NavigationLink {
                    StreamObsRemoteControlSettingsView(stream: stream)
                } label: {
                    HStack {
                        Text("OBS Remote Control")
                            .foregroundColor(.primary)
                        Spacer()
                        Toggle("", isOn: $stream.obsWebSocketEnabled)
                            .labelsHidden()
                            .onChange(of: stream.obsWebSocketEnabled) { _ in
                                if stream.enabled {
                                    model.obsWebSocketEnabledUpdated()
                                }
                            }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(16)
                }

                Divider()
                    .padding(.leading, 16)

                // OBS remote control is the last item
            }
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
