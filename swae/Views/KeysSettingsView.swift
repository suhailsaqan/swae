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
    @State private var hasCopiedPrivateKey: Bool = false
    @State private var showPrivateKeyCopyAlert: Bool = false

    var body: some View {
        List {
            Section {
                HStack {
                    Button(action: {
                        UIPasteboard.general.string = publicKey.npub
                        hasCopiedPublicKey = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            hasCopiedPublicKey = false
                        }
                    }) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Public Key")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(publicKey.npub)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: hasCopiedPublicKey ? "checkmark.circle.fill" : "doc.on.doc")
                                .foregroundColor(hasCopiedPublicKey ? .green : .purple)
                                .font(.system(size: 20))
                        }
                    }
                }
            } header: {
                Text("Your Identity")
            } footer: {
                Text("Your public key is your unique identifier on Nostr. Share it with others to let them find you.")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    if validPrivateKey {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 24))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private Key Configured")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Full access enabled")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        
                        SecureField("nsec...", text: $privateKeyNsec)
                            .disabled(true)
                            .font(.system(.body, design: .monospaced))
                            .textContentType(.password)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            showPrivateKeyCopyAlert = true
                        }) {
                            HStack {
                                Image(systemName: hasCopiedPrivateKey ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundColor(hasCopiedPrivateKey ? .green : .orange)
                                Text(hasCopiedPrivateKey ? "Copied!" : "Copy Private Key")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(8)
                        }
                        .padding(.top, 4)
                    } else {
                        SecureField("Enter your private key (nsec...)", text: $privateKeyNsec)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled(true)
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
                }
            } header: {
                Text("Private Key")
            } footer: {
                if validPrivateKey {
                    Text("Your private key is securely stored. You can create posts, interact with content, and manage your profile.")
                } else if privateKeyNsec.isEmpty {
                    Text("Without a private key, you can only view content. Enter your private key to unlock full functionality.")
                } else {
                    Text("The private key you entered doesn't match your public key. Please check and try again.")
                }
            }
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Private Key Mismatch",
            isPresented: $incorrectPrivateKeyAlertPresented
        ) {
            Button("OK") {
                privateKeyNsec = ""
            }
        } message: {
            Text("The private key you entered doesn't match your public key. Please verify and try again.")
        }
        .alert(
            "Copy Private Key?",
            isPresented: $showPrivateKeyCopyAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Copy", role: .destructive) {
                authenticateAndCopyPrivateKey()
            }
        } message: {
            Text("Your private key controls your identity. Never share it with anyone. Only copy it to back it up securely.")
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
    
    private func authenticateAndCopyPrivateKey() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to copy your private key") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        UIPasteboard.general.string = privateKeyNsec
                        hasCopiedPrivateKey = true
                        
                        // Clear clipboard after 60 seconds for security
                        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                            if UIPasteboard.general.string == privateKeyNsec {
                                UIPasteboard.general.string = ""
                            }
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            hasCopiedPrivateKey = false
                        }
                    }
                }
            }
        } else {
            // No biometrics available, copy directly after warning
            UIPasteboard.general.string = privateKeyNsec
            hasCopiedPrivateKey = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                if UIPasteboard.general.string == privateKeyNsec {
                    UIPasteboard.general.string = ""
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                hasCopiedPrivateKey = false
            }
        }
    }
}
