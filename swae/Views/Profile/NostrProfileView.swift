//
//  NostrProfileView.swift
//  swae
//
//  Created by Suhail Saqan on 3/8/25.
//

import NostrSDK
import SwiftData
import SwiftUI

struct NostrProfileView: View {
    let pubkey: String
    @ObservedObject var appState: AppState
    @StateObject private var profileService = NostrProfileService()
    @State private var showZapSheet = false
    @State private var showProfileEdit = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if profileService.isLoading {
                    LoadingProfileView()
                } else if let profile = profileService.profile {
                    ProfileHeaderView(
                        profile: profile,
                        onZapPressed: { showZapSheet = true },
                        onEditPressed: { showProfileEdit = true }
                    )

                    ProfileStatsView(
                        profile: profile,
                        zapStats: profileService.zapStats
                    )

                    ProfileContentSection(
                        profile: profile,
                        appState: appState
                    )
                } else {
                    EmptyProfileView()
                }
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            profileService.loadProfile(pubkey: pubkey, appState: appState)
        }
        .sheet(isPresented: $showZapSheet) {
            ZapProfileView(
                targetPubkey: pubkey,
                appState: appState
            )
        }
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditView(
                profile: profileService.profile,
                appState: appState
            )
        }
    }
}

struct LoadingProfileView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Profile picture placeholder
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 120)
                .overlay(
                    ProgressView()
                        .scaleEffect(1.5)
                )

            // Name placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 24)

            // Bio placeholder
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 16)
            }
        }
        .padding(.vertical, 40)
    }
}

struct EmptyProfileView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.circle")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.6))

            VStack(spacing: 8) {
                Text("Profile Not Found")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This profile could not be loaded.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 40)
    }
}

struct ProfileHeaderView: View {
    let profile: MetadataEvent
    let onZapPressed: () -> Void
    let onEditPressed: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Profile picture
            AsyncImage(url: profile.userMetadata?.pictureURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.orange, lineWidth: 3)
            )

            // Name and username
            VStack(spacing: 4) {
                Text(profile.userMetadata?.displayName ?? "")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                if let username = profile.userMetadata?.name, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Bio
            if let bio = profile.userMetadata?.about, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
            }

            // Action buttons
            HStack(spacing: 16) {
                Button(action: onZapPressed) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Zap")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.orange)
                    )
                }

                Button(action: onEditPressed) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .font(.headline)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.orange, lineWidth: 2)
                    )
                }
            }
        }
    }
}

struct ProfileStatsView: View {
    let profile: MetadataEvent
    let zapStats: ZapStats?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Stats")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                // Followers (placeholder - would need to implement)
                StatItemView(
                    title: "Followers",
                    value: "0",
                    icon: "person.2.fill"
                )

                Divider()
                    .frame(height: 40)

                // Following (placeholder - would need to implement)
                StatItemView(
                    title: "Following",
                    value: "0",
                    icon: "person.badge.plus"
                )

                Divider()
                    .frame(height: 40)

                // Zap stats
                StatItemView(
                    title: "Zaps",
                    value: "\(zapStats?.totalActivity ?? 0)",
                    icon: "bolt.fill"
                )
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
}

struct StatItemView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.orange)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProfileContentSection: View {
    let profile: MetadataEvent
    let appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // Lightning Address (if available)
            if let lightningAddress = profile.userMetadata?.lightningAddress {
                LightningAddressView(address: lightningAddress)
            }

            // Website (if available)
            if let website = profile.userMetadata?.website {
                WebsiteView(url: website.absoluteString)
            }

            // Nostr NIP-05 identifier (if available)
            if let nostrAddress = profile.userMetadata?.nostrAddress {
                NIP05View(identifier: nostrAddress)
            }
        }
    }
}

struct LightningAddressView: View {
    let address: String

    var body: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundColor(.orange)

            Text(address)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button(action: {
                UIPasteboard.general.string = address
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct WebsiteView: View {
    let url: String

    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(.blue)

                Text(url)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
        }
    }
}

struct NIP05View: View {
    let identifier: String

    var body: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)

            Text(identifier)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Text("Verified")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.1))
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
}

struct ZapProfileView: View {
    let targetPubkey: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAmount: Int64 = 1_000_000
    @State private var content: String = ""
    @State private var showCustomAmount = false

    @StateObject private var zapService: ZapService

    private let quickAmounts: [Int64] = [
        100_000,  // 100 sats
        500_000,  // 500 sats
        1_000_000,  // 1,000 sats
        5_000_000,  // 5,000 sats
        10_000_000,  // 10,000 sats
        25_000_000,  // 25,000 sats
    ]

