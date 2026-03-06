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

// MARK: - CGFloat Interpolation Extension
extension CGFloat {
    func interpolatingBetween(start: CGFloat, end: CGFloat) -> CGFloat {
        return start + (end - start) * self
    }

    func clamp(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        return Swift.min(Swift.max(self, min), max)
    }
}

struct LiveDismissGestureState {
    var totalVerticalDistance: CGFloat
    var videoVerticalMove: CGFloat
    var startHorizontalPosition: CGFloat
    var finalHorizontalPosition: CGFloat
    var finalHorizontalScale: CGFloat
    var finalVerticalScale: CGFloat
    var initialTouchPoint: CGPoint
}

class GenericLivePlayerController: UIViewController {
    let liveVideoPlayer = GenericPlayerView()
    let liveVideoParent = UIView()
    let horizontalVideoPlayer = GenericLargePlayerView()
    let horizontalVideoParent = UIView()

    let smallHeader = LiveStreamSmallHeaderView()
    let smallVideoCoverView = UIView()

    let player: VideoPlayer?

    var liveStream: LiveStream {
        didSet {
            updateLabels()
        }
    }

    // AppState and event references for real data
    weak var appState: AppState?
    var liveActivitiesEvent: LiveActivitiesEvent

    // Fullscreen constraints (not used - kept for backward compatibility)
    private var horizontalVideoParentWidthConstraint: NSLayoutConstraint?
    private var horizontalVideoParentLeadingConstraint: NSLayoutConstraint?
    private var horizontalVideoParentTrailingConstraint: NSLayoutConstraint?

    let safeAreaSpacer = UIView()
    var safeAreaConstraint: NSLayoutConstraint?
    var videoParentSmallHeightC: NSLayoutConstraint?
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

    private lazy var chatVC = LiveChatController(
        liveStream: liveStream,
        liveActivitiesEvent: liveActivitiesEvent,
        appState: appState
    )

    var currentTransitionProgress: CGFloat = 0
    var dismissGestureState: LiveDismissGestureState?

    @Published private var smallVideoPlayer: Bool = false
    @Published private var commentsOverride: Bool = false
    @Published private var smallVideoPlayerAnimating: Bool = false

    @Published var currentVideoRotation: UIDeviceOrientation = .portrait
    var isDismissingInteractively: Bool { currentTransitionProgress != 0 }

    var onDismiss: (() -> Void)?
    
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

        modalPresentationStyle = .overFullScreen

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
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Hide status bar in landscape or portrait fullscreen, show in portrait inline
    override var prefersStatusBarHidden: Bool { currentVideoRotation != .portrait || isPortraitFullscreen }

    // Allow all orientations when in fullscreen mode
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        liveVideoPlayer.backgroundColor = .black
        safeAreaSpacer.backgroundColor = .systemBackground
        contentBackgroundView.backgroundColor = .systemBackground

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

        liveVideoParent.addSubview(smallHeader)
        smallHeader.translatesAutoresizingMaskIntoConstraints = false
        smallHeader.alpha = 0
        smallHeader.isHidden = true  // Not used anymore - info is in dashboard header

        liveVideoParent.addSubview(liveVideoPlayer)
        liveVideoPlayer.translatesAutoresizingMaskIntoConstraints = false
        videoBotC = liveVideoParent.bottomAnchor.constraint(equalTo: liveVideoPlayer.bottomAnchor)
        videoBotC?.isActive = true

        liveVideoParent.addSubview(smallVideoCoverView)
        smallVideoCoverView.translatesAutoresizingMaskIntoConstraints = false
        smallVideoCoverView.isHidden = true

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

            smallHeader.topAnchor.constraint(equalTo: liveVideoParent.topAnchor),
            smallHeader.leadingAnchor.constraint(equalTo: liveVideoParent.leadingAnchor),
            smallHeader.trailingAnchor.constraint(equalTo: liveVideoParent.trailingAnchor),

            smallVideoCoverView.topAnchor.constraint(equalTo: liveVideoParent.topAnchor),
            smallVideoCoverView.bottomAnchor.constraint(equalTo: liveVideoParent.bottomAnchor),
            smallVideoCoverView.leadingAnchor.constraint(equalTo: liveVideoParent.leadingAnchor),
            smallVideoCoverView.trailingAnchor.constraint(equalTo: liveVideoParent.trailingAnchor),

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

