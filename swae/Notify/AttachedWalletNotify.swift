//
//  AttachedWalletNotify.swift
//  swae
//
//  Created by Suhail Saqan on 3/6/25.
//



import Foundation

struct AttachedWalletNotify: Notify {
    typealias Payload = WalletConnectURL
    var payload: Payload
}

extension NotifyHandler {
    static var attached_wallet: NotifyHandler<AttachedWalletNotify> {
        .init()
    }
}

extension Notifications {
    static func attached_wallet(_ payload: WalletConnectURL) -> Notifications<AttachedWalletNotify> {
        .init(.init(payload: payload))
    }
}
