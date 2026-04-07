//
//  ReelsPlayerController.swift
//  swae
//
//  Dedicated portrait reels player. One gesture, one state machine,
//  frame-based layout driven by a progress value (0 = full screen, 1 = comments open).
//

import AVFoundation
import Combine
import NostrSDK
import UIKit

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

class ReelsPlayerController: UIViewController {

    // MARK: - PlayerController Protocol Properties

    let videoPlayer: VideoPlayer?
    var liveStream: LiveStream
    var liveActivitiesEvent: LiveActivitiesEvent
    let chatController: LiveChatController
    weak var appState: AppState?
    var dismissSnapshotSourceView: UIView { playerView }

    var expandAnimationTargetFrame: CGRect {
        // Compute the player frame using screen bounds.
        // This is called before the view is laid out, so we use UIScreen.
        let screen = UIScreen.main.bounds
        let w = screen.width
        let h = screen.height
        // Estimate input bar height (60 base + safe area bottom ~34)
        let safeBottom: CGFloat = view.window?.safeAreaInsets.bottom ?? 34
        let inputH = max(60 + safeBottom, 50)
        let availableH = h - inputH

        let ratio: CGFloat = detectedAspectRatio != .unknown
            ? detectedAspectRatio.ratio : 9.0 / 16.0
        let isLandscape = ratio >= 1.0

        if isLandscape {
            // Landscape: target the compact/locked position (video at top).
            // This matches progress=1 layout so there's no jump after expand.
            let safeTop: CGFloat = view.window?.safeAreaInsets.top ?? 59
            let compactH = min(h * 0.35, w / ratio)
            return CGRect(x: 0, y: safeTop, width: w, height: compactH)
        } else {
            return CGRect(x: 0, y: 0, width: w, height: availableH)
        }
    }

    // MARK: - Views (non-optional, built in viewDidLoad)

    private let playerView = PlayerView()
    private let commentsContainer = UIView()
    private let controlsOverlay = PassthroughView()
    private let inputBar = TelegramChatInputBar()
    private var chatView: UIView!

