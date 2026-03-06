//
//  StreamSetupView.swift
//  swae
//
//  Unified stream setup view - goes directly to Zap Stream Core
//  Skips platform selection for simplified onboarding (Approach A)
//

import Combine
import SwiftUI

struct StreamSetupView: View {
    @EnvironmentObject private var model: Model
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.popToStreamsList) private var popToStreamsList
    
    // MARK: - State
    @State private var streamName: String = ""
    @State private var streamDescription: String = ""
    @State private var streamImage: String = ""
    @State private var selectedCategory: StreamCategory?
    @State private var selectedGameId: String?
    @State private var selectedGameName: String?
    @State private var additionalTags: String = ""
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var accountInfo: ZapStreamCoreAccountResponse?
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showCustomServer = false
    
    // MARK: - API Client
    // Create a single instance that persists across view updates
    private var apiClient: ZapStreamCoreApiClient {
        // This is fine because ZapStreamCoreApiClient is a class (reference type)
        // and we only use it for making API calls, not storing state
        ZapStreamCoreApiClient(config: ZapStreamCoreConfig())
    }
    
    private var canCreate: Bool {
        !streamName.trimmingCharacters(in: .whitespaces).isEmpty
            && accountInfo != nil
            && !isLoading
            && !isCreating
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
                streamNameField
                streamDescriptionField
                StreamCoverImageView(imageURL: $streamImage)
                CategoryPickerView(
                    selectedCategory: $selectedCategory,
                    selectedGameId: $selectedGameId,
                    selectedGameName: $selectedGameName,
                    additionalTags: $additionalTags
                )
                .disabled(accountInfo == nil)
                createButton
                Spacer(minLength: 40)
                customServerLink
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Set Up Stream")
        .navigationBarTitleDisplayMode(.inline)
        .settingsCloseButton()
        .onAppear {
            setupDefaults()
            connectToZapStreamCore()
        }
        .navigationDestination(isPresented: $showCustomServer) {
            StreamWizardCustomSettingsView(
                createStreamWizard: model.createStreamWizard,
                onComplete: {
                    model.createStreamFromWizard()
                    model.makeToast(title: "✅ Stream Created!", subTitle: "You're ready to go live")
                    // Pop to streams list instead of dismissing modal
                    if let popToStreamsList = popToStreamsList {
                        popToStreamsList()
                    } else {
                        dismiss()  // Fallback
                    }
                }
            )
            .environment(\.popToStreamsList, popToStreamsList)
        }
    }

    
    // MARK: - View Components
    
    private var headerView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.yellow)
            }
            
            Text("Set Up Your Stream")
                .font(.title2.bold())
                .foregroundColor(.primary)
            
            Text("Stream to Nostr and receive zaps from viewers")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    @ViewBuilder
    private var connectionStatusView: some View {
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
    
    private var noIdentityView: some View {
        VStack(spacing: 16) {
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
            
            Button {
                dismiss()
            } label: {
                Text("Create Identity")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
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

    
    private func connectedView(_ account: ZapStreamCoreAccountResponse) -> some View {
        let balance = model.zapStreamCoreBalance ?? account.balance
        return HStack(spacing: 12) {
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
            
            if let cost = account.endpoints.first?.cost {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(cost.rate)) sats/\(cost.unit)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Text("streaming cost")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var streamNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stream Title")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            
            TextField("My Stream", text: $streamName)
                .font(.body)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
                .disabled(accountInfo == nil)
        }
    }

    private var streamDescriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            TextField("What are you streaming today?", text: $streamDescription, axis: .vertical)
                .lineLimit(3...6)
                .font(.body)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
                .disabled(accountInfo == nil)
        }
    }

    private var createButton: some View {
        Button {
            createStream()
        } label: {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "bolt.fill")
                }
                Text("Create Stream")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canCreate ? Color.accentColor : Color.gray.opacity(0.3))
            )
            .foregroundColor(.white)
        }
        .disabled(!canCreate)
    }
    
    private var customServerLink: some View {
        Button {
            model.resetWizard()
            showCustomServer = true
        } label: {
            HStack {
                Text("Use custom server instead")
                    .font(.footnote)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundColor(Color(.separator).opacity(0.5))
            )
        }
    }

    
    // MARK: - Methods
    
    private func setupDefaults() {
        // Generate unique stream name
        let baseName = displayName ?? "My Stream"
        streamName = makeUniqueName(
            name: baseName,
            existingNames: model.database.streams
        )
        
        // Reset wizard state
        model.resetWizard()
        model.createStreamWizard.platform = .zapStreamCore
        model.createStreamWizard.networkSetup = .none
        model.createStreamWizard.customProtocol = .none
    }
    
    private func connectToZapStreamCore() {
        guard appState.keypair != nil else {
            isLoading = false
            print("ZapStreamCore: No keypair available")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        print("ZapStreamCore: Starting connection test...")
        
        // First test the connection
        apiClient.testConnection()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        self.isLoading = false
                        self.errorMessage = "Connection test failed: \(error.localizedDescription)"
                        print("ZapStreamCore: Connection test failed - \(error)")
                    }
                },
                receiveValue: { response in
                    print("ZapStreamCore: Connection test successful - \(response)")
                    // Now get account info
                    self.getAccountInfo()
                }
            )
            .store(in: &cancellables)
    }
    
    private func getAccountInfo() {
        print("ZapStreamCore: Getting account info...")
        
        apiClient.getAccountInfo(appState: appState)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoading = false
                    if case .failure(let error) = completion {
                        self.errorMessage = "Failed to get account info: \(error.localizedDescription)"
                        print("ZapStreamCore: Failed to get account info - \(error)")
                    }
                },
                receiveValue: { accountResponse in
                    print("ZapStreamCore: Got account info - balance: \(accountResponse.balance)")
                    self.accountInfo = accountResponse
                    self.errorMessage = nil

                    // Seed the shared model balance
                    self.model.zapStreamCoreBalance = accountResponse.balance
                    if let cost = accountResponse.endpoints.first?.cost {
                        self.model.zapStreamCoreRate = cost.rate
                    }
                    
                    // Store endpoint info in wizard
                    if let endpoint = accountResponse.endpoints.first {
                        let fullUrl = "\(endpoint.url)/\(endpoint.key)"
                        print("ZapStreamCore: Full RTMP URL: \(fullUrl)")
                        self.model.createStreamWizard.directIngest = fullUrl
                        self.model.createStreamWizard.directStreamKey = endpoint.key
                    } else {
                        print("ZapStreamCore: No endpoints available")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func createStream() {
        guard canCreate else { return }
        
        isCreating = true
        
        let trimmedName = streamName.trimmingCharacters(in: .whitespaces)
        model.createStreamWizard.name = trimmedName
        model.createStreamWizard.zapStreamCoreStreamTitle = trimmedName
        model.createStreamWizard.zapStreamCoreStreamDescription = streamDescription
            .trimmingCharacters(in: .whitespaces)
        model.createStreamWizard.zapStreamCoreStreamImage = streamImage
        model.createStreamWizard.zapStreamCoreStreamTags = CategoryTagsHelper.combine(
            category: selectedCategory,
            gameId: selectedGameId,
            additionalTags: additionalTags
        )
        model.createStreamWizard.zapStreamCoreIsPublic = true
        
        model.createStreamFromWizard()
        
        model.makeToast(title: "✅ Stream Created!", subTitle: "You're ready to go live")
        
        if let popToStreamsList = popToStreamsList {
            popToStreamsList()
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct StreamSetupView_Previews: PreviewProvider {
    static var previews: some View {
        StreamSetupView()
    }
}
#endif
