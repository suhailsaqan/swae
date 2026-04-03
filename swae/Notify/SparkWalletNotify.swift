//
//  SparkWalletNotify.swift
//  swae
//
//  Notification for when a Spark wallet is attached (connected).
//  Carries the Lightning address (lud16) string.
//

import Foundation

struct SparkWalletAttachedNotify: Notify {
    typealias Payload = String
    var payload: Payload
}

extension NotifyHandler {
    static var spark_wallet_attached: NotifyHandler<SparkWalletAttachedNotify> {
        .init()
    }
}

extension Notifications {
    static func spark_wallet_attached(_ payload: String) -> Notifications<SparkWalletAttachedNotify> {
        .init(.init(payload: payload))
    }
}
