//
//  PlayerConfig.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import Foundation
import NostrSDK

enum VideoAspectRatio: Equatable {
    case landscape16_9
    case portrait9_16
    case square1_1
    case unknown

    var ratio: CGFloat {
        switch self {
        case .landscape16_9: return 16.0 / 9.0
        case .portrait9_16: return 9.0 / 16.0
        case .square1_1: return 1.0
        case .unknown: return 16.0 / 9.0
        }
    }
}

struct PlayerConfig {
    /// The currently-playing live activity event (nil when no player is open)
    var selectedLiveActivitiesEvent: LiveActivitiesEvent?

    /// Detected video aspect ratio (set by HLS detection or AVPlayer observation)
    var videoAspectRatio: VideoAspectRatio = .unknown
}
