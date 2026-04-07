//
//  GenericLivePlayerController.swift
//  swae
//
//  Main controller for live video player
//

import AVFoundation
import AVKit
import Combine
import NostrSDK

class GenericLivePlayerController: UIViewController {
    let liveVideoPlayer = GenericPlayerView()
    let liveVideoParent = UIView()
    let horizontalVideoPlayer = GenericLargePlayerView()
    let horizontalVideoParent = UIView()
    
    let player: VideoPlayer?
    
    var liveStream: LiveStream
    
    // AppState and event references for real data
    weak var appState: AppState?
    var liveActivitiesEvent: LiveActivitiesEvent
    
    // Fullscreen constraints (not used - kept for backward compatibility)
    private var horizontalVideoParentWidthConstraint: NSLayoutConstraint?
    private var horizontalVideoParentLeadingConstraint: NSLayoutConstraint?
    private var horizontalVideoParentTrailingConstraint: NSLayoutConstraint?
    
    let safeAreaSpacer = UIView()
    var safeAreaConstraint: NSLayoutConstraint?
    var videoBotC: NSLayoutConstraint?
    
    let contentBackgroundView = UIView()
    let contentView = AutoHidingView()
    
    // Zap notifications container
    let zapNotificationsContainer = UIView()
    let maxVisibleZaps = 3
    
    var cancellables: Set<AnyCancellable> = []
    
    var videoAspect: CGFloat = 16 / 9
    
    // MARK: - Portrait Video Support
    /// Whether the current video is portrait (height > width)
    private(set) var isPortraitVideo: Bool = false
    /// Whether we're in portrait fullscreen mode (video fills screen in portrait orientation)
    private var isPortraitFullscreen = false
    /// Reference to the current video height constraint so we can deactivate it when aspect ratio changes
    private var videoAspectHeightConstraint: NSLayoutConstraint?
    /// Reference to the default 16:9 height constraint created in viewDidLoad
    private var defaultHeightConstraint: NSLayoutConstraint?
    /// Reference to the max-height constraint (square cap for landscape, 75% screen for portrait)
    private var maxHeightConstraint: NSLayoutConstraint?
    /// Tracks whether the current pan gesture started while in portrait fullscreen
    private var exitingPortraitFullscreenGesture = false
    /// Tracks whether the current pan gesture started while in landscape fullscreen
    private var exitingLandscapeFullscreenGesture = false
    /// Tracks whether the current pan gesture is a swipe-up-to-enter-fullscreen
    private var enteringFullscreenGesture = false
    
    /// Dismiss pan gesture for interactive swipe-down-to-close
    private var dismissPanGesture: UIPanGestureRecognizer?
    
    lazy var chatVC = LiveChatController(
        liveStream: liveStream,
        liveActivitiesEvent: liveActivitiesEvent,
        appState: appState
    )
    
    @Published var currentVideoRotation: UIDeviceOrientation = .portrait
    
    /// Saves the orientation lock before the player modifies it, so we can restore it on dismiss
    private var previousOrientationLock: UIInterfaceOrientationMask?
    
    /// Tracks whether the initial setup (safe area + transform) has been done
    private var hasPerformedInitialSetup = false
    
