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
        //        print("checking upcoming \(startsAt) \(endsAt)")
        guard let startsAt else {
            return false
        }

        guard let endsAt else {
            return startsAt >= Date.now
        }
        print("\(startsAt) \(Date.now) \(endsAt)")
        return startsAt >= Date.now || endsAt >= Date.now
    }

    var isPast: Bool {
        //        print("checking past \(startsAt) \(endsAt)")
        guard let startsAt else {
            return false
        }

        guard let endsAt else {
            return startsAt < Date.now
        }
        print("\(startsAt) \(Date.now) \(endsAt)")
        return endsAt < Date.now
    }
}
