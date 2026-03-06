//
//  FeedVisibilityNotify.swift
//  swae
//

import Foundation

/// Notifies when the feed becomes visible or hidden (e.g. camera swipe).
/// Payload is `true` when feed is visible, `false` when hidden.
struct FeedVisibilityNotify: Notify {
    typealias Payload = Bool
    var payload: Payload
}

extension NotifyHandler {
    static var feed_visibility: NotifyHandler<FeedVisibilityNotify> {
        .init()
    }
}

extension Notifications {
    static func feed_visibility(_ visible: Bool) -> Notifications<FeedVisibilityNotify> {
        .init(.init(payload: visible))
    }
}