        videoParentSmallHeightC = liveVideoParent.heightAnchor.constraint(equalToConstant: 104)

        contentBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentBackgroundView.topAnchor.constraint(
                equalTo: liveVideoParent.bottomAnchor, constant: -5),
        ])

        updateLabels()

        // Add tap gesture to small video cover
        let tapGesture = UITapGestureRecognizer(
            target: self, action: #selector(smallVideoCoverTapped))
        smallVideoCoverView.addGestureRecognizer(tapGesture)

        // Add pan gesture for dismissal
        let panGesture = UIPanGestureRecognizer(
            target: self, action: #selector(panGestureHandler(_:)))
        view.addGestureRecognizer(panGesture)

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

        // Mini player animation logic
        let shouldStartAnimating = Publishers.CombineLatest3(
            $smallVideoPlayer, $commentsOverride, $smallVideoPlayerAnimating
        )
        .filter { !$2 }
        .map { $0.0 || $0.1 }
        .removeDuplicates()
        .debounce(for: 0.1, scheduler: DispatchQueue.main)
        .removeDuplicates()
        .dropFirst()

        shouldStartAnimating
            .sink { [weak self] mini in
                self?.animateToMiniPlayer(mini)
            }
            .store(in: &cancellables)

        Publishers.Merge(
            shouldStartAnimating.map { _ in true },
            shouldStartAnimating.delay(for: 0.3, scheduler: DispatchQueue.main).map { _ in false }
        )
        .sink { [weak self] animating in
            self?.smallVideoPlayerAnimating = animating
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

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        player?.play()
        
        // NOTE: Anchor point and transform are set in viewDidLayoutSubviews
        // where the frame is guaranteed to be correct
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Restore previous orientation lock
        if let previous = previousOrientationLock {
            AppDelegate.orientationLock = previous
        }
        
        // Restore audio session for recording/streaming
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
            if !smallVideoPlayer {
                liveVideoPlayer.setAnchorPoint(CGPoint(x: 0, y: 0.5))
                liveVideoPlayer.transform = .init(translationX: -view.frame.width / 2, y: 0)
            }
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

        // CRITICAL: Set self as RootViewController's liveVideoController
        RootViewController.instance.liveVideoController = self

        if !smallVideoPlayer {
            // Make chat controller first responder to show the input bar
            // This is required because TelegramChatInputBar is used as inputAccessoryView
            chatVC.becomeFirstResponder()
        }

        // Fallback in case viewDidLayoutSubviews didn't complete setup
        if !hasPerformedInitialSetup {
            hasPerformedInitialSetup = true
            safeAreaConstraint?.constant = view.safeAreaInsets.top
            
            if !smallVideoPlayer {
                liveVideoPlayer.setAnchorPoint(CGPoint(x: 0, y: 0.5))
                liveVideoPlayer.transform = .init(translationX: -view.frame.width / 2, y: 0)
            }
        }
    }

    @objc private func smallVideoCoverTapped() {
        guard !commentsOverride else { return }
        chatVC.commentsTable.setContentOffset(chatVC.commentsTable.contentOffset, animated: false)
        smallVideoPlayer = false
        liveVideoPlayer.showControls()
    }

    func chatControllerRequestMiniPlayer(_ mini: Bool) {
        smallVideoPlayer = mini
    }

    func chatControllerRequestsMoreSpace() {
        commentsOverride = true
    }

    func chatControllerRequestsNormalSize() {
        commentsOverride = false
    }

    private func animateToMiniPlayer(_ mini: Bool) {
        guard let view = view else { return }

        videoParentSmallHeightC?.isActive = mini
        videoBotC?.isActive = !mini
        smallVideoCoverView.isHidden = !mini

        guard mini else {
            UIView.animate(withDuration: 0.3) {
                self.liveVideoPlayer.transform = CGAffineTransform(
                    translationX: -view.frame.width / 2, y: 0)
                // Don't force dashboard expand - let user control it in viewer mode
                // Streamer mode handles its own always-expanded state
                view.layoutIfNeeded()
            } completion: { finished in
                guard finished else { return }
                self.liveVideoParent.backgroundColor = .clear
                self.safeAreaSpacer.backgroundColor = .systemBackground
                self.chatVC.becomeFirstResponder()
            }
            return
        }

        let yOffset = liveVideoPlayer.frame.height - 104
        chatVC.topInfoView.transform = CGAffineTransform(translationX: 0, y: yOffset)

        let scale = 88 / liveVideoPlayer.frame.height

        safeAreaSpacer.backgroundColor = .systemBackground
        liveVideoParent.backgroundColor = .systemBackground
        liveVideoPlayer.hideControls()
        chatVC.resignFirstResponder()

        view.layoutIfNeeded()

        UIView.animate(withDuration: 0.3) {
            // Center the mini video horizontally
            // The video's anchor point is at (0, 0.5) - left center
            // Base position after scale puts left edge at screen left edge
            // We need to offset right by: (screenWidth - scaledWidth) / 2
            // In pre-scale coordinates (for translatedBy): offset / scale
            let scaledWidth = self.liveVideoPlayer.frame.width * scale
            let centerOffset = (view.frame.width - scaledWidth) / 2
            
            self.liveVideoPlayer.transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(
                    x: (-self.liveVideoPlayer.frame.width / 2 + centerOffset) / scale,
                    y: (104 - self.liveVideoPlayer.frame.height) / 2 / scale)
            // Collapse dashboard when video minimizes (but don't force expand when video expands)
            self.chatVC.setDashboardExpanded(false, animated: false)
            self.chatVC.topInfoView.transform = .identity
        }
    }

    @objc func panGestureHandler(_ gesture: UIPanGestureRecognizer) {
        guard let window = view.window else {
            print("⚠️ No window found")
            return
        }
        let touchPoint = gesture.location(in: window)

        // Swipe down in landscape → exit to portrait (same as tapping the shrink button)
        if currentVideoRotation.isLandscape || exitingLandscapeFullscreenGesture {
            if case .began = gesture.state {
                let velocity = gesture.velocity(in: view)
                // Only trigger on downward swipes (positive Y velocity in the rotated coordinate)
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

        guard currentVideoRotation.isPortrait, !smallVideoPlayer, !smallVideoPlayerAnimating else {
            print(
                "⚠️ Gesture blocked - portrait:\(currentVideoRotation.isPortrait) small:\(smallVideoPlayer) animating:\(smallVideoPlayerAnimating)"
            )
            return
        }

        // Exit portrait fullscreen on swipe down instead of minimizing.
        // We must consume the ENTIRE gesture (all states) to prevent the
        // dismiss-to-mini-player code from running on .changed/.ended events
        // after togglePortraitFullscreen flips the flag on .began.
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

        // Swipe UP on video → enter fullscreen (portrait or landscape depending on video type)
        if enteringFullscreenGesture {
            // Consume remaining events from the swipe-up gesture
            if gesture.state == .ended || gesture.state == .cancelled {
                enteringFullscreenGesture = false
            }
            return
        }

        if case .began = gesture.state {
            let velocity = gesture.velocity(in: view)
            // Detect upward swipe: negative Y, primarily vertical, not already fullscreen
            if velocity.y < -100 && abs(velocity.y) > abs(velocity.x) && !isPortraitFullscreen {
                enteringFullscreenGesture = true
                if isPortraitVideo {
                    togglePortraitFullscreen()
                } else {
                    rotateVideoPlayer(for: .landscapeRight)
                }
                return
            }
        }

        if case .began = gesture.state {
            print("🎬 Gesture BEGAN at touchPoint: \(touchPoint)")

            // Get the real mini player position from RootViewController
            let rootVC = RootViewController.instance
            let miniPlayer = rootVC.livePlayer
            miniPlayer.alpha = 0.01  // Make mini player visible for calculation

            let small = miniPlayer.convert(miniPlayer.bounds, to: nil)
            let large = liveVideoPlayer.convert(liveVideoPlayer.bounds, to: nil)

            print("📐 Small rect (real mini player): \(small)")
            print("📐 Large rect (full player): \(large)")
            print("📐 Window bounds: \(window.bounds)")

            // Add safeAreaInsets.top to compensate for the video starting below the safe area
            // Without this, the video ends up ~59 points higher than the mini player
            let safeAreaTop = view.safeAreaInsets.top
            let videoVerticalMove = (small.midY - large.midY) - 500 + safeAreaTop
            print("📏 videoVerticalMove: \(videoVerticalMove) (includes safeAreaTop: \(safeAreaTop))")
            print("📏 startHorizontalPosition: \(-large.width / 2)")
            print("📏 finalHorizontalPosition: \(small.minX)")

            dismissGestureState = LiveDismissGestureState(
                totalVerticalDistance: 500,
                videoVerticalMove: videoVerticalMove,
                startHorizontalPosition: -large.width / 2,
                finalHorizontalPosition: small.minX,
                finalHorizontalScale: small.width / large.width,
                finalVerticalScale: small.height / large.height,
                initialTouchPoint: touchPoint
            )

            liveVideoPlayer.hideControls()
            chatVC.input.textField.textView.resignFirstResponder()
            chatVC.resignFirstResponder()
            return
        }

        guard let dgs = dismissGestureState else { return }

        let delta = touchPoint.y - dgs.initialTouchPoint.y
        var percent = delta / dgs.totalVerticalDistance
        percent = percent.clamp(0, 1)

        if gesture.state == .changed {
            print("👆 Delta: \(delta), Percent: \(percent)")
        }

        switch gesture.state {
        case .changed, .began:
            setTransition(progress: percent)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view)
            print("🏁 Gesture ENDED - delta:\(delta) velocity:\(velocity.y)")
            if delta > 200 || velocity.y > 400 {
                print("✅ Dismissing to mini player (threshold reached)")
                UIView.animate(withDuration: 0.4) {
                    self.setTransition(progress: 1)
                } completion: { _ in
                    RootViewController.instance.livePlayer.alpha = 1

                    self.dismiss(animated: false) { [weak self] in
                        self?.resetDismissTransition()
                    }
                }
            } else {
                print("↩️ Resetting (threshold not reached)")
                UIView.animate(withDuration: 0.3) {
                    self.resetDismissTransition()
                } completion: { _ in
                    self.chatVC.becomeFirstResponder()
                }
            }
        default:
            break
        }
    }

    func setTransition(progress: CGFloat) {
        guard let dgs = dismissGestureState else { return }

        currentTransitionProgress = progress

        let viewTranslateY = progress * dgs.totalVerticalDistance
        let safeAreaTranslateY =
            -progress * dgs.totalVerticalDistance
            - progress.interpolatingBetween(start: 0, end: 200)
        let videoTranslateY = progress.interpolatingBetween(start: 0, end: dgs.videoVerticalMove)

        if progress == 0 || progress == 1 || Int(progress * 100) % 10 == 0 {
            #if DEBUG
            print("🎨 setTransition(\(String(format: "%.2f", progress)))")
            print("   view.transform.ty = \(viewTranslateY)")
            print("   safeAreaSpacer.transform.ty = \(safeAreaTranslateY)")
            print("   liveVideoPlayer.transform.ty = \(videoTranslateY)")
            print("   videoVerticalMove = \(dgs.videoVerticalMove)")
            #endif
        }

        // Transform the main view
        view.transform = .init(translationX: 0, y: viewTranslateY)

        // Adjust safeAreaSpacer
        safeAreaSpacer.transform = .init(translationX: 0, y: safeAreaTranslateY)

        // Transform content background
        contentBackgroundView.transform = .init(
            translationX: 0,
            y: progress.interpolatingBetween(start: 0, end: dgs.videoVerticalMove - 140))
        contentBackgroundView.alpha = progress.interpolatingBetween(start: 1.0, end: 0.0)
        chatVC.view.alpha = progress.interpolatingBetween(start: 1.0, end: 0.0)

        // Transform content view
        contentView.transform = .init(
            translationX: 0, y: progress.interpolatingBetween(start: 0, end: 1000))

        // Transform stream ended label
        liveVideoPlayer.streamEndedLabel.transform = .init(
            scaleX: progress.interpolatingBetween(
                start: 1, end: 12 / (16 * dgs.finalHorizontalScale)),
            y: progress.interpolatingBetween(start: 1, end: 12 / (16 * dgs.finalVerticalScale))
        )

        // Transform video player - THIS IS THE KEY!
        liveVideoPlayer.transform = CGAffineTransform(
            translationX: progress.interpolatingBetween(
                start: dgs.startHorizontalPosition,
                end: dgs.startHorizontalPosition + dgs.finalHorizontalPosition),
            y: videoTranslateY
        )
        .scaledBy(
            x: progress.interpolatingBetween(start: 1, end: dgs.finalHorizontalScale),
            y: progress.interpolatingBetween(start: 1, end: dgs.finalVerticalScale)
        )
    }

    func resetDismissTransition() {
        print("↩️ Resetting all transforms")
        view.transform = .identity
        liveVideoPlayer.transform = .init(translationX: -view.bounds.width / 2, y: 0)
        liveVideoPlayer.streamEndedLabel.transform = .identity
        safeAreaSpacer.transform = .identity
        contentView.transform = .identity
        contentBackgroundView.transform = .identity
        contentBackgroundView.alpha = 1
        chatVC.view.alpha = 1
        currentTransitionProgress = 0
    }

    private func rotateVideoPlayer(for orientation: UIDeviceOrientation) {
        // Don't rotate if dismissing, no player, or in mini player mode
        guard currentTransitionProgress < 0.01, 
              let player,
              !smallVideoPlayer,
              !smallVideoPlayerAnimating else { return }

        // Portrait videos should never rotate to landscape
        if isPortraitVideo && orientation.isLandscape {
            return
        }

        currentVideoRotation = orientation
        setNeedsStatusBarAppearanceUpdate()

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
            }
            
        case .unknown, .portraitUpsideDown, .faceUp, .faceDown:
            return
        @unknown default:
            return
        }
    }

    @MainActor
    func setVideoAspectRatio(_ aspect: CGFloat) {
        let isFirstDetection = videoAspect == 16.0 / 9.0
        videoAspect = aspect
        isPortraitVideo = aspect < 1.0

        // Guard: ensure view is loaded before modifying constraints
        guard isViewLoaded else { return }

        // Deactivate previous custom constraint
        videoAspectHeightConstraint?.isActive = false

        if isPortraitVideo {
            // --- YouTube-style portrait inline layout ---
            // Keep the SAME container height as landscape (16:9 ratio).
            // The video displays inside with .resizeAspect, which pillarboxes it
            // (black bars on left/right). This preserves chat space below.
            // The default 16:9 heightC and square-cap maxH stay active — no changes needed.

            if isFirstDetection {
                // First detection: set gravity instantly (no animation) to avoid
                // the visible zoom-in → zoom-out flash when the player first opens
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                liveVideoPlayer.playerLayer.videoGravity = .resizeAspect
                CATransaction.commit()
            } else {
                // Subsequent changes: animate smoothly
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.35)
                liveVideoPlayer.playerLayer.videoGravity = .resizeAspect
                CATransaction.commit()
            }

            liveVideoPlayer.backgroundColor = .black
            view.layoutIfNeeded()
        } else {
            // --- Standard landscape layout (existing behavior) ---
            let heightC = liveVideoPlayer.widthAnchor.constraint(
                equalTo: liveVideoPlayer.heightAnchor, multiplier: aspect)
            heightC.priority = .required
            heightC.isActive = true
            videoAspectHeightConstraint = heightC
            view.layoutIfNeeded()
        }
    }

    func updateLabels() {
        smallHeader.countLabel.text = "\(liveStream.viewerCount)"
        smallHeader.liveIcon.backgroundColor = liveStream.isLive ? .systemRed : .systemGray
        smallHeader.titleLabel.text = liveStream.title
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
                self.liveVideoPlayer.showControls()
            }

            liveVideoPlayer.fullscreenButton.setImage(
                UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
            setNeedsStatusBarAppearanceUpdate()

        } else {
            // --- EXITING FULLSCREEN ---
            liveVideoPlayer.hideControls()

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
                self.liveVideoPlayer.showControls()
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
            
            dismiss(animated: true) {
                self.onDismiss?()
            }
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
            let activityVC = UIActivityViewController(
                activityItems: [liveStream.title], applicationActivities: nil)
            present(activityVC, animated: true)
        case .mute:
            player?.avPlayer.isMuted.toggle()
        }
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
