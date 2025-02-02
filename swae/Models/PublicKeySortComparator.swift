//
//  PublicKeySortComparator.swift
//  swae
//
//  Created by Suhail Saqan on 11/25/24.
//

import Foundation
import NostrSDK

struct PublicKeySortComparator: SortComparator {
    var order: SortOrder
    let appState: AppState

    init(order: SortOrder, appState: AppState) {
        self.order = order
        self.appState = appState
    }

    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
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

    private func compareForward(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if lhs == rhs {
            return .orderedSame
        }

        switch (appState.followedPubkeys.contains(lhs), appState.followedPubkeys.contains(rhs)) {
        case (true, false):
            return .orderedAscending
        case (false, true):
            return .orderedDescending
        default:
            break
        }

        let lhsMetadataEvent = appState.metadataEvents[lhs]
        let rhsMetadataEvent = appState.metadataEvents[rhs]

        switch (lhsMetadataEvent, rhsMetadataEvent) {
        case (nil, nil):
            break
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        default:
            break
        }

        guard let lhsMetadataEvent, let rhsMetadataEvent else {
            if let lhsPublicKey = PublicKey(hex: lhs), let rhsPublicKey = PublicKey(hex: rhs) {
                return lhsPublicKey.npub.compare(rhsPublicKey.npub)
            } else {
                return lhs.compare(rhs)
            }
        }

        return lhsMetadataEvent.resolvedName.localizedCaseInsensitiveCompare(
            rhsMetadataEvent.resolvedName)
    }
}
