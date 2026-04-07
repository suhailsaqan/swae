//
//  PlayerController.swift
//  swae
//
//  Protocol that both GenericLivePlayerController (landscape) and
//  ReelsPlayerController (portrait) conform to. Allows RootViewController
//  to manage either player type uniformly.
//

import UIKit
import NostrSDK

protocol PlayerController: UIViewController {
    /// The video player wrapper (nil if no URL was available)
    var videoPlayer: VideoPlayer? { get }

    /// The live stream model — mutable for live→recording transitions
    var liveStream: LiveStream { get set }

    /// The Nostr live activity event — mutable for live→recording transitions
    var liveActivitiesEvent: LiveActivitiesEvent { get set }

    /// The chat controller managing messages, zaps, and the comments table
    var chatController: LiveChatController { get }

    /// App-wide state
    var appState: AppState? { get }

    /// The view to snapshot for the dismiss animation.
    /// Landscape returns the full view; reels returns just the player view.
    var dismissSnapshotSourceView: UIView { get }

    /// The target frame for the expand-from-thumbnail animation.
    /// Returns the player view's frame at its initial state (progress=0).
    /// Used by RootViewController.presentPlayer() so the snapshot expands
    /// to the video area, not the full screen.
    var expandAnimationTargetFrame: CGRect { get }

    /// Called by RootViewController after a cancelled dismiss gesture
    /// to restore controls that were hidden during the drag.
    func restoreControlsAfterCancelledDismiss()

    /// Called by RootViewController after the expand-from-thumbnail animation completes.
    /// The controller view is fully opaque and the snapshot has been removed.
    func expandAnimationDidComplete()
}

// Default empty implementation so existing conformers don't need to change.
extension PlayerController {
    func expandAnimationDidComplete() {}
}
