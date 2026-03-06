//
//  PlayerConfig.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import AVKit
import Foundation
import NostrSDK
import SwiftUI

enum PlayerState: Equatable {
    case hidden
    case minimized
    case fullscreen
    case fullscreenWithChat
}

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
        case .unknown: return 16.0 / 9.0  // Default to landscape
        }
    }
}

struct PlayerConfig {
    var position: CGFloat = .zero
    var lastPosition: CGFloat = .zero
    var progress: CGFloat = .zero
    var selectedLiveActivitiesEvent: LiveActivitiesEvent?
    var showMiniPlayer: Bool = false

    // YouTube-like draggable player properties
    var playerState: PlayerState = .hidden
    var draggablePosition: CGPoint = CGPoint(x: 0, y: 0)
    var lastDraggablePosition: CGPoint = CGPoint(x: 0, y: 0)
    var isDragging: Bool = false
    var miniPlayerSize: CGSize = CGSize(width: 240, height: 135)  // 16:9 aspect ratio
    var cornerRadius: CGFloat = 6
    var shadowOpacity: Double = 0.3

    // Animation and interaction properties
    var dragVelocity: CGSize = .zero
    var snapToEdge: Bool = true
    var isAnimating: Bool = false

    // LiveChatView integration properties
    var chatRevealProgress: CGFloat = 1.0  // 0 = hidden, 1 = fully revealed
    var isDraggingChat: Bool = false
    var chatDragOffset: CGFloat = 0.0
    var showChatByDefault: Bool = true

    // Video aspect ratio and sizing
    var videoAspectRatio: VideoAspectRatio = .unknown
    var videoSize: CGSize = .zero
    var adaptiveVideoSize: CGSize = .zero

    // Orientation state tracking
    var isLandscapeMode: Bool = false
    var orientationLocked: Bool = false

    mutating func resetPosition() {
        position = .zero
        lastPosition = .zero
        progress = .zero
        playerState = .hidden
        draggablePosition = CGPoint(x: 0, y: 0)
        lastDraggablePosition = CGPoint(x: 0, y: 0)
        isDragging = false
        isAnimating = false
        chatRevealProgress = 0.0
        isDraggingChat = false
        chatDragOffset = 0.0
    }

    mutating func setMinimizedState() {
        playerState = .minimized
        showMiniPlayer = true
    }

    mutating func setFullscreenState() {
        playerState = showChatByDefault ? .fullscreenWithChat : .fullscreen
        showMiniPlayer = true
        chatRevealProgress = showChatByDefault ? 1.0 : 0.0
    }

    mutating func toggleChatDefault() {
        showChatByDefault.toggle()
    }

    mutating func setFullscreenWithChatState() {
        playerState = .fullscreenWithChat
        showMiniPlayer = true
        chatRevealProgress = 1.0
    }

    mutating func setHiddenState() {
        playerState = .hidden
        showMiniPlayer = false
        resetPosition()
    }

    // MARK: - Video Aspect Ratio Helpers

    mutating func updateVideoAspectRatio(from size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }

        let ratio = size.width / size.height

        if ratio > 1.5 {
            videoAspectRatio = .landscape16_9
        } else if ratio < 0.7 {
            videoAspectRatio = .portrait9_16
        } else if ratio > 0.9 && ratio < 1.1 {
            videoAspectRatio = .square1_1
        } else {
            videoAspectRatio = .unknown
        }

        videoSize = size
        updateAdaptiveVideoSize()
    }

    mutating func updateAdaptiveVideoSize() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        switch videoAspectRatio {
        case .landscape16_9:
            adaptiveVideoSize = CGSize(
                width: screenWidth, height: screenWidth / videoAspectRatio.ratio)
        case .portrait9_16:
            adaptiveVideoSize = CGSize(
                width: screenWidth, height: screenWidth / videoAspectRatio.ratio)
        case .square1_1:
            adaptiveVideoSize = CGSize(width: screenWidth, height: screenWidth)
        case .unknown:
            adaptiveVideoSize = CGSize(width: screenWidth, height: screenWidth / (16.0 / 9.0))
        }
    }

    // Initialize with default values
    mutating func initializeDefaults() {
        if adaptiveVideoSize == .zero {
            adaptiveVideoSize = CGSize(
                width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width / (16.0 / 9.0)
            )
        }
    }

    // MARK: - Orientation Management

    mutating func toggleOrientation() {
        isLandscapeMode.toggle()
        orientationLocked = true
    }

    mutating func setPortraitMode() {
        isLandscapeMode = false
        orientationLocked = true
    }

    mutating func setLandscapeMode() {
        isLandscapeMode = true
        orientationLocked = true
    }

    mutating func unlockOrientation() {
        orientationLocked = false
        isLandscapeMode = false
    }

    // MARK: - GenericLivePlayer Integration

    /// Opens the GenericLivePlayer with the given event
    mutating func openGenericLivePlayer(with event: LiveActivitiesEvent) {
        selectedLiveActivitiesEvent = event
        setFullscreenWithChatState()
    }

    /// Closes the GenericLivePlayer
    mutating func closeGenericLivePlayer() {
        setHiddenState()
        selectedLiveActivitiesEvent = nil
    }
}

// MARK: - Equatable Conformance

extension PlayerConfig: Equatable {
    static func == (lhs: PlayerConfig, rhs: PlayerConfig) -> Bool {
        // Compare all properties for equality
        return lhs.position == rhs.position && lhs.lastPosition == rhs.lastPosition
            && lhs.progress == rhs.progress
            && lhs.selectedLiveActivitiesEvent == rhs.selectedLiveActivitiesEvent
            && lhs.showMiniPlayer == rhs.showMiniPlayer && lhs.playerState == rhs.playerState
            && lhs.draggablePosition == rhs.draggablePosition
            && lhs.lastDraggablePosition == rhs.lastDraggablePosition
            && lhs.isDragging == rhs.isDragging && lhs.miniPlayerSize == rhs.miniPlayerSize
            && lhs.cornerRadius == rhs.cornerRadius && lhs.shadowOpacity == rhs.shadowOpacity
            && lhs.dragVelocity == rhs.dragVelocity && lhs.snapToEdge == rhs.snapToEdge
            && lhs.isAnimating == rhs.isAnimating
            && lhs.chatRevealProgress == rhs.chatRevealProgress
            && lhs.isDraggingChat == rhs.isDraggingChat && lhs.chatDragOffset == rhs.chatDragOffset
            && lhs.showChatByDefault == rhs.showChatByDefault
            && lhs.videoAspectRatio == rhs.videoAspectRatio && lhs.videoSize == rhs.videoSize
            && lhs.adaptiveVideoSize == rhs.adaptiveVideoSize
            && lhs.isLandscapeMode == rhs.isLandscapeMode
            && lhs.orientationLocked == rhs.orientationLocked
    }
}
