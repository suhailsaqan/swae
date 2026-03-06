//
//  FollowedNotify.swift
//  swae
//
//  Created by Suhail Saqan on 3/1/25.
//


import Foundation
import NostrSDK

struct FollowedNotify: Notify {
    typealias Payload = [String]
    var payload: Payload
}

extension NotifyHandler {
    static var followed: NotifyHandler<FollowedNotify> {
        .init()
    }
}

extension Notifications {
    static func followed(_ profiles: [String]) -> Notifications<FollowedNotify> {
        .init(.init(payload: profiles))
    }
}
