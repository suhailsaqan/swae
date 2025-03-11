//
//  ConnectWalletView.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//


import SwiftUI

struct ConnectWalletView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: WalletModel
    
    @State var scanning: Bool = false
    @State private var showAlert = false
    @State var error: String? = nil
    @State var wallet_scan_result: WalletScanResult = .scanning
    
    var body: some View {
        MainContent
            .navigationTitle(NSLocalizedString("Wallet", comment: "Navigation title for attaching Nostr Wallet Connect lightning wallet."))
            .navigationBarTitleDisplayMode(.inline)
            .padding()
            .onChange(of: wallet_scan_result) { res in
                scanning = false
                
                switch res {
                case .success(let url):
                    error = nil
                    self.model.new(url)
                    
                case .failed:
                    showAlert.toggle()
                
                case .scanning:
                    error = nil
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Invalid Nostr wallet connection string", comment: "Error message when an invalid Nostr wallet connection string is provided."),
                    message: Text("Make sure the wallet you are connecting to supports NWC.", comment: "Hint message when an invalid Nostr wallet connection string is provided."),
                    dismissButton: .default(Text("OK", comment: "Button label indicating user wants to proceed.")) {
                        wallet_scan_result = .scanning
                    }
                )
            }
    }
    
    func AreYouSure(nwc: WalletConnectURL) -> some View {
        VStack(spacing: 25) {

            Text("Are you sure you want to connect this wallet?", comment: "Prompt to ask user if they want to attach their Nostr Wallet Connect lightning wallet.")
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(nwc.relay.url.absoluteString)
                .font(.body)
                .foregroundColor(.gray)

            if let lud16 = nwc.lud16 {
                Text(lud16)
                    .font(.body)
                    .foregroundColor(.gray)
            }
            
            Button(action: {
                model.connect(nwc)
            }) {
                HStack {
                    Text("Connect", comment: "Text for button to conect to Nostr Wallet Connect lightning wallet.")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
            }
//            .buttonStyle(GradientButtonStyle())
            
            Button(action: {
                model.cancel()
            }) {
                HStack {
                    Text("Cancel", comment: "Text for button to cancel out of connecting Nostr Wallet Connect lightning wallet.")
                        .padding()
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
//            .buttonStyle(NeutralButtonStyle())
        }
    }
    
    var ConnectWallet: some View {
        VStack(spacing: 25) {
            
            AlbyButton() {
                openURL(URL(string:"https://nwc.getalby.com/apps/new")!)
            }
            
            CoinosButton() {
                openURL(URL(string:"https://coinos.io/settings/nostr")!)
            }
            
            Button(action: {
                if let pasted_nwc = UIPasteboard.general.string {
                    guard let url = WalletConnectURL(str: pasted_nwc) else {
                        wallet_scan_result = .failed
                        return
                    }
                    
                    wallet_scan_result = .success(url)
                }
            }) {
                HStack {
                    Image("clipboard")
                    Text("Paste NWC Address", comment: "Text for button to connect a lightning wallet.")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
            }
//            .buttonStyle(GradientButtonStyle())
            
            NavigationLink(destination: WalletScannerView(result: $wallet_scan_result)) {
                HStack {
                    Image("qr-code")
                    Text("Scan NWC Address", comment: "Text for button to connect a lightning wallet.")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
            }
//            .buttonStyle(GradientButtonStyle())

            
            if let err = self.error {
                Text(err)
                    .foregroundColor(.red)
            }
        }
    }
    
    var TopSection: some View {
        HStack(spacing: 0) {
            Button(action: {}, label: {
                Image("swae")
                    .resizable()
                    .frame(width: 30, height: 30)
            })
//            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15), cornerRadius: 9999))
            .disabled(true)
            .padding(.horizontal, 30)
            
            Image("chevron-double-right")
                .resizable()
                .frame(width: 25, height: 25)
            
            Button(action: {}, label: {
                Image("wallet")
                    .resizable()
                    .frame(width: 30, height: 30)
//                    .foregroundStyle(LINEAR_GRADIENT)
            })
//            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15), cornerRadius: 9999))
            .disabled(true)
            .padding(.horizontal, 30)
        }
    }
    
    var TitleSection: some View {
        VStack(spacing: 25) {
            Text("Swae Wallet")
                .fontWeight(.bold)
            
            Text("Securely connect Swae to your wallet using Nostr Wallet Connect")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
    
    var MainContent: some View {
        VStack {
            TopSection
            switch model.connect_state {
            case .new(let nwc):
                AreYouSure(nwc: nwc)
            case .existing:
                Text(verbatim: "Shouldn't happen")
            case .none:
                TitleSection
                ConnectWallet
            }
        }
    }
}
