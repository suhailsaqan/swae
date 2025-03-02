//
//  UnfollowedNotify.swift
//  swae
//
//  Created by Suhail Saqan on 3/1/25.
//


import Foundation
import NostrSDK

struct UnfollowedNotify: Notify {
    typealias Payload = [String]
    var payload: Payload
}

extension NotifyHandler {
    static var unfollowed: NotifyHandler<UnfollowedNotify> {
        .init()
    }
}

extension Notifications {
    static func unfollowed(_ profiles: [String]) -> Notifications<UnfollowedNotify> {
        .init(.init(payload: profiles))
    }
}
