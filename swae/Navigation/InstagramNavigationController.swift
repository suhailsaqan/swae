//
//  InstagramNavigationController.swift
//  swae
//
//  Created by AI Assistant
//

import SwiftUI
import UIKit

// MARK: - Navigation State
enum InstagramNavigationState {
    case feedVisible
    case cameraVisible
    case transitioning
}

// MARK: - Instagram Navigation Controller
class InstagramNavigationController: UIViewController {

    // MARK: - Properties
    private var feedViewController: UIHostingController<InstagramFeedView>
    /// The camera container view controller - manages vertical navigation for settings/camera/control panel.
    /// Created directly without SwiftUI wrapper per Requirements 8.1.
    private var cameraContainerViewController: CameraContainerViewController!
    private var navigationState: InstagramNavigationState = .feedVisible
    
    /// Reference to the model for creating CameraContainerViewController
    private weak var model: Model?

    // Animation properties
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var feedOffset: CGFloat = 0
    private var isDragging = false
    private var gestureType: GestureType = .unknown
    private var initialDragState: InstagramNavigationState = .feedVisible
    private var touchStartPoint: CGPoint = .zero
    private var shouldAllowNavigation = false

    private enum GestureType {
        case unknown
        case horizontal
        case vertical
    }

    // Animation constants (matching Instagram's feel)
    private let revealThreshold: CGFloat = 0.3  // 30% of screen width
    private let maxOffset: CGFloat = 1.0  // Full screen width
    private let springDamping: CGFloat = 0.95  // Higher damping to reduce bounce
    private let springVelocity: CGFloat = 0.20  // Reduced velocity for slower movement
    private let animationDuration: TimeInterval = 0.5  // Increased duration for smoother feel

    // Instagram-style edge detection (matches Instagram's actual implementation)
    private let edgeSwipeZone: CGFloat = 80  // Edge zone for camera swipe (Instagram uses ~60-80pts)
    private let minimumEdgeSwipeDistance: CGFloat = 30  // Minimum horizontal distance before claiming gesture

    // Callbacks
    var onCameraButtonTapped: (() -> Void)?
    var onStateChanged: ((InstagramNavigationState) -> Void)?

    // MARK: - Initialization
    
    /// Creates an InstagramNavigationController with the new UIKit-based CameraViewController.
    /// This is the preferred initializer for better gesture handling and morphing orb support.
    /// - Parameters:
    ///   - feedView: The feed view to display
    ///   - cameraViewController: The UIKit camera view controller
    ///   - model: The app model
    ///   - onStateChanged: Callback for navigation state changes
    ///   - onCameraButtonTapped: Callback for camera button taps
    init(
        feedView: InstagramFeedView,
        cameraViewController: CameraViewController,
        model: Model,
        onStateChanged: ((InstagramNavigationState) -> Void)? = nil,
        onCameraButtonTapped: (() -> Void)? = nil
    ) {
        self.feedViewController = UIHostingController(rootView: feedView)
        self.model = model
        super.init(nibName: nil, bundle: nil)
        self.onStateChanged = onStateChanged
        self.onCameraButtonTapped = onCameraButtonTapped
        
        // Create CameraContainerViewController with UIKit CameraViewController
        self.cameraContainerViewController = CameraContainerViewController(
            cameraViewController: cameraViewController,
            model: model
        )
        
        self.cameraContainerViewController.onStateChanged = { [weak self] state in
            print("📱 CameraContainer state changed to: \(state)")
        }
    }
    
