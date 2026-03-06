//
//  CameraContainerViewController.swift
//  swae
//
//  Instagram-style vertical navigation for camera settings
//

import SwiftUI
import UIKit

// MARK: - Camera State
enum CameraContainerState {
    case settings      // Settings visible (above camera - swipe DOWN to reveal)
    case camera        // Camera visible (default)
    case controlPanel  // Control panel/live chat visible (below camera - swipe UP to reveal)
    case transitioning // Animating between states
}

// MARK: - Gesture Direction
/// Represents the primary direction of a pan gesture.
/// Used for Instagram-style direction detection where navigation and scrolling
/// work together based on gesture direction.
enum GestureDirection {
    case unknown    // Direction not yet determined (gesture just started)
    case up         // Swiping upward (negative Y velocity)
    case down       // Swiping downward (positive Y velocity)
    case horizontal // Primarily horizontal gesture (ignored for vertical navigation)
}

// MARK: - Animation Constants
/// Constants for Instagram-style spring animations and gesture thresholds.
/// These values are tuned for smooth, native-feeling navigation.
struct AnimationConstants {
    /// Spring damping ratio for animations (0.8-0.9 for natural feel)
    static let springDamping: CGFloat = 0.85
    /// Initial spring velocity for animations
    static let springVelocity: CGFloat = 0.6
    /// Duration of spring animations
    static let animationDuration: TimeInterval = 0.5
    /// Threshold for completing a transition (30% of screen height)
    static let revealThreshold: CGFloat = 0.3
    /// Velocity threshold for quick swipes (points per second)
    static let velocityThreshold: CGFloat = 400
    /// Maximum dimming alpha for overlay
    static let dimmingAlphaMax: CGFloat = 0.4
    /// Minimum gesture distance before direction is determined
    static let minimumGestureDistance: CGFloat = 10
    /// Points of over-scroll to trigger navigation
    static let overscrollNavigationThreshold: CGFloat = 50
}

// MARK: - Notification Names
extension Notification.Name {
    static let dismissCameraSettings = Notification.Name("dismissCameraSettings")
}

// MARK: - Camera Container View Controller
class CameraContainerViewController: UIViewController {

    // MARK: - Properties
    private var settingsViewController: UIViewController?      // Above camera (swipe down)
    private var controlPanelViewController: UIViewController?  // Below camera (swipe up) - live chat
    
    // Camera view - can be either UIKit CameraViewController or legacy SwiftUI wrapper
    private var cameraViewControllerUIKit: CameraViewController?
    private var cameraViewControllerSwiftUI: UIHostingController<AnyView>?
    private var cameraView: UIViewController {
        return cameraViewControllerUIKit ?? cameraViewControllerSwiftUI!
    }
    
    private(set) var currentState: CameraContainerState = .camera

    // Gesture properties
    private var verticalPanGesture: UIPanGestureRecognizer!
    /// Navigation offset representing the current position in the vertical stack.
    /// Range: -1 (settings fully visible) to +1 (control panel fully visible), 0 = camera centered
    private(set) var navigationOffset: CGFloat = 0
    private var isDragging = false
    private var initialDragState: CameraContainerState = .camera
    private var gestureStartLocation: CGPoint?
    private var gestureDirection: GestureDirection = .unknown
    private var isDirectionLocked = false  // Once direction is determined, it's locked for the gesture

    // Layout constants
    private let maxOffset: CGFloat = 1.0
    private let sectionHeightRatio: CGFloat = 1.0
    private let minimumVerticalDistance: CGFloat = 20

    // Dimming overlay
    private let dimmingView = UIView()

    // Model reference
    private weak var model: Model?
    
    // Scroll view coordination
    /// The currently active scroll view being tracked for over-scroll navigation.
    private weak var activeScrollView: UIScrollView?
    /// Delegate proxy for intercepting scroll view events.
    private var scrollViewDelegateProxy: ScrollViewDelegateProxy?
    /// Tracks whether we're in the process of transitioning from scroll to navigation.
    private var isTransitioningFromScroll: Bool = false
    /// The over-scroll amount that triggered the transition.
    private var overscrollNavigationProgress: CGFloat = 0

    // Callbacks
    var onStateChanged: ((CameraContainerState) -> Void)?

    // MARK: - Initialization
    
