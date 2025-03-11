//
//  WalletModel.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//

import Foundation
import SwiftUI
import NostrSDK

enum WalletConnectState {
    case new(WalletConnectURL)
    case existing(WalletConnectURL)
    case none
}

class WalletModel: ObservableObject {
    var publicKey: PublicKey
    private(set) var previous_state: WalletConnectState
    let nostrWalletConnectSecureStorage = NostrWalletConnectKeyStorage()
    
    @Published private(set) var connect_state: WalletConnectState
    
    init(state: WalletConnectState, publicKey: PublicKey) {
        self.connect_state = state
        self.previous_state = .none
        self.publicKey = publicKey
    }
    
    init(publicKey: PublicKey) {
        self.publicKey = publicKey
        if let nwc = nostrWalletConnectSecureStorage.nostrWalletConnectURL(for: publicKey) {
            self.previous_state = .existing(nwc)
            self.connect_state = .existing(nwc)
            print("setting to existing, \(publicKey)")
        } else {
            print("setting to none, \(publicKey)")
            self.previous_state = .none
            self.connect_state = .none
        }
    }
    
    func cancel() {
        self.connect_state = previous_state
        self.objectWillChange.send()
    }
    
    func disconnect() {
        self.nostrWalletConnectSecureStorage.delete(for: publicKey)
        self.connect_state = .none
        self.previous_state = .none
    }
    
    func new(_ nwc: WalletConnectURL) {
        self.connect_state = .new(nwc)
    }
    
    func connect(_ nwc: WalletConnectURL) {
        self.nostrWalletConnectSecureStorage.store(publicKey: publicKey, walletConnectURL: nwc)
        notify(.attached_wallet(nwc))
        self.connect_state = .existing(nwc)
        self.previous_state = .existing(nwc)
    }
}
