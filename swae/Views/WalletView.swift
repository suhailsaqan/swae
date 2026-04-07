//
//  WalletView.swift
//  swae
//
//  Created by Suhail Saqan on 3/4/25.
//

import SwiftUI

struct WalletView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var model: WalletModel

    init( /*appState: AppState,*/model: WalletModel) {
        //        self.appState = appState
        //        self._model = ObservedObject(wrappedValue: model ?? appState.wallet)
        self._model = ObservedObject(wrappedValue: model)
    }

    func MainWalletView(nwc: WalletConnectURL) -> some View {
        WalletMainView(walletModel: model)
    }

    var body: some View {
        NavigationStack {
            if appState.isAutoConnectingWallet {
                // Auto wallet setup in progress — show loading instead of onboarding
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Setting up your wallet...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch model.connect_state {
                case .new:
                    ConnectWalletView(model: model)
                        .environmentObject(appState)
                case .none:
                    ConnectWalletView(model: model)
                        .environmentObject(appState)
                case .existing(let nwc):
                    MainWalletView(nwc: nwc)
                case .spark:
                    WalletMainView(walletModel: model)
                }
            }
        }
    }
}
