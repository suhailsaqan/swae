//
//  RootViewController.swift
//  swae
//
//  UIKit root view controller — manages the app's child VC and the player overlay.
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

final class RootViewController: UIViewController {
    static let instance = RootViewController()

    // Current child view controller (hosts SwiftUI content)
    private(set) var currentChild: UIViewController?

    // MARK: - Player Container

    /// The currently-presented player, added as a child VC on top of the feed.
    private(set) var currentPlayerController: (any PlayerController)?

    /// Source rect in window coordinates — used for dismiss animation (Step 2+).
    private var playerSourceRect: CGRect = .zero
    private var playerSourceCornerRadius: CGFloat = 0

    // Reference to AppState
    weak var appState: AppState?

    // Late aspect ratio detection — no longer needed (unified ReelsPlayerController)
    // private var aspectRatioCancellable: AnyCancellable?

    // MARK: - Orientation & Status Bar

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if currentPlayerController != nil {
            return .allButUpsideDown
        }
        return AppDelegate.orientationLock
    }

    override var prefersStatusBarHidden: Bool {
        if let player = currentPlayerController {
            return player.prefersStatusBarHidden
        }
        return false
    }

    override var childForStatusBarHidden: UIViewController? {
        return currentPlayerController ?? currentChild
    }

    // MARK: - Init

    private init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    func setup(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Child View Controller Management

    func setChild(_ viewController: UIViewController) {
        currentChild?.willMove(toParent: nil)
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        addChild(viewController)
        view.insertSubview(viewController.view, at: 0)
        viewController.view.frame = view.bounds
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        viewController.didMove(toParent: self)

        currentChild = viewController
    }

    // MARK: - Player Presentation

    /// Presents the player as a child VC on top of the feed.
    /// If sourceRect is provided, animates an expand-from-thumbnail transition.
    /// If sourceRect is .zero (deep link, profile tap), fades in at full screen.
    func presentPlayer(
        _ controller: any PlayerController,
        from sourceRect: CGRect = .zero,
        cornerRadius: CGFloat = 0,
        thumbnailImage: UIImage? = nil
    ) {
        guard currentPlayerController == nil else { return }

        currentPlayerController = controller
        playerSourceRect = sourceRect
        playerSourceCornerRadius = cornerRadius

        // Hide the tab bar so it doesn't show through the player
        findTabBarController()?.tabBar.isHidden = true

        let fullFrame = view.bounds

        // Add as child VC at full screen size (one layout pass at correct size)
        addChild(controller)
        controller.view.frame = fullFrame
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)

        // Start with content hidden — the snapshot or fade handles the reveal.
        // The view itself stays opaque (backgroundColor = .black) so the feed
        // never shows through.
        controller.view.alpha = 0

        if sourceRect != .zero && sourceRect.width > 0 {
            // --- Expand-from-thumbnail transition ---
            // The snapshot expands from the thumbnail to the player's video area
            // (not the full screen — the input bar area stays clear).

            let targetFrame = controller.expandAnimationTargetFrame

            // Black backdrop so the feed never peeks through during the expand
            let backdrop = UIView(frame: fullFrame)
            backdrop.backgroundColor = .black
            backdrop.alpha = 0
            view.insertSubview(backdrop, belowSubview: controller.view)

            // Determine if the thumbnail image is portrait or landscape
            let imageIsPortrait: Bool = {
                guard let img = thumbnailImage else { return false }
                return img.size.height > img.size.width
            }()

            // Snapshot placed at thumbnail position.
            // Portrait thumbnails: .scaleAspectFill so they fill top-to-bottom with no black bars.
            // Landscape thumbnails: .scaleAspectFit so they keep their ratio and don't stretch vertically.
            let snapshot = UIImageView(image: thumbnailImage)
            snapshot.contentMode = imageIsPortrait ? .scaleAspectFill : .scaleAspectFit
            snapshot.clipsToBounds = true
            snapshot.layer.cornerRadius = cornerRadius
            snapshot.frame = sourceRect
            snapshot.backgroundColor = .black
            view.addSubview(snapshot)

            // Start the controller view slightly scaled down for a lift-off feel
            controller.view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)

            // Phase 1: Expand snapshot to the video area + fade in backdrop
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
                snapshot.frame = targetFrame
                snapshot.layer.cornerRadius = 0
                backdrop.alpha = 1
            } completion: { _ in }

            // Phase 2: Crossfade to controller view with a subtle scale-up
            UIView.animate(withDuration: 0.25, delay: 0.15, options: .curveEaseOut, animations: {
                controller.view.alpha = 1
                controller.view.transform = .identity
            }) { [weak self] _ in
                snapshot.removeFromSuperview()
                backdrop.removeFromSuperview()
                controller.view.clipsToBounds = false
                self?.setNeedsStatusBarAppearanceUpdate()
                controller.expandAnimationDidComplete()
            }
        } else {
            // --- No source rect: simple fade in ---
            UIView.animate(withDuration: 0.25) {
                controller.view.alpha = 1
            } completion: { [weak self] _ in
                self?.setNeedsStatusBarAppearanceUpdate()
                controller.expandAnimationDidComplete()
            }
        }
    }

    /// Dismisses the player with a shrink-to-thumbnail animation (for dismiss button tap).
    func dismissPlayer() {
        guard let controller = currentPlayerController else { return }

        let targetRect = playerSourceRect
        let targetRadius = playerSourceCornerRadius

        if targetRect != .zero && targetRect.width > 0 {
            // Render the video area as a UIImage so we can use .scaleAspectFill.
            // This keeps the center of the video visible as the frame shrinks,
            // instead of deforming/squishing the content.
            let sourceView = controller.dismissSnapshotSourceView
            let snapshotFrame = sourceView.convert(sourceView.bounds, to: view)

            let renderer = UIGraphicsImageRenderer(bounds: sourceView.bounds)
            let snapshotImage = renderer.image { ctx in
                sourceView.drawHierarchy(in: sourceView.bounds, afterScreenUpdates: false)
            }

            let snapshot = UIImageView(image: snapshotImage)
            snapshot.contentMode = .scaleAspectFill
            snapshot.clipsToBounds = true
            snapshot.frame = snapshotFrame
            snapshot.layer.cornerRadius = sourceView.layer.cornerRadius

            // Black backdrop that fades out — prevents snap-to-feed for landscape videos
            let backdrop = UIView(frame: view.bounds)
            backdrop.backgroundColor = .black
            view.addSubview(backdrop)
            view.addSubview(snapshot)

            // Hide the controller — backdrop covers the feed during the animation
            controller.view.alpha = 0

            // Show the tab bar so the feed looks normal when backdrop fades
            findTabBarController()?.tabBar.isHidden = false

            // Animate snapshot to the thumbnail position — stays fully opaque
            let animator = UIViewPropertyAnimator(duration: 0.35, dampingRatio: 0.92) {
                snapshot.frame = targetRect
                snapshot.layer.cornerRadius = targetRadius
                backdrop.alpha = 0
            }

            // Subtle fade only at the very end so it doesn't pop when removed
            animator.addAnimations({
                snapshot.alpha = 0
            }, delayFactor: 0.7)

            animator.addCompletion { [weak self] _ in
                snapshot.removeFromSuperview()
                backdrop.removeFromSuperview()
                controller.view.alpha = 1
                self?.cleanupPlayer()
            }

            animator.startAnimation()
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                controller.view.alpha = 0
            }) { [weak self] _ in
                controller.view.alpha = 1
                self?.cleanupPlayer()
            }
        }
    }

    // MARK: - Interactive Dismiss Support

    /// Called by the player's dismiss pan gesture on .changed to update visual state.
    /// Instagram-style: video follows finger with rubber-banding and minimal scale.
    func updateDismissProgress(translation: CGPoint) {
        guard let controller = currentPlayerController else { return }

        // Rubber-band the translation — movement slows down the further you drag.
        let maxFreeMovement: CGFloat = 120
        let dampenedX = rubberBand(translation.x, limit: maxFreeMovement)
        let dampenedY = rubberBand(translation.y, limit: maxFreeMovement)

        // Pure translation — no scale. The view moves like you're peeling the screen.
        controller.view.transform = CGAffineTransform(translationX: dampenedX, y: dampenedY)

        // Corner radius matches the device display — constant, not animated.
        controller.view.layer.cornerRadius = UIScreen.displayCornerRadius
        controller.view.clipsToBounds = true
    }

    /// Rubber-band function — 1:1 tracking up to `limit`, then logarithmic dampening beyond.
    /// Same physics as UIScrollView's bounce.
    private func rubberBand(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = offset < 0 ? -1 : 1
        let abs = abs(offset)

        if abs <= limit {
            return offset  // 1:1 tracking within the free zone
        }

        // Beyond the limit: logarithmic dampening
        // The formula: limit + (1 - 1/(x/limit * 0.55 + 1)) * limit
        // This asymptotically approaches limit * 2 — you can never drag more than ~2x the limit
        let overflow = abs - limit
        let dampened = limit + (1.0 - 1.0 / (overflow / limit * 0.55 + 1.0)) * limit
        return dampened * sign
    }

    /// Called by the player's dismiss pan gesture on .ended to finish or cancel.
    func finishOrCancelDismiss(shouldDismiss: Bool, velocity: CGPoint = .zero) {
        guard let controller = currentPlayerController else { return }

        if shouldDismiss {
            controller.videoPlayer?.pause()

            let targetRect = playerSourceRect
            let targetRadius = playerSourceCornerRadius

            if targetRect != .zero && targetRect.width > 0 {
                // Render the video area as a UIImage for .scaleAspectFill cropping
                let sourceView = controller.dismissSnapshotSourceView
                let snapshotFrame = sourceView.convert(sourceView.bounds, to: view)

                let renderer = UIGraphicsImageRenderer(bounds: sourceView.bounds)
                let snapshotImage = renderer.image { ctx in
                    sourceView.drawHierarchy(in: sourceView.bounds, afterScreenUpdates: false)
                }

                let snapshot = UIImageView(image: snapshotImage)
                snapshot.contentMode = .scaleAspectFill
                snapshot.clipsToBounds = true
                snapshot.frame = snapshotFrame
                snapshot.layer.cornerRadius = sourceView.layer.cornerRadius

                // Place snapshot on top of the controller — no backdrop needed.
                // The controller stays visible underneath so there's no black flash.
                view.addSubview(snapshot)

                // Show the tab bar so the feed looks normal as the controller fades
                findTabBarController()?.tabBar.isHidden = false

                // Animate: snapshot shrinks to thumbnail, controller fades out simultaneously
                let animator = UIViewPropertyAnimator(duration: 0.35, dampingRatio: 0.92) {
                    snapshot.frame = targetRect
                    snapshot.layer.cornerRadius = targetRadius
                    // Fade out the controller smoothly — reveals the feed behind it
                    controller.view.alpha = 0
                }

                // Snapshot fades only at the very end so it doesn't pop when removed
                animator.addAnimations({
                    snapshot.alpha = 0
                }, delayFactor: 0.7)

                animator.addCompletion { [weak self] _ in
                    snapshot.removeFromSuperview()
                    controller.view.transform = .identity
                    controller.view.layer.cornerRadius = 0
                    controller.view.alpha = 1
                    self?.cleanupPlayer()
                }

                animator.startAnimation()
            } else {
                // No source rect — fade out
                UIView.animate(withDuration: 0.2, animations: {
                    controller.view.alpha = 0
                }) { [weak self] _ in
                    controller.view.transform = .identity
                    controller.view.alpha = 1
                    self?.cleanupPlayer()
                }
            }
        } else {
            // Snap back to full screen
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: []) {
                controller.view.transform = .identity
                controller.view.layer.cornerRadius = 0
            } completion: { _ in
                controller.restoreControlsAfterCancelledDismiss()
            }
        }
    }

    /// Shared cleanup for all dismiss paths.
    private func cleanupPlayer() {
        guard let controller = currentPlayerController else { return }

        if let appState, let event = appState.playerConfig.selectedLiveActivitiesEvent {
            appState.unsubscribeFromLiveChat(for: event)
        }
        NowPlayingService.shared.deactivate()
        appState?.playerConfig.selectedLiveActivitiesEvent = nil
        appState?.playerConfig.videoAspectRatio = .unknown

        NotificationCenter.default.post(
            name: NSNotification.Name("RestoreStreamingAudioSession"),
            object: nil
        )

        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        currentPlayerController = nil

        // Show the tab bar again
        findTabBarController()?.tabBar.isHidden = false

        // Notify feed it's visible again — triggers deferred rebuilds
        notify(.feed_visibility(true))

        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Helpers

    private func findTabBarController() -> UITabBarController? {
        func search(_ vc: UIViewController) -> UITabBarController? {
            if let tab = vc as? UITabBarController { return tab }
            for child in vc.children {
                if let found = search(child) { return found }
            }
            return nil
        }
        if let child = currentChild {
            return search(child)
        }
        return nil
    }
}