    init(liveStream: LiveStream, liveActivitiesEvent: LiveActivitiesEvent, appState: AppState?) {
        self.liveStream = liveStream
        self.liveActivitiesEvent = liveActivitiesEvent
        self.appState = appState
        
        // Create VideoPlayer
        if let urlString = liveStream.videoURL?.absoluteString {
            player = VideoPlayer(url: urlString, liveStream: liveStream)
        } else {
            player = nil
        }
        
        player?.play()
        liveVideoPlayer.player = player
        
        super.init(nibName: nil, bundle: nil)
        
        DispatchQueue.main.async {
            self.player?.avPlayer.isMuted = false
        }
        
        // Check if playerConfig already has a cached orientation (from didSelectEvent cache hit)
        if let appState, appState.playerConfig.videoAspectRatio != .unknown {
            let cached = appState.playerConfig.videoAspectRatio
            videoAspect = cached.ratio
            isPortraitVideo = (cached == .portrait9_16)
            // Pre-set video gravity for portrait so the player opens correctly
            if isPortraitVideo {
                liveVideoPlayer.playerLayer.videoGravity = .resizeAspect
            }
        }
        
        // Get video aspect ratio — must account for preferredTransform (portrait videos
        // are often encoded as landscape with a 90° rotation transform)
        if let asset = player?.avPlayer.currentItem?.asset as? AVURLAsset {
            Task { [weak self] in
                do {
                    if let track = try await asset.loadTracks(withMediaType: .video).first {
                        let size = try await track.load(.naturalSize)
                        let transform = try await track.load(.preferredTransform)
                        let transformedSize = size.applying(transform)
                        let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                        await MainActor.run {
                            self?.setVideoAspectRatio(displaySize.width / displaySize.height)
                            // Cache the result for future opens of this stream
                            if let self {
                                let aspect = displaySize.width / displaySize.height
                                let detectedRatio: VideoAspectRatio
                                if aspect < 0.8 { detectedRatio = .portrait9_16 }
                                else if aspect > 1.2 { detectedRatio = .landscape16_9 }
                                else { detectedRatio = .square1_1 }
                                self.appState?.detectedOrientations[self.liveActivitiesEvent.id] = detectedRatio
                                // Notify RootViewController for potential swap to ReelsPlayerController
                                self.appState?.playerConfig.videoAspectRatio = detectedRatio
                            }
                        }
                    }
                } catch {
                    print("Error loading video aspect ratio: \(error)")
                }
            }
        }
        
        // Fallback: observe AVPlayerItem for video dimensions via presentationSize
        // This handles HLS streams where AVURLAsset tracks may not be immediately available
        player?.avPlayer.currentItem?.publisher(for: \.presentationSize)
            .filter { $0.width > 0 && $0.height > 0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard let self else { return }
                let aspect = size.width / size.height
                // Only update if we haven't already detected a non-default aspect ratio
                if self.videoAspect == 16.0 / 9.0 || self.videoAspect == 0 {
                    self.setVideoAspectRatio(aspect)
                }
                // Cache the result for future opens of this stream
                let detectedRatio: VideoAspectRatio
                if aspect < 0.8 { detectedRatio = .portrait9_16 }
                else if aspect > 1.2 { detectedRatio = .landscape16_9 }
                else { detectedRatio = .square1_1 }
                self.appState?.detectedOrientations[self.liveActivitiesEvent.id] = detectedRatio
                // Notify RootViewController for potential swap to ReelsPlayerController
                self.appState?.playerConfig.videoAspectRatio = detectedRatio
            }
            .store(in: &cancellables)
        
        // Observe playerConfig for late-arriving HLS manifest detection results
        // (fires when didSelectEvent's background HLS fetch completes after player is already open)
        appState?.$playerConfig
            .map(\.videoAspectRatio)
            .removeDuplicates()
            .filter { $0 != .unknown }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ratio in
                guard let self else { return }
                let aspect = ratio.ratio
                // Only apply if we haven't already detected from AVPlayer
                if self.videoAspect == 16.0 / 9.0 || self.videoAspect == 0 {
                    self.setVideoAspectRatio(aspect)
                }
            }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    // Hide status bar in landscape or portrait fullscreen
    override var prefersStatusBarHidden: Bool { currentVideoRotation != .portrait || isPortraitFullscreen }
    
    // Allow all orientations when in fullscreen mode
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        
        liveVideoPlayer.backgroundColor = .black
        safeAreaSpacer.backgroundColor = .black
        contentBackgroundView.backgroundColor = .black
        
