//
//  SwitchedTabNotify.swift
//  gibbe
//
//  Created by Suhail Saqan on 10/5/24.
//

import Foundation

struct SwitchedTabNotify: Notify {
    typealias Payload = ScreenTabs
    var payload: Payload
}

extension NotifyHandler {
    static var switched_tab: NotifyHandler<SwitchedTabNotify> {
        .init()
    }
}

extension Notifications {
    static func switched_tab(_ screen_tab: ScreenTabs) -> Notifications<SwitchedTabNotify> {
        .init(.init(payload: screen_tab))
    }
}
