//
//  ScrollToTopNotify.swift
//  swae
//
//  Created by Suhail Saqan on 10/5/24.
//

import Foundation

struct ScrollToTopNotify: Notify {
    typealias Payload = ()
    var payload: ()
}

extension NotifyHandler {
    static var scroll_to_top: NotifyHandler<ScrollToTopNotify> {
        .init()
    }
}

extension Notifications {
    static var scroll_to_top: Notifications<ScrollToTopNotify> {
        .init(.init(payload: ()))
    }
}