        // Setup chat controller
        contentBackgroundView.addSubview(chatVC.view)
        chatVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chatVC.view.topAnchor.constraint(equalTo: contentBackgroundView.topAnchor, constant: 5),
            chatVC.view.bottomAnchor.constraint(equalTo: contentBackgroundView.bottomAnchor),
            chatVC.view.leadingAnchor.constraint(equalTo: contentBackgroundView.leadingAnchor),
            chatVC.view.trailingAnchor.constraint(equalTo: contentBackgroundView.trailingAnchor),
        ])
        
        chatVC.willMove(toParent: self)
        addChild(chatVC)
        view.addSubview(contentBackgroundView)
        chatVC.didMove(toParent: self)
        
        // Setup video stack
        let videoStack = UIStackView(arrangedSubviews: [safeAreaSpacer, liveVideoParent])
        videoStack.axis = .vertical
        videoStack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(videoStack)
        videoStack.translatesAutoresizingMaskIntoConstraints = false
        
        let heightC = liveVideoPlayer.heightAnchor.constraint(
            equalTo: liveVideoPlayer.widthAnchor, multiplier: 9 / 16)
        heightC.priority = .defaultHigh
        defaultHeightConstraint = heightC
        
        view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Position contentView relative to contentBackgroundView
        NSLayoutConstraint.activate([
            contentView.bottomAnchor.constraint(equalTo: contentBackgroundView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentBackgroundView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentBackgroundView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: contentBackgroundView.topAnchor, constant: 5),
        ])
        
        view.addSubview(horizontalVideoParent)
        horizontalVideoParent.translatesAutoresizingMaskIntoConstraints = false
        
        horizontalVideoParent.addSubview(horizontalVideoPlayer)
        horizontalVideoPlayer.translatesAutoresizingMaskIntoConstraints = false
        horizontalVideoParent.isHidden = true
        
        // Setup zap notifications container
        view.addSubview(zapNotificationsContainer)
        zapNotificationsContainer.translatesAutoresizingMaskIntoConstraints = false
        zapNotificationsContainer.isUserInteractionEnabled = false
        
        liveVideoParent.addSubview(liveVideoPlayer)
        liveVideoPlayer.translatesAutoresizingMaskIntoConstraints = false
        videoBotC = liveVideoParent.bottomAnchor.constraint(equalTo: liveVideoPlayer.bottomAnchor)
        videoBotC?.isActive = true
        
        let maxH = liveVideoPlayer.heightAnchor.constraint(lessThanOrEqualTo: liveVideoPlayer.widthAnchor)
        maxHeightConstraint = maxH
        
        NSLayoutConstraint.activate([
            videoStack.topAnchor.constraint(equalTo: view.topAnchor),
            videoStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            heightC,
            
            liveVideoPlayer.topAnchor.constraint(equalTo: liveVideoParent.topAnchor),
            liveVideoPlayer.leadingAnchor.constraint(equalTo: liveVideoParent.leadingAnchor),
            liveVideoPlayer.trailingAnchor.constraint(equalTo: liveVideoParent.trailingAnchor),
            maxH,
            
            contentView.topAnchor.constraint(equalTo: contentBackgroundView.topAnchor, constant: 5),
            contentView.bottomAnchor.constraint(equalTo: contentBackgroundView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentBackgroundView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentBackgroundView.trailingAnchor),
            
            // horizontalVideoParent fills the entire screen in landscape
            horizontalVideoParent.topAnchor.constraint(equalTo: view.topAnchor),
            horizontalVideoParent.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            horizontalVideoParent.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            horizontalVideoParent.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // horizontalVideoPlayer fills parent and maintains aspect ratio
            horizontalVideoPlayer.leadingAnchor.constraint(
                equalTo: horizontalVideoParent.leadingAnchor),
            horizontalVideoPlayer.trailingAnchor.constraint(
                equalTo: horizontalVideoParent.trailingAnchor),
            horizontalVideoPlayer.topAnchor.constraint(
                equalTo: horizontalVideoParent.topAnchor),
            horizontalVideoPlayer.bottomAnchor.constraint(
                equalTo: horizontalVideoParent.bottomAnchor),
        ])
        
        safeAreaConstraint = safeAreaSpacer.heightAnchor.constraint(
            equalToConstant: view.safeAreaInsets.top)
        safeAreaConstraint?.isActive = true
        
        contentBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentBackgroundView.topAnchor.constraint(
                equalTo: liveVideoParent.bottomAnchor, constant: -5),
        ])
        
        // Add interactive dismiss gesture (swipe down to shrink back to thumbnail)
        let dismissGesture = UIPanGestureRecognizer(
            target: self, action: #selector(handleDismissPan(_:)))
        dismissGesture.delegate = self
        view.addGestureRecognizer(dismissGesture)
        dismissPanGesture = dismissGesture
        
        liveVideoPlayer.delegate = self
        horizontalVideoPlayer.delegate = self
        
        // Observe device orientation changes with debouncing to prevent rapid rotation issues
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .compactMap { _ in UIDevice.current.orientation }
            .filter { $0 == .portrait || $0.isLandscape }
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] orientation in
                self?.rotateVideoPlayer(for: orientation)
            }
            .store(in: &cancellables)
        
        // Subscribe to event updates for live→recording transition detection
        subscribeToEventUpdates()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Save current orientation lock before we modify it
        previousOrientationLock = AppDelegate.orientationLock
        
        // Ensure we start in portrait
        AppDelegate.orientationLock = .portrait
        
        // Only configure audio session and start playback on first presentation.
        // When re-expanding from mini player, the AVPlayer is already playing
        // with the correct audio session — changing it would cause a brief pause.
        if player?.avPlayer.timeControlStatus != .playing {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
        
        // Activate lock screen / Control Center now-playing controls.
        // Safe to call on re-expand — NowPlayingService handles idempotency.
        if let player {
            NowPlayingService.shared.activate(player: player, liveStream: liveStream)
        }
        
        // NOTE: Anchor point and transform are set in viewDidLayoutSubviews
        // where the frame is guaranteed to be correct
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Restore previous orientation lock
        if let previous = previousOrientationLock {
            AppDelegate.orientationLock = previous
        }
        
        // Restore the streaming audio session
        NotificationCenter.default.post(
            name: NSNotification.Name("RestoreStreamingAudioSession"),
            object: nil
        )
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Perform initial setup on first layout pass when frame and safe area are correct
        // This happens BEFORE the view is visible, preventing any glitches
        if !hasPerformedInitialSetup && view.frame.width > 0 && view.safeAreaInsets.top > 0 {
            hasPerformedInitialSetup = true
            
            // Set safe area constraint
            safeAreaConstraint?.constant = view.safeAreaInsets.top
            
            // Set anchor point and transform with correct frame values
            liveVideoPlayer.setAnchorPoint(CGPoint(x: 0, y: 0.5))
            liveVideoPlayer.transform = .init(translationX: -view.frame.width / 2, y: 0)
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        
        // Update safe area constraint when insets change (e.g., rotation)
        // Only update after initial setup to avoid conflicts
        if hasPerformedInitialSetup {
            safeAreaConstraint?.constant = view.safeAreaInsets.top
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Make chat controller first responder to show the input bar
        chatVC.becomeFirstResponder()
        
        // Fallback in case viewDidLayoutSubviews didn't complete setup
        if !hasPerformedInitialSetup {
            hasPerformedInitialSetup = true
            safeAreaConstraint?.constant = view.safeAreaInsets.top
            
            liveVideoPlayer.setAnchorPoint(CGPoint(x: 0, y: 0.5))
            liveVideoPlayer.transform = .init(translationX: -view.frame.width / 2, y: 0)
        }
    }
    
    // MARK: - Interactive Dismiss Gesture
    
    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        
        // --- Landscape: swipe down exits to portrait ---
        if currentVideoRotation.isLandscape || exitingLandscapeFullscreenGesture {
            if case .began = gesture.state {
                if abs(velocity.y) > abs(velocity.x) && velocity.y > 100 {
                    exitingLandscapeFullscreenGesture = true
                    rotateVideoPlayer(for: .portrait)
                }
            }
            if gesture.state == .ended || gesture.state == .cancelled {
                exitingLandscapeFullscreenGesture = false
            }
            return
        }
        
        // --- Portrait fullscreen: swipe down exits fullscreen ---
        if isPortraitFullscreen || exitingPortraitFullscreenGesture {
            if case .began = gesture.state {
                exitingPortraitFullscreenGesture = true
                togglePortraitFullscreen()
            }
            if gesture.state == .ended || gesture.state == .cancelled {
                exitingPortraitFullscreenGesture = false
            }
            return
        }
        
        // --- Swipe up: enter fullscreen ---
        if enteringFullscreenGesture {
            if gesture.state == .ended || gesture.state == .cancelled {
                enteringFullscreenGesture = false
            }
            return
        }
        
        if case .began = gesture.state {
            if velocity.y < -100 && abs(velocity.y) > abs(velocity.x) && !isPortraitFullscreen {
                // Swipe up enters fullscreen
                enteringFullscreenGesture = true
                if isPortraitVideo {
                    togglePortraitFullscreen()
                } else {
                    rotateVideoPlayer(for: .landscapeRight)
                }
                return
            }
        }
        
        // --- Normal dismiss: drag to shrink back to thumbnail ---
        switch gesture.state {
        case .began:
            liveVideoPlayer.hideControls()
            
        case .changed:
            RootViewController.instance.updateDismissProgress(translation: translation)
            
        case .ended, .cancelled:
            let distance = sqrt(translation.x * translation.x + translation.y * translation.y)
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
            let shouldDismiss = distance > 120 || speed > 800
            
            if shouldDismiss {
                player?.pause()
            }
            RootViewController.instance.finishOrCancelDismiss(
                shouldDismiss: shouldDismiss,
                velocity: velocity
            )
            
        default:
            break
        }
    }
    
    private func rotateVideoPlayer(for orientation: UIDeviceOrientation) {
        // Don't rotate if no player
        guard let player else { return }
        
        // Portrait videos should never rotate to landscape
        if isPortraitVideo && orientation.isLandscape {
            return
        }
        
        currentVideoRotation = orientation
        setNeedsStatusBarAppearanceUpdate()
        
        // Save controls visibility before transition so we can restore it after
        let controlsWereVisible = !liveVideoPlayer.controlsView.isHidden
        liveVideoPlayer.hideControls()
        horizontalVideoPlayer.hideControls()
        
        switch orientation {
        case .portrait:
            // Request portrait orientation from the system
            AppDelegate.orientationLock = .portrait
            
            self.chatVC.becomeFirstResponder()
            
            // Crossfade: fade out landscape player while fading in portrait player
            self.liveVideoPlayer.playerView.alpha = 0
            UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut) {
                self.horizontalVideoParent.alpha = 0
                self.liveVideoPlayer.playerView.alpha = 1
            } completion: { _ in
                self.horizontalVideoPlayer.player = nil
                self.horizontalVideoParent.isHidden = true
                self.horizontalVideoParent.alpha = 1
                // Restore controls state after transition
                if controlsWereVisible {
                    self.liveVideoPlayer.showControls()
                }
            }
            
        case .landscapeLeft, .landscapeRight:
            // IMPORTANT: UIDeviceOrientation and UIInterfaceOrientationMask are INVERTED for landscape
            // When device is in landscapeLeft (home button right), interface should be landscapeRight
            // When device is in landscapeRight (home button left), interface should be landscapeLeft
            AppDelegate.orientationLock = orientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
            
            chatVC.resignFirstResponder()
            
            // Prepare landscape player (hidden, ready to fade in)
            horizontalVideoParent.alpha = 0
            horizontalVideoParent.isHidden = false
            horizontalVideoParent.transform = .identity
            horizontalVideoPlayer.player = player
            
            // Crossfade: fade out portrait player while fading in landscape player
            UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut) {
                self.horizontalVideoParent.alpha = 1
                self.liveVideoPlayer.playerView.alpha = 0
            } completion: { _ in
                // Restore controls state on the landscape player after transition
                if controlsWereVisible {
                    self.horizontalVideoPlayer.showControls()
                }
            }
            
        case .unknown, .portraitUpsideDown, .faceUp, .faceDown:
            return
        @unknown default:
            return
        }
    }
    
    @MainActor
    func setVideoAspectRatio(_ aspect: CGFloat) {
        let isFirstDetection = videoAspectHeightConstraint == nil && liveVideoPlayer.playerLayer.videoGravity == .resizeAspectFill
        videoAspect = aspect
        isPortraitVideo = aspect < 1.0
        
        // Guard: ensure view is loaded before modifying constraints
        guard isViewLoaded else { return }
        
        // Deactivate previous custom constraint
        videoAspectHeightConstraint?.isActive = false
        
        if isPortraitVideo {
            // Portrait detected — RootViewController will swap to ReelsPlayerController.
            // Hide the landscape UI so the user sees a black screen with the video
            // instead of the feed showing through the transparent areas.
            contentBackgroundView.isHidden = true
            contentView.isHidden = true
            safeAreaSpacer.isHidden = true
            chatVC.resignFirstResponder()
        } else {
            // Landscape confirmed — restore proper background colors
            safeAreaSpacer.backgroundColor = .systemBackground
            contentBackgroundView.backgroundColor = .systemBackground
            
            // --- Standard landscape layout (existing behavior) ---
            let heightC = liveVideoPlayer.widthAnchor.constraint(
                equalTo: liveVideoPlayer.heightAnchor, multiplier: aspect)
            heightC.priority = .required
            heightC.isActive = true
            videoAspectHeightConstraint = heightC
            view.layoutIfNeeded()
        }
    }
    
    // MARK: - Portrait Fullscreen

    private func togglePortraitFullscreen() {
        isPortraitFullscreen.toggle()

        if isPortraitFullscreen {
            // --- ENTERING FULLSCREEN ---
            UIView.performWithoutAnimation {
                chatVC.resignFirstResponder()
            }

            // Deactivate current height constraints BEFORE animation
            videoAspectHeightConstraint?.isActive = false
            defaultHeightConstraint?.isActive = false
            maxHeightConstraint?.isActive = false

            // Collapse safe area spacer so video starts at screen top
            safeAreaConstraint?.constant = 0

            // Add padding to progress bar for portrait fullscreen
            liveVideoPlayer.updateProgressBarMargin(20)

            // Set new height to fill screen
            let fullHeight = view.bounds.height
            let heightC = liveVideoPlayer.heightAnchor.constraint(equalToConstant: fullHeight)
            heightC.priority = .required
            heightC.isActive = true
            videoAspectHeightConstraint = heightC

            // Single animation block
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction]
            ) {
                self.safeAreaSpacer.alpha = 0
                self.contentBackgroundView.alpha = 0
                // Ensure no underlying views peek through
                self.view.backgroundColor = .black
                self.view.layoutIfNeeded()
            } completion: { _ in
                self.safeAreaSpacer.isHidden = true
                // Don't toggle controls — preserve whatever state they were in
            }

            liveVideoPlayer.fullscreenButton.setImage(
                UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
            setNeedsStatusBarAppearanceUpdate()

        } else {
            // --- EXITING FULLSCREEN ---
            // Don't toggle controls — preserve whatever state they were in

            // Prepare safe area spacer for animation
            safeAreaSpacer.isHidden = false
            safeAreaSpacer.alpha = 0

            // Restore safe area height
            safeAreaConstraint?.constant = view.safeAreaInsets.top

            // Reset progress bar margin to inline default
            liveVideoPlayer.updateProgressBarMargin(0)

            // Deactivate fullscreen constraint
            videoAspectHeightConstraint?.isActive = false

            // Restore the default 16:9 + square-cap constraints for inline mode
            defaultHeightConstraint?.isActive = true
            maxHeightConstraint?.isActive = true

            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction]
            ) {
                self.safeAreaSpacer.alpha = 1
                self.contentBackgroundView.alpha = 1
                self.view.backgroundColor = nil
                self.view.layoutIfNeeded()
            } completion: { _ in
                self.chatVC.becomeFirstResponder()
                // Don't toggle controls — preserve whatever state they were in
            }

            liveVideoPlayer.fullscreenButton.setImage(
                UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    // MARK: - Live → Recording Transition

    /// Subscribes to event updates to detect when a live stream ends and a recording becomes available
    private func subscribeToEventUpdates() {
        guard let appState,
              let coordinates = liveActivitiesEvent.coordinateTag else {
            return
        }

        appState.$liveActivitiesEvents
            .compactMap { $0[coordinates]?.first }
            .removeDuplicates { $0.id == $1.id && $0.status == $1.status && $0.recording == $1.recording }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedEvent in
                guard let self else { return }
                let previousStatus = self.liveActivitiesEvent.status
                let previousRecording = self.liveActivitiesEvent.recording

                // Update stored event
                self.liveActivitiesEvent = updatedEvent

                // Rebuild liveStream model with updated data
                let updatedLiveStream = updatedEvent.toLiveStream()
                self.liveStream = updatedLiveStream

                // Detect live → ended transition
                if previousStatus == .live && updatedEvent.status == .ended {
                    if let recordingURL = updatedEvent.recording {
                        // Recording available — switch player to it
                        self.player?.liveStream = updatedLiveStream
                        self.player?.switchToURL(recordingURL)
                        self.liveVideoPlayer.updateRecordingModeUI()
                        self.horizontalVideoPlayer.updateRecordingModeUI()
                        self.showTransitionToast("Stream ended — playing recording")
                    } else {
                        // No recording — show ended message
                        self.showTransitionToast("Stream has ended")
                    }
                }
                // Detect recording URL appearing on an already-ended event
                else if updatedEvent.status == .ended && previousRecording == nil,
                        let recordingURL = updatedEvent.recording {
                    self.player?.liveStream = updatedLiveStream
                    self.player?.switchToURL(recordingURL)
                    self.liveVideoPlayer.updateRecordingModeUI()
                    self.horizontalVideoPlayer.updateRecordingModeUI()
                    self.showTransitionToast("Recording available")
                }
            }
            .store(in: &cancellables)
    }

    /// Shows a brief toast banner at the top of the video player
    private func showTransitionToast(_ message: String) {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        container.layer.cornerRadius = 8
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        liveVideoParent.addSubview(container)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            container.centerXAnchor.constraint(equalTo: liveVideoParent.centerXAnchor),
            container.topAnchor.constraint(equalTo: liveVideoParent.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])

        container.alpha = 0
        UIView.animate(withDuration: 0.3) {
            container.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UIView.animate(withDuration: 0.3, animations: {
                container.alpha = 0
            }) { _ in
                container.removeFromSuperview()
            }
        }
    }

}