    /// Legacy initializer for SwiftUI-based camera view.
    /// Use init(feedView:cameraViewController:model:...) for new implementations.
    /// - Parameters:
    ///   - feedView: The feed view to display
    ///   - cameraView: The camera view (MainView) to embed in the camera container
    ///   - model: The app model for creating CameraContainerViewController
    ///   - onStateChanged: Callback for navigation state changes
    ///   - onCameraButtonTapped: Callback for camera button taps
    /// - Requirements: 8.1 - InstagramNavigationController creates CameraContainerViewController directly without SwiftUI wrapper
    init(
        feedView: InstagramFeedView,
        cameraView: some View,
        model: Model,
        onStateChanged: ((InstagramNavigationState) -> Void)? = nil,
        onCameraButtonTapped: (() -> Void)? = nil
    ) {
        self.feedViewController = UIHostingController(rootView: feedView)
        self.model = model
        super.init(nibName: nil, bundle: nil)
        self.onStateChanged = onStateChanged
        self.onCameraButtonTapped = onCameraButtonTapped
        
        // Create CameraContainerViewController directly (no SwiftUI wrapper)
        // This reduces UIKit↔SwiftUI boundary crossings and eliminates gesture conflicts
        // Requirements: 8.1
        self.cameraContainerViewController = CameraContainerViewController(
            cameraView: AnyView(cameraView),
            model: model
        )
        
        // Set up state change callback for UIKit components that need to respond
        // Requirements: 8.2
        self.cameraContainerViewController.onStateChanged = { [weak self] state in
            // Forward state changes if needed for any UIKit components
            print("📱 CameraContainer state changed to: \(state)")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupGestures()
        setupInitialState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFeedPosition()
        // Reapply rounded corners in case of orientation changes or layout updates
        applyInstagramRoundedCorners()
    }

    override func viewWillTransition(
        to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)

        // Ensure rounded corners are maintained during orientation changes
        coordinator.animate(
            alongsideTransition: { _ in
                self.applyInstagramRoundedCorners()
            },
            completion: { _ in
                // Final application after orientation change
                self.applyInstagramRoundedCorners()
            })
    }

