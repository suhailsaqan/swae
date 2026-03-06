//
//  WalletConnectionViews.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import SwiftUI

// MARK: - Wallet Tab View
struct WalletTabView: View {
    @EnvironmentObject var appState: AppState
    let onNavigateToProfile: () -> Void

    var body: some View {
        Group {
            if let wallet = appState.wallet {
                WalletView(model: wallet)
                    .setupTab(.wallet)
            } else {
                WalletConnectionView(onNavigateToProfile: onNavigateToProfile)
                    .setupTab(.wallet)
            }
        }
    }
}

// MARK: - Wallet Connection View
struct WalletConnectionView: View {
    let onNavigateToProfile: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Bolt icon with orange glow
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.orange)
            }

            Text("Zaps Await")
                .font(.title2)
                .fontWeight(.bold)

            Text("Sign in with your Nostr key to set up a wallet and start sending zaps.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button(action: { onNavigateToProfile() }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Go to Profile")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.orange)
                )
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WalletConnectionView(onNavigateToProfile: {})
        // Note: WalletTabView now requires appState environment object
        // WalletTabView(onNavigateToProfile: {})
    }
    .padding()
    .preferredColorScheme(.dark)
}
