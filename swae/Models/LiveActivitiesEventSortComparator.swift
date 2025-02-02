//
//  LiveActivitiesEventSortComparator.swift
//  swae
//
//  Created by Suhail Saqan on 12/7/24.
//

import Foundation
import NostrSDK

struct LiveActivitiesEventSortComparator: SortComparator {
    var order: SortOrder

    func compare(_ lhs: LiveActivitiesEvent, _ rhs: LiveActivitiesEvent) -> ComparisonResult {
        let comparisonResult = compareForward(lhs, rhs)
        switch order {
        case .forward:
            return comparisonResult
        case .reverse:
            switch comparisonResult {
            case .orderedAscending:
                return .orderedDescending
            case .orderedDescending:
                return .orderedAscending
            case .orderedSame:
                return .orderedSame
            }
        }
    }

    private func compareForward(_ lhs: LiveActivitiesEvent, _ rhs: LiveActivitiesEvent)
        -> ComparisonResult
    {
        if lhs == rhs {
            return .orderedSame
        }

        guard let lhsStartTimestamp = lhs.startsAt else {
            return .orderedDescending
        }

        guard let rhsStartTimestamp = rhs.startsAt else {
            return .orderedAscending
        }

        let lhsEndTimestamp = lhs.endsAt ?? lhsStartTimestamp
        let rhsEndTimestamp = rhs.endsAt ?? rhsStartTimestamp

        if lhsStartTimestamp < rhsStartTimestamp {
            return .orderedAscending
        } else if lhsStartTimestamp > rhsStartTimestamp {
            return .orderedDescending
        } else {
            if lhsEndTimestamp < rhsEndTimestamp {
                return .orderedAscending
            } else if lhsEndTimestamp > rhsEndTimestamp {
                return .orderedDescending
            } else {
                return .orderedSame
            }
        }
    }
}
