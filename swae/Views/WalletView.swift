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
    
    init(/*appState: AppState,*/ model: WalletModel) {
//        self.appState = appState
//        self._model = ObservedObject(wrappedValue: model ?? appState.wallet)
        self._model = ObservedObject(wrappedValue: model)
    }
    
    func MainWalletView(nwc: WalletConnectURL) -> some View {
        ScrollView {
            VStack(spacing: 35) {
                VStack(spacing: 5) {
                    VStack(spacing: 10) {
                        Text("Wallet Relay", comment: "Label text indicating that below it is the information about the wallet relay.")
                            .fontWeight(.semibold)
                            .padding(.top)
                    }
                    .frame(maxWidth: .infinity, minHeight: 125, alignment: .top)
                    .padding(.horizontal, 10)
                    .cornerRadius(10)
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 10)
//                    )
                    
                    if let lud16 = nwc.lud16 {
                        VStack(spacing: 10) {
                            Text("Wallet Address", comment: "Label text indicating that below it is the wallet address.")
                                .fontWeight(.semibold)
                            
                            Divider()
                            
                            Text(lud16)
                        }
                        .frame(maxWidth: .infinity, minHeight: 75, alignment: .center)
                        .padding(.horizontal, 10)
                        .cornerRadius(10)
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 10)
//                        )
                    }
                }
                
                Spacer()
                
                Button(action: {
                    self.model.disconnect()
                }) {
                    HStack {
                        Text("Disconnect Wallet", comment: "Text for button to disconnect from Nostr Wallet Connect lightning wallet.")
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
                }
//                .buttonStyle(GradientButtonStyle())
                .padding(.bottom, 50)
                
            }
            .navigationTitle(NSLocalizedString("Wallet", comment: "Navigation title for Wallet view"))
            .navigationBarTitleDisplayMode(.inline)
            .padding()
        }
    }
    
    var body: some View {
        NavigationView {
            switch model.connect_state {
            case .new:
                ConnectWalletView(model: model)
            case .none:
                ConnectWalletView(model: model)
            case .existing(let nwc):
                MainWalletView(nwc: nwc)
            }
        }
    }
}
