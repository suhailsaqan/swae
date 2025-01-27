//
//  Home.swift
//  gibbe
//
//  Created by Suhail Saqan on 8/23/24.
//

import NostrSDK
import SwiftData
import SwiftUI

struct HomeView: View {
    
    //    @State private var privateKeyNsec: String = ""
    
    //    @State private var validPrivateKey: Bool = false
    
    //    @State private var incorrectPrivateKeyAlertPresented: Bool = false
    
    @State private var hasCopiedPublicKey: Bool = false
    
    @State private var viewModel: ViewModel
    
    @State private var inputKey: String = ""
    @State private var statusMessage: String = ""
    @EnvironmentObject var keychainHelper: KeychainHelper
    
    init(appState: AppState) {
        let viewModel = ViewModel(appState: appState)
        _viewModel = State(initialValue: viewModel)
    }
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            let publicKeyHex = viewModel.publicKeyHex
            if let publicKeyHex, let publicKey = PublicKey(hex: publicKeyHex) {
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
            } else {
                Button(action: {
                    let success = keychainHelper.deleteSecretKey()
                    statusMessage = success ? "Key deleted successfully." : "Failed to delete key."
                }) {
                    Text("Delete Key")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
    }
}

extension HomeView {
    @Observable class ViewModel {
        let appState: AppState

        init(appState: AppState) {
            self.appState = appState
        }

        var publicKeyHex: String? {
            appState.appSettings?.activeProfile?.publicKeyHex
        }

        var activeProfile: Profile? {
            appState.appSettings?.activeProfile
        }

        var activeProfileName: String {
            profileName(publicKeyHex: publicKeyHex)
        }

        var profiles: [Profile] {
            appState.profiles
        }

        func profileName(publicKeyHex: String?) -> String {
            Utilities.shared.profileName(
                publicKeyHex: publicKeyHex,
                appState: appState
            )
        }

        var isActiveProfileSignedInWithPrivateKey: Bool {
            guard let activeProfile = appState.appSettings?.activeProfile else {
                return false
            }
            return isSignedInWithPrivateKey(activeProfile)
        }

        func isSignedInWithPrivateKey(_ profile: Profile) -> Bool {
            guard let publicKeyHex = profile.publicKeyHex, let publicKey = PublicKey(hex: publicKeyHex) else {
                return false
            }
            return PrivateKeySecureStorage.shared.keypair(for: publicKey) != nil
        }

        func signOut(_ profile: Profile) {
            appState.deleteProfile(profile)
        }

        func isActiveProfile(_ profile: Profile) -> Bool {
            return appState.appSettings?.activeProfile == profile
        }
    }
}
