//
//  InviteGuestSheet.swift
//  swae
//
//  SwiftUI sheet for selecting a guest to invite to a collab call.
//  Shows the user's follow list with profile pictures and display names,
//  plus a manual npub entry field.
//

import NostrSDK
import SwiftUI

struct InviteGuestSheet: View {
    @EnvironmentObject var model: Model
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var manualNpub = ""
    @State private var showManualEntry = false
    @State private var npubError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showManualEntry {
                    manualEntrySection
                } else {
                    followListSection
                }
            }
            .navigationTitle("Invite Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(showManualEntry ? "Follow List" : "Enter npub") {
                        showManualEntry.toggle()
                        npubError = nil
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Follow List

    private var followListSection: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search follows...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 8)

            if filteredFollows.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Follows" : "No Results",
                    systemImage: "person.2.slash",
                    description: Text(searchText.isEmpty
                        ? "Your follow list is empty."
                        : "No follows matching \"\(searchText)\".")
                )
            } else {
                List(filteredFollows, id: \.self) { pubkey in
                    Button {
                        inviteGuest(pubkey: pubkey)
                    } label: {
                        FollowRow(pubkey: pubkey, appState: appState)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Manual npub Entry

    private var manualEntrySection: some View {
        VStack(spacing: 16) {
            Text("Enter the guest's npub or hex pubkey")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 20)

            TextField("npub1... or hex pubkey", text: $manualNpub)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal)

            if let error = npubError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Button {
                resolveAndInvite()
            } label: {
                Label("Send Invite", systemImage: "paperplane.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualNpub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Data

    private var filteredFollows: [String] {
        let follows = Array(appState.followedPubkeys)
        if searchText.isEmpty { return follows.sorted() }
        let query = searchText.lowercased()
        return follows.filter { pubkey in
            if pubkey.lowercased().contains(query) { return true }
            if let meta = appState.metadataEvents[pubkey]?.userMetadata {
                if let name = meta.name, name.lowercased().contains(query) { return true }
                if let displayName = meta.displayName, displayName.lowercased().contains(query) { return true }
            }
            return false
        }.sorted()
    }

    // MARK: - Actions

    private func inviteGuest(pubkey: String) {
        let title = model.stream.name.isEmpty ? "Live Stream" : model.stream.name
        model.startCollabCall(
            guestPubkey: pubkey,
            streamTitle: title,
            streamId: nil
        )
        dismiss()
    }

    private func resolveAndInvite() {
        let input = manualNpub.trimmingCharacters(in: .whitespacesAndNewlines)
        npubError = nil

        // Try npub first
        if input.lowercased().hasPrefix("npub1") {
            if let pk = PublicKey(npub: input) {
                inviteGuest(pubkey: pk.hex)
            } else {
                npubError = "Invalid npub — check for typos"
            }
            return
        }

        // Try hex pubkey (64 hex chars)
        if input.count == 64, input.allSatisfy({ $0.isHexDigit }) {
            inviteGuest(pubkey: input)
            return
        }

        npubError = "Enter a valid npub1... or 64-character hex pubkey"
    }
}

// MARK: - Follow Row

private struct FollowRow: View {
    let pubkey: String
    let appState: AppState

    private var metadata: UserMetadata? {
        appState.metadataEvents[pubkey]?.userMetadata
    }

    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            if let url = metadata?.pictureURL {
                CacheAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)
            }

            // Name + npub
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(truncatedNpub)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "paperplane.fill")
                .foregroundColor(.accentColor)
                .font(.body)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Invite \(displayName)")
    }

    private var displayName: String {
        if let dn = metadata?.displayName, !dn.isEmpty { return dn }
        if let n = metadata?.name, !n.isEmpty { return n }
        return truncatedNpub
    }

    private var truncatedNpub: String {
        if let pk = PublicKey(hex: pubkey) {
            let npub = pk.npub
            return String(npub.prefix(10)) + "..." + String(npub.suffix(5))
        }
        return String(pubkey.prefix(8)) + "..."
    }
}
