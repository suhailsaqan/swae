//
//  BackupWalletView.swift
//  swae
//
//  Shows the 12-word recovery phrase for the Spark wallet.
//  Requires biometric/passcode auth before revealing.
//

import SwiftUI
import LocalAuthentication

struct BackupWalletView: View {
    @ObservedObject var walletModel: WalletModel
    @Environment(\.dismiss) private var dismiss

    @State private var isAuthenticated = false
    @State private var authError: String?
    @State private var copied = false

    private var words: [String] {
        guard let mnemonic = walletModel.sparkService?.mnemonic else { return [] }
        return mnemonic.split(separator: " ").map(String.init)
    }

    private var fullMnemonic: String {
        walletModel.sparkService?.mnemonic ?? ""
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if !isAuthenticated {
                    authPromptView
                } else if words.isEmpty {
                    unavailableView
                } else {
                    mnemonicView
                }
            }
            .navigationTitle("Recovery Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { authenticate() }
    }

    // MARK: - Auth

    private var authPromptView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "faceid")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
            }

            Text("Authenticate to view\nyour recovery phrase")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
            }

            Button(action: authenticate) {
                Text("Authenticate")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.orange))
            }
            .padding(.horizontal, 40)
        }
        .padding(40)
    }

    // MARK: - Unavailable

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Recovery phrase not available")
                .font(.headline)
                .foregroundColor(.white)
            Text("Connect your wallet first.")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(40)
    }

    // MARK: - Mnemonic Display

    private var mnemonicView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: "key.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 8)

                    // Description
                    Text("Write down these 12 words in order.\nThis is the only way to recover your wallet.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    // Word grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack(spacing: 6) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .frame(width: 20, alignment: .trailing)
                                Text(word)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 100)
            }

            // Bottom bar with copy button
            VStack(spacing: 0) {
                Divider().background(Color.gray.opacity(0.3))
                Button(action: copyMnemonic) {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 16, weight: .medium))
                        Text(copied ? "Copied" : "Copy to Clipboard")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(copied ? .green : .black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(copied ? Color.green.opacity(0.15) : Color.orange)
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.black)
            }
        }
    }

    // MARK: - Actions

    private func copyMnemonic() {
        UIPasteboard.general.string = fullMnemonic
        withAnimation(.easeInOut(duration: 0.2)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) { copied = false }
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "View your wallet recovery phrase"
            ) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        isAuthenticated = true
                        authError = nil
                    } else {
                        authError = authenticationError?.localizedDescription
                    }
                }
            }
        } else {
            isAuthenticated = true
        }
    }
}
