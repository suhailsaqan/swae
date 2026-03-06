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
            switch model.connect_state {
            case .new:
                ConnectWalletView(model: model)
                    .environmentObject(appState)
            case .none:
                ConnectWalletView(model: model)
                    .environmentObject(appState)
            case .existing(let nwc):
                MainWalletView(nwc: nwc)
            }
        }
    }
}
