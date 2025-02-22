//
//  LiveActivitiesEvent+Extensions.swift
//  swae
//
//  Created by Suhail Saqan on 12/7/24.
//

import Foundation
import NostrSDK

extension LiveActivitiesEvent {
    var isUpcoming: Bool {
        guard let startsAt else {
            return false
        }

        guard let endsAt else {
            return startsAt >= Date.now
        }
        return startsAt >= Date.now || endsAt >= Date.now
    }

    var isPast: Bool {
        guard let startsAt else {
            return false
        }

        guard let endsAt else {
            return startsAt < Date.now
        }
        return endsAt < Date.now
    }
}