// MARK: - UIGestureRecognizerDelegate

extension GenericLivePlayerController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        // --- Dismiss pan gesture ---
        guard pan === dismissPanGesture else { return true }

        let velocity = pan.velocity(in: view)
        let location = pan.location(in: view)

        // Must have some downward component
        guard velocity.y > 0 else { return false }

        // Block in chat area for landscape layout (video top, chat bottom)
        if !isPortraitVideo && currentVideoRotation == .portrait {
            let videoBottom = liveVideoParent.frame.maxY
            if location.y > videoBottom { return false }
        }

        // Block in progress bar area when controls visible
        let controlsVisible = !liveVideoPlayer.controlsView.isHidden
        if controlsVisible {
            let touchInPlayer = pan.location(in: liveVideoPlayer)
            let hitArea = liveVideoPlayer.progressHitArea
            if !hitArea.isHidden, hitArea.alpha > 0 {
                let hitAreaFrame = hitArea.convert(hitArea.bounds, to: liveVideoPlayer)
                let exclusionZone = hitAreaFrame.insetBy(dx: 0, dy: -20)
                if exclusionZone.contains(touchInPlayer) { return false }
            }
        }

        return true
    }
}

extension GenericLivePlayerController: GenericPlayerViewDelegate {
    func playerViewPerformAction(_ action: GenericPlayerViewAction) {
        switch action {
        case .dismiss:
            // If in portrait fullscreen, exit that first
            if isPortraitFullscreen {
                togglePortraitFullscreen()
                return
            }

            // Reset to portrait before dismissing if in landscape
            if currentVideoRotation != .portrait {
                currentVideoRotation = .portrait
                AppDelegate.orientationLock = .portrait
            }

            // Dismiss via RootViewController container
            player?.pause()
            RootViewController.instance.dismissPlayer()
        case .fullscreen:
            if isPortraitVideo {
                // Portrait videos: expand/collapse in portrait orientation
                togglePortraitFullscreen()
            } else {
                // Landscape videos: rotate to/from landscape (existing behavior)
                if currentVideoRotation == .portrait {
                    rotateVideoPlayer(for: .landscapeRight)
                } else {
                    rotateVideoPlayer(for: .portrait)
                }
            }
        case .share:
            // Build the swae.live watch URL: /watch/<pubkey>:<dTag>
            let streamId = "\(liveActivitiesEvent.pubkey):\(liveActivitiesEvent.identifier ?? "")"
            let watchURL = URL(string: "https://swae.live/watch/\(streamId)")!
            let activityVC = UIActivityViewController(
                activityItems: [watchURL], applicationActivities: nil)
            present(activityVC, animated: true)
        case .mute:
            player?.avPlayer.isMuted.toggle()
        }
    }
}

// MARK: - PlayerController Conformance

extension GenericLivePlayerController: PlayerController {
    var videoPlayer: VideoPlayer? { player }
    var chatController: LiveChatController { chatVC }
    var dismissSnapshotSourceView: UIView { view }
    var expandAnimationTargetFrame: CGRect { view.bounds }

    func restoreControlsAfterCancelledDismiss() {
        liveVideoPlayer.showControls()
    }
}