    /// Creates a CameraContainerViewController with the new UIKit-based CameraViewController.
    /// This is the preferred initializer for better gesture handling and morphing orb support.
    init(cameraViewController: CameraViewController, model: Model) {
        self.cameraViewControllerUIKit = cameraViewController
        self.cameraViewControllerSwiftUI = nil
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    
    /// Legacy initializer for SwiftUI-based camera view.
    /// Use init(cameraViewController:model:) for new implementations.
    init(cameraView: AnyView, model: Model) {
        self.cameraViewControllerUIKit = nil
        self.cameraViewControllerSwiftUI = UIHostingController(rootView: cameraView)
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupGestures()
        setupNotifications()
        setupInitialState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeScrollViewProxy()
    }

    // MARK: - Setup
    private func setupViews() {
        view.backgroundColor = .black
        // Note: clipsToBounds must be false to allow settings/control panel views
        // to be visible when transformed from their off-screen positions
        view.clipsToBounds = false

        // Add camera view (fills screen edge-to-edge)
        addChild(cameraView)
        view.addSubview(cameraView.view)
        cameraView.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            cameraView.view.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        cameraView.didMove(toParent: self)

        // Add dimming overlay
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingView.alpha = 0
        dimmingView.isUserInteractionEnabled = false
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        cameraView.view.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: cameraView.view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: cameraView.view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: cameraView.view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: cameraView.view.bottomAnchor),
        ])
    }

    private func setupGestures() {
        verticalPanGesture = UIPanGestureRecognizer(
            target: self, action: #selector(handleVerticalPan(_:)))
        verticalPanGesture.delegate = self
        // Don't cancel touches in other views - allows table view selection to work
        verticalPanGesture.cancelsTouchesInView = false
        verticalPanGesture.delaysTouchesBegan = false
        view.addGestureRecognizer(verticalPanGesture)
        print("✅ Vertical pan gesture added to camera container")
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissSettings),
            name: .dismissCameraSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenControlPanel),
            name: NSNotification.Name("OpenCameraSettings"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: NSNotification.Name("OpenSettings"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraViewDidAppear),
            name: NSNotification.Name("CameraViewDidAppear"),
            object: nil
        )
    }
    
    @objc private func handleCameraViewDidAppear() {
        if currentState == .controlPanel {
            print("📱 Camera appeared with control panel visible - notifying")
            notifyControlPanelDidAppear()
        }
    }

    private func setupInitialState() {
        navigationOffset = 0
        updateViewPositions()
        updateState(.camera)
    }
    
    // MARK: - Gesture Direction Detection
    
    /// Determines the primary direction of a gesture based on translation.
    /// Direction is vertical if angle < 45° from vertical axis.
    /// - Parameter translation: The translation point from the pan gesture
    /// - Returns: The determined gesture direction
    func determineGestureDirection(translation: CGPoint) -> GestureDirection {
        let distance = sqrt(translation.x * translation.x + translation.y * translation.y)
        
        // Don't determine direction until we have enough movement
        guard distance >= AnimationConstants.minimumGestureDistance else {
            return .unknown
        }
        
        // Calculate angle from vertical axis
        // Vertical axis is Y, so we compare |x| vs |y|
        // If |y| > |x|, the gesture is more vertical than horizontal
        // This is equivalent to angle < 45° from vertical
        let absX = abs(translation.x)
        let absY = abs(translation.y)
        
        // Horizontal if |x| >= |y| (angle >= 45° from vertical)
        if absX >= absY {
            return .horizontal
        }
        
        // Vertical gesture - determine up or down based on translation
        // Positive Y translation = finger moved DOWN = swipe DOWN = reveal settings
        // Negative Y translation = finger moved UP = swipe UP = reveal control panel
        let direction: GestureDirection = translation.y > 0 ? .down : .up
        print("📐 Direction detection: translation.y=\(translation.y), direction=\(direction)")
        return direction
    }
    
    /// Determines if the container should claim the gesture based on current state and direction.
    /// - Parameter direction: The determined gesture direction
    /// - Returns: true if the container should claim the gesture, false if it should defer to child views
    func shouldClaimGesture(direction: GestureDirection) -> Bool {
        // Disable swipe navigation in landscape mode
        if model?.orientation.isPortrait == false { return false }
        
        let result: Bool
        
        switch direction {
        case .unknown, .horizontal:
            // Don't claim unknown or horizontal gestures
            result = false
            
        case .up, .down:
            switch currentState {
            case .camera:
                // In camera state: only claim upward gestures for control panel
                // Up → control panel (allowed)
                // Down → settings (DISABLED - settings button is now on camera view)
                result = direction == .up
                
            case .settings:
                // In settings state:
                // - UP (dismiss direction) → claim for navigation
                // - DOWN (scroll direction) → fail to allow scroll view to handle
                result = direction == .up
                
            case .controlPanel:
                // In control panel state:
                // - DOWN (dismiss direction) → claim for navigation
                // - UP (scroll direction) → fail to allow scroll view to handle
                result = direction == .down
                
            case .transitioning:
                // Don't claim new gestures while transitioning
                result = false
            }
        }
        
        print("🎯 shouldClaimGesture: direction=\(direction), state=\(currentState), result=\(result)")
        return result
    }

    // MARK: - Settings View Management (Above camera - swipe DOWN to reveal)
    private func createSettingsViewIfNeeded() {
        guard settingsViewController == nil else {
            print("📱 createSettingsViewIfNeeded: Already exists")
            return
        }
        guard let model = model else {
            print("⚠️ createSettingsViewIfNeeded: No model!")
            return
        }

        print("📱 Creating settings view controller (above camera)")

        // Create SwiftUI SettingsRootView with NavigationStack
        let settingsView = SettingsRootView(onDismiss: { [weak self] in
            self?.hideSettings()
        })
        .environmentObject(model)
        .environmentObject(AppCoordinator.shared.appState)
        
        let settingsVC = UIHostingController(rootView: settingsView)

        addChild(settingsVC)
        view.addSubview(settingsVC.view)
        settingsVC.view.translatesAutoresizingMaskIntoConstraints = false

        // Position settings view ABOVE the screen (bottom edge at screen top)
        // It will be transformed down into view when revealed
        NSLayoutConstraint.activate([
            settingsVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settingsVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsVC.view.heightAnchor.constraint(equalTo: view.heightAnchor),
            settingsVC.view.bottomAnchor.constraint(equalTo: view.topAnchor),
        ])

        settingsVC.didMove(toParent: self)

        // Apply rounded corners at bottom (since it slides down from top)
        settingsVC.view.layer.cornerRadius = 16
        settingsVC.view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        settingsVC.view.clipsToBounds = true

        settingsViewController = settingsVC
        view.layoutIfNeeded()
        
        print("✅ Settings view created successfully!")
        print("   - Frame: \(settingsVC.view.frame)")
        print("   - Superview: \(settingsVC.view.superview != nil ? "yes" : "no")")
    }
    
    // MARK: - Control Panel View Management (Below camera - swipe UP to reveal) - Live Chat
    private func createControlPanelViewIfNeeded() {
        guard controlPanelViewController == nil else {
            print("📱 createControlPanelViewIfNeeded: Already exists")
            return
        }
        guard let model = model else {
            print("⚠️ createControlPanelViewIfNeeded: No model!")
            return
        }

        print("📱 Creating control panel view controller (below camera - live chat)")

        // Create UIKit ControlPanelViewController directly (no SwiftUI wrapper)
        let controlPanelVC = ControlPanelViewController()
        controlPanelVC.model = model

        addChild(controlPanelVC)
        view.addSubview(controlPanelVC.view)
        controlPanelVC.view.translatesAutoresizingMaskIntoConstraints = false

        // Position control panel BELOW the screen (top edge at screen bottom)
        // It will be transformed up into view when revealed
        NSLayoutConstraint.activate([
            controlPanelVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlPanelVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlPanelVC.view.heightAnchor.constraint(equalTo: view.heightAnchor),
            controlPanelVC.view.topAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        controlPanelVC.didMove(toParent: self)

        // Apply rounded corners at top (since it slides up from bottom)
        controlPanelVC.view.layer.cornerRadius = 16
        controlPanelVC.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        controlPanelVC.view.clipsToBounds = true

        controlPanelViewController = controlPanelVC
        view.layoutIfNeeded()
        
        print("✅ Control panel view created successfully!")
        print("   - Frame: \(controlPanelVC.view.frame)")
        print("   - Superview: \(controlPanelVC.view.superview != nil ? "yes" : "no")")
        print("   - Background: \(controlPanelVC.view.backgroundColor?.description ?? "nil")")
    }

    // MARK: - Gesture Handling
    @objc private func handleVerticalPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            // Reset gesture state
            isDragging = false
            initialDragState = currentState
            gestureStartLocation = gesture.location(in: view)
            gestureDirection = .unknown
            isDirectionLocked = false

            let location = gesture.location(in: view)
            print("📍 Vertical gesture began at y: \(location.y), state: \(currentState)")

        case .changed:
            // Determine direction if not yet locked (first 10pts of movement)
            if !isDirectionLocked {
                let detectedDirection = determineGestureDirection(translation: translation)
                
                // Only lock direction once we have a definitive direction
                if detectedDirection != .unknown {
                    gestureDirection = detectedDirection
                    isDirectionLocked = true
                    
                    print("🔒 Direction locked: \(gestureDirection), translation.y=\(translation.y)")
                    
                    // Determine if we should claim or fail the gesture
                    if shouldClaimGesture(direction: gestureDirection) {
                        isDragging = true
                        updateState(.transitioning)
                        print("✅ Gesture claimed for navigation")
                    } else {
                        // Fail gesture to allow child views (scroll views) to handle it
                        print("❌ Deferring to child view - direction: \(gestureDirection), state: \(currentState)")
                        gesture.state = .failed
                        return
                    }
                }
            }

            guard isDragging else { return }

            let screenHeight = view.bounds.height

            // Handle drag based on initial state
            // Create views lazily based on ACTUAL translation direction (not locked direction)
            // This handles cases where the initial direction detection might differ from the main swipe
            switch initialDragState {
            case .camera:
                // Only handle upward swipes (control panel)
                // Downward swipes to settings are DISABLED - settings button is now on camera view
                if translation.y < 0 {
                    // Swipe up: show control panel (positive offset)
                    // Create control panel view if needed (lazy creation based on actual direction)
                    if controlPanelViewController == nil {
                        createControlPanelViewIfNeeded()
                        print("📱 Created control panel view for upward swipe")
                    }
                    let dragProgress = -translation.y / screenHeight
                    navigationOffset = min(dragProgress, maxOffset)
                }
                
            case .settings:
                // From settings (top): swipe up to return to camera
                if translation.y < 0 {
                    view.window?.endEditing(true)
                    let dragProgress = -translation.y / screenHeight
                    navigationOffset = -maxOffset + min(dragProgress, maxOffset)
                }
                
            case .controlPanel:
                // From control panel (bottom): swipe down to return to camera
                if translation.y > 0 {
                    view.window?.endEditing(true)
                    dismissKeyboardInControlPanel()
                    let dragProgress = translation.y / screenHeight
                    navigationOffset = maxOffset - min(dragProgress, maxOffset)
                }
                
            case .transitioning:
                break
            }
            
            updateViewPositions()
            updateDimmingOverlay()

        case .ended, .cancelled:
            if isDragging {
                isDragging = false
                gestureStartLocation = nil
                gestureDirection = .unknown
                isDirectionLocked = false
                
                let finalState = determineFinalState(offset: navigationOffset, velocity: velocity.y)
                animateToState(finalState)
            } else {
                gestureStartLocation = nil
                gestureDirection = .unknown
                isDirectionLocked = false
            }

        case .failed:
            print("🔄 Vertical gesture failed")
            isDragging = false
            gestureStartLocation = nil
            gestureDirection = .unknown
            isDirectionLocked = false

        default:
            break
        }
    }

    @objc private func handleDismissSettings() {
        if currentState == .settings {
            hideSettings()
        } else if currentState == .controlPanel {
            hideControlPanel()
        }
    }

    @objc private func handleOpenControlPanel() {
        showControlPanel()
    }
    
    @objc private func handleOpenSettings() {
        showSettings()
    }

    /// Determines the final state based on drag offset and velocity.
    /// Complete transition if offset > 30% threshold OR velocity > 400 pts/sec.
    /// - Parameters:
    ///   - offset: Current navigation offset (-1 to +1)
    ///   - velocity: Gesture velocity in points per second (negative = up, positive = down)
    /// - Returns: The target state to animate to
    func determineFinalState(offset: CGFloat, velocity: CGFloat) -> CameraContainerState {
        // Velocity: negative = upward, positive = downward
        // Offset: negative = settings (top), positive = control panel (bottom)
        let threshold = AnimationConstants.revealThreshold
        let velocityThreshold = AnimationConstants.velocityThreshold
        
        switch initialDragState {
        case .camera:
            // Check if we should complete transition to settings (negative offset)
            if offset < -threshold || (velocity > velocityThreshold && offset < -0.1) {
                return .settings
            }
            // Check if we should complete transition to control panel (positive offset)
            else if offset > threshold || (velocity < -velocityThreshold && offset > 0.1) {
                return .controlPanel
            }
            return .camera
            
        case .settings:
            // From settings: swipe up to return to camera
            // Complete if offset moved past threshold toward camera OR velocity is fast enough
            if offset > -threshold || velocity < -velocityThreshold {
                return .camera
            }
            return .settings
            
        case .controlPanel:
            // From control panel: swipe down to return to camera
            // Complete if offset moved past threshold toward camera OR velocity is fast enough
            if offset < threshold || velocity > velocityThreshold {
                return .camera
            }
            return .controlPanel
            
        case .transitioning:
            return .camera
        }
    }

    // MARK: - Animation
    
    /// Animates the container to the specified state using spring-based animation.
    /// Uses AnimationConstants for spring damping (0.85) and velocity (0.6).
    /// Triggers haptic feedback on completion.
    /// - Parameter state: The target state to animate to
    func animateToState(_ state: CameraContainerState) {
        let targetOffset: CGFloat
        switch state {
        case .settings:
            targetOffset = -maxOffset     // Negative = settings visible (top)
        case .camera:
            targetOffset = 0
        case .controlPanel:
            targetOffset = maxOffset      // Positive = control panel visible (bottom)
        case .transitioning:
            targetOffset = 0
        }
        
        // Notify before animation if hiding
        if state == .camera {
            view.window?.endEditing(true)
            if currentState == .controlPanel || initialDragState == .controlPanel {
                notifyControlPanelWillDisappear()
            }
            // Tear down scroll view observation when returning to camera
            teardownScrollViewObservation()
        }
        
        // Notify IMMEDIATELY when going to control panel (before animation)
        // This makes the chat input appear faster
        if state == .controlPanel {
            notifyControlPanelDidAppear()
        }
        
        // Reset scroll transition state
        isTransitioningFromScroll = false
        overscrollNavigationProgress = 0

        UIView.animate(
            withDuration: AnimationConstants.animationDuration,
            delay: 0,
            usingSpringWithDamping: AnimationConstants.springDamping,
            initialSpringVelocity: AnimationConstants.springVelocity,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.navigationOffset = targetOffset
                self.updateViewPositions()
                self.updateDimmingOverlay()
            },
            completion: { _ in
                // Trigger haptic feedback on state change completion
                if state != self.currentState {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                
                self.updateState(state)
                
                if state == .controlPanel {
                    // Set up scroll view observation for control panel
                    self.setupScrollViewObservation()
                } else if state == .settings {
                    // Set up scroll view observation for settings
                    self.setupScrollViewObservation()
                }
            }
        )
    }
    
    private func notifyControlPanelDidAppear() {
        NotificationCenter.default.post(
            name: NSNotification.Name("ControlPanelDidAppear"),
            object: nil
        )
    }
    
    private func notifyControlPanelWillDisappear() {
        NotificationCenter.default.post(
            name: NSNotification.Name("ControlPanelWillDisappear"),
            object: nil
        )
    }

    // MARK: - Position Updates
    
    /// Updates view positions based on the current navigationOffset.
    /// Applies CGAffineTransform to position views, including:
    /// - 95% scale on camera view during transitions
    /// - Dimming overlay proportional to offset
    func updateViewPositions() {
        let screenHeight = view.bounds.height
        let sectionHeight = screenHeight * sectionHeightRatio
        
        if navigationOffset < 0 {
            // Moving toward settings (top) - negative offset
            // Settings is positioned ABOVE screen (bottom at view.top)
            // To slide it DOWN into view, we need POSITIVE Y translation equal to sectionHeight
            // At offset = -1, settings should be fully visible (translated down by sectionHeight)
            let progress = abs(navigationOffset)  // 0 to 1, clamped
            let clampedProgress = min(progress, 1.0)
            let settingsTranslation = clampedProgress * sectionHeight  // Settings moves DOWN (positive Y)
            
            print("📱 updateViewPositions: offset=\(navigationOffset), settingsExists=\(settingsViewController != nil), translation=\(settingsTranslation)")
            
            // Camera moves DOWN to make room
            cameraView.view.transform = CGAffineTransform(translationX: 0, y: settingsTranslation)
            
            // Settings view moves DOWN from above the screen
            if let settingsVC = settingsViewController {
                settingsVC.view.transform = CGAffineTransform(translationX: 0, y: settingsTranslation)
                print("📱 Settings view frame: \(settingsVC.view.frame), transform: \(settingsVC.view.transform)")
            } else {
                print("⚠️ Settings view is nil during updateViewPositions!")
            }
            
            // Reset control panel position
            controlPanelViewController?.view.transform = .identity
            
            // Ensure settings is on top
            if let settingsView = settingsViewController?.view {
                view.bringSubviewToFront(settingsView)
            }
        } else if navigationOffset > 0 {
            // Moving toward control panel (bottom) - positive offset
            // Control panel is positioned BELOW screen (top at view.bottom)
            // To slide it UP into view, we need NEGATIVE Y translation equal to sectionHeight
            // At offset = 1, control panel should be fully visible (translated up by sectionHeight)
            let progress = navigationOffset  // 0 to 1
            let clampedProgress = min(progress, 1.0)
            let controlPanelTranslation = clampedProgress * sectionHeight  // Amount to move
            
            // Camera moves UP to make room
            cameraView.view.transform = CGAffineTransform(translationX: 0, y: -controlPanelTranslation)
            
            // Control panel moves UP (negative Y)
            controlPanelViewController?.view.transform = CGAffineTransform(translationX: 0, y: -controlPanelTranslation)
            
            // Reset settings position
            settingsViewController?.view.transform = .identity
            
            // Ensure control panel is on top
            if let controlPanelView = controlPanelViewController?.view {
                view.bringSubviewToFront(controlPanelView)
            }
        } else {
            // Camera centered - reset all transforms
            cameraView.view.transform = .identity
            settingsViewController?.view.transform = .identity
            controlPanelViewController?.view.transform = .identity
        }
    }

    /// Updates the dimming overlay alpha proportional to the navigation offset.
    private func updateDimmingOverlay() {
        dimmingView.alpha = abs(navigationOffset) * AnimationConstants.dimmingAlphaMax
    }

    // MARK: - Public Methods
    func showSettings() {
        guard currentState == .camera else { return }

        isDragging = false
        initialDragState = .camera
        updateState(.transitioning)

        if settingsViewController == nil {
            createSettingsViewIfNeeded()
        }

        animateToState(.settings)
    }

    func hideSettings() {
        guard currentState == .settings else { return }

        isDragging = false
        initialDragState = .settings
        updateState(.transitioning)
        
        animateToState(.camera)
    }
    
    func showControlPanel() {
        guard currentState == .camera else { return }

        isDragging = false
        initialDragState = .camera
        updateState(.transitioning)

        if controlPanelViewController == nil {
            createControlPanelViewIfNeeded()
        }

        animateToState(.controlPanel)
    }

    func hideControlPanel() {
        guard currentState == .controlPanel else { return }

        isDragging = false
        initialDragState = .controlPanel
        updateState(.transitioning)
        
        dismissKeyboardInControlPanel()
        
        animateToState(.camera)
    }

    func toggleControlPanel() {
        switch currentState {
        case .camera:
            showControlPanel()
        case .controlPanel:
            hideControlPanel()
        default:
            break
        }
    }
    
    func toggleSettings() {
        switch currentState {
        case .camera:
            showSettings()
        case .settings:
            hideSettings()
        default:
            break
        }
    }
    
    // MARK: - Keyboard Management
    
    private func dismissKeyboardInControlPanel() {
        NotificationCenter.default.post(
            name: NSNotification.Name("DismissControlPanelKeyboard"),
            object: nil
        )
    }

    // MARK: - State Management
    private func updateState(_ newState: CameraContainerState) {
        currentState = newState
        onStateChanged?(newState)

        print("📱 Camera container state: \(newState)")
    }
}

