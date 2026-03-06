//
//  DetachedWalletNotify.swift
//  swae
//
//  Created by Kiro on 2/23/26.
//

import Foundation

struct DetachedWalletNotify: Notify {
    typealias Payload = String?
    var payload: Payload
}

extension NotifyHandler {
    static var detached_wallet: NotifyHandler<DetachedWalletNotify> {
        .init()
    }
}

extension Notifications {
    static func detached_wallet(_ payload: String?) -> Notifications<DetachedWalletNotify> {
        .init(.init(payload: payload))
    }
}
