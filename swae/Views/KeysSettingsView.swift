//
//  KeysSettingsView.swift
//  swae
//
//  Created by Suhail Saqan on 2/22/25.
//


import Combine
import LocalAuthentication
import NostrSDK
import SwiftUI

struct KeysSettingsView: View {

    let publicKey: PublicKey
    @State private var privateKeyNsec: String = ""

    @EnvironmentObject var appState: AppState

    @State private var validPrivateKey: Bool = false

    @State private var incorrectPrivateKeyAlertPresented: Bool = false

    @State private var hasCopiedPublicKey: Bool = false

    var body: some View {
        List {
            Section(
                content: {
                    HStack {
                        Button(action: {
                            UIPasteboard.general.string = publicKey.npub
                            hasCopiedPublicKey = true
                        }, label: {
                            HStack {
                                Text(publicKey.npub)
                                    .textContentType(.username)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.1)

                                if hasCopiedPublicKey {
                                    Image(systemName: "doc.on.doc.fill")
                                } else {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                        })
                        .foregroundStyle(.primary)
                    }
                },
                header: {
                    Text("Public Key", comment: "Section header for public key.")
                }
            )

            Section(
                content: {
                    HStack {
                        SecureField(String(localized: "nsec...", comment: "Placeholder text to prompt user to enter private key."), text: $privateKeyNsec)
                            .disabled(validPrivateKey)
                            .autocorrectionDisabled(false)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .onReceive(Just(privateKeyNsec)) { newValue in
                                let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                privateKeyNsec = filtered

                                if let keypair = Keypair(nsec: filtered) {
                                    if keypair.publicKey == publicKey {
                                        appState.privateKeySecureStorage.store(for: keypair)
                                        privateKeyNsec = keypair.privateKey.nsec
                                        validPrivateKey = true
                                    } else {
                                        validPrivateKey = false
                                        incorrectPrivateKeyAlertPresented = true
                                    }
                                } else {
                                    validPrivateKey = false
                                }
                            }
                    }
                },
                header: {
                    Text("Private Key", comment: "Section header for private key.")
                },
                footer: {
                    if validPrivateKey {
                        Text("You have entered a private key, which means you will be able to view, create, modify, and RSVP to events.", comment: "Footer text indicating what it means to have a private key entered.")
                    } else if privateKeyNsec.isEmpty {
                        Text("You have not entered a private key, which means you will be not be able to create, modify, or RSVP to events.", comment: "Footer text indicating what it means to not have a private key entered.")
                    } else {
                        Text("You have entered an incorrect private key, which means you will be not be able to create, modify, or RSVP to events.", comment: "Footer text indicating what it means to have an incorrect private key entered.")
                    }
                }
            )
        }
        .alert(
            Text("Private key does not match the public key.", comment: "Alert message to tell user that the private key that they entered does not match the public key."),
            isPresented: $incorrectPrivateKeyAlertPresented
        ) {
            Button(String(localized: "OK", comment: "Button to acknowledge and dismiss an alert.")) {
                privateKeyNsec = ""
            }
        }
        .task {
            if let nsec = appState.privateKeySecureStorage.keypair(for: publicKey)?.privateKey.nsec {
                privateKeyNsec = nsec
                validPrivateKey = true
            } else {
                privateKeyNsec = ""
                validPrivateKey = false
            }
        }
    }
}
