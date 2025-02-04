//
//  SignInView.swift
//  swae
//
//  Created by Suhail Saqan on 2/1/25.
//

import Combine
import NostrSDK
import SwiftData
import SwiftUI

struct SignInView: View, RelayURLValidating {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var appState: AppState

    @State private var nostrIdentifier: String = ""
    @State private var primaryRelay: String = ""

    @State private var validKey: Bool = false
    @State private var validatedRelayURL: URL?

    @State private var keypair: Keypair?
    @State private var publicKey: PublicKey?

//    private func relayFooter() -> AttributedString {
//        var footer = AttributedString(localized: .localizable.tryDefaultRelay(AppState.defaultRelayURLString))
//        if let range = footer.range(of: AppState.defaultRelayURLString) {
//            footer[range].underlineStyle = .single
//            footer[range].foregroundColor = .accent
//        }
//
//        return footer
//    }

    private func isValidRelay(address: String) -> Bool {
        (try? validateRelayURLString(address)) != nil
    }

    @MainActor
    private func signIn() {
        guard let validatedRelayURL else {
            return
        }

        if let keypair {
            appState.signIn(keypair: keypair, relayURLs: [validatedRelayURL])
            dismiss()
        } else if let publicKey {
            appState.signIn(publicKey: publicKey, relayURLs: [validatedRelayURL])
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    content: {
                        TextField("wss://relay.example.com", text: $primaryRelay)
                            .autocorrectionDisabled(false)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onReceive(Just(primaryRelay)) { newValue in
                                let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                primaryRelay = filtered

                                if filtered.isEmpty {
                                    return
                                }

                                validatedRelayURL = try? validateRelayURLString(filtered)
                            }
                    },
                    header: {
                        Text("Primary Relay (required)")
                    },
                    footer: {
//                        Text(relayFooter())
                        Text("")
                            .onTapGesture {
                                primaryRelay = AppState.defaultRelayURLString
                            }
                    }
                )

                Section(
                    content: {
                        SecureField("Enter your nsec", text: $nostrIdentifier)
                            .autocorrectionDisabled(false)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .onReceive(Just(nostrIdentifier)) { newValue in
                                let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                nostrIdentifier = filtered

                                if let keypair = Keypair(nsec: filtered) {
                                    self.keypair = keypair
                                    self.publicKey = keypair.publicKey
                                    validKey = true
                                } else if let publicKey = PublicKey(npub: filtered) {
                                    self.keypair = nil
                                    self.publicKey = publicKey
                                    validKey = true
                                } else {
                                    self.keypair = nil
                                    self.publicKey = nil
                                    validKey = false
                                }
                            }
                    },
                    header: {
                        Text("nsec")
                    },
                    footer: {
                        if keypair != nil {
                            Text("you have entered private key")
                        } else if publicKey != nil {
                            Text("you have entered public key")
                        }
                    }
                )
            }

            Button("sign in") {
                signIn()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!validKey || validatedRelayURL == nil)
        }
        .onAppear {
            let credentialHandler = CredentialHandler(appState: appState)
            credentialHandler.checkCredentials()
        }
    }
}

//struct SignInView_Previews: PreviewProvider {
//
//    @State static var appState = AppState()
//
//    static var previews: some View {
//        SignInView()
//            .environmentObject(appState)
//    }
//}
