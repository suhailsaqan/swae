//
//  RootViewController.swift
//  swae
//
//  UIKit root view controller
//

import AVFoundation
import Combine
import SwiftUI
import UIKit

final class RootViewController: UIViewController {
    static let instance = RootViewController()

    // Current child view controller (hosts SwiftUI content)
    private(set) var currentChild: UIViewController?

    // Allow rotation when live player is presented, otherwise defer to AppDelegate.orientationLock
    // which is managed by ContentView based on which screen (feed vs camera) is visible
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if presentedViewController is GenericLivePlayerController {
            return .allButUpsideDown
        }
        return AppDelegate.orientationLock
    }

    // Forward status bar hidden preference to presented controller
    override var prefersStatusBarHidden: Bool {
        if let presentedViewController {
            return presentedViewController.prefersStatusBarHidden
        }
        return false
    }

    // Live video player reference - STRONG reference to keep controller alive while mini player is visible
    var liveVideoController: GenericLivePlayerController? {
        didSet {
            print("📌 liveVideoController didSet: \(liveVideoController != nil ? "SET" : "NIL")")

            if let liveVideoController, let player = liveVideoController.player {
                livePlayer.setup(player: player, liveStream: liveVideoController.liveStream)
            } else {
                livePlayer.removePlayer()
            }

            if liveVideoController == nil {
                print("🔴 Hiding mini player")
                UIView.animate(withDuration: 0.2) {
                    self.livePlayer.alpha = 0
                } completion: { _ in
                    self.livePlayer.alpha = 1
                    self.livePlayer.isHidden = true
                }
            } else {
                print("🟢 Showing mini player at bottom")
                livePlayer.isHidden = false
                livePlayer.frame = .init(
                    x: 16,
                    y: view.frame.height - view.safeAreaInsets.bottom - 166,
                    width: 199,
                    height: 112
                )
            }
        }
    }

    var livePlayer = LiveVideoEmbeddedView()

    private var cancellables: Set<AnyCancellable> = []

    // Reference to AppState for observing player config changes
    weak var appState: AppState?

    private init() {
        super.init(nibName: nil, bundle: nil)

        view.addSubview(livePlayer)
        livePlayer.frame = .init(x: 16, y: 500, width: 178, height: 100)
        livePlayer.isHidden = true

        // Tap gesture to reopen
        let liveTap = UITapGestureRecognizer(target: self, action: #selector(miniPlayerTapped))
        liveTap.delegate = self
        liveTap.numberOfTapsRequired = 1
        liveTap.numberOfTouchesRequired = 1
        liveTap.cancelsTouchesInView = false  // Allow touches to reach buttons

        // Move gesture for dragging
        let move = LivePlayerMoveGesture()
        move.delegate = self

        // Add gestures
        [move, liveTap].forEach { livePlayer.addGestureRecognizer($0) }
    }

    func setupAppStateObserver(appState: AppState) {
        self.appState = appState

        // Observe player config changes
        appState.$playerConfig
            .sink { [weak self] config in
                guard let self else { return }

                // If should show player and no controller exists or not presented
                if config.showMiniPlayer,
                    let event = config.selectedLiveActivitiesEvent,
                    self.liveVideoController == nil || self.presentedViewController == nil
                {

                    let liveStream = event.toLiveStream()
                    let controller = GenericLivePlayerController(
                        liveStream: liveStream,
                        liveActivitiesEvent: event,
                        appState: appState
                    )

                    controller.onDismiss = {
                        print("🔴 onDismiss called - clearing controller reference")
                        
                        // Clean up chat subscription when player is FULLY dismissed
                        if let event = config.selectedLiveActivitiesEvent {
                            appState.unsubscribeFromLiveChat(for: event)
                        }
                        
                        // Clear the controller reference
                        RootViewController.instance.liveVideoController = nil
                        // Reset player config
                        appState.playerConfig.setHiddenState()
                        appState.playerConfig.selectedLiveActivitiesEvent = nil
                    }

                    self.present(controller, animated: true)
                }
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Child View Controller Management

    func setChild(_ viewController: UIViewController) {
        // Remove old child
        currentChild?.willMove(toParent: nil)
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        // Add new child
        addChild(viewController)
        view.insertSubview(viewController.view, at: 0)  // Behind mini player
        viewController.view.frame = view.bounds
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        viewController.didMove(toParent: self)

        currentChild = viewController
    }

    // MARK: - Mini Player Tap Handler

    @objc private func miniPlayerTapped() {
        print("🎬 Mini player tapped - expanding to fullscreen")

        guard let live = liveVideoController else {
            print("⚠️ No live controller available")
            return
        }

        print("✅ Re-presenting live controller: \(live)")

        // Re-present the controller (it was dismissed to show mini player)
        present(live, animated: true) {
            print("✅ Live controller presented successfully")
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension RootViewController: UIGestureRecognizerDelegate {
    /// Allow gestures to receive touches simultaneously with other gestures
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Don't allow simultaneous recognition - let them compete naturally
        // Tap will fire for quick taps, pan will fire for drags
        return false
    }

    /// Allow touches to pass through to buttons
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
        -> Bool
    {
        let touchView = touch.view
        let gestureName = gestureRecognizer is UITapGestureRecognizer ? "TAP" : "PAN"
        print(
            "👆 Touch on mini player - gesture: \(gestureName), view: \(String(describing: type(of: touchView)))"
        )

        // If touch is on a button, don't intercept it
        if touchView is UIButton {
            print("  ✅ Touch is on button, letting button handle it (blocking \(gestureName))")
            return false
        }

        // Check if the touch is on any subview that is a button
        var view = touchView
        while view != nil && view != livePlayer {
            if view is UIButton {
                print(
                    "  ✅ Touch is in button hierarchy, letting button handle it (blocking \(gestureName))"
                )
                return false
            }
            view = view?.superview
        }

        print("  ⚙️ \(gestureName) gesture will handle this touch")
        return true
    }
}
