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
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    @State private var nostrIdentifier: String = ""
    @State private var primaryRelay: String = ""
    @State private var showAdvancedOptions: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    @State private var validKey: Bool = false
    @State private var validatedRelayURL: URL?
    @State private var keypair: Keypair?
    @State private var publicKey: PublicKey?
    @State private var credentialHandler: CredentialHandler?

    @MainActor
    private func signIn() {
        guard let validatedRelayURL else {
            errorMessage = "Please enter a valid relay URL"
            showError = true
            return
        }

        if let keypair {
            appState.signIn(keypair: keypair, relayURLs: [validatedRelayURL])
            // Auto-connect wallet in the background
            if WalletModel.useSparkBackend {
                appState.autoConnectSparkWallet(keypair: keypair)
            } else {
                appState.autoConnectCoinosWallet(keypair: keypair)
            }
            hasCompletedOnboarding = true
            dismiss()
        } else if let publicKey {
            appState.signIn(publicKey: publicKey, relayURLs: [validatedRelayURL])
            hasCompletedOnboarding = true
            dismiss()
        }
    }
    
    private func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            nostrIdentifier = clipboardString
            validateKey(clipboardString)
        }
    }
    
    private func validateKey(_ value: String) {
        let filtered = value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)
                        
                        Text("Sign In")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Enter your Nostr key to access your account")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 20)
                    
                    // Key Input Section
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Key")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                SecureField("nsec... or npub...", text: $nostrIdentifier)
                                    .font(.system(.body, design: .monospaced))
                                    .textContentType(.password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(12)
                                    .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                    .onReceive(Just(nostrIdentifier)) { newValue in
                                        validateKey(newValue)
                                    }
                                
                                Button(action: pasteFromClipboard) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 20))
                                        .foregroundColor(.purple)
                                        .frame(width: 44, height: 44)
                                        .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color(UIColor.systemGray6))
                                        .cornerRadius(10)
                                }
                            }
                            
                            // Key Status Indicator
                            if !nostrIdentifier.isEmpty {
                                HStack(spacing: 6) {
                                    if validKey {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        if keypair != nil {
                                            Text("Private key detected - Full access")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else {
                                            Text("Public key detected - Read-only access")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    } else {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.red)
                                        Text("Invalid key format")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Info Box
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Key Format")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Private key (nsec...): Full access to post and interact")
                                Text("• Public key (npub...): View-only access")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal, 20)
                    }
                    
                    // Advanced Options
                    VStack(spacing: 16) {
                        Button(action: {
                            withAnimation {
                                showAdvancedOptions.toggle()
                            }
                        }) {
                            HStack {
                                Text("Advanced Options")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                        }
                        
                        if showAdvancedOptions {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Primary Relay")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("wss://relay.example.com", text: $primaryRelay)
                                    .font(.system(.body, design: .monospaced))
                                    .textContentType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(12)
                                    .background(colorScheme == .dark ? Color(UIColor.secondarySystemGroupedBackground) : Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                    .onReceive(Just(primaryRelay)) { newValue in
                                        let filtered = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        primaryRelay = filtered

                                        if filtered.isEmpty {
                                            validatedRelayURL = nil
                                            return
                                        }

                                        validatedRelayURL = try? validateRelayURLString(filtered)
                                    }
                                
                                if validatedRelayURL != nil {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Valid relay URL")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                    .padding(.top, 4)
                                }
                                
                                Button(action: {
                                    primaryRelay = AppState.defaultRelayURLString
                                }) {
                                    Text("Use Default Relay")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    
                    Spacer()
                    
                    // Sign In Button
                    VStack(spacing: 16) {
                        Button(action: signIn) {
                            HStack {
                                Spacer()
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(16)
                            .background(validKey && validatedRelayURL != nil ? Color.purple : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(!validKey || validatedRelayURL == nil)
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            primaryRelay = AppState.defaultRelayURLString
            // Validate the default relay immediately
            validatedRelayURL = try? validateRelayURLString(AppState.defaultRelayURLString)
            let handler = CredentialHandler(appState: appState)
            handler.onSignInComplete = {
                hasCompletedOnboarding = true
                dismiss()
            }
            credentialHandler = handler
            handler.checkCredentials()
        }
    }
}