    /// Thumbnail placeholder shown until video starts playing — eliminates black flash
    private let thumbnailImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .black
        return iv
    }()

    /// Loading timer for showing the seek ring after a delay on initial load
    /// (No longer used — loading state is driven by syncPlayPauseButton via $playbackState)
    private var thumbnailLoadingTimer: Timer?

    // MARK: - Controls

    private let dismissButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let liveDot = UIView()
    private let liveLabel = UILabel()
    private let viewerCountLabel = UILabel()
    private var controlsAutoHideTimer: Timer?
    /// Whether controls are currently visible (independent of progress)
    private var controlsVisible = true

    // MARK: - Play/Pause Button (centered on video)

    /// Tappable play/pause/loading button — shadow for visibility, no background.
    /// Driven by VideoPlayer.$playbackState so the icon is always correct.
    private let playPauseButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.adjustsImageWhenHighlighted = false
        // Shadow for readability over any video content
        btn.layer.shadowColor = UIColor.black.cgColor
        btn.layer.shadowOpacity = 0.55
        btn.layer.shadowRadius = 10
        btn.layer.shadowOffset = .zero
        // Start with pause icon (video is playing when opened)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        btn.setImage(UIImage(systemName: "pause.fill", withConfiguration: config)?.withRenderingMode(.alwaysTemplate), for: .normal)
        return btn
    }()

    /// Spinner layer added directly to the playPauseButton — replaces the separate seekLoadingRing.
    private let spinnerLayer: CAShapeLayer = {
        let l = CAShapeLayer()
        l.fillColor = UIColor.clear.cgColor
        l.strokeColor = UIColor.white.cgColor
        l.lineWidth = 3
        l.lineCap = .round
        l.strokeStart = 0
        l.strokeEnd = 0.25
        l.isHidden = true
        return l
    }()

    /// Whether the video is currently paused by user tap (not by system/buffering).
    private var isPausedByUser = false

    /// Tracks the last icon name set on the button to avoid redundant updates.
    private var currentPlayPauseIcon: String = "pause.fill"

    /// Delays showing the spinner so transient loading states (e.g. play → brief buffer → playing)
    /// don't flash the spinner.
    private var spinnerDelayTimer: Timer?

    // (Seek loading is now integrated into playPauseButton via spinnerLayer)

    // MARK: - Progress Bar (recordings only)

    private let progressBar = ReelsProgressBar()

    // MARK: - Emoji Picker

    private var currentEmojiModal: MorphingEmojiModal?

    // MARK: - Gesture State

    private enum GestureMode { case idle, draggingComments, draggingDismiss }
    private var gestureMode: GestureMode = .idle
    private var panGesture: UIPanGestureRecognizer!
    private var currentProgress: CGFloat = 0.0
    private var dragStartProgress: CGFloat = 0.0
    private var dragStartTranslation: CGPoint = .zero
    private let maxDragDistance: CGFloat = 300
    private var isCommentsOpen = false

    // MARK: - Layout State

    private var keyboardHeight: CGFloat = 0
    private var statusBarHidden = true
    private var isUpdatingLayout = false
    private var isInteractiveDismiss = false
    private var progressBarBottomConstraint: NSLayoutConstraint?
    private var progressBarLeadingConstraint: NSLayoutConstraint?
    private var progressBarTrailingConstraint: NSLayoutConstraint?
    private var fullscreenButtonBottomConstraint: NSLayoutConstraint?

    // MARK: - Aspect Ratio Detection

    /// Detected video aspect ratio — updated by Combine subscriptions.
    /// Used by updateLayout() instead of synchronous AVAsset.tracks reading.
    private var detectedAspectRatio: VideoAspectRatio = .unknown

    // MARK: - Layout Mode

    /// Determines gesture and layout behavior based on video orientation.
    /// Portrait: full progress range (0→1), chat toggleable, swipe-down-to-close.
    /// Landscape: chat locked open (progress=1), swipe-down-to-dismiss directly.
    private enum LayoutMode { case portrait, landscape }
    private var layoutMode: LayoutMode = .portrait

    // MARK: - Auto-Open Chat (Landscape)

    /// Whether the expand-from-thumbnail animation has completed.
    /// Set by expandAnimationDidComplete() called from RootViewController.
    private var expandAnimationComplete = false

    /// Whether chat has been auto-opened for a landscape video.
    /// Set once; never reset — respects user intent if they close chat manually.
    private var hasAutoOpenedChat = false

    // MARK: - Fullscreen (Landscape Videos)

    /// Whether the player is in landscape fullscreen mode
    private var isFullscreen = false
    /// The progress value before entering fullscreen, restored on exit
    private var progressBeforeFullscreen: CGFloat = 0
    /// Fullscreen button (only visible for landscape videos)
    private let fullscreenButton = UIButton(type: .system)

    // MARK: - Orientation

    private var previousOrientationLock: UIInterfaceOrientationMask?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Standard init — creates VideoPlayer and LiveChatController from scratch.
    init(liveStream: LiveStream, liveActivitiesEvent: LiveActivitiesEvent, appState: AppState?) {
        self.liveStream = liveStream
        self.liveActivitiesEvent = liveActivitiesEvent
        self.appState = appState

        if let urlString = liveStream.videoURL?.absoluteString {
            self.videoPlayer = VideoPlayer(url: urlString, liveStream: liveStream)
        } else {
            self.videoPlayer = nil
        }

        // Set up audio session BEFORE first play() to avoid the pause-resume glitch
        // caused by changing the audio category while AVPlayer is already buffering.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        videoPlayer?.play()

        self.chatController = LiveChatController(
            liveStream: liveStream,
            liveActivitiesEvent: liveActivitiesEvent,
            appState: appState
        )

        // Check cached orientation before super.init
        if let appState, appState.playerConfig.videoAspectRatio != .unknown {
            self.detectedAspectRatio = appState.playerConfig.videoAspectRatio
            let isLandscape = self.detectedAspectRatio == .landscape16_9
                           || self.detectedAspectRatio == .square1_1
            self.layoutMode = isLandscape ? .landscape : .portrait
        }

        super.init(nibName: nil, bundle: nil)
        DispatchQueue.main.async { [weak self] in self?.videoPlayer?.avPlayer.isMuted = false }
        setupAspectRatioDetection()
    }

    /// Swap init — reuses existing VideoPlayer and LiveChatController.
    init(liveStream: LiveStream, liveActivitiesEvent: LiveActivitiesEvent,
         appState: AppState?, existingPlayer: VideoPlayer,
         existingChatController: LiveChatController) {
        self.liveStream = liveStream
        self.liveActivitiesEvent = liveActivitiesEvent
        self.appState = appState
        self.videoPlayer = existingPlayer
        self.chatController = existingChatController
        if let appState, appState.playerConfig.videoAspectRatio != .unknown {
            self.detectedAspectRatio = appState.playerConfig.videoAspectRatio
            let isLandscape = self.detectedAspectRatio == .landscape16_9
                           || self.detectedAspectRatio == .square1_1
            self.layoutMode = isLandscape ? .landscape : .portrait
        }
        super.init(nibName: nil, bundle: nil)
        setupAspectRatioDetection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Sets the thumbnail image shown as a placeholder until video starts playing.
    /// Call before the view is presented.
    func setThumbnailImage(_ image: UIImage?) {
        thumbnailImageView.image = image
        // Portrait thumbnails fill edge-to-edge; landscape thumbnails keep their ratio
        if let image {
            let isPortrait = image.size.height > image.size.width
            thumbnailImageView.contentMode = isPortrait ? .scaleAspectFill : .scaleAspectFit
        }
    }

    deinit {
        if let observer = timeObserver {
            videoPlayer?.avPlayer.removeTimeObserver(observer)
        }
        controlsAutoHideTimer?.invalidate()
        spinnerDelayTimer?.invalidate()
        thumbnailLoadingTimer?.invalidate()
    }

    // MARK: - Aspect Ratio Detection

    private func setupAspectRatioDetection() {
        // Listen to HLS detection results via playerConfig
        appState?.$playerConfig
            .map(\.videoAspectRatio)
            .removeDuplicates()
            .filter { $0 != .unknown }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ratio in
                guard let self else { return }
                self.detectedAspectRatio = ratio
                self.updateLayoutMode()
                if self.isViewLoaded && !self.isFullscreen {
                    self.updateLayout(progress: self.currentProgress)
                }
                // Show/hide fullscreen button based on aspect ratio
                self.fullscreenButton.isHidden = (ratio == .portrait9_16)
                self.autoOpenChatForLandscapeIfNeeded()
            }
            .store(in: &cancellables)

        // Fallback: observe AVPlayerItem.presentationSize for non-HLS streams
        videoPlayer?.avPlayer.currentItem?.publisher(for: \.presentationSize)
            .filter { $0.width > 0 && $0.height > 0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                guard let self else { return }
                let aspect = size.width / size.height
                let ratio: VideoAspectRatio
                if aspect < 0.8 { ratio = .portrait9_16 }
                else if aspect > 1.2 { ratio = .landscape16_9 }
                else { ratio = .square1_1 }
                self.detectedAspectRatio = ratio
                self.updateLayoutMode()
                self.appState?.detectedOrientations[self.liveActivitiesEvent.id] = ratio
                self.appState?.playerConfig.videoAspectRatio = ratio
                if self.isViewLoaded && !self.isFullscreen {
                    self.updateLayout(progress: self.currentProgress)
                }
                self.fullscreenButton.isHidden = (ratio == .portrait9_16)
                self.autoOpenChatForLandscapeIfNeeded()
            }
            .store(in: &cancellables)

        // Auto-rotate for landscape videos
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .compactMap { _ in UIDevice.current.orientation }
            .filter { $0 == .portrait || $0.isLandscape }
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] orientation in
                guard let self else { return }
                let isLandscapeVideo = self.detectedAspectRatio == .landscape16_9
                    || self.detectedAspectRatio == .square1_1
                guard isLandscapeVideo else { return }
                if orientation.isLandscape && !self.isFullscreen {
                    self.enterFullscreen(for: orientation)
                } else if orientation == .portrait && self.isFullscreen {
                    self.exitFullscreen()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Status Bar

    override var prefersStatusBarHidden: Bool { statusBarHidden }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    // MARK: - Input Accessory View (iMessage-style docked input bar)

    override var canBecomeFirstResponder: Bool { !isFullscreen }
    override var inputAccessoryView: UIView? { isFullscreen ? nil : inputBar }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isOpaque = true

        // 1. Player view (frame-based)
        playerView.clipsToBounds = true
        playerView.backgroundColor = .black
        view.addSubview(playerView)
        playerView.player = videoPlayer?.avPlayer
        playerView.playerLayer.videoGravity = .resizeAspectFill

        // 1b. Thumbnail placeholder (ON TOP of player — covers the black AVPlayerLayer until video renders)
        thumbnailImageView.isUserInteractionEnabled = false
        view.addSubview(thumbnailImageView)

        // Fade out thumbnail and cancel any pending loading spinner when video starts playing
        videoPlayer?.$playbackState
            .filter { $0 == .playing }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Cancel any pending spinner from showSeekLoading
                self.showSeekLoading(false)
                UIView.animate(withDuration: 0.3) {
                    self.thumbnailImageView.alpha = 0
                } completion: { _ in
                    self.thumbnailImageView.isHidden = true
                }
            }
            .store(in: &cancellables)

        // Drive play/pause/loading button from actual playback state — always correct, no delay
        videoPlayer?.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.syncPlayPauseButton(to: state)
            }
            .store(in: &cancellables)

        // 2. Comments container (frame-based)
        commentsContainer.backgroundColor = .clear
        commentsContainer.clipsToBounds = true
        view.addSubview(commentsContainer)

        // 3. Chat controller as child VC (inside comments container)
        addChild(chatController)
        chatController.isEmbeddedInReels = true
        chatController.view.translatesAutoresizingMaskIntoConstraints = true
        chatController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        chatController.input.isHidden = true
        commentsContainer.addSubview(chatController.view)
        chatController.didMove(toParent: self)
        chatView = chatController.view

        // 4. Configure input bar (managed by UIKit as inputAccessoryView — NOT added to view hierarchy)
        inputBar.onSendMessage = { [weak self] text in
            self?.chatController.sendMessageFromReels(text)
        }
        inputBar.isZapMode = true
        inputBar.zapTargetPubkey = liveActivitiesEvent.hostPubkeyHex
        inputBar.zapEventCoordinate = liveActivitiesEvent.coordinateTag
        inputBar.onSendZap = { [weak self] amount, message in
            self?.chatController.sendZapFromReels(amount: amount, message: message)
        }
        inputBar.onEmojiTapped = { [weak self] in
            self?.presentEmojiPicker()
        }

        // Auto-expand comments when user taps the text field
        inputBar.textField.onBeginEditing = { [weak self] in
            guard let self, self.currentProgress < 1.0 else { return }
            // Fade progress bar out immediately so it doesn't linger during the animation
            if !self.progressBar.isHidden {
                UIView.animate(withDuration: 0.15) { self.progressBar.alpha = 0 }
            }
            // Just set progress — keyboardWillShow will call updateLayout with proper animation
            self.currentProgress = 1.0
            self.isCommentsOpen = true
        }

        // 5. Controls overlay (frame-based, tracks playerView)
        controlsOverlay.backgroundColor = .clear
        view.addSubview(controlsOverlay)
        setupControlsOverlay()

        // 7. Single pan gesture
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)

        // 8. Progress bar (must be after pan gesture for require(toFail:))
        setupProgressBar()

        // 9. Keyboard observer
        setupKeyboardObserver()

        // 10. Tap to dismiss keyboard (cancelsTouchesInView=false so it coexists with controls tap)
        let tapToDismiss = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapToDismiss.cancelsTouchesInView = false
        tapToDismiss.require(toFail: panGesture)
        view.addGestureRecognizer(tapToDismiss)

        // 11. Force layout, then set initial frames
        view.layoutIfNeeded()
        updateLayout(progress: 0)

        // 11b. Landscape cache hit: lock chat open immediately so the controller
        // view is already at progress=1 when it crossfades in during the expand animation.
        if layoutMode == .landscape {
            currentProgress = 1.0
            isCommentsOpen = true
            hasAutoOpenedChat = true
            updateLayout(progress: 1.0)
        }

        // 12. Live → recording transition
        subscribeToEventUpdates()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !isFirstResponder {
            becomeFirstResponder()
        }
        makeInputAccessoryBackgroundTransparent()
        // Start auto-hide timer so controls fade out after initial display
        startAutoHideTimer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousOrientationLock = AppDelegate.orientationLock
        AppDelegate.orientationLock = .portrait

        // Audio session and play() are handled in init — no need to repeat here.
        // Calling play() again + changing audio category mid-buffer causes a
        // visible pause-then-resume glitch.

        if let player = videoPlayer {
            NowPlayingService.shared.activate(player: player, liveStream: liveStream)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let previous = previousOrientationLock {
            AppDelegate.orientationLock = previous
        }
        NotificationCenter.default.post(
            name: NSNotification.Name("RestoreStreamingAudioSession"), object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isUpdatingLayout, !isInteractiveDismiss else { return }
        if isFullscreen {
            // In fullscreen, playerView fills top-to-bottom but respects left/right safe area
            // (notch/Dynamic Island). Controls overlay matches the player frame.
            let bounds = view.bounds
            let insets = view.safeAreaInsets
            let playerFrame = CGRect(x: insets.left, y: 0,
                                     width: bounds.width - insets.left - insets.right,
                                     height: bounds.height)
            playerView.frame = playerFrame
            playerView.layer.cornerRadius = 0
            controlsOverlay.frame = playerFrame
            // Move comments off-screen so they can't peek through during rotation
            commentsContainer.frame = CGRect(x: 0, y: bounds.height,
                                             width: bounds.width, height: 0)
            commentsContainer.alpha = 0
            // Reposition progress bar for fullscreen — match player horizontal bounds + 16pt inset
            // Sit above the bottom safe area so it doesn't conflict with the home indicator
            if !progressBar.isHidden {
                let bottomSafe = view.safeAreaInsets.bottom
                progressBarLeadingConstraint?.constant = insets.left + 16
                progressBarTrailingConstraint?.constant = -(insets.right + 16)
                // Progress bar bottom = screen bottom minus safe area minus 10pt extra breathing room
                progressBarBottomConstraint?.constant = bounds.height - bottomSafe - 10
                progressBar.alpha = 1
                // For recordings, move fullscreen button above the progress bar.
                // The constraint is relative to safeAreaLayoutGuide.bottomAnchor (already above home indicator).
                // Progress bar is 44pt tall + 10pt extra offset, 0pt gap to button.
                fullscreenButtonBottomConstraint?.constant = -(44 + 10 + 0)
            } else {
                // Live: fullscreen button at normal position (12pt above safe area bottom)
                fullscreenButtonBottomConstraint?.constant = -12
            }
        } else {
            // Reset progress bar to edge-to-edge for portrait layout
            progressBarLeadingConstraint?.constant = 0
            progressBarTrailingConstraint?.constant = 0
            // Reset fullscreen button to normal position
            fullscreenButtonBottomConstraint?.constant = -12
            updateLayout(progress: currentProgress)
        }
    }

    // MARK: - Layout

    /// Sets every visual property as a function of progress (0 = full screen, 1 = comments open).
    /// Frame-based for player/comments/overlay. Constraint-based for input container height.
    private func updateLayout(progress: CGFloat) {
        isUpdatingLayout = true
        defer { isUpdatingLayout = false }

        let w = view.bounds.width
        let h = view.bounds.height
        let safeTop = view.safeAreaInsets.top

        // Input bar height (inputBar is managed by UIKit as inputAccessoryView)
        let safeBottom = view.safeAreaInsets.bottom
        let fullInputH = max(inputBar.intrinsicContentSize.height + safeBottom, 50)

        // Determine aspect ratio from detection (no synchronous AVAsset.tracks reading)
        let numericAspectRatio: CGFloat = detectedAspectRatio != .unknown
            ? detectedAspectRatio.ratio
            : 9.0 / 16.0  // Default portrait until detected
        let isLandscapeVideo = numericAspectRatio >= 1.0

        // --- Full-screen state (progress=0) ---
        let availableH = h - fullInputH
        let fs_x: CGFloat
        let fs_y: CGFloat
        let fs_w: CGFloat
        let fs_h: CGFloat

        if isLandscapeVideo {
            // Landscape: size playerView to match video aspect ratio, centered vertically.
            // This keeps controls overlay positioned relative to the visible video content.
            let videoNaturalH = w / numericAspectRatio
            let videoH = min(videoNaturalH, availableH)
            fs_x = 0
            fs_y = (availableH - videoH) / 2
            fs_w = w
            fs_h = videoH
        } else {
            // Portrait: fill available space, resizeAspectFill crops
            fs_x = 0
            fs_y = 0
            fs_w = w
            fs_h = availableH
        }

        // --- Compact state (progress=1) ---
        let minVideoH = h * 0.35
        let compactW: CGFloat
        let compactH: CGFloat
        if isLandscapeVideo {
            // Landscape: full width, height from aspect ratio
            compactW = w
            compactH = min(minVideoH, w / numericAspectRatio)
        } else {
            // Portrait: height is minVideoH, width from aspect ratio
            compactH = minVideoH
            compactW = min(w, minVideoH * numericAspectRatio)
        }

        let cp_x: CGFloat = (w - compactW) / 2
        let cp_y: CGFloat = safeTop
        let cp_w: CGFloat = compactW
        let cp_h: CGFloat = compactH

        // Linear interpolation: each edge moves at constant speed from full-screen to compact
        let videoX = fs_x + (cp_x - fs_x) * progress
        let videoY = fs_y + (cp_y - fs_y) * progress
        let videoW = fs_w + (cp_w - fs_w) * progress
        let videoH = fs_h + (cp_h - fs_h) * progress

        playerView.frame = CGRect(x: videoX, y: videoY, width: videoW, height: videoH)
        playerView.layer.cornerRadius = isLandscapeVideo ? 0 : 12 * progress
        playerView.playerLayer.videoGravity = .resizeAspectFill

        // Thumbnail tracks player frame
        thumbnailImageView.frame = playerView.frame
        thumbnailImageView.layer.cornerRadius = playerView.layer.cornerRadius

        // Controls overlay tracks player frame (visibility managed by tap toggle, not progress)
        controlsOverlay.frame = playerView.frame

        // Progress bar fades out in the first 10% of expansion
        if !progressBar.isHidden {
            progressBar.alpha = max(0, 1 - progress * 10)
            // Position at the bottom of the player frame
            progressBarBottomConstraint?.constant = videoY + videoH
        }

        // Comments sheet — slides up from bottom.
        // Uses actual compact height so landscape videos get more comments space.
        let commentsOpenY = safeTop + compactH
        let commentsOffScreenY = h
        let commentsY = commentsOffScreenY - (commentsOffScreenY - commentsOpenY) * progress
        let commentsH = h - commentsOpenY
        commentsContainer.frame = CGRect(x: 0, y: commentsY, width: w, height: commentsH)
        commentsContainer.alpha = 1.0

        // Chat view fills entire comments area
        chatView.frame = CGRect(x: 0, y: 0, width: w, height: commentsH)

        // Status bar
        let shouldHide = progress < 0.5
        if shouldHide != statusBarHidden {
            statusBarHidden = shouldHide
            UIView.animate(withDuration: 0.2) {
                self.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    // MARK: - Gesture Handling

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        // In fullscreen, swipe down exits fullscreen
        if isFullscreen {
            if gesture.state == .ended || gesture.state == .cancelled {
                let velocity = gesture.velocity(in: view)
                if velocity.y > 300 {
                    exitFullscreen()
                }
            }
            return
        }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            guard abs(velocity.y) > abs(velocity.x) else {
                gestureMode = .idle
                return
            }

            switch layoutMode {
            case .landscape:
                // Landscape: chat is locked. Any downward swipe = dismiss.
                // Upward swipe = no-op (chat already open).
                if velocity.y > 0 {
                    gestureMode = .draggingDismiss
                    prepareForDismiss()
                } else {
                    gestureMode = .idle
                }

            case .portrait:
                // Portrait: existing behavior
                if velocity.y < 0 {
                    gestureMode = .draggingComments
                } else if currentProgress > 0.01 {
                    gestureMode = .draggingComments
                    inputBar.textField.textView.resignFirstResponder()
                } else {
                    gestureMode = .draggingDismiss
                    prepareForDismiss()
                }
            }
            dragStartProgress = currentProgress
            dragStartTranslation = translation

        case .changed:
            switch gestureMode {
            case .draggingComments:
                let dragDelta = -(translation.y - dragStartTranslation.y) / maxDragDistance
                let newProgress = (dragStartProgress + dragDelta).clamped(to: 0...1)

                // Seamless handoff: progress hit 0, user still dragging down
                if newProgress <= 0 && velocity.y > 0 && dragStartProgress > 0.01 {
                    gestureMode = .draggingDismiss
                    dragStartTranslation = translation
                    currentProgress = 0
                    updateLayout(progress: 0)
                    isCommentsOpen = false
                    prepareForDismiss()
                    return
                }

                currentProgress = newProgress
                updateLayout(progress: newProgress)

            case .draggingDismiss:
                let dt = CGPoint(
                    x: translation.x - dragStartTranslation.x,
                    y: translation.y - dragStartTranslation.y
                )
                RootViewController.instance.updateDismissProgress(translation: dt)

            case .idle:
                break
            }

        case .ended, .cancelled:
            switch gestureMode {
            case .draggingComments:
                snapToNearestState(velocity: velocity)
            case .draggingDismiss:
                let dt = CGPoint(
                    x: translation.x - dragStartTranslation.x,
                    y: translation.y - dragStartTranslation.y
                )
                let distance = sqrt(dt.x * dt.x + dt.y * dt.y)
                let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                let shouldDismiss = distance > 120 || speed > 800
                if shouldDismiss { videoPlayer?.pause() }
                RootViewController.instance.finishOrCancelDismiss(
                    shouldDismiss: shouldDismiss, velocity: velocity)
            case .idle:
                break
            }
            gestureMode = .idle

        default: break
        }
    }

    private func prepareForDismiss() {
        hideControls()
        isPausedByUser = false
        isInteractiveDismiss = true
    }

    private func snapToNearestState(velocity: CGPoint) {
        let projectedProgress = currentProgress + (-velocity.y / maxDragDistance * 0.15)
        let targetProgress: CGFloat = projectedProgress > 0.5 ? 1.0 : 0.0
        animateToProgress(targetProgress, velocity: velocity)
    }

    private func closeChat() {
        animateToProgress(0, velocity: .zero)
    }

    private func animateToProgress(_ targetProgress: CGFloat, velocity: CGPoint) {
        let distance = max(abs(targetProgress - currentProgress), 0.01)
        let initialVelocity = min(abs(velocity.y) / (distance * maxDragDistance), 3.0)

        UIView.animate(
            withDuration: 0.3, delay: 0,
            usingSpringWithDamping: 1.0,
            initialSpringVelocity: initialVelocity,
            options: []
        ) {
            self.currentProgress = targetProgress
            self.updateLayout(progress: targetProgress)
        } completion: { _ in
            self.isCommentsOpen = targetProgress == 1.0
        }
    }

    // MARK: - Controls Overlay

    private func setupControlsOverlay() {
        // --- Top-left: Dismiss ---
        dismissButton.setImage(UIImage(systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal)
        dismissButton.tintColor = .white
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        controlsOverlay.addSubview(dismissButton)

        // --- Top-right: More (•••), Zap (⚡), Mute (🔇) ---
        moreButton.setImage(UIImage(systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal)
        moreButton.tintColor = .white
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = buildMoreMenu()
        controlsOverlay.addSubview(moreButton)

        // Update menu when quality variants become available
        videoPlayer?.$availableQualities
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.moreButton.menu = self?.buildMoreMenu()
            }
            .store(in: &cancellables)

        muteButton.setImage(UIImage(systemName: "speaker.wave.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal)
        muteButton.tintColor = .white
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        controlsOverlay.addSubview(muteButton)

        // --- Bottom-left: Live badge + viewer count ---
        liveDot.backgroundColor = .systemRed
        liveDot.layer.cornerRadius = 4
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlay.addSubview(liveDot)

        liveLabel.text = "LIVE"
        liveLabel.textColor = .white
        liveLabel.font = .systemFont(ofSize: 12, weight: .bold)
        liveLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlay.addSubview(liveLabel)

        viewerCountLabel.text = liveStream.isLive ? "\(liveStream.viewerCount) watching" : ""
        viewerCountLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        viewerCountLabel.font = .systemFont(ofSize: 11, weight: .medium)
        viewerCountLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsOverlay.addSubview(viewerCountLabel)

        // Hide live badge for recordings
        if !liveStream.isLive {
            liveDot.isHidden = true
            liveLabel.isHidden = true
            viewerCountLabel.isHidden = true
        }

        // Tap to toggle controls — on the main view so it works regardless of
        // controlsOverlay alpha (alpha=0 views don't receive touches in UIKit)
        let tap = UITapGestureRecognizer(target: self, action: #selector(videoAreaTapped(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            // Dismiss (top-left)
            dismissButton.topAnchor.constraint(equalTo: controlsOverlay.safeAreaLayoutGuide.topAnchor, constant: 8),
            dismissButton.leadingAnchor.constraint(equalTo: controlsOverlay.leadingAnchor, constant: 12),
            dismissButton.widthAnchor.constraint(equalToConstant: 36),
            dismissButton.heightAnchor.constraint(equalToConstant: 36),

            // More (top-right, rightmost)
            moreButton.topAnchor.constraint(equalTo: controlsOverlay.safeAreaLayoutGuide.topAnchor, constant: 8),
            moreButton.trailingAnchor.constraint(equalTo: controlsOverlay.trailingAnchor, constant: -12),
            moreButton.widthAnchor.constraint(equalToConstant: 36),
            moreButton.heightAnchor.constraint(equalToConstant: 36),

            // Mute (left of more)
            muteButton.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),
            muteButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            muteButton.widthAnchor.constraint(equalToConstant: 36),
            muteButton.heightAnchor.constraint(equalToConstant: 36),

            // Live badge (bottom-left)
            liveDot.bottomAnchor.constraint(equalTo: controlsOverlay.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            liveDot.leadingAnchor.constraint(equalTo: controlsOverlay.leadingAnchor, constant: 16),
            liveDot.widthAnchor.constraint(equalToConstant: 8),
            liveDot.heightAnchor.constraint(equalToConstant: 8),

            liveLabel.centerYAnchor.constraint(equalTo: liveDot.centerYAnchor),
            liveLabel.leadingAnchor.constraint(equalTo: liveDot.trailingAnchor, constant: 6),

            viewerCountLabel.centerYAnchor.constraint(equalTo: liveDot.centerYAnchor),
            viewerCountLabel.leadingAnchor.constraint(equalTo: liveLabel.trailingAnchor, constant: 8),
        ])

        // --- Bottom-right: Fullscreen button (landscape videos only) ---
        fullscreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal)
        fullscreenButton.tintColor = .white
        fullscreenButton.translatesAutoresizingMaskIntoConstraints = false
        fullscreenButton.addTarget(self, action: #selector(fullscreenTapped), for: .touchUpInside)
        fullscreenButton.isHidden = (detectedAspectRatio == .portrait9_16 || detectedAspectRatio == .unknown)
        controlsOverlay.addSubview(fullscreenButton)

        fullscreenButtonBottomConstraint = fullscreenButton.bottomAnchor.constraint(
            equalTo: controlsOverlay.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate([
            fullscreenButtonBottomConstraint!,
            fullscreenButton.trailingAnchor.constraint(equalTo: controlsOverlay.trailingAnchor, constant: -16),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 36),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        // --- Center: Play/Pause button ---
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        controlsOverlay.addSubview(playPauseButton)
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: controlsOverlay.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: controlsOverlay.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 48),
            playPauseButton.heightAnchor.constraint(equalToConstant: 48),
        ])

        // Spinner ring on the button itself (hidden until loading state)
        let ringSize: CGFloat = 44
        let ringPath = UIBezierPath(
            arcCenter: CGPoint(x: 24, y: 24),
            radius: (ringSize - 3) / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        spinnerLayer.path = ringPath.cgPath
        spinnerLayer.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        playPauseButton.layer.addSublayer(spinnerLayer)

        // Setup progress bar (recordings only) — called after pan gesture is created
    }

    // MARK: - Control Actions

    @objc private func dismissTapped() {
        // Exit fullscreen first if active
        if isFullscreen {
            exitFullscreen()
            return
        }
        // Portrait: close chat first, then dismiss.
        // Landscape: skip chat close (it's locked), dismiss directly.
        if layoutMode == .portrait && isCommentsOpen {
            currentProgress = 0
            updateLayout(progress: 0)
            isCommentsOpen = false
        }
        videoPlayer?.pause()
        RootViewController.instance.dismissPlayer()
    }

    @objc private func fullscreenTapped() {
        if isFullscreen {
            exitFullscreen()
        } else {
            enterFullscreen(for: .landscapeRight)
        }
    }

    @objc private func muteTapped() {
        videoPlayer?.avPlayer.isMuted.toggle()
        let isMuted = videoPlayer?.avPlayer.isMuted ?? false
        let icon = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.setImage(UIImage(systemName: icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal)
    }

    private func buildMoreMenu() -> UIMenu {
        var actions: [UIMenuElement] = []

        // Quality submenu (only if HLS variants are available)
        let qualities = videoPlayer?.availableQualities ?? []
        if !qualities.isEmpty {
            let currentQuality = videoPlayer?.preferredQuality
            var qualityActions: [UIAction] = []

            // Auto option
            qualityActions.append(UIAction(
                title: "Auto",
                state: currentQuality == nil ? .on : .off
            ) { [weak self] _ in
                self?.videoPlayer?.preferredQuality = nil
            })

            // Each quality tier
            for tier in qualities {
                qualityActions.append(UIAction(
                    title: "\(tier.label)  \(tier.bandwidthLabel)",
                    state: currentQuality == tier ? .on : .off
                ) { [weak self] _ in
                    self?.videoPlayer?.preferredQuality = tier
                })
            }

            actions.append(UIMenu(title: "Quality", image: UIImage(systemName: "slider.horizontal.3"), children: qualityActions))
        }

        // Share
        actions.append(UIAction(title: "Share Stream", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
            self?.shareStream()
        })

        return UIMenu(children: actions)
    }

    @objc private func videoAreaTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)

        // Tapping the video area dismisses keyboard and closes chat
        inputBar.textField.textView.resignFirstResponder()

        if isCommentsOpen && layoutMode == .portrait {
            closeChat()
            return
        }

        // Only handle taps within the player view area
        guard playerView.frame.contains(location) else { return }

        // Toggle controls visibility (play/pause button lives inside controls overlay)
        if controlsVisible {
            hideControls()
        } else {
            showControls()
        }
    }

    @objc private func playPauseTapped() {
        guard let player = videoPlayer else { return }

        if player.isPlaying || player.playbackState == .loading {
            player.pause()
            isPausedByUser = true
            controlsAutoHideTimer?.invalidate()
        } else {
            // If recording finished, replay from the beginning
            if player.didFinishPlaying {
                player.replay()
            } else {
                player.play()
            }
            isPausedByUser = false
            startAutoHideTimer()
        }
        // Icon update is handled by the $playbackState subscription — always correct
    }

    /// Driven by $playbackState — sets the correct icon and spinner state with no delay.
    /// Only one is visible at a time: either the play/pause icon OR the spinner, with a crossfade.
    private func syncPlayPauseButton(to state: PlaybackState) {
        let showSpinner: Bool

        switch state {
        case .playing:
            showSpinner = false
        case .paused:
            showSpinner = false
        case .loading:
            showSpinner = true
        }

        // Transition between spinner and icon — only one visible at a time
        if showSpinner {
            // Keep controls visible while loading (YouTube behavior)
            controlsAutoHideTimer?.invalidate()
            if !controlsVisible {
                showControls()
            }

            // Delay showing spinner — skip it for transient loading states (< 0.1s)
            if spinnerLayer.isHidden && spinnerDelayTimer == nil {
                spinnerDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.spinnerDelayTimer = nil
                    // Re-check: still loading?
                    guard self.videoPlayer?.playbackState == .loading else { return }

                    self.spinnerLayer.isHidden = false
                    self.spinnerLayer.opacity = 0
                    let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                    rotation.fromValue = 0
                    rotation.toValue = CGFloat.pi * 2
                    rotation.duration = 0.8
                    rotation.repeatCount = .infinity
                    rotation.timingFunction = CAMediaTimingFunction(name: .linear)
                    self.spinnerLayer.add(rotation, forKey: "spin")

                    UIView.animate(withDuration: 0.15) {
                        self.playPauseButton.imageView?.alpha = 0
                    }
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 0
                    fade.toValue = 1
                    fade.duration = 0.15
                    self.spinnerLayer.opacity = 1
                    self.spinnerLayer.add(fade, forKey: "fadeIn")
                }
            }
            return  // Don't update icon while loading
        }

        // Not loading — cancel pending spinner timer and hide spinner if showing
        spinnerDelayTimer?.invalidate()
        spinnerDelayTimer = nil

        if !spinnerLayer.isHidden {
            spinnerLayer.isHidden = true
            spinnerLayer.removeAnimation(forKey: "spin")
            spinnerLayer.removeAnimation(forKey: "fadeIn")
            // Restore icon visibility
            playPauseButton.imageView?.alpha = 1
        }

        // Restart auto-hide now that loading is done (unless user paused)
        if state == .playing && !isPausedByUser {
            startAutoHideTimer()
        }

        // Update icon only if it changed
        let targetIcon = state == .playing ? "pause.fill" : "play.fill"
        guard targetIcon != currentPlayPauseIcon else {
            // Ensure icon is visible even if no change (e.g. loading → paused with same icon)
            if playPauseButton.imageView?.alpha != 1 {
                UIView.animate(withDuration: 0.15) {
                    self.playPauseButton.imageView?.alpha = 1
                }
            }
            return
        }
        currentPlayPauseIcon = targetIcon

        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let newImage = UIImage(systemName: targetIcon, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)

        // Ensure alpha is 1 before crossfade (may have been 0 from spinner state)
        playPauseButton.imageView?.alpha = 1
        UIView.transition(with: playPauseButton, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.playPauseButton.setImage(newImage, for: .normal)
        }
    }

    /// No longer used — kept as empty stub for any remaining call sites.
    private func showPlayPauseIndicator(isPlaying: Bool) {}
    private func updatePlayPauseIcon(animated: Bool) {}

    private func showControls() {
        controlsVisible = true
        controlsAutoHideTimer?.invalidate()
        UIView.animate(withDuration: 0.2) {
            self.controlsOverlay.alpha = 1
        }
        if !isPausedByUser {
            startAutoHideTimer()
        }
    }

    private func hideControls() {
        controlsVisible = false
        controlsAutoHideTimer?.invalidate()
        UIView.animate(withDuration: 0.3) {
            self.controlsOverlay.alpha = 0
        }
    }

    @objc private func dismissKeyboard() {
        // inputBar lives in UIKit's input accessory container, not in self.view,
        // so view.endEditing(true) can't find it. Resign the text view directly.
        inputBar.textField.textView.resignFirstResponder()
    }

    /// Clears the opaque background UIKit adds to the inputAccessoryView system container.
    /// Must be called after becomeFirstResponder and after keyboard shows.
    private func makeInputAccessoryBackgroundTransparent() {
        var currentView: UIView? = inputBar.superview
        while let v = currentView {
            v.backgroundColor = .clear
            v.isOpaque = false
            currentView = v.superview
            let typeName = String(describing: type(of: v))
            if typeName.contains("InputSet") || typeName.contains("InputAccessory") {
                break
            }
        }
    }

    func restoreControlsAfterCancelledDismiss() {
        isInteractiveDismiss = false
        showControls()
    }

    private func startAutoHideTimer() {
        controlsAutoHideTimer?.invalidate()
        controlsAutoHideTimer = Timer.scheduledTimer(
            withTimeInterval: 3.0, repeats: false
        ) { [weak self] _ in
            self?.hideControls()
        }
    }

    // MARK: - Fullscreen (Landscape Videos)

    private func enterFullscreen(for deviceOrientation: UIDeviceOrientation) {
        guard !isFullscreen else { return }
        isFullscreen = true
        progressBeforeFullscreen = currentProgress

        // Hide input bar: resign first responder and force UIKit to re-query inputAccessoryView
        resignFirstResponder()
        reloadInputViews()

        // Rotate to landscape
        // UIDeviceOrientation and UIInterfaceOrientationMask are INVERTED for landscape
        let interfaceOrientation: UIInterfaceOrientationMask =
            deviceOrientation == .landscapeLeft ? .landscapeRight : .landscapeLeft
        AppDelegate.orientationLock = interfaceOrientation

        // Hide status bar
        statusBarHidden = true
        setNeedsStatusBarAppearanceUpdate()

        // Animate to fullscreen layout — top-to-bottom, safe area on left/right
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut) {
            let bounds = self.view.bounds
            let insets = self.view.safeAreaInsets
            let playerFrame = CGRect(x: insets.left, y: 0,
                                     width: bounds.width - insets.left - insets.right,
                                     height: bounds.height)
            self.playerView.frame = playerFrame
            self.playerView.layer.cornerRadius = 0
            self.controlsOverlay.frame = playerFrame
            self.commentsContainer.alpha = 0
            if !self.progressBar.isHidden {
                let bottomSafe = self.view.safeAreaInsets.bottom
                self.progressBarLeadingConstraint?.constant = insets.left + 16
                self.progressBarTrailingConstraint?.constant = -(insets.right + 16)
                self.progressBarBottomConstraint?.constant = bounds.height - bottomSafe - 10
                self.progressBar.alpha = 1
                self.fullscreenButtonBottomConstraint?.constant = -(44 + 10 + 0)
            } else {
                self.fullscreenButtonBottomConstraint?.constant = -12
            }
        }

        // Show controls with auto-hide
        showControls()

        // Update fullscreen button icon
        fullscreenButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal)
    }

    private func exitFullscreen() {
        guard isFullscreen else { return }
        isFullscreen = false

        // Rotate back to portrait
        AppDelegate.orientationLock = .portrait

        // Restore previous progress state
        currentProgress = progressBeforeFullscreen
        isCommentsOpen = progressBeforeFullscreen > 0.5

        // Status bar follows progress
        statusBarHidden = currentProgress < 0.5
        setNeedsStatusBarAppearanceUpdate()

        // Update fullscreen button icon
        fullscreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal)

        // Restore input bar after rotation settles
        // reloadInputViews forces UIKit to re-query canBecomeFirstResponder and inputAccessoryView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.reloadInputViews()
            if !self.isFirstResponder {
                self.becomeFirstResponder()
            }
            self.makeInputAccessoryBackgroundTransparent()
            self.autoOpenChatForLandscapeIfNeeded()
        }

        // Layout will be restored by viewDidLayoutSubviews calling updateLayout
    }

    // MARK: - Layout Mode

    /// Updates layoutMode based on the current detectedAspectRatio.
    private func updateLayoutMode() {
        let isLandscape = detectedAspectRatio == .landscape16_9
                       || detectedAspectRatio == .square1_1
        layoutMode = isLandscape ? .landscape : .portrait
    }

    /// Automatically opens the chat panel for landscape videos and locks it.
    /// Called after aspect ratio detection AND after the expand animation completes.
    /// Uses a spring animation that mimics a natural drag-release.
    private func autoOpenChatForLandscapeIfNeeded() {
        guard layoutMode == .landscape,
              currentProgress < 0.99,
              !isFullscreen,
              !hasAutoOpenedChat,
              expandAnimationComplete else { return }

        hasAutoOpenedChat = true

        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.6,
            options: [.curveEaseOut]
        ) {
            self.currentProgress = 1.0
            self.updateLayout(progress: 1.0)
        } completion: { _ in
            self.isCommentsOpen = true
        }
    }

    func expandAnimationDidComplete() {
        expandAnimationComplete = true
        autoOpenChatForLandscapeIfNeeded()
    }

    // MARK: - Seek Loading

    private var seekLoadingTimer: Timer?

    /// Shows/hides the loading spinner on the play/pause button.
    /// Hides the play/pause icon while spinner is visible — only one at a time.
    private func showSeekLoading(_ show: Bool) {
        if show {
            seekLoadingTimer?.invalidate()
            seekLoadingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self else { return }
                // Hide icon, show spinner
                self.playPauseButton.imageView?.alpha = 0
                self.spinnerLayer.isHidden = false
                self.spinnerLayer.opacity = 1
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.fromValue = 0
                rotation.toValue = CGFloat.pi * 2
                rotation.duration = 0.8
                rotation.repeatCount = .infinity
                rotation.timingFunction = CAMediaTimingFunction(name: .linear)
                self.spinnerLayer.add(rotation, forKey: "spin")
            }
        } else {
            seekLoadingTimer?.invalidate()
            seekLoadingTimer = nil
            // Hide spinner, restore icon
            spinnerLayer.isHidden = true
            spinnerLayer.removeAnimation(forKey: "spin")
            playPauseButton.imageView?.alpha = 1
        }
    }

    // MARK: - Progress Bar (Recordings)

    private func setupProgressBar() {
        // Add to main view ABOVE controlsOverlay so the progress bar receives
        // touches when controls are visible. The progress bar's 44pt hit area
        // must not be blocked by the transparent controlsOverlay.
        view.addSubview(progressBar)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBarBottomConstraint = progressBar.bottomAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        progressBarLeadingConstraint = progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        progressBarTrailingConstraint = progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            progressBarLeadingConstraint!,
            progressBarTrailingConstraint!,
            progressBar.heightAnchor.constraint(equalToConstant: 44),
            progressBarBottomConstraint!,
        ])

        // Only visible for recordings
        progressBar.isHidden = liveStream.isLive
        if !liveStream.isLive {
            startTimeObserver()
        }

        // Wire scrub callbacks
        progressBar.onScrubEnded = { [weak self] progress in
            guard let self,
                  let duration = self.videoPlayer?.avPlayer.currentItem?.duration,
                  duration.isNumeric, !duration.isIndefinite else { return }
            let totalSeconds = CMTimeGetSeconds(duration)
            let targetTime = CMTime(seconds: Double(progress) * totalSeconds, preferredTimescale: 600)

            // Lock the bar at the tapped position and show centered loading spinner
            self.progressBar.beginSeeking()
            self.showSeekLoading(true)

            self.videoPlayer?.avPlayer.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.progressBar.endSeeking()
                    self?.showSeekLoading(false)
                }
            }
        }

        // Progress bar scrub gesture should take priority over the main pan
        // only for horizontal drags within the bar. We handle this in the
        // gesture delegate instead of require(toFail:) which blocks ALL pan
        // gestures (including vertical swipe-to-dismiss) near the progress bar.
    }

    private var timeObserver: Any?

    private func startTimeObserver() {
        guard let player = videoPlayer?.avPlayer else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self,
                  let duration = player.currentItem?.duration,
                  duration.isNumeric, !duration.isIndefinite else { return }
            let current = CMTimeGetSeconds(time)
            let total = CMTimeGetSeconds(duration)
            guard total > 0 else { return }
            self.progressBar.updateProgress(CGFloat(current / total))
            self.progressBar.updateTimeLabel(current: current, total: total)
        }
    }

    // MARK: - Share

    private func shareStream() {
        let streamId = "\(liveActivitiesEvent.pubkey):\(liveActivitiesEvent.identifier ?? "")"
        let watchURL = URL(string: "https://swae.live/watch/\(streamId)")!
        let activityVC = UIActivityViewController(
            activityItems: [watchURL], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    // MARK: - Emoji Picker

    private func presentEmojiPicker() {
        guard let window = view.window, let appState else { return }

        // Toggle: if modal is already open, dismiss it
        if let modal = currentEmojiModal {
            modal.dismiss()
            return
        }

        var packs = appState.emojiPackService?.packs ?? []
        if packs.isEmpty {
            // Fallback: collect from recent chat messages
            var seen: [String: CustomEmoji] = [:]
            for item in chatController.chatItems {
                if case .message(let msg) = item {
                    for emoji in msg.customEmojis { seen[emoji.shortcode] = emoji }
                }
            }
            if !seen.isEmpty {
                packs = [EmojiPack(id: "chat", name: "Chat", authorPubkey: "",
                                   emojis: Array(seen.values))]
            }
        }

        currentEmojiModal = MorphingEmojiModal.present(
            from: inputBar.textField.emojiButton,
            in: window,
            emojiPacks: packs,
            appState: appState
        ) { [weak self] shortcodeText in
            guard let self else { return }
            let shortcode = shortcodeText.trimmingCharacters(
                in: CharacterSet(charactersIn: ":"))
            if let url = appState.emojiPackCache[shortcode] {
                self.inputBar.textField.insertEmote(shortcode: shortcode, url: url)
            } else {
                let current = self.inputBar.textField.text
                self.inputBar.textField.text = current + shortcodeText
            }
        }

        currentEmojiModal?.onDismissed = { [weak self] in
            self?.currentEmojiModal = nil
        }
    }

    // MARK: - Keyboard

    private func setupKeyboardObserver() {
        // Keyboard show — update layout to shrink comments for keyboard
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self,
                      !self.isFullscreen,
                      let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
                      let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
                else { return }

                // Ignore spurious keyboardWillShow fired when becomeFirstResponder()
                // re-attaches the inputAccessoryView without an actual keyboard.
                guard self.inputBar.textField.textView.isFirstResponder else { return }

                let screenH = UIScreen.main.bounds.height
                self.keyboardHeight = max(0, screenH - endFrame.origin.y)
                self.isInteractiveDismiss = false

                let options = UIView.AnimationOptions(rawValue: curve << 16)
                UIView.animate(withDuration: duration, delay: 0, options: options) {
                    self.updateLayout(progress: self.currentProgress)
                    // Update chat table insets so messages shift above the keyboard
                    self.chatController.updateKeyboardInset(self.keyboardHeight)
                }
                self.makeInputAccessoryBackgroundTransparent()
            }
            .store(in: &cancellables)

        // Keyboard frame change — ONLY for interactive dismiss detection, NO layout updates
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self,
                      let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }

                let screenH = UIScreen.main.bounds.height
                let newKbH = max(0, screenH - endFrame.origin.y)

                // Detect interactive dismiss: height decreasing but not yet 0
                if newKbH < self.keyboardHeight && newKbH > 0 && self.keyboardHeight > 0 {
                    self.isInteractiveDismiss = true
                }

                self.keyboardHeight = newKbH
            }
            .store(in: &cancellables)

        // Keyboard hide — final layout update, keep chat open
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self, !self.isFullscreen else { return }
                let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0

                self.keyboardHeight = 0
                self.isInteractiveDismiss = false

                let options = UIView.AnimationOptions(rawValue: curve << 16)
                UIView.animate(withDuration: duration, delay: 0, options: options) {
                    // Reset chat table insets back to no-keyboard state
                    self.chatController.updateKeyboardInset(0)
                    self.updateLayout(progress: self.currentProgress)
                } completion: { _ in
                    if !self.isFirstResponder {
                        self.becomeFirstResponder()
                    }
                    self.makeInputAccessoryBackgroundTransparent()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Live → Recording Transition

    private func subscribeToEventUpdates() {
        guard let appState,
              let coordinates = liveActivitiesEvent.coordinateTag else { return }

        appState.$liveActivitiesEvents
            .compactMap { $0[coordinates]?.first }
            .removeDuplicates { $0.id == $1.id && $0.status == $1.status && $0.recording == $1.recording }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] updatedEvent in
                guard let self else { return }
                let previousStatus = self.liveActivitiesEvent.status
                let previousRecording = self.liveActivitiesEvent.recording

                self.liveActivitiesEvent = updatedEvent
                self.liveStream = updatedEvent.toLiveStream()

                if previousStatus == .live && updatedEvent.status == .ended {
                    if let recordingURL = updatedEvent.recording {
                        self.videoPlayer?.liveStream = self.liveStream
                        self.videoPlayer?.switchToURL(recordingURL)
                        self.showTransitionToast("Stream ended — playing recording")
                    } else {
                        self.showTransitionToast("Stream has ended")
                    }
                } else if updatedEvent.status == .ended && previousRecording == nil,
                          let recordingURL = updatedEvent.recording {
                    self.videoPlayer?.liveStream = self.liveStream
                    self.videoPlayer?.switchToURL(recordingURL)
                    self.showTransitionToast("Recording available")
                }
            }
            .store(in: &cancellables)
    }

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

        playerView.addSubview(container)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
     
            container.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            container.topAnchor.constraint(equalTo: playerView.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])

        container.alpha = 0
        UIView.animate(withDuration: 0.3) { container.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            UIView.animate(withDuration: 0.3, animations: { container.alpha = 0 }) { _ in
                container.removeFromSuperview()
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ReelsPlayerController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // Don't intercept touches on buttons (let button actions fire instead)
        return !(touch.view is UIButton)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Allow the controls toggle tap and keyboard dismiss tap to fire together
        if gestureRecognizer is UITapGestureRecognizer && other is UITapGestureRecognizer {
            return true
        }
        // Allow the main pan and progress bar scrub to recognize simultaneously.
        // handlePan checks velocity direction — vertical swipes become dismiss,
        // horizontal ones stay idle and let the scrub gesture handle it.
        if gestureRecognizer == panGesture && other == progressBar.scrubGesture {
            return true
        }
        if gestureRecognizer == progressBar.scrubGesture && other == panGesture {
            return true
        }
        return false
    }
}

// MARK: - PlayerController Conformance

extension ReelsPlayerController: PlayerController {}
