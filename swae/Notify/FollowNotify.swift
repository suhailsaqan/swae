//
//  FollowNotify.swift
//  swae
//
//  Created by Suhail Saqan on 3/1/25.
//


import Foundation
import NostrSDK

struct FollowNotify: Notify {
    typealias Payload = [String]
    var payload: Payload
}

extension NotifyHandler {
    static var follow: NotifyHandler<FollowNotify> {
        NotifyHandler<FollowNotify>()
    }
}

extension Notifications {
    static func follow(_ profiles: [String]) -> Notifications<FollowNotify> {
        .init(.init(payload: profiles))
    }
}
