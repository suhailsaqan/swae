//
//  UnfollowNotify.swift
//  swae
//
//  Created by Suhail Saqan on 3/1/25.
//


import Foundation
import NostrSDK

/// Notification sent when an unfollow action is initiatied. Not to be confused with unfollowed
struct UnfollowNotify: Notify {
    typealias Payload = [String]
    var payload: Payload
}

extension NotifyHandler {
    static var unfollow: NotifyHandler<UnfollowNotify> {
        .init()
    }
}

extension Notifications {
    static func unfollow(_ profiles: [String]) -> Notifications<UnfollowNotify> {
        .init(.init(payload: profiles))
    }
}