// MARK: - UIGestureRecognizerDelegate
extension CameraContainerViewController: UIGestureRecognizerDelegate {
    
    /// Allows simultaneous recognition with scroll view gestures until the container claims the gesture.
    /// This enables direction-based competition between navigation and scrolling.
    /// - Requirements: 10.1, 3.2, 3.4
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer == verticalPanGesture else {
            return true
        }
        
        // Once we've claimed the gesture (isDragging = true), don't allow simultaneous recognition
        // This ensures our navigation gesture takes priority after direction is determined
        if isDragging && isDirectionLocked {
            return false
        }
        
        // Allow simultaneous recognition with scroll views until we determine direction
        // This enables the direction-based competition pattern from Requirements 10.1
        return true
    }

    /// Checks if the gesture should begin based on direction validity for the current state.
    /// In camera state, allows vertical gestures in either direction.
    /// In panel states, only allows gestures in the dismiss direction.
    /// - Requirements: 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == verticalPanGesture else {
            return true
        }
        
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        
        let velocity = panGesture.velocity(in: view)
        
        // Check if gesture is primarily vertical (angle < 45° from vertical)
        // This is equivalent to |y| > |x|
        let isVerticalGesture = abs(velocity.y) > abs(velocity.x)
        
        if !isVerticalGesture {
            // Horizontal gestures are not handled by this recognizer
            print("🚫 gestureRecognizerShouldBegin: Blocked - horizontal gesture")
            return false
        }
        
        // Determine swipe direction from velocity
        let isSwipingDown = velocity.y > 0  // Positive Y = downward
        let isSwipingUp = velocity.y < 0    // Negative Y = upward
        
        print("📍 gestureRecognizerShouldBegin: velocity.y=\(velocity.y), isSwipingDown=\(isSwipingDown), isSwipingUp=\(isSwipingUp), state=\(currentState)")
        
        switch currentState {
        case .camera:
            // Camera state: only allow upward gestures for control panel
            // Up → control panel (allowed, even while streaming)
            // Down → settings (DISABLED - settings button is now on camera view)
            let allowed = isSwipingUp
            print("\(allowed ? "✅" : "🚫") gestureRecognizerShouldBegin: \(allowed ? "Allowed" : "Blocked") - camera state, isSwipingUp=\(isSwipingUp)")
            return allowed
            
        case .settings:
            // Settings state: only allow upward swipes (dismiss direction)
            // Downward swipes should be handled by scroll views
            let allowed = isSwipingUp
            print("\(allowed ? "✅" : "🚫") gestureRecognizerShouldBegin: \(allowed ? "Allowed" : "Blocked") - settings state, isSwipingUp=\(isSwipingUp)")
            return allowed
            
        case .controlPanel:
            // Control panel state: only allow downward swipes (dismiss direction)
            // Allowed even while streaming so user can return to camera
            let allowed = isSwipingDown
            print("\(allowed ? "✅" : "🚫") gestureRecognizerShouldBegin: \(allowed ? "Allowed" : "Blocked") - controlPanel state, isSwipingDown=\(isSwipingDown)")
            return allowed
            
        case .transitioning:
            // Don't start new gestures while transitioning
            print("🚫 gestureRecognizerShouldBegin: Blocked - transitioning")
            return false
        }
    }

    /// Filters out interactive elements to allow taps and interactions to pass through.
    /// Returns false for buttons, text fields, switches, sliders, and table/collection view cells.
    /// - Requirements: 3.1, 3.3
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer == verticalPanGesture else {
            return true
        }
        
        // Filter out interactive elements in settings and control panel
        // This allows taps to pass through to buttons, text fields, etc.
        if currentState == .settings || currentState == .controlPanel {
            if let touchedView = touch.view {
                // Direct interactive element checks
                if touchedView is UIButton ||
                   touchedView is UITextField ||
                   touchedView is UITextView ||
                   touchedView is UISwitch ||
                   touchedView is UISlider {
                    return false
                }
                
                // Check if touch is inside a table view cell (for row selection)
                if isDescendant(of: UITableViewCell.self, view: touchedView) {
                    return false
                }
                
                // Check if touch is inside a collection view cell
                if isDescendant(of: UICollectionViewCell.self, view: touchedView) {
                    return false
                }
            }
        }
        
        // Don't receive touches on the morphing glass modal - it handles its own gestures
        if let touchedView = touch.view {
            if isDescendant(of: MorphingGlassModal.self, view: touchedView) ||
               isDescendant(of: GlassContainerView.self, view: touchedView) ||
               isDescendant(of: WidgetPositionOverlayView.self, view: touchedView) {
                return false
            }
        }

        return true
    }
    
    /// Determines if our gesture should require failure of another gesture.
    /// Used to coordinate with scroll views that have content to scroll.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer == verticalPanGesture else {
            return false
        }
        
        // In panel states, if there's a scroll view with content that can be scrolled
        // in the non-dismiss direction, we should wait for it to fail first
        if currentState == .settings || currentState == .controlPanel {
            if let scrollView = otherGestureRecognizer.view as? UIScrollView {
                let canScrollVertically = scrollView.contentSize.height > scrollView.bounds.height
                
                // Only require failure if scroll view has content and isn't at boundary
                if canScrollVertically {
                    if currentState == .settings && scrollView.contentOffset.y > 0 {
                        // Settings: scroll view has content above, let it handle upward scrolls
                        return true
                    }
                    if currentState == .controlPanel {
                        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
                        if scrollView.contentOffset.y < maxOffset {
                            // Control panel: scroll view has content below, let it handle downward scrolls
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - Helper Methods
    
    private func findScrollView(at point: CGPoint, in view: UIView?) -> UIScrollView? {
        guard let view = view else { return nil }
        
        if let scrollView = view as? UIScrollView {
            let pointInScrollView = view.convert(point, from: settingsViewController?.view ?? controlPanelViewController?.view)
            if scrollView.bounds.contains(pointInScrollView) {
                return scrollView
            }
        }
        
        for subview in view.subviews.reversed() {
            if let found = findScrollView(at: point, in: subview) {
                return found
            }
        }
        
        return nil
    }
    
    // MARK: - Scroll View Discovery and Proxy Setup
    
    /// Finds the active scroll view at the given point in the current panel.
    /// Walks the view hierarchy to find scroll views that can handle scrolling.
    /// - Parameter point: The point in the container's coordinate space
    /// - Returns: The scroll view at the point, or nil if none found
    /// - Requirements: 14.1, 14.4
    func findActiveScrollView(at point: CGPoint) -> UIScrollView? {
        let targetView: UIView?
        
        switch currentState {
        case .settings:
            targetView = settingsViewController?.view
        case .controlPanel:
            targetView = controlPanelViewController?.view
        default:
            return nil
        }
        
        guard let targetView = targetView else { return nil }
        
        // Convert point to target view's coordinate space
        let pointInTarget = view.convert(point, to: targetView)
        
        // Walk the view hierarchy to find scroll views
        return findScrollViewRecursively(at: pointInTarget, in: targetView)
    }
    
    /// Recursively searches for a scroll view at the given point.
    /// Prioritizes deeper scroll views (more specific) over shallower ones.
    private func findScrollViewRecursively(at point: CGPoint, in view: UIView) -> UIScrollView? {
        // Check subviews first (depth-first search for more specific scroll views)
        for subview in view.subviews.reversed() {
            let pointInSubview = view.convert(point, to: subview)
            
            // Only check if point is within subview bounds
            guard subview.bounds.contains(pointInSubview) else { continue }
            
            // Check if subview is hidden or has user interaction disabled
            guard !subview.isHidden && subview.isUserInteractionEnabled else { continue }
            
            // Recursively search in subview
            if let found = findScrollViewRecursively(at: pointInSubview, in: subview) {
                return found
            }
        }
        
        // Check if this view is a scroll view
        if let scrollView = view as? UIScrollView {
            // Only return scroll views that can actually scroll vertically
            let canScrollVertically = scrollView.contentSize.height > scrollView.bounds.height ||
                                      scrollView.alwaysBounceVertical
            if canScrollVertically {
                return scrollView
            }
        }
        
        return nil
    }
    
    /// Installs a delegate proxy on the given scroll view to intercept scroll events.
    /// - Parameter scrollView: The scroll view to proxy
    /// - Requirements: 14.1, 14.4
    private func installScrollViewProxy(for scrollView: UIScrollView) {
        // Remove existing proxy if any
        removeScrollViewProxy()
        
        // Create and install new proxy
        scrollViewDelegateProxy = ScrollViewDelegateProxy(scrollView: scrollView, delegate: self)
        activeScrollView = scrollView
        
        print("📜 Installed scroll view proxy for: \(type(of: scrollView))")
    }
    
    /// Removes the current scroll view delegate proxy and restores the original delegate.
    private func removeScrollViewProxy() {
        scrollViewDelegateProxy?.uninstall()
        scrollViewDelegateProxy = nil
        activeScrollView = nil
        isTransitioningFromScroll = false
        overscrollNavigationProgress = 0
    }
    
    /// Sets up scroll view observation for the current panel.
    /// Called when a panel becomes visible to enable scroll-to-navigation coordination.
    private func setupScrollViewObservation() {
        // Find the main scroll view in the current panel
        let centerPoint = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        
        if let scrollView = findActiveScrollView(at: centerPoint) {
            installScrollViewProxy(for: scrollView)
        }
    }
    
    /// Tears down scroll view observation when leaving a panel.
    private func teardownScrollViewObservation() {
        removeScrollViewProxy()
    }
    
    // MARK: - Over-scroll Detection
    
    /// Handles over-scroll detection and translates it to navigation progress.
    /// - In settings: detects contentOffset < 0 (pulled past top)
    /// - In controlPanel: detects contentOffset > max (pulled past bottom)
    /// - Parameter scrollView: The scroll view to check for over-scroll
    /// - Requirements: 13.1, 13.2, 13.3, 13.4
    private func handleScrollViewOverscroll(_ scrollView: UIScrollView) {
        let contentOffset = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let boundsHeight = scrollView.bounds.height
        let maxContentOffset = max(0, contentHeight - boundsHeight)
        
        // Calculate over-scroll amount based on current state
        var overscrollAmount: CGFloat = 0
        
        switch currentState {
        case .settings:
            // In settings: detect contentOffset < 0 (pulled past top)
            // This means user is pulling down, which should dismiss settings
            if contentOffset < 0 {
                overscrollAmount = -contentOffset  // Make positive
                print("📜 Settings over-scroll detected: \(overscrollAmount)pt past top")
            }
            
        case .controlPanel:
            // In controlPanel: detect contentOffset > max (pulled past bottom)
            // This means user is pulling up, which should dismiss control panel
            if contentOffset > maxContentOffset && maxContentOffset >= 0 {
                overscrollAmount = contentOffset - maxContentOffset
                print("📜 Control panel over-scroll detected: \(overscrollAmount)pt past bottom")
            }
            
        default:
            return
        }
        
        // Translate over-scroll to navigation progress
        if overscrollAmount > 0 {
            translateOverscrollToNavigation(overscrollAmount, in: scrollView)
        } else if isTransitioningFromScroll {
            // User reversed direction, cancel transition
            cancelOverscrollNavigation()
        }
    }
    
    /// Translates over-scroll distance to navigation progress.
    /// - Parameters:
    ///   - overscrollAmount: The amount of over-scroll in points
    ///   - scrollView: The scroll view being over-scrolled
    /// - Requirements: 13.3, 13.4
    private func translateOverscrollToNavigation(_ overscrollAmount: CGFloat, in scrollView: UIScrollView) {
        let threshold = AnimationConstants.overscrollNavigationThreshold
        let screenHeight = view.bounds.height
        
        // Calculate navigation progress (0 to 1)
        // Use a larger divisor for smoother feel
        let progress = min(overscrollAmount / (screenHeight * AnimationConstants.revealThreshold), 1.0)
        
        // Mark that we're transitioning from scroll
        if !isTransitioningFromScroll && overscrollAmount > threshold * 0.5 {
            isTransitioningFromScroll = true
            initialDragState = currentState
            print("📜 Starting scroll-to-navigation transition")
        }
        
        if isTransitioningFromScroll {
            overscrollNavigationProgress = progress
            
            // Update navigation offset based on current state
            switch currentState {
            case .settings:
                // Moving from settings (-1) toward camera (0)
                navigationOffset = -maxOffset + (progress * maxOffset)
                
            case .controlPanel:
                // Moving from control panel (+1) toward camera (0)
                navigationOffset = maxOffset - (progress * maxOffset)
                
            default:
                break
            }
            
            updateViewPositions()
            updateDimmingOverlay()
        }
    }
    
    /// Cancels an in-progress over-scroll navigation and resets to the current state.
    private func cancelOverscrollNavigation() {
        guard isTransitioningFromScroll else { return }
        
        print("📜 Cancelling over-scroll navigation")
        
        isTransitioningFromScroll = false
        overscrollNavigationProgress = 0
        
        // Animate back to current state
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                switch self.currentState {
                case .settings:
                    self.navigationOffset = -self.maxOffset
                case .controlPanel:
                    self.navigationOffset = self.maxOffset
                default:
                    break
                }
                self.updateViewPositions()
                self.updateDimmingOverlay()
            }
        )
    }
    
    /// Calculates the over-scroll amount for a scroll view.
    /// - Parameter scrollView: The scroll view to check
    /// - Returns: The over-scroll amount (positive if over-scrolled in dismiss direction)
    func calculateOverscrollAmount(for scrollView: UIScrollView) -> CGFloat {
        let contentOffset = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let boundsHeight = scrollView.bounds.height
        let maxContentOffset = max(0, contentHeight - boundsHeight)
        
        switch currentState {
        case .settings:
            // Over-scroll at top (negative offset)
            if contentOffset < 0 {
                return -contentOffset
            }
            
        case .controlPanel:
            // Over-scroll at bottom (past max offset)
            if contentOffset > maxContentOffset {
                return contentOffset - maxContentOffset
            }
            
        default:
            break
        }
        
        return 0
    }
    
    private func isDescendant<T: UIView>(of type: T.Type, view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current {
            if v is T {
                return true
            }
            current = v.superview
        }
        return false
    }
}

// MARK: - ScrollViewDelegateProxyDelegate
extension CameraContainerViewController: ScrollViewDelegateProxyDelegate {
    
    func scrollViewDelegateProxy(_ proxy: ScrollViewDelegateProxy, didScroll scrollView: UIScrollView) {
        // Handle over-scroll detection for navigation
        handleScrollViewOverscroll(scrollView)
        
        // Handle continuous gesture flow - detect boundary during drag
        if proxy.isDragging {
            handleContinuousGestureFlow(scrollView)
        }
    }
    
    func scrollViewDelegateProxy(_ proxy: ScrollViewDelegateProxy, willBeginDragging scrollView: UIScrollView) {
        // Reset transition state when user starts dragging
        isTransitioningFromScroll = false
        overscrollNavigationProgress = 0
    }
    
    func scrollViewDelegateProxy(
        _ proxy: ScrollViewDelegateProxy,
        willEndDragging scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // Check if we should complete navigation based on over-scroll and velocity
        if isTransitioningFromScroll {
            let threshold = AnimationConstants.revealThreshold
            let velocityThreshold = AnimationConstants.velocityThreshold
            
            // Determine velocity in dismiss direction
            let dismissVelocity: CGFloat
            switch currentState {
            case .settings:
                // Dismiss direction is down (positive velocity)
                dismissVelocity = velocity.y
            case .controlPanel:
                // Dismiss direction is up (negative velocity)
                dismissVelocity = -velocity.y
            default:
                dismissVelocity = 0
            }
            
            // Determine if we should complete the navigation
            let shouldComplete = overscrollNavigationProgress > threshold ||
                                 dismissVelocity > velocityThreshold
            
            if shouldComplete {
                // Stop the scroll view's deceleration
                targetContentOffset.pointee = scrollView.contentOffset
                
                // Complete navigation to camera
                animateToState(.camera)
            } else {
                // Cancel navigation, let scroll view bounce back
                cancelOverscrollNavigation()
            }
        }
    }
    
    func scrollViewDelegateProxy(
        _ proxy: ScrollViewDelegateProxy,
        didEndDragging scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        // If not decelerating and we were transitioning, handle completion
        if !decelerate && isTransitioningFromScroll {
            let threshold = AnimationConstants.revealThreshold
            
            if overscrollNavigationProgress > threshold {
                animateToState(.camera)
            } else {
                // Reset to current state
                cancelOverscrollNavigation()
            }
        }
    }
    
    func scrollViewDelegateProxy(_ proxy: ScrollViewDelegateProxy, didEndDecelerating scrollView: UIScrollView) {
        // Reset transition state after deceleration completes
        isTransitioningFromScroll = false
        overscrollNavigationProgress = 0
    }
    
    // MARK: - Continuous Gesture Flow
    
    /// Handles continuous gesture flow from scrolling to navigation.
    /// Detects when scroll view reaches boundary during drag and seamlessly
    /// transitions to navigation without requiring the user to lift their finger.
    /// - Parameter scrollView: The scroll view being dragged
    /// - Requirements: 15.1, 15.2, 15.3, 15.4
    private func handleContinuousGestureFlow(_ scrollView: UIScrollView) {
        let contentOffset = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let boundsHeight = scrollView.bounds.height
        let maxContentOffset = max(0, contentHeight - boundsHeight)
        
        switch currentState {
        case .settings:
            // Settings: scrolling to top and continuing should transition to camera
            // Check if at top boundary (contentOffset <= 0)
            if contentOffset <= 0 {
                // User is at top and continuing to pull down
                // The over-scroll handling will take care of the transition
                // This method ensures we detect the boundary crossing
                if !isTransitioningFromScroll && contentOffset < -5 {
                    print("📜 Continuous flow: Settings reached top boundary")
                }
            } else if isTransitioningFromScroll {
                // User reversed direction - has content to scroll
                // Return to scrolling mode
                print("📜 Continuous flow: Returning to scroll mode (content available)")
                cancelOverscrollNavigation()
            }
            
        case .controlPanel:
            // Control panel: scrolling to bottom and continuing should transition to camera
            // Check if at bottom boundary (contentOffset >= maxContentOffset)
            if contentOffset >= maxContentOffset {
                // User is at bottom and continuing to pull up
                // The over-scroll handling will take care of the transition
                if !isTransitioningFromScroll && contentOffset > maxContentOffset + 5 {
                    print("📜 Continuous flow: Control panel reached bottom boundary")
                }
            } else if isTransitioningFromScroll {
                // User reversed direction - has content to scroll
                // Return to scrolling mode
                print("📜 Continuous flow: Returning to scroll mode (content available)")
                cancelOverscrollNavigation()
            }
            
        default:
            break
        }
    }
    
    /// Checks if the scroll view can scroll in the given direction.
    /// - Parameters:
    ///   - scrollView: The scroll view to check
    ///   - direction: The direction to check (up or down)
    /// - Returns: true if the scroll view has content in that direction
    func canScrollInDirection(_ scrollView: UIScrollView, direction: GestureDirection) -> Bool {
        let contentOffset = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let boundsHeight = scrollView.bounds.height
        let maxContentOffset = max(0, contentHeight - boundsHeight)
        
        switch direction {
        case .up:
            // Can scroll up if not at bottom
            return contentOffset < maxContentOffset
        case .down:
            // Can scroll down if not at top
            return contentOffset > 0
        default:
            return false
        }
    }
}
