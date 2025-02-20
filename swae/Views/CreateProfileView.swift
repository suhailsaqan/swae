//
//  CreateProfileView.swift
//  swae
//
//  Created by Suhail Saqan on 2/19/25.
//


import Kingfisher
import NostrSDK
import OrderedCollections
import SwiftUI

struct CreateProfileView: View, EventCreating {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var appState: AppState

    @State private var credentialHandler: CredentialHandler

    @State private var keypair: Keypair = Keypair.init()!

    @State private var username: String = ""
    @State private var about: String = ""
    @State private var picture: String = ""
    @State private var displayName: String = ""

    @State private var hasCopiedPublicKey: Bool = false
    @State private var hasCopiedPrivateKey: Bool = false

    init(appState: AppState) {
        credentialHandler = CredentialHandler(appState: appState)
    }

    var validatedPictureURL: URL? {
        guard let url = URL(string: picture.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return url
    }

    var canSave: Bool {
        return username.trimmedOrNilIfEmpty != nil && (picture.trimmedOrNilIfEmpty == nil || validatedPictureURL != nil)
    }

    var body: some View {
        Form {
            Section {
                Button(action: {
                    UIPasteboard.general.string = keypair.publicKey.npub
                    hasCopiedPublicKey = true
                }, label: {
                    HStack {
                        Text(keypair.publicKey.npub)
                            .textContentType(.username)
                            .disabled(true)
                            .lineLimit(2)
                            .minimumScaleFactor(0.1)

                        if hasCopiedPublicKey {
                            Image(systemName: "doc.on.doc.fill")
                        } else {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                })
            } header: {
                Text("Public Key", comment: "Section header for public key.")
            } footer: {
                Text("This public key is your unique identifier. You can share it with other people to identify you across any Nostr app. Save it in a place you will remember to look.", comment: "Footer text to explain what is the created public key.")
            }

            Section {
                Button(action: {
                    UIPasteboard.general.string = keypair.privateKey.nsec
                    hasCopiedPrivateKey = true
                }, label: {
                    HStack {
                        Text(keypair.privateKey.nsec)
                            .textContentType(.newPassword)
                            .disabled(true)
                            .lineLimit(2)
                            .minimumScaleFactor(0.1)

                        if hasCopiedPrivateKey {
                            Image(systemName: "doc.on.doc.fill")
                        } else {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                })
            } header: {
                Text("Private Key", comment: "Section header for private key.")
            } footer: {
                Text("This private key should not be shared with anyone. You can use it to sign into any Nostr app. Keep it secure in a password manager. You will not be able to recover it after you leave this screen.", comment: "Footer text to explain what is the created private key.")
            }

            let usernameTitle = String(localized: "Username", comment: "Section title for username entry.")
            Section {
                TextField(usernameTitle, text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text(usernameTitle)
            } footer: {
                Text("Usernames are not unique and not used for signing into an account. More than one person can have the same username.", comment: "Footer text to explain usernames.")
            }

            let displayNameTitle = String(localized: "Display Name (Optional)", comment: "Section title for display name entry.")
            Section {
                TextField(displayNameTitle, text: $displayName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text(displayNameTitle)
            } footer: {
                Text("An alternative, bigger name with richer characters than username.", comment: "Footer text to explain what is the display name.")
            }

            Section {
                TextField(String(localized: "https://example.com/image.png", comment: "Example image URL of a calendar event image."), text: $picture)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let validatedPictureURL {
                    KFImage.url(validatedPictureURL)
                        .resizable()
                        .placeholder { ProgressView() }
                        .scaledToFit()
                        .frame(maxWidth: 100, maxHeight: 200)
                }
            } header: {
                Text("Profile Picture (Optional)", comment: "Section title for profile picture entry.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    credentialHandler.saveCredential(keypair: keypair)
                    appState.privateKeySecureStorage.store(for: keypair)
                    let userMetadata = UserMetadata(name: username.trimmedOrNilIfEmpty, displayName: displayName.trimmedOrNilIfEmpty, pictureURL: validatedPictureURL)

                    do {
                        let readRelayURLs = appState.relayReadPool.relays.map { $0.url }
                        let writeRelayURLs = appState.relayWritePool.relays.map { $0.url }

                        let metadataEvent = try metadataEvent(withUserMetadata: userMetadata, signedBy: keypair)
                        let followListEvent = try followList(withPubkeys: [keypair.publicKey.hex], signedBy: keypair)
                        appState.relayWritePool.publishEvent(metadataEvent)
                        appState.relayWritePool.publishEvent(followListEvent)

                        let persistentNostrEvents = [
                            PersistentNostrEvent(nostrEvent: metadataEvent),
                            PersistentNostrEvent(nostrEvent: followListEvent)
                        ]
                        persistentNostrEvents.forEach {
                            appState.modelContext.insert($0)
                        }

                        try appState.modelContext.save()

                        appState.loadPersistentNostrEvents(persistentNostrEvents)

                        appState.signIn(keypair: keypair, relayURLs: Array(Set(readRelayURLs + writeRelayURLs)))
                    } catch {
                        print("Unable to publish or save MetadataEvent for new profile \(keypair.publicKey.npub).")
                    }

                    dismiss()
                }, label: {
                    Text("Create Profile", comment: "Button to create a profile.")
                })
                .disabled(!canSave)
            }
        }
    }
}