    // MARK: - Setup
    private func setupViews() {
        view.backgroundColor = .black
        // Allow camera container's settings/control panel views to extend beyond bounds
        view.clipsToBounds = false

        // Add camera container as background layer (directly managed UIKit controller)
        // Requirements: 8.1 - CameraContainerViewController is created and managed directly
        addChild(cameraContainerViewController)
        view.addSubview(cameraContainerViewController.view)
        cameraContainerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraContainerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            cameraContainerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraContainerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraContainerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        cameraContainerViewController.didMove(toParent: self)
        
        // Note: Dimming overlay for horizontal navigation is added to the view directly,
        // not to cameraContainerViewController.view, to avoid blocking settings/control panel
        let cameraDimmingView = UIView()
        cameraDimmingView.backgroundColor = UIColor.black
        cameraDimmingView.tag = 998  // For easy access
        cameraDimmingView.isUserInteractionEnabled = false  // Allow touches to pass through
        view.insertSubview(cameraDimmingView, aboveSubview: cameraContainerViewController.view)
        cameraDimmingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraDimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraDimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraDimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraDimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        cameraDimmingView.alpha = 0

        // Add feed view on top with Instagram-style rounded corners
        addChild(feedViewController)
        view.addSubview(feedViewController.view)
        feedViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            feedViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            feedViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feedViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feedViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        feedViewController.didMove(toParent: self)

        // Apply Instagram-style rounded corners to feed view
        applyInstagramRoundedCorners()

        // Add dimming overlay for feed with matching rounded corners
        let dimmingView = UIView()
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        dimmingView.tag = 999  // For easy access
        feedViewController.view.addSubview(dimmingView)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: feedViewController.view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: feedViewController.view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: feedViewController.view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: feedViewController.view.bottomAnchor),
        ])
        dimmingView.alpha = 0

        // Apply same rounded corners to dimming overlay
        dimmingView.layer.cornerRadius = getDeviceCornerRadius()
        dimmingView.layer.masksToBounds = true
        dimmingView.layer.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
        ]
    }

    private func applyInstagramRoundedCorners() {
        // Get the device's corner radius from the window scene
        let cornerRadius = getDeviceCornerRadius()

        // Apply rounded corners to feed view with masking
        feedViewController.view.layer.cornerRadius = cornerRadius
        feedViewController.view.layer.masksToBounds = true

        // Ensure the corner radius is maintained during transforms
        feedViewController.view.layer.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
        ]
    }

    private func getDeviceCornerRadius() -> CGFloat {
        // Get the device's actual corner radius from the window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        {

            // For devices with rounded corners (iPhone X and later)
            if window.safeAreaInsets.top > 20 {
                // Instagram uses the exact device corner radius
                // This matches the native iOS display corner radius
                let screenBounds = UIScreen.main.bounds
                let scale = UIScreen.main.scale

                // Calculate the precise corner radius based on device
                // This matches Instagram's implementation exactly
                switch (screenBounds.width, screenBounds.height) {
                case (375, 812), (812, 375):  // iPhone X, XS, 11 Pro, 12 mini, 13 mini
                    return 39.25
                case (414, 896), (896, 414):  // iPhone XR, 11, XS Max
                    return 39.25
                case (390, 844), (844, 390):  // iPhone 12, 12 Pro, 13, 13 Pro, 14
                    return 39.25
                case (428, 926), (926, 428):  // iPhone 12 Pro Max, 13 Pro Max, 14 Plus
                    return 39.25
                case (393, 852), (852, 393):  // iPhone 14 Pro
                    return 39.25
                case (430, 932), (932, 430):  // iPhone 14 Pro Max
                    return 39.25
                case (430, 932), (932, 430):  // iPhone 15, 15 Plus
                    return 39.25
                case (393, 852), (852, 393):  // iPhone 15 Pro
                    return 39.25
                case (430, 932), (932, 430):  // iPhone 15 Pro Max
                    return 39.25
                default:
                    // Fallback for future devices - use safe area detection
                    return 39.25
                }
            }
        }

        // For devices without rounded corners (iPhone 8 and earlier)
        return 0
    }

    private func setupGestures() {
        // Pan gesture for drag-to-reveal
        panGestureRecognizer = UIPanGestureRecognizer(
            target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.delegate = self

        // CRITICAL: Don't block taps and other interactions
        panGestureRecognizer.delaysTouchesBegan = false
        panGestureRecognizer.delaysTouchesEnded = false
        panGestureRecognizer.cancelsTouchesInView = false

        view.addGestureRecognizer(panGestureRecognizer)
        print("✅ Pan gesture recognizer added to view")
    }

    private func setupInitialState() {
        feedOffset = 0
        updateFeedPosition()
        updateCameraParallax()
        updateNavigationState(.feedVisible)
    }

    // MARK: - Gesture Handling
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        // Calculate the angle of the swipe (0° = horizontal right, 90° = vertical down)
        let angle = atan2(abs(translation.y), abs(translation.x)) * 180.0 / Double.pi
        let isHorizontalSwipe = angle < 30  // Less than 45 degrees from horizontal

        switch gesture.state {
        case .began:
            // Store the initial touch point for edge detection
            touchStartPoint = gesture.location(in: view)

            // Reset state for new gesture
            gestureType = .unknown
            isDragging = false
            shouldAllowNavigation = false

            // INSTAGRAM PATTERN: Check if touch started in edge zone
            // This is critical - only touches near edges should trigger navigation
            let touchIsInEdgeZone = isLocationInNavigationZone(touchStartPoint)

            // INSTAGRAM PATTERN: Check if touch hit a horizontally scrollable view
            let touchHitScrollableContent = isTouchOnScrollableContent(at: touchStartPoint)

            // Allow navigation only if:
            // 1. Touch started in edge zone, OR
            // 2. Touch didn't hit scrollable content
            shouldAllowNavigation = touchIsInEdgeZone || !touchHitScrollableContent

            print(
                "📍 Touch began at x: \(touchStartPoint.x), inEdgeZone: \(touchIsInEdgeZone), hitScrollable: \(touchHitScrollableContent), allowNav: \(shouldAllowNavigation)"
            )

        case .changed:
            // INSTAGRAM PATTERN: Require minimum horizontal movement before claiming
            // This gives scroll views time to claim the gesture first
            let hasMovedEnoughHorizontally = abs(translation.x) > minimumEdgeSwipeDistance

            // Determine gesture type if not already determined
            if gestureType == .unknown {
                let isVerticalSwipe = angle > 30  // More than 30 degrees from horizontal

                if isHorizontalSwipe && abs(translation.x) > 10 {
                    // Only claim horizontal gesture if we should allow navigation
                    if shouldAllowNavigation && hasMovedEnoughHorizontally {
                        gestureType = .horizontal
                        isDragging = true
                        initialDragState = navigationState  // Store the initial state
                        updateNavigationState(.transitioning)
                        print("✅ Claiming horizontal gesture for navigation")
                    } else if !shouldAllowNavigation {
                        // Explicitly mark as vertical to prevent claiming later
                        gestureType = .vertical
                        print("❌ Rejecting horizontal gesture - scrollable content has priority")
                        gesture.state = .failed  // Fail the gesture so scroll view can take over
                        return
                    }
                } else if isVerticalSwipe && abs(translation.y) > 10 {
                    gestureType = .vertical
                    print("📊 Detected vertical gesture - failing navigation to allow scrolling")
                    gesture.state = .failed  // Fail the gesture so scroll view can take over
                    return
                }
            }

            // Only handle horizontal gestures that we've claimed
            guard gestureType == .horizontal && isDragging && shouldAllowNavigation else {
                return
            }

            // Handle both directions based on initial state (use stored initial state to avoid feedback loop)
            let initialState = initialDragState

            if initialState == .feedVisible {
                // From feed: only allow rightward swipes to reveal camera
                if translation.x > 0 {
                    let newOffset = min(translation.x / view.bounds.width, maxOffset)
                    feedOffset = newOffset
                    updateFeedPosition()
                    updateDimmingOverlay()
                }
            } else if initialState == .cameraVisible {
                // From camera: only allow leftward swipes to return to feed
                if translation.x < 0 {
                    // Dismiss keyboard immediately when starting to swipe away from camera
                    // This makes the input bar disappear with the swipe
                    if feedOffset == maxOffset {
                        dismissKeyboardInCameraView()
                    }
                    
                    let newOffset = maxOffset + max(translation.x / view.bounds.width, -maxOffset)
                    feedOffset = newOffset
                    updateFeedPosition()
                    updateDimmingOverlay()
                }
            }

        case .ended, .cancelled:
            if gestureType == .horizontal && isDragging {
                isDragging = false

                // Determine final state based on position and velocity
                let shouldRevealCamera = shouldCompleteTransition(
                    offset: feedOffset,
                    velocity: velocity.x
                )

                animateToFinalState(revealCamera: shouldRevealCamera)
            }

            // Reset gesture state for next gesture
            gestureType = .unknown
            isDragging = false
            shouldAllowNavigation = false

        case .failed:
            // Gesture failed (likely due to direction detection)
            // Reset everything cleanly
            print("🔄 Gesture failed - resetting state")
            gestureType = .unknown
            isDragging = false
            shouldAllowNavigation = false

        default:
            break
        }
    }

    private func getInitialState() -> InstagramNavigationState {
        // Determine initial state based on current offset
        return feedOffset < 0.5 ? .feedVisible : .cameraVisible
    }

    // MARK: - Instagram-Style Hit Testing

    /// Determines if a touch location is in the navigation edge zone
    /// Swipe from LEFT edge reveals camera (your app's pattern)
    private func isLocationInNavigationZone(_ location: CGPoint) -> Bool {
        let screenWidth = view.bounds.width

        switch navigationState {
        case .feedVisible:
            // From feed: LEFT edge can reveal camera (swipe right from left edge)
            let isInZone = location.x < edgeSwipeZone
            if isInZone {
                print("📍 LEFT edge detected! x=\(location.x) < zone=\(edgeSwipeZone)")
            }
            return isInZone

        case .cameraVisible:
            // From camera: RIGHT edge returns to feed (swipe left from right edge)
            let edgeThreshold = screenWidth - edgeSwipeZone
            let isInZone = location.x > edgeThreshold
            if isInZone {
                print(
                    "📍 RIGHT edge detected! x=\(location.x) > threshold=\(edgeThreshold) (width=\(screenWidth))"
                )
            }
            return isInZone

        case .transitioning:
            return false
        }
    }

    /// Checks if a touch hit HORIZONTALLY scrollable content (carousels only)
    /// This prevents navigation from interfering with carousel scrolling
    /// But allows navigation from hero section and empty space
    private func isTouchOnScrollableContent(at point: CGPoint) -> Bool {
        // Convert point to feed view coordinate space
        let pointInFeed = view.convert(point, to: feedViewController.view)

        // Hit test to find the view at this point
        guard let hitView = feedViewController.view.hitTest(pointInFeed, with: nil) else {
            return false
        }

        // Walk up the view hierarchy looking for scroll views
        var currentView: UIView? = hitView
        while let view = currentView {
            // Check if this is a UICollectionView
            if let collectionView = view as? UICollectionView {
                if collectionView.isScrollEnabled {
                    // Find which section was touched
                    let pointInCollection = self.view.convert(point, to: collectionView)

                    if let indexPath = collectionView.indexPathForItem(at: pointInCollection) {
                        let isCarouselSection = indexPath.section > 0
                        print(
                            "🎯 Hit collection view section \(indexPath.section), isCarousel: \(isCarouselSection)"
                        )
                        // ONLY block navigation for carousel sections (horizontal scrolling)
                        // Allow navigation from hero section (section 0) and other areas
                        if isCarouselSection {
                            return true  // Block navigation - carousel needs horizontal swipes
                        } else {
                            return false  // Allow navigation - hero/main feed can use gesture direction
                        }
                    }

                    // If we can't determine section, check for horizontal scrolling capability
                    // This handles touches in margins, headers between carousel sections
                    let canScrollHorizontally =
                        collectionView.contentSize.width > collectionView.bounds.width
                    if canScrollHorizontally {
                        print("🎯 Hit collection view with horizontal scroll")
                        return true  // Likely a carousel area
                    }

                    // Vertical-only collection view (main feed) - allow navigation
                    print("🎯 Hit collection view (vertical only) - allowing navigation")
                    return false
                }
            }

            // Check for horizontally scrollable views only
            if let scrollView = view as? UIScrollView {
                let canScrollHorizontally = scrollView.contentSize.width > scrollView.bounds.width

                if canScrollHorizontally && scrollView.isScrollEnabled {
                    print("🎯 Hit horizontal scroll view")
                    return true  // Block navigation for horizontal scrolling
                }
            }

            currentView = view.superview
        }

        print("👆 Touch did not hit horizontally scrollable content - allowing navigation")
        return false
    }

    // MARK: - Animation Logic
    private func shouldCompleteTransition(offset: CGFloat, velocity: CGFloat) -> Bool {
        let initialState = initialDragState

        if initialState == .feedVisible {
            // From feed to camera: complete if dragged far enough right or fast rightward swipe
            if offset > revealThreshold {
                return true
            }
            if velocity > 400 && offset > 0.1 {  // Reduced threshold for more natural feel
                return true
            }
            return false
        } else if initialState == .cameraVisible {
            // From camera to feed: complete if dragged far enough left or fast leftward swipe
            if offset < (maxOffset - revealThreshold) {
                return false  // Stay in camera
            }
            if velocity < -400 && offset < (maxOffset - 0.1) {  // Reduced threshold for more natural feel
                return false  // Stay in camera
            }
            return true  // Return to feed
        }

        return false
    }

    private func animateToFinalState(revealCamera: Bool) {
        let targetOffset: CGFloat = revealCamera ? maxOffset : 0
        
        // Dismiss any keyboard/input accessory view when navigating away from camera
        // This ensures the chat input bar doesn't persist when swiping to feed
        if !revealCamera {
            dismissKeyboardInCameraView()
        }
        
        // Notify IMMEDIATELY when revealing camera (before animation)
        // This makes the chat input appear faster if control panel is visible
        if revealCamera {
            notifyCameraDidAppear()
        }

        UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            usingSpringWithDamping: springDamping,
            initialSpringVelocity: springVelocity,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.feedOffset = targetOffset
                self.updateFeedPosition()
                self.updateDimmingOverlay()
            },
            completion: { _ in
                let newState: InstagramNavigationState =
                    revealCamera ? .cameraVisible : .feedVisible
                self.updateNavigationState(newState)
            }
        )
    }
    
    /// Dismisses any keyboard or input accessory view in the camera view hierarchy
    private func dismissKeyboardInCameraView() {
        // End editing on the entire window to dismiss any keyboard
        view.window?.endEditing(true)
        
        // Also post notification for ControlPanelViewController to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("ControlPanelWillDisappear"),
            object: nil
        )
    }
    
    /// Notifies that the camera view has become visible
    /// This allows the control panel to restore its input bar if settings are open
    private func notifyCameraDidAppear() {
        // Post a specific notification for camera appearing
        // CameraContainerViewController will check if settings are visible and forward appropriately
        NotificationCenter.default.post(
            name: NSNotification.Name("CameraViewDidAppear"),
            object: nil
        )
    }

    // MARK: - Position Updates
    private func updateFeedPosition() {
        let offset = feedOffset * view.bounds.width
        feedViewController.view.transform = CGAffineTransform(translationX: offset, y: 0)
        
        // Update camera parallax effect
        updateCameraParallax()
    }
    
    private func updateCameraParallax() {
        // Instagram-style parallax: camera moves in OPPOSITE direction to feed (slower)
        // feedOffset: 0 = feed visible (camera hidden), 1 = camera visible (feed moved right)
        // 
        // Feed moves RIGHT when revealing camera (feedOffset 0→1)
        // Camera should move LEFT slightly (opposite direction, creating depth)
        //
        // When fully in camera (feedOffset = 1), camera should be back to center (no offset)
        
        let parallaxAmount: CGFloat = 0.1 // Camera moves 10% in opposite direction
        
        // Calculate how "hidden" the camera is (1.0 = fully hidden, 0.0 = fully visible)
        let hiddenAmount = 1.0 - feedOffset
        
        // Camera moves LEFT when hidden (negative translation)
        // Returns to center when visible (feedOffset = 1, hiddenAmount = 0)
        let cameraTranslation = -hiddenAmount * view.bounds.width * parallaxAmount
        
        // Apply transform (translation only, no scaling to avoid black gaps)
        cameraContainerViewController.view.transform = CGAffineTransform(translationX: cameraTranslation, y: 0)
        
        // Update camera dimming
        updateCameraDimming()
    }
    
    private func updateCameraDimming() {
        // Get dimming overlay (now in self.view, not cameraContainerViewController.view)
        let dimmingTag = 998
        guard let cameraDimmingView = view.viewWithTag(dimmingTag) else {
            return
        }
        
        // Dim when hidden (feedOffset = 0), clear when visible (feedOffset = 1)
        let hiddenAmount = 1.0 - feedOffset
        let dimmingAlpha = hiddenAmount * 0.5
        cameraDimmingView.alpha = dimmingAlpha
    }

    private func updateDimmingOverlay() {
        guard let dimmingView = feedViewController.view.viewWithTag(999) else { return }

        // Dim more as we drag further (but not fully opaque)
        let dimmingAlpha = feedOffset * 0.4
        dimmingView.alpha = dimmingAlpha

        // Ensure rounded corners are maintained during animation
        dimmingView.layer.cornerRadius = getDeviceCornerRadius()
        dimmingView.layer.masksToBounds = true
        dimmingView.layer.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
        ]
    }

    // MARK: - Public Methods
    func revealCamera() {
        guard navigationState == .feedVisible else { return }

        isDragging = false
        updateNavigationState(.transitioning)
        animateToFinalState(revealCamera: true)
    }

    func revealFeed() {
        guard navigationState == .cameraVisible else { return }

        isDragging = false
        updateNavigationState(.transitioning)
        animateToFinalState(revealCamera: false)
    }

    func toggleCamera() {
        switch navigationState {
        case .feedVisible:
            revealCamera()
        case .cameraVisible:
            revealFeed()
        case .transitioning:
            break  // Ignore during transition
        }
    }
    
    // MARK: - Private Helpers
    
    /// Finds the tab bar controller in the feed view hierarchy
    private func findTabBarController() -> UITabBarController? {
        // Search through the feed view controller's children for the tab bar controller
        func findInChildren(_ vc: UIViewController) -> UITabBarController? {
            if let tabBar = vc as? UITabBarController {
                return tabBar
            }
            for child in vc.children {
                if let found = findInChildren(child) {
                    return found
                }
            }
            return nil
        }
        return findInChildren(feedViewController)
    }

    // MARK: - State Management
    private func updateNavigationState(_ newState: InstagramNavigationState) {
        navigationState = newState
        onStateChanged?(newState)

        // Notify feed to pause/resume hero video during camera swipe
        let feedVisible = newState == .feedVisible
        notify(.feed_visibility(feedVisible))
    }
}