    init(targetPubkey: String, appState: AppState) {
        self.targetPubkey = targetPubkey
        self.appState = appState
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Send Zap")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Send a Lightning payment to this profile")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Amount selection
                VStack(spacing: 16) {
                    Text("Select Amount")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 3),
                        spacing: 12
                    ) {
                        ForEach(quickAmounts, id: \.self) { amount in
                            Button(action: {
                                selectedAmount = amount
                                showCustomAmount = false
                            }) {
                                VStack(spacing: 4) {
                                    Text("\(amount / 1000)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text("sats")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            selectedAmount == amount && !showCustomAmount
                                                ? Color.orange.opacity(0.2) : Color(.systemGray6)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    selectedAmount == amount && !showCustomAmount
                                                        ? Color.orange : Color.clear, lineWidth: 2)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    // Custom amount
                    Button(action: {
                        showCustomAmount = true
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Custom Amount")
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange, lineWidth: 1)
                        )
                    }
                }

                // Message
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message (Optional)")
                        .font(.headline)

                    TextField("Zap message...", text: $content, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                }

                Spacer()

                // Send button
                Button(action: sendZap) {
                    HStack {
                        if zapService.isProcessingZap {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "bolt.fill")
                        }

                        Text("Send \(selectedAmount / 1000) sats")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange)
                    )
                }
                .disabled(zapService.isProcessingZap)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Zap Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCustomAmount) {
                CustomAmountView(
                    selectedAmount: $selectedAmount,
                    onConfirm: { amount in
                        selectedAmount = amount
                        showCustomAmount = false
                    },
                    onCancel: {
                        showCustomAmount = false
                    }
                )
            }
            .onChange(of: zapService.zapSuccess) { success in
                if success {
                    dismiss()
                }
            }
        }
    }

    private func sendZap() {
        Task {
            let success = await zapService.sendZap(
                amount: selectedAmount,
                targetPubkey: targetPubkey,
                content: content.isEmpty ? "Zap! ⚡" : content
            )

            if success {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

struct CustomAmountView: View {
    @Binding var selectedAmount: Int64
    let onConfirm: (Int64) -> Void
    let onCancel: () -> Void

    @State private var amountText: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Enter Custom Amount")
                        .font(.title2)
                        .fontWeight(.semibold)

                    TextField("Amount in sats", text: $amountText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.title3)
                        .multilineTextAlignment(.center)

                    Text("sats")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        if let amount = Int64(amountText), amount > 0 {
                            onConfirm(amount * 1000)  // Convert to millisats
                        }
                    }) {
                        Text("Confirm")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.orange)
                            )
                    }
                    .disabled(
                        amountText.isEmpty || Int64(amountText) == nil || Int64(amountText)! <= 0)

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Profile Edit View

struct ProfileEditView: View {
    let profile: MetadataEvent?
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var profileService = NostrProfileService()
    @State private var displayName: String = ""
    @State private var about: String = ""
    @State private var picture: String = ""
    @State private var banner: String = ""
    @State private var website: String = ""
    @State private var lightningAddress: String = ""
    @State private var nip05: String = ""
    @State private var isSaving = false

    init(profile: MetadataEvent?, appState: AppState) {
        self.profile = profile
        self.appState = appState
        self._displayName = State(initialValue: profile?.userMetadata?.displayName ?? "")
        self._about = State(initialValue: profile?.userMetadata?.about ?? "")
        self._picture = State(initialValue: profile?.userMetadata?.pictureURL?.absoluteString ?? "")
        self._banner = State(
            initialValue: profile?.userMetadata?.bannerPictureURL?.absoluteString ?? "")
        self._website = State(initialValue: profile?.userMetadata?.website?.absoluteString ?? "")
        self._lightningAddress = State(initialValue: profile?.userMetadata?.lightningAddress ?? "")
        self._nip05 = State(initialValue: profile?.userMetadata?.nostrAddress ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Basic Information") {
                    TextField("Display Name", text: $displayName)
                    TextField("About", text: $about, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Images") {
                    TextField("Profile Picture URL", text: $picture)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("Banner URL", text: $banner)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }

                Section("Links") {
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }

                Section("Lightning") {
                    TextField("Lightning Address (user@domain.com)", text: $lightningAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }

                Section("Verification") {
                    TextField("NIP-05 Identifier", text: $nip05)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func saveProfile() {
        isSaving = true

        let profileData: [String: Any] = [
            "display_name": displayName,
            "about": about,
            "picture": picture.isEmpty ? nil : picture,
            "banner": banner.isEmpty ? nil : banner,
            "website": website.isEmpty ? nil : website,
            "lud16": lightningAddress.isEmpty ? nil : lightningAddress,
            "nip05": nip05.isEmpty ? nil : nip05,
        ].compactMapValues { $0 }

        Task {
            do {
                try await profileService.updateProfile(profileData, appState: appState)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    // Handle error
                }
            }
        }
    }
}

#Preview {
    NostrProfileView(
        pubkey: "test",
        appState: AppState(modelContext: ModelContext(try! ModelContainer(for: AppSettings.self)))
    )
}
