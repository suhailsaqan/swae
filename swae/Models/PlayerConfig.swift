//
//  PlayerConfig.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//


import Foundation
import NostrSDK

struct PlayerConfig: Equatable {
    var position: CGFloat = .zero
    var lastPosition: CGFloat = .zero
    var progress: CGFloat = .zero
    var selectedLiveActivitiesEvent: LiveActivitiesEvent?
    var showMiniPlayer: Bool = false
    
    mutating func resetPosition() {
        position = .zero
        lastPosition = .zero
        progress = .zero
    }
}