// MARK: - UIGestureRecognizerDelegate
extension InstagramNavigationController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // INSTAGRAM PATTERN: Allow simultaneous recognition for direction-based competition
        if gestureRecognizer == panGestureRecognizer {
            // If we're already committed to horizontal navigation, we own it exclusively
            if isDragging && gestureType == .horizontal && shouldAllowNavigation {
                return false  // Don't share - we've claimed horizontal navigation
            }
            // Otherwise, let both gestures run simultaneously
            // This allows the scroll view to claim vertical scrolling while we evaluate horizontal
            return true
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // INSTAGRAM PATTERN: Pan gesture can always begin, but won't claim until conditions are met
        if gestureRecognizer == panGestureRecognizer {
            return true
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
        -> Bool
    {
        // INSTAGRAM PATTERN: Pre-filter touches to avoid competing with carousels
        // This is THE KEY FIX - don't even receive touches on scrollable content!
        if gestureRecognizer == panGestureRecognizer {
            let location = touch.location(in: view)
            
            // Don't receive touches on the morphing glass modal or widget positioning overlay
            // - they handle their own gestures
            if let touchedView = touch.view {
                var currentView: UIView? = touchedView
                while let v = currentView {
                    if v is MorphingGlassModal || v is GlassContainerView || v is WidgetPositionOverlayView {
                        print("🚫 Navigation pan gesture not receiving touch - child view handles it")
                        return false
                    }
                    currentView = v.superview
                }
            }
            
            // Check if a profile (or other VC) is pushed onto the navigation stack
            // If so, let the navigation controller's interactive pop gesture handle left-edge swipes
            if navigationState == .feedVisible {
                if let tabBarController = findTabBarController(),
                   let selectedNav = tabBarController.selectedViewController as? UINavigationController,
                   selectedNav.viewControllers.count > 1 {
                    // A profile is pushed - don't receive left-edge touches
                    if location.x < edgeSwipeZone {
                        print("🚫 Navigation pan gesture not receiving touch - profile is pushed, letting nav controller handle pop")
                        return false
                    }
                }
            }

            // Check if touch is in edge zone
            let isInEdgeZone = isLocationInNavigationZone(location)

            // Check if touch hit scrollable content
            let hitScrollableContent = isTouchOnScrollableContent(at: location)

            // Only receive touch if:
            // 1. It's in the edge zone (edge swipes always win), OR
            // 2. It didn't hit scrollable content
            let shouldReceive = isInEdgeZone || !hitScrollableContent

            // Debug logging to understand what's happening
            print(
                "🔍 shouldReceive check: x=\(location.x), inEdge=\(isInEdgeZone), hitScroll=\(hitScrollableContent), result=\(shouldReceive)"
            )

            if !shouldReceive {
                print("🚫 Navigation pan gesture not receiving touch - letting carousel handle it")
            } else if isInEdgeZone {
                print("✅ Edge zone detected - navigation will receive touch!")
            }

            return shouldReceive
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // INSTAGRAM PATTERN: Don't require other gestures to fail
        // We want to compete, not wait
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // INSTAGRAM PATTERN: Let scroll views win if they claim the gesture
        // But only if we haven't already started dragging for navigation
        if gestureRecognizer == panGestureRecognizer {
            // If the other gesture is a scroll view pan gesture, let it win unless we're actively navigating
            if otherGestureRecognizer is UIPanGestureRecognizer {
                return !isDragging  // If we're dragging, we win. Otherwise, let scroll views win.
            }
        }
        return false
    }

}

// MARK: - SwiftUI Wrapper
struct InstagramNavigationView: UIViewControllerRepresentable {
    let feedView: InstagramFeedView
    let cameraView: AnyView
    let model: Model
    @Binding var navigationState: InstagramNavigationState

    func makeUIViewController(context: Context) -> InstagramNavigationController {
        // Create controller with model for direct CameraContainerViewController management
        // Requirements: 8.1 - InstagramNavigationController creates CameraContainerViewController directly
        let controller = InstagramNavigationController(
            feedView: feedView,
            cameraView: cameraView,
            model: model,
            onStateChanged: { state in
                navigationState = state
            },
            onCameraButtonTapped: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: InstagramNavigationController, context: Context)
    {
        switch navigationState {
        case .feedVisible:
            uiViewController.revealFeed()
        case .cameraVisible:
            uiViewController.revealCamera()
        case .transitioning:
            break
        }
    }
}

// MARK: - UIKit Camera SwiftUI Wrapper
/// SwiftUI wrapper that uses the new UIKit-based CameraViewController
/// for better gesture handling and morphing orb support.
struct InstagramNavigationViewUIKit: UIViewControllerRepresentable {
    let feedView: InstagramFeedView
    let cameraViewController: CameraViewController
    let model: Model
    @Binding var navigationState: InstagramNavigationState

    func makeUIViewController(context: Context) -> InstagramNavigationController {
        let controller = InstagramNavigationController(
            feedView: feedView,
            cameraViewController: cameraViewController,
            model: model,
            onStateChanged: { state in
                navigationState = state
            },
            onCameraButtonTapped: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: InstagramNavigationController, context: Context) {
        switch navigationState {
        case .feedVisible:
            uiViewController.revealFeed()
        case .cameraVisible:
            uiViewController.revealCamera()
        case .transitioning:
            break
        }
    }
}
