//
//  LiveChatController.swift
//  swae
//
//  Chat controller for live streaming
//

import Combine
import NostrSDK
import UIKit

// MARK: - EventCreating Protocol Extension

extension LiveChatController: EventCreating {
    // EventCreating protocol provides liveChatMessageEvent() helper
}

// MARK: - Chat Item Types

enum LiveChatItem: Equatable {
    case message(LiveChatMessageEvent)
    case zapReceipt(LightningZapsReceiptEvent)
    case dateSeparator(Date)  // Day separator label
    case raid(LiveStreamRaidEvent)  // Raid event (Kind 1312) - separate event type, not a chat message
    case pendingMessage(PendingChatMessage)   // Optimistic display — not yet confirmed by relay
    case pendingZap(PendingChatZap)           // Optimistic display — zap in flight

    var createdAt: Int64 {
        switch self {
        case .message(let message):
            return message.createdAt
        case .zapReceipt(let zapReceipt):
            // Use the embedded zap request's timestamp (when user sent the zap)
            // rather than the receipt timestamp (when LNURL provider processed it)
            // This ensures zaps are interleaved correctly with messages
            return zapReceipt.description?.createdAt ?? zapReceipt.createdAt
        case .dateSeparator(let date):
            return Int64(date.timeIntervalSince1970)
        case .raid(let raidEvent):
            return raidEvent.createdAt
        case .pendingMessage(let pending):
            return pending.createdAt
        case .pendingZap(let pending):
            return pending.createdAt
        }
    }

    var id: String {
        switch self {
        case .message(let message):
            return message.id
        case .zapReceipt(let zapReceipt):
            return zapReceipt.id
        case .dateSeparator(let date):
            // Unique ID based on the day
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return "date-\(formatter.string(from: date))"
        case .raid(let raidEvent):
            return "raid-\(raidEvent.id)"
        case .pendingMessage(let pending):
            return "pending-msg-\(pending.localId)"
        case .pendingZap(let pending):
            return "pending-zap-\(pending.localId)"
        }
    }
    
    var isPending: Bool {
        switch self {
        case .pendingMessage, .pendingZap: return true
        default: return false
        }
    }

    static func == (lhs: LiveChatItem, rhs: LiveChatItem) -> Bool {
        return lhs.id == rhs.id
    }
}

class LiveChatController: UIViewController, UIGestureRecognizerDelegate {
    // New Streamer Dashboard (replaces old header)
    let dashboardView = StreamerDashboardView()
    
    // Legacy header (kept for backward compatibility with GenericLivePlayerController)
    let header = LiveStreamHeaderView()
    let topInfoView = UIView()
    
    let commentsTable = UITableView()
    
    // Telegram-style liquid glass input bar
    let input = TelegramChatInputBar()
    
    // Track if we're in streamer mode (shows dashboard) or viewer mode (shows legacy header)
    var isStreamerMode: Bool = false

    var cancellables: Set<AnyCancellable> = []

    // Real data from AppState - LOCAL CACHES
    var chatItems: [LiveChatItem] = []
    var liveChatMessages: [LiveChatMessageEvent] = []
    var liveZapReceipts: [LightningZapsReceiptEvent] = []  // Local zap cache

    /// Optional callback fired whenever chatItems changes.
    /// Used by ControlPanelViewController to bridge sorted chat data to NostrChatEffect.
    /// NOT set by GenericLivePlayerController (viewer mode) — nil by default.
    var onChatItemsChanged: (([LiveChatItem]) -> Void)?
    
    // Track seen IDs for O(1) duplicate detection
    private var seenMessageIds = Set<String>()
    private var seenZapIds = Set<String>()
    private var chatItemIds = Set<String>()  // Mirrors chatItems for O(1) duplicate check
    
    // MARK: - Pending Items (Optimistic Display)
    private var pendingMessages: [String: PendingChatMessage] = [:]  // localId -> pending
    private var pendingZaps: [String: PendingChatZap] = [:]          // localId -> pending
    private var pendingEventIdMap: [String: String] = [:]             // eventId -> localId (for message reconciliation)
    private var pendingTimeouts: [String: Timer] = [:]                // localId -> timeout timer
    
    // Skeleton loading state
    private var isShowingSkeletons = true
    private let skeletonContainerView = UIView()
    private var skeletonViews: [ChatSkeletonRowView] = []

    // AppState reference
    weak var appState: AppState?

    // LiveActivitiesEvent reference for subscriptions (optional for camera streaming)
    var liveActivitiesEvent: LiveActivitiesEvent?
    
    // Separate cancellable set for chat subscriptions so they can be torn down
    // independently when the liveActivitiesEvent changes (resubscription)
    private var chatSubscriptionCancellables: Set<AnyCancellable> = []

    var liveStream: LiveStream {
        didSet {
            updateLabels()
        }
    }

    var videoController: GenericLivePlayerController? {
        parent as? GenericLivePlayerController
    }
    
    var miniPlayerController: MiniPlayerSupport? {
        parent as? MiniPlayerSupport
    }

    // Pagination (unified time-based)
    private let pageSize: Int = 200              // Items per pagination load
    private let initialPageSize: Int = 100     // Items to show on initial load
    private let maxPreloadItems: Int = 1000    // Max items to preload in background
    private var hasMoreItems: Bool = true
    private var isLoadingPage: Bool = false
    private var isBackgroundLoading: Bool = false
    
    // Initial load phase tracking
    // During initial phase, we rebuild the entire display when new data arrives
    // After 300ms of no updates, we switch to incremental mode and start background loading
    private var initialLoadComplete = false
    private var initialLoadTimer: Timer?

    // Metadata loading
    private var pubkeysToPullMetadata = Set<String>()
    private var metadataPullCancellable: AnyCancellable?
    
    // Fix #5: Cache for parsed mentions to avoid re-parsing in cells
    private var mentionCache: [Int: Set<String>] = [:]  // content.hashValue -> pubkeys
    
    // Pre-computed emoji maps per message ID (avoids re-iterating emojiPackCache on every cell configure)
    private var emojiMapCache: [String: [String: URL]] = [:]  // message.id -> shortcode -> URL
    private var prefetchedPubkeys: Set<String> = []
    
    // Zap service
    private var zapService: ZapService?
    
    // Keyboard tracking for iMessage-like behavior
    private var currentKeyboardHeight: CGFloat = 0
    private var isKeyboardVisible: Bool = false
    
    // Stream start time for duration tracking (used in streamer mode)
    var streamStartTime: ContinuousClock.Instant?

    init(liveStream: LiveStream, liveActivitiesEvent: LiveActivitiesEvent?, appState: AppState?) {
        self.liveStream = liveStream
        self.liveActivitiesEvent = liveActivitiesEvent
        self.appState = appState
        
        // Initialize zap service if appState is available
        if let appState = appState {
            self.zapService = ZapService(appState: appState)
        }
        
        super.init(nibName: nil, bundle: nil)

        // Flip table for bottom-up layout (newest messages at bottom visually)
        // Note: This inverts scroll direction - "down" in code = "up" visually
        commentsTable.transform = CGAffineTransform(rotationAngle: .pi)
    }
    
    /// Convenience initializer for streamer mode (from camera/control panel)
    convenience init(liveStream: LiveStream, liveActivitiesEvent: LiveActivitiesEvent?, appState: AppState?, streamStartTime: ContinuousClock.Instant?, isStreamerMode: Bool) {
        self.init(liveStream: liveStream, liveActivitiesEvent: liveActivitiesEvent, appState: appState)
        self.streamStartTime = streamStartTime
        self.isStreamerMode = isStreamerMode
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    deinit {
        initialLoadTimer?.invalidate()
        initialLoadTimer = nil
        for (_, timer) in pendingTimeouts { timer.invalidate() }
        pendingTimeouts.removeAll()
        chatSubscriptionCancellables.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        if isStreamerMode {
            // STREAMER MODE: Use dashboard with streamer layout (activity metrics)
            setupStreamerDashboard()
        } else {
            // VIEWER MODE: Use dashboard with viewer layout (profile pic + follow)
            setupViewerDashboard()
        }
        
        // Common table setup
        setupCommentsTable()
        
        // Setup skeleton loading view
        setupSkeletonView()

        // Tap anywhere to dismiss keyboard (works with interactive drag dismiss)
        setupTapToDismissKeyboard()

        // Forward text view events
        input.textField.textView.delegate = self

        setupInputObservers()
        setupActions()
        updateLabels()

        // Subscribe to real chat data from AppState
        subscribeToLiveChat()
    }
    
    /// Gets the safe area top inset from the key window.
    /// This is needed because the control panel view is positioned off-screen and transformed into view.
    private func getSafeAreaTop() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window.safeAreaInsets.top
        }
        // Fallback for devices with notch (59pt)
        return 59
    }
    
    private func setupStreamerDashboard() {
        // Add dashboard view
        view.addSubview(dashboardView)
        
        // Add table below dashboard
        view.addSubview(commentsTable)
        commentsTable.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure dashboard for streamer mode
        dashboardView.mode = .streamer
        
        // Set safe area for transform-based layout (control panel is positioned off-screen)
        dashboardView.safeAreaTopInset = getSafeAreaTop()
        
        dashboardView.configure(
            title: liveStream.title,
            isLive: liveStream.isLive,
            streamStartTime: streamStartTime,
            liveActivitiesEvent: liveActivitiesEvent,
            appState: appState
        )
        
        // Dashboard expand/collapse callback (disabled for streamer mode but kept for consistency)
        dashboardView.onExpandToggle = { [weak self] expanded in
            print("📊 Dashboard \(expanded ? "expanded" : "collapsed")")
        }
        
        NSLayoutConstraint.activate([
            // Dashboard at top (includes safe area padding internally)
            dashboardView.topAnchor.constraint(equalTo: view.topAnchor),
            dashboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dashboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Table below dashboard (constraint-based, not overlay)
            commentsTable.topAnchor.constraint(equalTo: dashboardView.bottomAnchor),
            commentsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func setupViewerDashboard() {
        // Add dashboard view
        view.addSubview(dashboardView)
        
        // Add table below dashboard
        view.addSubview(commentsTable)
        commentsTable.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure dashboard for viewer mode
        if let hostPubkey = liveActivitiesEvent?.hostPubkeyHex {
            dashboardView.configureForViewer(
                streamerPubkey: hostPubkey,
                liveActivitiesEvent: liveActivitiesEvent,
                appState: appState
            )
        } else {
            // Fallback to streamer mode if no host pubkey
            dashboardView.mode = .streamer
            dashboardView.configure(
                title: liveStream.title,
                isLive: liveStream.isLive,
                streamStartTime: nil,
                liveActivitiesEvent: liveActivitiesEvent,
                appState: appState
            )
        }
        
        // Dashboard expand/collapse callback
        dashboardView.onExpandToggle = { [weak self] expanded in
            print("📊 Viewer dashboard \(expanded ? "expanded" : "collapsed")")
        }
        
        // Handle follow button tap
        dashboardView.onFollowTapped = { [weak self] pubkey in
            self?.handleFollowTapped(pubkey: pubkey)
        }
        
        // Handle profile tap
        dashboardView.onProfileTapped = { [weak self] pubkey in
            self?.handleProfileTap(pubkeyHex: pubkey)
        }
        
        NSLayoutConstraint.activate([
            // Dashboard at top
            dashboardView.topAnchor.constraint(equalTo: view.topAnchor),
            dashboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dashboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Table below dashboard
            commentsTable.topAnchor.constraint(equalTo: dashboardView.bottomAnchor),
            commentsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        // Also setup legacy header for backward compatibility (hidden)
        setupLegacyHeaderHidden()
    }
    
    private func setupLegacyHeaderHidden() {
        // Keep legacy header for backward compatibility but hidden
        view.addSubview(topInfoView)
        topInfoView.addSubview(header)
        topInfoView.backgroundColor = .secondarySystemBackground
        topInfoView.translatesAutoresizingMaskIntoConstraints = false
        topInfoView.alpha = 0  // Hidden - using dashboard instead
        topInfoView.isHidden = true
        header.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            topInfoView.topAnchor.constraint(equalTo: view.topAnchor),
            topInfoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topInfoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            header.topAnchor.constraint(equalTo: topInfoView.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: topInfoView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: topInfoView.trailingAnchor),
            header.bottomAnchor.constraint(equalTo: topInfoView.bottomAnchor),
        ])
    }
    
    private func handleFollowTapped(pubkey: String) {
        guard let appState = appState else { return }
        
        var currentFollows = appState.activeFollowList?.followedPubkeys ?? []
        
        if appState.followedPubkeys.contains(pubkey) {
            // Unfollow: remove from complete list
            currentFollows.removeAll { $0 == pubkey }
            notify(.unfollow(currentFollows))
        } else {
            // Follow: add to complete list
            if !currentFollows.contains(pubkey) {
                currentFollows.append(pubkey)
            }
            notify(.follow(currentFollows))
        }
    }
    
    private func setupLegacyHeader() {
        // Add table to view
        view.addSubview(commentsTable)
        commentsTable.translatesAutoresizingMaskIntoConstraints = false

        // Add top info view (VISIBLE by default)
        view.addSubview(topInfoView)
        topInfoView.addSubview(header)
        topInfoView.backgroundColor = .secondarySystemBackground
        topInfoView.translatesAutoresizingMaskIntoConstraints = false
        topInfoView.alpha = 1  // VISIBLE by default - hidden only when video becomes small
        header.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topInfoView.topAnchor.constraint(equalTo: view.topAnchor),
            topInfoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topInfoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            header.topAnchor.constraint(equalTo: topInfoView.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: topInfoView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: topInfoView.trailingAnchor),
            header.bottomAnchor.constraint(equalTo: topInfoView.bottomAnchor),

            // Table fills entire view (overlay approach for legacy)
            commentsTable.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            commentsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            commentsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            commentsTable.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func setupCommentsTable() {
        commentsTable.backgroundColor = .systemBackground
        commentsTable.delegate = self
        commentsTable.dataSource = self
        commentsTable.register(LiveChatMessageCell.self, forCellReuseIdentifier: "messageCell")
        commentsTable.register(LiveChatZapCell.self, forCellReuseIdentifier: "zapCell")
        commentsTable.register(DateSeparatorCell.self, forCellReuseIdentifier: "dateSeparatorCell")
        commentsTable.register(LiveChatRaidCell.self, forCellReuseIdentifier: "raidCell")
        commentsTable.showsVerticalScrollIndicator = false
        commentsTable.separatorStyle = .none
        // Interactive dismissal with keyboard dragging - iMessage style
        commentsTable.keyboardDismissMode = .interactiveWithAccessory
        // Initial content inset will be set in viewDidLayoutSubviews
        // For flipped table: top = visual bottom (near input bar)
        commentsTable.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        commentsTable.scrollIndicatorInsets = UIEdgeInsets.zero
        commentsTable.alwaysBounceVertical = true  // Allows dragging even when content is small
    }
    
    private func setupSkeletonView() {
        // Container for skeleton rows
        skeletonContainerView.backgroundColor = .systemBackground
        skeletonContainerView.translatesAutoresizingMaskIntoConstraints = false
        skeletonContainerView.clipsToBounds = true  // Prevent overflow past container bounds
        view.addSubview(skeletonContainerView)
        
        // Position skeleton container over the table area
        NSLayoutConstraint.activate([
            skeletonContainerView.topAnchor.constraint(equalTo: commentsTable.topAnchor),
            skeletonContainerView.leadingAnchor.constraint(equalTo: commentsTable.leadingAnchor),
            skeletonContainerView.trailingAnchor.constraint(equalTo: commentsTable.trailingAnchor),
            skeletonContainerView.bottomAnchor.constraint(equalTo: commentsTable.bottomAnchor),
        ])
        
        // Create skeleton rows (show 6 placeholder messages)
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        skeletonContainerView.addSubview(stackView)
        
        // Anchor to BOTTOM using same calculation as table content inset
        // inputBarHeight (60) + safeAreaBottom + small padding
        let inputBarHeight: CGFloat = 60
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: skeletonContainerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: skeletonContainerView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: skeletonContainerView.safeAreaLayoutGuide.bottomAnchor, constant: -(inputBarHeight + 10)),
        ])
        
        // Add skeleton rows with varying widths for natural look
        let messageWidths: [CGFloat] = [0.7, 0.5, 0.85, 0.6, 0.75, 0.55, 0.8, 0.45, 0.65, 0.7]
        for width in messageWidths {
            let row = ChatSkeletonRowView(messageWidthRatio: width)
            skeletonViews.append(row)
            stackView.addArrangedSubview(row)
            row.startAnimating()
        }
    }
    
    private func hideSkeletons() {
        guard isShowingSkeletons else { return }
        isShowingSkeletons = false
        
        UIView.animate(withDuration: 0.3) {
            self.skeletonContainerView.alpha = 0
        } completion: { _ in
            self.skeletonContainerView.isHidden = true
            self.skeletonViews.forEach { $0.stopAnimating() }
        }
    }

    @objc private func inputTapped() {
        // Make text view first responder to show keyboard
        input.textField.textView.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // DON'T automatically become first responder here
        // The input bar should only appear when the control panel is visible
        // This is handled by ControlPanelViewController.panelDidAppear() via notification
        
        // Make input accessory view background transparent (Telegram style)
        // This is safe to call even when not first responder
        makeInputAccessoryBackgroundTransparent()
        
        // Update content inset now that we have proper frame
        updateTableContentInsetForKeyboard()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update content inset when layout changes (rotation, etc.)
        // Only update if keyboard is not visible to avoid conflicts
        if !isKeyboardVisible {
            updateTableContentInsetForKeyboard()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // DON'T unsubscribe here - subscription is cleaned up in
        // RootViewController.onDismiss when player is FULLY dismissed.
        // This preserves chat data during mini player mode (profile navigation).
    }
    
    /// Makes the input accessory view's container background transparent
    /// This removes the gray bar that iOS adds by default
    private func makeInputAccessoryBackgroundTransparent() {
        // The inputAccessoryView is wrapped in a system container
        // We need to make that container transparent
        // Walk up the view hierarchy and clear backgrounds
        var currentView: UIView? = input.superview
        while let view = currentView {
            view.backgroundColor = .clear
            view.isOpaque = false
            currentView = view.superview
            
            // Stop at UIInputSetContainerView or similar system container
            let typeName = String(describing: type(of: view))
            if typeName.contains("InputSet") || typeName.contains("InputAccessory") {
                break
            }
        }
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override var inputAccessoryView: UIView? {
        return input
    }

    private func setupInputObservers() {
        // Listen for keyboard show/hide to coordinate with video mini player
        // and adjust table view content inset
        // 
        // IMPORTANT: Table is rotated 180°, so:
        // - TOP inset in code = BOTTOM visually (near input bar)
        // - BOTTOM inset in code = TOP visually (near header)
        //
        // For iMessage-like behavior:
        // 1. When keyboard shows, push messages up (adjust top inset)
        // 2. Keep user's scroll position or scroll to bottom if they were at bottom
        // 3. During interactive dismissal, track keyboard frame changes
        
        // Keyboard will show - animate content inset change
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleKeyboardWillShow(notification)
            }
            .store(in: &cancellables)

        // Keyboard will hide - reset content inset
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleKeyboardWillHide(notification)
            }
            .store(in: &cancellables)
        
        // Keyboard frame change - for interactive dismissal tracking
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleKeyboardWillChangeFrame(notification)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Keyboard Handling
    
    private func handleKeyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let keyboardHeight = keyboardFrame.height
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let animationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        
        // Track keyboard state
        currentKeyboardHeight = keyboardHeight
        isKeyboardVisible = true
        
        // Make input accessory background transparent
        makeInputAccessoryBackgroundTransparent()
        
        // Check if user was at the bottom before keyboard shows
        let wasAtBottom = isScrolledNearBottom()
        
        // Animate content inset change synchronized with keyboard
        let options = UIView.AnimationOptions(rawValue: animationCurve << 16)
        UIView.animate(withDuration: animationDuration, delay: 0, options: options) {
            self.updateTableContentInsetForKeyboard()
            
            // If user was at bottom, keep them there (iMessage behavior)
            if wasAtBottom {
                self.scrollToNewestMessage(animated: false)
            }
        }
    }
    
    private func handleKeyboardWillHide(_ notification: Notification) {
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let animationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        
        // Track keyboard state
        currentKeyboardHeight = 0
        isKeyboardVisible = false
        
        // Animate content inset change synchronized with keyboard
        let options = UIView.AnimationOptions(rawValue: animationCurve << 16)
        UIView.animate(withDuration: animationDuration, delay: 0, options: options) {
            self.updateTableContentInsetForKeyboard()
        }
    }
    
    private func handleKeyboardWillChangeFrame(_ notification: Notification) {
        // This handles interactive keyboard dismissal
        // The keyboard frame changes as user drags
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        let screenHeight = UIScreen.main.bounds.height
        let keyboardVisibleHeight = max(0, screenHeight - keyboardFrame.origin.y)
        
        // Only update during interactive dismissal (when keyboard is partially visible)
        // Don't interfere with the show/hide animations
        if keyboardVisibleHeight > 0 && keyboardVisibleHeight < currentKeyboardHeight {
            // Interactive dismissal in progress - update inset to track keyboard
            let baseInset = calculateBaseInputBarInset()
            let newTopInset = max(keyboardVisibleHeight, baseInset) + 10
            
            commentsTable.contentInset.top = newTopInset
            commentsTable.scrollIndicatorInsets.top = newTopInset - baseInset
        }
    }
    
    /// Updates the table content inset based on current keyboard state
    /// For flipped table: top inset = visual bottom (space for input bar/keyboard)
    private func updateTableContentInsetForKeyboard() {
        let baseInset = calculateBaseInputBarInset()
        
        let topInset: CGFloat
        if isKeyboardVisible && currentKeyboardHeight > 0 {
            // Keyboard is showing - use keyboard height
            topInset = currentKeyboardHeight + 10
        } else {
            // Keyboard is hidden - use input bar height + safe area
            topInset = baseInset + 10
        }
        
        commentsTable.contentInset = UIEdgeInsets(
            top: topInset,      // Visual bottom - space for input bar/keyboard
            left: 0,
            bottom: 10,         // Visual top - space from header
            right: 0
        )
        
        // Scroll indicator should not overlap with input bar
        commentsTable.scrollIndicatorInsets = UIEdgeInsets(
            top: topInset - 10,
            left: 0,
            bottom: 0,
            right: 0
        )
    }
    
    /// Calculates the base inset needed for the input bar when keyboard is hidden
    private func calculateBaseInputBarInset() -> CGFloat {
        // Input bar intrinsic height is 60, but it also has safe area padding
        let inputBarHeight: CGFloat = 60
        let safeAreaBottom = view.safeAreaInsets.bottom
        return inputBarHeight + safeAreaBottom
    }
    
    /// Checks if the user is scrolled near the bottom (newest messages)
    /// For flipped table, "bottom" is at contentOffset.y near 0
    private func isScrolledNearBottom() -> Bool {
        // Consider "near bottom" if within 100pt of the newest messages
        return commentsTable.contentOffset.y <= 100
    }
    
    /// Scrolls to show the newest message (visual bottom, which is row 0 in flipped table)
    private func scrollToNewestMessage(animated: Bool) {
        guard chatItems.count > 0 else { return }
        // For flipped table, row 0 is at the visual bottom (newest message)
        commentsTable.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)
    }

    private func setupActions() {
        // TelegramChatInputBar uses callbacks instead of target-action
        input.onSendMessage = { [weak self] text in
            self?.dismissEmojiPickerIfNeeded()
            self?.sendMessageWithText(text)
        }
        
        // Enable zap mode and set up zap target
        input.isZapMode = true
        updateZapTarget()
        updateWalletState()
        
        // Handle no-wallet — navigate to wallet tab
        input.onNoWallet = { [weak self] in
            self?.dismissEmojiPickerIfNeeded()
            self?.navigateToWalletTab()
        }
        
        // Handle zap sends
        input.onSendZap = { [weak self] amount, message in
            self?.dismissEmojiPickerIfNeeded()
            self?.sendZap(amount: amount, message: message)
        }
        
        input.onAttachmentTapped = { [weak self] in
            self?.dismissEmojiPickerIfNeeded()
            print("📎 Attachment tapped")
        }
        
        input.onMicrophoneTapped = { [weak self] in
            self?.dismissEmojiPickerIfNeeded()
            print("🎤 Microphone tapped")
        }
        
        input.onEmojiTapped = { [weak self] in
            self?.presentEmojiPicker()
        }
    }
    
    private func dismissEmojiPickerIfNeeded() {
        currentEmojiModal?.dismiss()
    }
    
    // MARK: - Zap Integration
    
    private func updateWalletState() {
        if let wallet = appState?.wallet,
           case .existing = wallet.connect_state {
            input.hasConnectedWallet = true
        } else {
            input.hasConnectedWallet = false
        }
    }
    
    private func navigateToWalletTab() {
        // Dismiss the player first, then switch to wallet tab
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        // Find the MainTabBarProtocol controller
        func findMainTabBar(in vc: UIViewController) -> (UIViewController & MainTabBarProtocol)? {
            if let tabBar = vc as? (UIViewController & MainTabBarProtocol) {
                return tabBar
            }
            for child in vc.children {
                if let found = findMainTabBar(in: child) {
                    return found
                }
            }
            return nil
        }
        
        // Dismiss any presented view controllers, then switch tab
        if let presented = rootVC.presentedViewController {
            presented.dismiss(animated: true) {
                if let tabBar = findMainTabBar(in: rootVC) {
                    tabBar.switchToTab(.wallet, open: nil)
                }
            }
        } else if let tabBar = findMainTabBar(in: rootVC) {
            tabBar.switchToTab(.wallet, open: nil)
        }
    }
    
    private func updateZapTarget() {
        guard let liveActivitiesEvent = liveActivitiesEvent else { return }
        
        // Get host pubkey
        input.zapTargetPubkey = liveActivitiesEvent.hostPubkeyHex
        input.zapEventCoordinate = liveActivitiesEvent.coordinateTag
    }
    
    private func sendZap(amount: Int64, message: String?) {
        guard let zapService = zapService,
              let targetPubkey = input.zapTargetPubkey,
              let appState = appState else {
            print("❌ Cannot send zap: No zap service or target pubkey")
            return
        }
        
        // 1. Create pending zap and insert immediately (optimistic display)
        let localId = UUID().uuidString
        let pending = PendingChatZap(
            localId: localId,
            senderPubkey: appState.keypair?.publicKey.hex ?? "",
            recipientPubkey: targetPubkey,
            amount: amount,
            content: message,
            createdAt: Int64(Date().timeIntervalSince1970),
            eventCoordinate: input.zapEventCoordinate,
            status: .sending
        )
        insertPendingZap(pending)
        
        // 2. Set initial timeout in case the async task never completes
        //    (e.g., app backgrounded, network hangs indefinitely)
        schedulePendingTimeout(localId: localId, delay: 45.0)
        
        // 3. Send zap asynchronously
        Task {
            let success = await zapService.sendZap(
                amount: amount,
                targetPubkey: targetPubkey,
                eventCoordinate: input.zapEventCoordinate,
                content: message
            )
            
            await MainActor.run {
                if success {
                    // Zap payment succeeded — pending item stays until real receipt arrives
                    // Extend timeout since receipt can take a while
                    self.schedulePendingTimeout(localId: localId, delay: 30.0)
                    
                    let impact = UIImpactFeedbackGenerator(style: .heavy)
                    impact.impactOccurred()
                    print("✅ Zap sent: \(amount / 1000) sats")
                } else {
                    // Payment failed — mark pending item as failed
                    self.markPendingAsFailed(
                        localId: localId,
                        error: zapService.zapError ?? "Zap failed"
                    )
                    
                    let notification = UINotificationFeedbackGenerator()
                    notification.notificationOccurred(.error)
                    print("❌ Zap failed: \(zapService.zapError ?? "Unknown error")")
                }
            }
        }
    }

    // MARK: - Tap to Dismiss Keyboard
    
    private func setupTapToDismissKeyboard() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardIfNeeded))
        tapGesture.cancelsTouchesInView = false  // Don't block cell selection or other touches
        tapGesture.delegate = self
        commentsTable.addGestureRecognizer(tapGesture)
    }
    
    @objc private func dismissKeyboardIfNeeded() {
        // Only dismiss if text view is actually first responder
        if input.textField.textView.isFirstResponder {
            input.textField.textView.resignFirstResponder()
        }
    }

    // MARK: - Emoji Picker
    
    private var currentEmojiModal: MorphingEmojiModal?
    
    private func presentEmojiPicker() {
        // Toggle: if modal is already open, dismiss it
        if let modal = currentEmojiModal {
            modal.dismiss()
            return
        }
        
        guard let window = view.window,
              let appState = appState else { return }
        
        // Collect emojis from loaded packs
        var packs = appState.emojiPackService?.packs ?? []
        
        // Also collect emojis seen in recent chat messages as a fallback
        // This ensures the picker has content even if no kind 10030/30030 packs are loaded
        if packs.isEmpty {
            var seenEmojis: [CustomEmoji] = []
            for item in chatItems {
                if case .message(let msg) = item {
                    seenEmojis.append(contentsOf: msg.customEmojis)
                }
            }
            if !seenEmojis.isEmpty {
                // Deduplicate by shortcode
                var unique: [String: CustomEmoji] = [:]
                for emoji in seenEmojis { unique[emoji.shortcode] = emoji }
                packs = [EmojiPack(
                    id: "chat-emojis",
                    name: "Chat Emojis",
                    authorPubkey: "",
                    emojis: Array(unique.values)
                )]
            }
        }
        
        currentEmojiModal = MorphingEmojiModal.present(
            from: input.textField.emojiButton,
            in: window,
            emojiPacks: packs,
            appState: appState
        ) { [weak self] shortcodeText in
            guard let self else { return }
            // Extract shortcode from ":shortcode:" format and insert as inline image
            let shortcode = shortcodeText.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            if let url = appState.emojiPackCache[shortcode] {
                self.input.textField.insertEmote(shortcode: shortcode, url: url)
            } else {
                // Fallback: insert as text if URL not found
                let current = self.input.textField.text
                self.input.textField.text = current + shortcodeText
            }
        }
        
        currentEmojiModal?.onDismissed = { [weak self] in
            self?.currentEmojiModal = nil
            // Restore input bar by reclaiming first responder
            self?.becomeFirstResponder()
        }
        
        currentEmojiModal?.onSearchResigned = { [weak self] in
            // Search field resigned — restore the chat input bar
            self?.becomeFirstResponder()
        }
    }

    /// Send message with the provided text (called from TelegramChatInputBar callback)
    private func sendMessageWithText(_ text: String) {
        guard !text.isEmpty else { return }
        guard let appState = appState else { return }
        guard let liveActivitiesEvent = liveActivitiesEvent else {
            print("⚠️ Cannot send message: No LiveActivitiesEvent available")
            return
        }
        
        // Fix 4: Check relay connectivity before creating event
        guard appState.relayWritePool.relays.contains(where: { $0.state == .connected }) else {
            print("⚠️ Cannot send message: No connected write relays")
            return
        }

        // Create and send the live chat message event
        guard let keypair = appState.keypair,
            let identifier = liveActivitiesEvent.identifier,
            !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        do {
            // Extract NIP-30 custom emoji shortcodes from the message text
            let emojisToAttach: [CustomEmoji]? = {
                guard let regex = try? NSRegularExpression(pattern: ":([_a-zA-Z0-9]+):") else { return nil }
                let nsRange = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, range: nsRange)
                guard !matches.isEmpty else { return nil }
                
                let shortcodes = matches.compactMap { match -> String? in
                    guard let range = Range(match.range(at: 1), in: text) else { return nil }
                    return String(text[range])
                }
                
                // Look up shortcodes in the event's available emoji packs via AppState
                let found = shortcodes.compactMap { shortcode -> CustomEmoji? in
                    guard let url = appState.resolveEmojiURL(shortcode: shortcode) else { return nil }
                    return CustomEmoji(shortcode: shortcode, imageURL: url)
                }
                return found.isEmpty ? nil : found
            }()
            
            let liveChatMessageEvent = try liveChatMessageEvent(
                content: text,
                liveEventPubKey: liveActivitiesEvent.pubkey,
                d: identifier,
                relay: "wss://relay.damus.io",
                customEmojis: emojisToAttach,
                signedBy: keypair
            )

            // 1. Create pending item with the REAL event ID (available after signing)
            let localId = UUID().uuidString
            let pending = PendingChatMessage(
                localId: localId,
                eventId: liveChatMessageEvent.id,
                pubkey: keypair.publicKey.hex,
                content: text,
                createdAt: liveChatMessageEvent.createdAt,
                status: .sending
            )

            // 2. Insert into chat immediately (optimistic display)
            insertPendingMessage(pending)

            // 3. Publish to relays (write pool + read pool for echo-back guarantee)
            appState.publishEventToAllRelays(liveChatMessageEvent)
            
            // 4. Register OK confirmation callback — relay accepted the event
            appState.registerPendingConfirmation(eventId: liveChatMessageEvent.id) { [weak self] success in
                guard let self = self,
                      let p = self.pendingMessages[localId],
                      case .sending = p.status else { return }
                if success {
                    // Relay accepted — update visual state to confirmed (checkmark)
                    var confirmed = p
                    confirmed.status = .confirmed
                    self.pendingMessages[localId] = confirmed
                    self.replacePendingItem(localId: localId, with: .pendingMessage(confirmed))
                    // Shorten safety-net timeout — echo-back should arrive quickly now
                    self.schedulePendingTimeout(localId: localId, delay: 15.0)
                }
            }

            // 5. Set timeout for failure detection (30s base, extended to 60s on OK)
            schedulePendingTimeout(localId: localId, delay: 30.0)

            // Input is cleared by TelegramChatInputBar automatically
        } catch {
            print("Failed to send message: \(error)")
        }
    }

    @available(*, deprecated, message: "Use sendMessageWithText instead")
    @objc private func sendMessage() {
        let text = input.textField.text
        guard !text.isEmpty else { return }
        sendMessageWithText(text)
    }

    private func updateLabels() {
        // Update legacy header (for viewer mode)
        header.titleLabel.text = liveStream.title
        header.countLabel.text = "\(liveStream.viewerCount)"
        header.timeLabel.text = liveStream.startedText
        header.liveIcon.backgroundColor = liveStream.isLive ? .systemRed : .systemGray
        
        // Update dashboard (for streamer mode)
        if isStreamerMode {
            dashboardView.configure(
                title: liveStream.title,
                isLive: liveStream.isLive,
                streamStartTime: streamStartTime,
                liveActivitiesEvent: liveActivitiesEvent,
                appState: appState
            )
        }
    }
    
    /// Updates the dashboard with new stream start time (called when going live)
    func updateStreamStartTime(_ startTime: ContinuousClock.Instant?) {
        self.streamStartTime = startTime
        if isStreamerMode {
            dashboardView.configure(
                title: liveStream.title,
                isLive: liveStream.isLive,
                streamStartTime: startTime,
                liveActivitiesEvent: liveActivitiesEvent,
                appState: appState
            )
        }
    }
    
    /// Updates the live activities event and resubscribes chat if the coordinate changed.
    /// Called by ControlPanelViewController when it detects the user's live event has changed.
    func updateLiveActivitiesEvent(_ newEvent: LiveActivitiesEvent) {
        let oldCoordinate = liveActivitiesEvent?.coordinateTag
        let newCoordinate = newEvent.coordinateTag
        
        // Always update the reference (event object may have updated fields even if coordinate is same)
        liveActivitiesEvent = newEvent
        
        // If the coordinate actually changed, we need to tear down and rebuild chat subscriptions
        if oldCoordinate != newCoordinate {
            print("🔄 LiveChatController: Event coordinate changed from \(oldCoordinate ?? "nil") to \(newCoordinate ?? "nil") — resubscribing")
            
            // Unsubscribe from old coordinate's relay subscriptions
            if let appState = appState,
               let oldCoord = oldCoordinate {
                appState.unsubscribeFromLiveChat(forCoordinate: oldCoord)
            }
            
            // Reset local chat state for fresh start
            chatItems.removeAll()
            onChatItemsChanged?(chatItems)
            liveChatMessages.removeAll()
            liveZapReceipts.removeAll()
            seenMessageIds.removeAll()
            seenZapIds.removeAll()
            chatItemIds.removeAll()
            initialLoadComplete = false
            initialLoadTimer?.invalidate()
            initialLoadTimer = nil
            hasMoreItems = true
            mentionCache.removeAll()
            
            // Clear pending items (they belong to the old stream) — Issue 10 fix
            for (_, timer) in pendingTimeouts { timer.invalidate() }
            pendingTimeouts.removeAll()
            pendingMessages.removeAll()
            pendingZaps.removeAll()
            pendingEventIdMap.removeAll()
            
            // Show skeleton again for the new subscription
            isShowingSkeletons = true
            skeletonContainerView.isHidden = false
            skeletonContainerView.alpha = 1
            skeletonViews.forEach { $0.startAnimating() }
            
            commentsTable.reloadData()
            
            // Resubscribe with the new event
            subscribeToLiveChat()
        }
        
        // Update dashboard and zap target regardless
        updateLabels()
        updateZapTarget()
    }
    
    /// Sets the dashboard expanded state (called by parent controllers)
    func setDashboardExpanded(_ expanded: Bool, animated: Bool) {
        // Both streamer and viewer modes now use the dashboard
        dashboardView.setExpanded(expanded, animated: animated)
        
        // Also update legacy header alpha for backward compatibility
        if !isStreamerMode {
            UIView.animate(withDuration: animated ? 0.3 : 0) {
                self.topInfoView.alpha = expanded ? 1 : 0
            }
        }
    }

    // MARK: - Real Data Loading from AppState

    private func subscribeToLiveChat() {
        guard let appState = appState else { return }
        guard let liveActivitiesEvent = liveActivitiesEvent else {
            print("⚠️ No LiveActivitiesEvent - chat subscription skipped")
            // No live event means no chat to load - hide skeleton immediately
            hideSkeletons()
            return
        }
        let coordinates = liveActivitiesEvent.coordinateTag ?? ""

        // Cancel any previous chat-specific subscriptions (for resubscription)
        chatSubscriptionCancellables.removeAll()

        // Subscribe to AppState relay subscription
        appState.subscribeToLiveChat(for: liveActivitiesEvent)
        
        // Load streamer's emoji packs for the emoji picker and sending
        let streamerPubkey = liveActivitiesEvent.pubkey
        appState.emojiPackService?.loadPacks(
            userPubkey: appState.keypair?.publicKey.hex,
            streamerPubkey: streamerPubkey
        )
        
        // Observe EOSE (End of Stored Events) to know when initial load is complete
        // Only hide skeleton on EOSE if there's no data (empty chat)
        // If there is data, let the data arrival code hide it
        appState.$liveChatLoadComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loadedCoordinates in
                guard let self = self else { return }
                if loadedCoordinates.contains(coordinates) {
                    // Only hide if no data arrived - empty chat case
                    let hasMessages = !(appState.liveChatMessagesEvents[coordinates]?.isEmpty ?? true)
                    let hasZaps = !(appState.zapReceiptEvents[coordinates]?.isEmpty ?? true)
                    if !hasMessages && !hasZaps {
                        self.hideSkeletons()
                    }
                }
            }
            .store(in: &chatSubscriptionCancellables)

        // SINGLE COMBINED SINK with debounce for messages, zaps, and raids
        Publishers.CombineLatest3(
            appState.$liveChatMessagesEvents
                .map { $0[coordinates] ?? [] },
            appState.$zapReceiptEvents
                .map { $0[coordinates] ?? [] },
            appState.$raidEvents
                .map { $0[coordinates] ?? [] }
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] (incomingMessages, incomingZaps, incomingRaids) in
            self?.processChatUpdate(messages: incomingMessages, zaps: incomingZaps, raids: incomingRaids)
        }
        .store(in: &chatSubscriptionCancellables)

        // Subscribe to metadata changes (keep existing debounced implementation)
        appState.$metadataEvents
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Use reloadData instead of reloadRows to avoid crash when row count changes
                // This is safer when items are being added/removed concurrently
                guard let visibleIndexPaths = self.commentsTable.indexPathsForVisibleRows,
                      !visibleIndexPaths.isEmpty else { return }
                
                // Validate index paths are still within bounds
                let rowCount = self.chatItems.count
                let validIndexPaths = visibleIndexPaths.filter { $0.row < rowCount }
                
                if validIndexPaths.count == visibleIndexPaths.count {
                    // All index paths valid, safe to reload specific rows
                    self.commentsTable.reloadRows(at: validIndexPaths, with: .none)
                } else {
                    // Row count changed, just reload visible area
                    self.commentsTable.reloadData()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Chat Update Processing
    
    /// Processes incoming messages and zaps efficiently
    /// - During initial phase: rebuilds entire display from all available data
    /// - After initial phase: only adds truly new items (incremental)
    /// - Uses local caches to survive AppState clearing (fixes zap disappearance bug)
    private func processChatUpdate(messages: [LiveChatMessageEvent], zaps: [LightningZapsReceiptEvent], raids: [LiveStreamRaidEvent]) {
        let wasAtBottom = isScrolledNearBottom()
        var pubkeysToFetch = Set<String>()
        
        // Hide skeleton loader once we have data
        if !messages.isEmpty || !zaps.isEmpty || !raids.isEmpty {
            hideSkeletons()
        }
        
        if !initialLoadComplete {
            // During initial load phase, rebuild from all available data
            // This ensures no gaps when messages and zaps arrive in separate batches
            rebuildChatItems(messages: messages, zaps: zaps, raids: raids, pubkeysToFetch: &pubkeysToFetch)
            
            // Only start the timer if we actually have data
            // This prevents marking initial load complete before data arrives
            if !messages.isEmpty || !zaps.isEmpty || !raids.isEmpty {
                // Reset timer - mark complete 300ms after last update WITH data
                initialLoadTimer?.invalidate()
                initialLoadTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    self?.initialLoadComplete = true
                    self?.initialLoadTimer = nil
                    // Start background loading to preload up to maxPreloadItems
                    self?.startBackgroundLoading()
                }
            }
        } else {
            // After initial load, only add truly new items (efficient)
            processIncrementalUpdate(messages: messages, zaps: zaps, raids: raids, pubkeysToFetch: &pubkeysToFetch)
        }
        
        // FETCH METADATA (debounced via scheduleMetadataPull)
        if !pubkeysToFetch.isEmpty {
            pubkeysToPullMetadata.formUnion(pubkeysToFetch)
            scheduleMetadataPull()
        }

        // AUTO-SCROLL if user was at bottom (iMessage behavior)
        if wasAtBottom && !chatItems.isEmpty {
            DispatchQueue.main.async {
                self.scrollToNewestMessage(animated: true)
            }
        }
    }
    
    /// Rebuilds the entire chat display from all available data
    /// Called during initial load phase to ensure no gaps when data arrives in batches
    private func rebuildChatItems(
        messages: [LiveChatMessageEvent],
        zaps: [LightningZapsReceiptEvent],
        raids: [LiveStreamRaidEvent],
        pubkeysToFetch: inout Set<String>
    ) {
        // Combine ALL available items
        var allItems: [LiveChatItem] = []
        allItems.reserveCapacity(messages.count + zaps.count + raids.count)
        
        // Add messages (Kind 1311 - regular chat messages only)
        allItems.append(contentsOf: messages.map { LiveChatItem.message($0) })
        
        // Add zaps
        allItems.append(contentsOf: zaps.map { LiveChatItem.zapReceipt($0) })
        
        // Add raids (Kind 1312 - separate event type)
        allItems.append(contentsOf: raids.map { LiveChatItem.raid($0) })
        
        // Sort ascending (oldest first)
        allItems.sort { $0.createdAt < $1.createdAt }
        
        // Fix 3: Deduplicate current user's retry duplicates (legacy cleanup)
        // Only dedup own messages — other users' messages can't have retry duplicates.
        // Uses a 30-second sliding window to catch retries without suppressing intentional repeats.
        let myPubkey = appState?.keypair?.publicKey.hex
        if let myPubkey = myPubkey {
            var deduped: [LiveChatItem] = []
            deduped.reserveCapacity(allItems.count)
            var recentOwnMessages: [(content: String, timestamp: Int64)] = []
            
            for item in allItems {
                if case .message(let msg) = item, msg.pubkey == myPubkey {
                    let isDuplicate = recentOwnMessages.contains {
                        $0.content == msg.content && abs(msg.createdAt - $0.timestamp) < 30
                    }
                    if isDuplicate { continue }
                    recentOwnMessages.append((content: msg.content, timestamp: msg.createdAt))
                }
                deduped.append(item)
            }
            allItems = deduped
        }
        
        // Take newest initialPageSize items for initial load
        let latestPage = Array(allItems.suffix(initialPageSize))
        
        // Track ALL IDs as seen (prevents re-processing in incremental updates)
        seenMessageIds = Set(messages.map { $0.id })
        seenZapIds = Set(zaps.map { $0.id })
        
        // Update chatItemIds to match displayed items
        chatItemIds = Set(latestPage.map { $0.id })
        
        // Extract to local caches (for liveChatMessages/liveZapReceipts)
        liveChatMessages = latestPage.compactMap { item -> LiveChatMessageEvent? in
            if case .message(let msg) = item { return msg }
            return nil
        }
        liveZapReceipts = latestPage.compactMap { item -> LightningZapsReceiptEvent? in
            if case .zapReceipt(let zap) = item { return zap }
            return nil
        }
        
        // Fix #5: Collect pubkeys for metadata fetch INCLUDING mentioned pubkeys
        for item in latestPage {
            switch item {
            case .message(let msg):
                pubkeysToFetch.insert(msg.pubkey)
                // Extract mentioned pubkeys from message content
                pubkeysToFetch.formUnion(extractMentionedPubkeys(from: msg.content))
            case .raid(let raid):
                pubkeysToFetch.insert(raid.pubkey)
                // Fetch metadata for source and target stream hosts
                // First add the pubkeys from the a tags as fallback
                if let sourceRef = raid.sourceStreamReference {
                    pubkeysToFetch.insert(sourceRef.pubkey)
                }
                if let targetRef = raid.targetStreamReference {
                    pubkeysToFetch.insert(targetRef.pubkey)
                }
                // Also look up the actual host pubkeys from LiveActivitiesEvents (per NIP-53)
                if let appState = appState,
                   let sourceCoord = raid.sourceStreamCoordinate,
                   let sourceEvent = appState.liveActivitiesEvents[sourceCoord]?.first {
                    pubkeysToFetch.insert(sourceEvent.hostPubkeyHex)
                }
                if let appState = appState,
                   let targetCoord = raid.targetStreamCoordinate,
                   let targetEvent = appState.liveActivitiesEvents[targetCoord]?.first {
                    pubkeysToFetch.insert(targetEvent.hostPubkeyHex)
                }
            case .zapReceipt(let zap):
                if let sender = zap.zapSenderPubkey { pubkeysToFetch.insert(sender) }
                if let recipient = zap.recipientPubkey { pubkeysToFetch.insert(recipient) }
                // Extract mentioned pubkeys from zap message
                if let content = zap.description?.content {
                    pubkeysToFetch.formUnion(extractMentionedPubkeys(from: content))
                }
            case .dateSeparator:
                break
            case .pendingMessage, .pendingZap:
                break  // Pending items don't need metadata fetch here
            }
        }
        
        // Insert date separators and sort DESCENDING for flipped table
        chatItems = insertDateSeparators(into: latestPage).sorted { $0.createdAt > $1.createdAt }
        
        // Issue 3 fix: Re-insert active pending items that weren't reconciled
        var pendingToReinsert: [LiveChatItem] = []
        var reconciledPendingIds: [String] = []  // Collect IDs to clean up AFTER iteration
        for (localId, pending) in pendingMessages {
            // Skip if the real event already arrived
            if let eventId = pending.eventId, seenMessageIds.contains(eventId) {
                reconciledPendingIds.append(localId)
                continue
            }
            pendingToReinsert.append(.pendingMessage(pending))
        }
        // Clean up reconciled items AFTER the loop to avoid mutating dictionary during iteration
        for localId in reconciledPendingIds {
            cleanupPendingItem(localId: localId)
        }
        for (_, pending) in pendingZaps {
            pendingToReinsert.append(.pendingZap(pending))
        }
        if !pendingToReinsert.isEmpty {
            for item in pendingToReinsert {
                chatItems.insert(item, at: 0)  // Pending items are newest, go at front
                chatItemIds.insert(item.id)
            }
        }
        
        onChatItemsChanged?(chatItems)
        
        // Update chatItemIds to include date separators
        chatItemIds = Set(chatItems.map { $0.id })
        
        // Full reload (not batch updates during rebuild)
        commentsTable.reloadData()
        
        // Update hasMoreItems - only set to false if we actually have data
        // If allItems is empty, keep hasMoreItems true to allow future loads
        if allItems.isEmpty {
            hasMoreItems = true  // Data might arrive later
        } else {
            hasMoreItems = allItems.count > initialPageSize
        }
    }
    
    /// Processes incremental updates after initial load is complete
    /// Only adds truly new items that haven't been seen before
    private func processIncrementalUpdate(
        messages: [LiveChatMessageEvent],
        zaps: [LightningZapsReceiptEvent],
        raids: [LiveStreamRaidEvent],
        pubkeysToFetch: inout Set<String>
    ) {
        var newItems: [LiveChatItem] = []
        var reconciledLocalIds: [String] = []  // Issue 2 fix: collect for batch cleanup
        
        // Find truly new messages via O(1) Set lookup (Kind 1311 - regular chat messages only)
        let newMessages = messages.filter { !seenMessageIds.contains($0.id) }
        for msg in newMessages {
            seenMessageIds.insert(msg.id)
            liveChatMessages.append(msg)
            
            // Pre-compute emoji map for this message (avoids per-cell iteration of emojiPackCache)
            var emojiMap: [String: URL] = [:]
            for emoji in msg.customEmojis {
                emojiMap[emoji.shortcode] = emoji.imageURL
            }
            if let appState {
                for (sc, url) in appState.emojiPackCache where emojiMap[sc] == nil {
                    emojiMap[sc] = url
                }
            }
            if !emojiMap.isEmpty {
                emojiMapCache[msg.id] = emojiMap
                // Cap cache size
                if emojiMapCache.count > 2000 { emojiMapCache.removeAll() }
            }
            
            // Check if this matches a pending message — reconcile
            if let localId = pendingEventIdMap[msg.id] {
                reconciledLocalIds.append(localId)
            }
            
            newItems.append(LiveChatItem.message(msg))
            pubkeysToFetch.insert(msg.pubkey)
            // Fix #5: Extract mentioned pubkeys from message content
            pubkeysToFetch.formUnion(extractMentionedPubkeys(from: msg.content))
        }
        
        // Find truly new zaps via O(1) Set lookup
        let newZaps = zaps.filter { !seenZapIds.contains($0.id) }
        for zap in newZaps {
            seenZapIds.insert(zap.id)
            liveZapReceipts.append(zap)
            
            // Check if this matches a pending zap — reconcile
            reconcilePendingZap(with: zap, reconciledLocalIds: &reconciledLocalIds)
            
            newItems.append(LiveChatItem.zapReceipt(zap))
            if let sender = zap.zapSenderPubkey { pubkeysToFetch.insert(sender) }
            if let recipient = zap.recipientPubkey { pubkeysToFetch.insert(recipient) }
            // Fix #5: Extract mentioned pubkeys from zap message
            if let content = zap.description?.content {
                pubkeysToFetch.formUnion(extractMentionedPubkeys(from: content))
            }
        }
        
        // Find truly new raids via O(1) Set lookup (Kind 1312 - separate event type)
        // Note: We use seenMessageIds for raids too since they're unique event IDs
        let newRaids = raids.filter { !seenMessageIds.contains($0.id) }
        for raid in newRaids {
            seenMessageIds.insert(raid.id)
            newItems.append(LiveChatItem.raid(raid))
            pubkeysToFetch.insert(raid.pubkey)
            // Fetch metadata for source and target stream hosts
            if let sourceRef = raid.sourceStreamReference {
                pubkeysToFetch.insert(sourceRef.pubkey)
            }
            if let targetRef = raid.targetStreamReference {
                pubkeysToFetch.insert(targetRef.pubkey)
            }
        }
        
        // Issue 2 fix: Remove reconciled pending items AFTER the loop, before inserting real items
        // This avoids double table reload (cleanupPendingItem doesn't call reloadData)
        for localId in reconciledLocalIds {
            cleanupPendingItem(localId: localId)
        }
        
        // Insert new items using efficient merge
        if !newItems.isEmpty {
            insertNewChatItems(newItems)
        }
    }
    
    /// Fix #5: Extracts mentioned pubkeys from content with caching
    /// Uses content hash as cache key to avoid re-parsing
    private func extractMentionedPubkeys(from content: String) -> Set<String> {
        let cacheKey = content.hashValue
        
        if let cached = mentionCache[cacheKey] {
            return cached
        }
        
        let segments = NostrTextParser.parse(content)
        let pubkeys = Set(NostrTextParser.extractPubkeys(from: segments))
        
        // Limit cache size to prevent unbounded growth
        if mentionCache.count > 500 {
            mentionCache.removeAll()
        }
        mentionCache[cacheKey] = pubkeys
        
        return pubkeys
    }
    
    // MARK: - Pending Item Management (Optimistic Display)
    
    func insertPendingMessage(_ pending: PendingChatMessage) {
        pendingMessages[pending.localId] = pending
        if let eventId = pending.eventId {
            pendingEventIdMap[eventId] = pending.localId
        }
        let item = LiveChatItem.pendingMessage(pending)
        insertNewChatItems([item])
    }
    
    func insertPendingZap(_ pending: PendingChatZap) {
        pendingZaps[pending.localId] = pending
        let item = LiveChatItem.pendingZap(pending)
        insertNewChatItems([item])
    }
    
    func markPendingAsFailed(localId: String, error: String) {
        pendingTimeouts[localId]?.invalidate()
        pendingTimeouts.removeValue(forKey: localId)
        
        // Fix 2: Don't mark as failed if the real event already arrived via the subscription.
        // This prevents the false "Timed out" failure when the echo-back was processed
        // but reconciliation didn't clean up the pending item (e.g., during rebuild phase).
        if let msg = pendingMessages[localId],
           let eventId = msg.eventId,
           seenMessageIds.contains(eventId) {
            cleanupPendingItem(localId: localId)
            commentsTable.reloadData()
            return
        }
        
        if var msg = pendingMessages[localId] {
            msg.status = .failed(error: error)
            pendingMessages[localId] = msg
            // Move failed item to top (index 0 = newest in descending table)
            // so the user doesn't have to scroll up to find it in a fast chat
            moveFailedPendingToTop(localId: localId, newItem: .pendingMessage(msg))
        } else if var zap = pendingZaps[localId] {
            zap.status = .failed(error: error)
            pendingZaps[localId] = zap
            moveFailedPendingToTop(localId: localId, newItem: .pendingZap(zap))
        }
    }
    
    /// Moves a failed pending item to the top of chatItems (index 0 = visual bottom / newest)
    /// so the user always sees the failure near the input bar, even in a fast-moving chat.
    private func moveFailedPendingToTop(localId: String, newItem: LiveChatItem) {
        let msgId = "pending-msg-\(localId)"
        let zapId = "pending-zap-\(localId)"
        if let index = chatItems.firstIndex(where: { $0.id == msgId || $0.id == zapId }) {
            chatItems.remove(at: index)
            chatItems.insert(newItem, at: 0)
            commentsTable.reloadData()
            // Scroll to show the failed item if user is near the bottom
            if isScrolledNearBottom() {
                scrollToNewestMessage(animated: true)
            }
        }
    }
    
    /// Removes a pending item and reloads the table. Used for timeout failures and manual removal.
    func removePendingItem(localId: String) {
        pendingTimeouts[localId]?.invalidate()
        pendingTimeouts.removeValue(forKey: localId)
        
        if let msg = pendingMessages.removeValue(forKey: localId) {
            if let eventId = msg.eventId {
                pendingEventIdMap.removeValue(forKey: eventId)
                appState?.pendingEventOKCallbacks.removeValue(forKey: eventId)
            }
        }
        pendingZaps.removeValue(forKey: localId)
        
        let msgId = "pending-msg-\(localId)"
        let zapId = "pending-zap-\(localId)"
        if let index = chatItems.firstIndex(where: { $0.id == msgId || $0.id == zapId }) {
            let removedId = chatItems[index].id
            chatItems.remove(at: index)
            chatItemIds.remove(removedId)
            commentsTable.reloadData()
        }
    }
    
    /// Removes a pending item from tracking and chatItems WITHOUT triggering a table reload.
    /// Used during reconciliation where insertNewChatItems will handle the table update.
    private func cleanupPendingItem(localId: String) {
        pendingTimeouts[localId]?.invalidate()
        pendingTimeouts.removeValue(forKey: localId)
        
        if let msg = pendingMessages.removeValue(forKey: localId) {
            if let eventId = msg.eventId {
                pendingEventIdMap.removeValue(forKey: eventId)
                appState?.pendingEventOKCallbacks.removeValue(forKey: eventId)
            }
        }
        pendingZaps.removeValue(forKey: localId)
        
        let msgId = "pending-msg-\(localId)"
        let zapId = "pending-zap-\(localId)"
        if let index = chatItems.firstIndex(where: { $0.id == msgId || $0.id == zapId }) {
            let removedId = chatItems[index].id
            chatItems.remove(at: index)
            chatItemIds.remove(removedId)
        }
    }
    
    func schedulePendingTimeout(localId: String, delay: TimeInterval) {
        pendingTimeouts[localId]?.invalidate()
        pendingTimeouts[localId] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.markPendingAsFailed(localId: localId, error: "Timed out")
        }
    }
    
    private func replacePendingItem(localId: String, with newItem: LiveChatItem) {
        let msgId = "pending-msg-\(localId)"
        let zapId = "pending-zap-\(localId)"
        if let index = chatItems.firstIndex(where: { $0.id == msgId || $0.id == zapId }) {
            chatItems[index] = newItem
            if let visiblePaths = commentsTable.indexPathsForVisibleRows,
               visiblePaths.contains(IndexPath(row: index, section: 0)) {
                commentsTable.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
        }
    }
    
    /// Matches an incoming zap receipt to a pending zap by sender, amount, and approximate timestamp
    private func reconcilePendingZap(with zapReceipt: LightningZapsReceiptEvent, reconciledLocalIds: inout [String]) {
        let senderPubkey = zapReceipt.zapSenderPubkey ?? ""
        let amount = Int64(zapReceipt.description?.amount ?? 0)
        let receiptTime = zapReceipt.description?.createdAt ?? zapReceipt.createdAt
        
        for (localId, pending) in pendingZaps {
            if pending.senderPubkey == senderPubkey &&
               pending.amount == amount &&
               abs(receiptTime - pending.createdAt) < 60 {
                reconciledLocalIds.append(localId)
                break
            }
        }
    }
    
    // MARK: - Retry Logic
    
    func retryPendingMessage(localId: String) {
        guard let pending = pendingMessages[localId],
              let appState = appState,
              let keypair = appState.keypair,
              let liveActivitiesEvent = liveActivitiesEvent,
              let identifier = liveActivitiesEvent.identifier else { return }
        
        // Update status to sending
        var updated = pending
        updated.status = .sending
        pendingMessages[localId] = updated
        replacePendingItem(localId: localId, with: .pendingMessage(updated))
        
        do {
            let event = try liveChatMessageEvent(
                content: pending.content,
                liveEventPubKey: liveActivitiesEvent.pubkey,
                d: identifier,
                relay: "wss://relay.damus.io",
                signedBy: keypair
            )
            
            // Update event ID mapping (new event ID after re-signing — Issue 9)
            // Fix: Also insert old event ID into seenMessageIds so that if the original
            // event echoes back from the relay, it's filtered out and doesn't create a duplicate.
            if let oldEventId = pending.eventId {
                pendingEventIdMap.removeValue(forKey: oldEventId)
                seenMessageIds.insert(oldEventId)
            }
            var retryPending = updated
            retryPending.eventId = event.id
            pendingMessages[localId] = retryPending
            pendingEventIdMap[event.id] = localId
            
            appState.publishEventToAllRelays(event)
            
            // Register OK confirmation callback — relay accepted the event
            appState.registerPendingConfirmation(eventId: event.id) { [weak self] success in
                guard let self = self,
                      let p = self.pendingMessages[localId],
                      case .sending = p.status else { return }
                if success {
                    var confirmed = p
                    confirmed.status = .confirmed
                    self.pendingMessages[localId] = confirmed
                    self.replacePendingItem(localId: localId, with: .pendingMessage(confirmed))
                    self.schedulePendingTimeout(localId: localId, delay: 15.0)
                }
            }
            
            schedulePendingTimeout(localId: localId, delay: 30.0)
        } catch {
            markPendingAsFailed(localId: localId, error: "Retry failed")
        }
    }
    
    func retryPendingZap(localId: String) {
        guard let pending = pendingZaps[localId] else { return }
        
        // Remove the failed pending item and re-send
        removePendingItem(localId: localId)
        sendZap(amount: pending.amount, message: pending.content)
    }
    
    /// Inserts date separator labels between items from different days
    /// Items should be sorted ASCENDING (oldest first) before calling this
    private func insertDateSeparators(into items: [LiveChatItem]) -> [LiveChatItem] {
        guard !items.isEmpty else { return items }
        
        var result: [LiveChatItem] = []
        result.reserveCapacity(items.count + 10)  // Estimate ~10 days max
        
        let calendar = Calendar.current
        var lastDate: Date?
        var daysFound: Set<String> = []
        let debugFormatter = DateFormatter()
        debugFormatter.dateFormat = "yyyy-MM-dd"
        
        print("📅 insertDateSeparators: Processing \(items.count) items")
        
        for item in items {
            // Skip existing date separators
            if case .dateSeparator = item { continue }
            
            let itemDate = Date(timeIntervalSince1970: TimeInterval(item.createdAt))
            let itemDay = calendar.startOfDay(for: itemDate)
            let dayString = debugFormatter.string(from: itemDay)
            
            // Track unique days for debugging
            if !daysFound.contains(dayString) {
                daysFound.insert(dayString)
                print("📅 Found new day: \(dayString) (timestamp: \(item.createdAt))")
            }
            
            // Insert separator if this is a new day
            if let last = lastDate, !calendar.isDate(itemDay, inSameDayAs: last) {
                result.append(.dateSeparator(itemDay))
                print("📅 Inserted separator for: \(dayString)")
            } else if lastDate == nil {
                // First item - add separator for its day
                result.append(.dateSeparator(itemDay))
                print("📅 Inserted FIRST separator for: \(dayString)")
            }
            
            result.append(item)
            lastDate = itemDay
        }
        
        print("📅 Total days found: \(daysFound.sorted())")
        print("📅 Result has \(result.count) items (original: \(items.count))")
        
        return result
    }
    
    /// Inserts date separators for paginated items, considering existing items
    /// Items should be sorted ASCENDING (oldest first)
    private func insertDateSeparatorsForPagination(_ newItems: [LiveChatItem], existingItems: [LiveChatItem]) -> [LiveChatItem] {
        guard !newItems.isEmpty else { return newItems }
        
        var result: [LiveChatItem] = []
        result.reserveCapacity(newItems.count + 10)
        
        let calendar = Calendar.current
        var lastDate: Date?
        
        // Find the oldest existing item's date (existingItems is DESCENDING, so last is oldest)
        let oldestExistingDate: Date? = existingItems.last.flatMap { item -> Date? in
            if case .dateSeparator = item { return nil }
            return Date(timeIntervalSince1970: TimeInterval(item.createdAt))
        }
        
        for item in newItems {
            if case .dateSeparator = item { continue }
            
            let itemDate = Date(timeIntervalSince1970: TimeInterval(item.createdAt))
            let itemDay = calendar.startOfDay(for: itemDate)
            
            // Insert separator if this is a new day compared to previous item in this batch
            if let last = lastDate, !calendar.isDate(itemDay, inSameDayAs: last) {
                result.append(.dateSeparator(itemDay))
            } else if lastDate == nil {
                // First item in batch - check if it's a different day than oldest existing
                if let existingDate = oldestExistingDate {
                    let existingDay = calendar.startOfDay(for: existingDate)
                    if !calendar.isDate(itemDay, inSameDayAs: existingDay) {
                        result.append(.dateSeparator(itemDay))
                    }
                } else {
                    // No existing items, add separator
                    result.append(.dateSeparator(itemDay))
                }
            }
            
            result.append(item)
            lastDate = itemDay
        }
        
        return result
    }
    
    // MARK: - Efficient Table Updates
    
    /// Inserts new chat items efficiently using merge sort
    /// - chatItems is sorted DESCENDING (newest first, row 0 = visual bottom)
    /// - New items are merged at correct positions to maintain sort order
    /// - Fix #3: Uses performBatchUpdates for small insertions, reloadData for large batches
    ///
    /// CRITICAL: IndexPaths must be calculated relative to the FINAL merged array state.
    /// The merge algorithm guarantees UITableView consistency:
    /// oldCount + insertedCount = newCount
    private func insertNewChatItems(_ newItems: [LiveChatItem]) {
        guard !newItems.isEmpty else { return }
        
        // STEP 1: Deduplicate newItems (remove duplicates within the array itself)
        var seenInBatch = Set<String>()
        let dedupedNewItems = newItems.filter { item in
            if seenInBatch.contains(item.id) {
                return false
            }
            seenInBatch.insert(item.id)
            return true
        }
        
        // STEP 2: Filter out items already in chatItems using O(1) Set lookup
        let uniqueNewItems = dedupedNewItems.filter { !chatItemIds.contains($0.id) }
        
        guard !uniqueNewItems.isEmpty else { return }
        
        // STEP 3: Sort new items by createdAt DESCENDING (same as chatItems)
        let sortedNewItems = uniqueNewItems.sorted { $0.createdAt > $1.createdAt }
        
        // STEP 4: Merge the two sorted arrays and track insert positions
        // This gives us IndexPaths relative to the FINAL merged array
        var mergedItems: [LiveChatItem] = []
        mergedItems.reserveCapacity(chatItems.count + sortedNewItems.count)
        var insertedIndexPaths: [IndexPath] = []
        insertedIndexPaths.reserveCapacity(sortedNewItems.count)
        
        var oldIndex = 0
        var newIndex = 0
        var mergedIndex = 0
        
        while oldIndex < chatItems.count || newIndex < sortedNewItems.count {
            if oldIndex >= chatItems.count {
                // No more old items, append remaining new items
                mergedItems.append(sortedNewItems[newIndex])
                insertedIndexPaths.append(IndexPath(row: mergedIndex, section: 0))
                newIndex += 1
            } else if newIndex >= sortedNewItems.count {
                // No more new items, append remaining old items
                mergedItems.append(chatItems[oldIndex])
                oldIndex += 1
            } else {
                // Compare timestamps (DESCENDING order)
                let oldItem = chatItems[oldIndex]
                let newItem = sortedNewItems[newIndex]
                
                if newItem.createdAt >= oldItem.createdAt {
                    // New item is newer or same time, insert it first
                    mergedItems.append(newItem)
                    insertedIndexPaths.append(IndexPath(row: mergedIndex, section: 0))
                    newIndex += 1
                } else {
                    // Old item is newer, keep it
                    mergedItems.append(oldItem)
                    oldIndex += 1
                }
            }
            mergedIndex += 1
        }
        
        // STEP 5: Verify consistency before updating
        // UITableView requires: oldCount + insertedCount = newCount
        let oldCount = chatItems.count
        let insertedCount = insertedIndexPaths.count
        let newCount = mergedItems.count
        
        guard oldCount + insertedCount == newCount else {
            // Fallback to full reload to avoid crash
            chatItems = mergedItems
            onChatItemsChanged?(chatItems)
            // CRITICAL: Also update chatItemIds to stay in sync
            for item in uniqueNewItems {
                chatItemIds.insert(item.id)
            }
            commentsTable.reloadData()
            return
        }
        
        // STEP 6: Update data source BEFORE table updates
        let wasAtBottom = isScrolledNearBottom()
        chatItems = mergedItems
        onChatItemsChanged?(chatItems)
        
        // STEP 6.5: Update chatItemIds Set to stay in sync
        for item in uniqueNewItems {
            chatItemIds.insert(item.id)
        }
        
        // Fix #3: Use batch updates for small insertions, full reload for large batches
        // Batch updates provide smooth animations but can be problematic with flipped tables
        // for large insertions or insertions at row 0 (visual bottom)
        let hasRow0Insertion = insertedIndexPaths.contains { $0.row == 0 }
        let shouldUseBatchUpdates = insertedCount <= 3 && !hasRow0Insertion && oldCount > 0
        
        if shouldUseBatchUpdates {
            // Use batch updates for smooth animation
            commentsTable.performBatchUpdates({
                self.commentsTable.insertRows(at: insertedIndexPaths, with: .fade)
            }, completion: { [weak self] _ in
                // Scroll to bottom if user was there
                if wasAtBottom {
                    self?.scrollToNewestMessage(animated: true)
                }
            })
        } else {
            // For large batches or row 0 insertions, use full reload
            commentsTable.reloadData()
            if wasAtBottom {
                scrollToNewestMessage(animated: false)
            }
        }
    }

    private func scheduleMetadataPull() {
        guard let appState = appState else { return }

        // Cancel previous scheduled call
        metadataPullCancellable?.cancel()

        // Schedule after 0.5s of inactivity
        metadataPullCancellable = Just(())
            .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let pubkeysArray = Array(self.pubkeysToPullMetadata)
                appState.pullMissingEventsFromPubkeysAndFollows(pubkeysArray)
                self.pubkeysToPullMetadata.removeAll()
            }
    }

    // MARK: - Time-Based Pagination
    
    /// Loads older items (messages AND zaps) when user scrolls to see history
    /// Uses TIME-BASED pagination to ensure temporal consistency
    /// - Finds the oldest visible timestamp
    /// - Loads items older than that timestamp from BOTH sources
    /// - Ensures no temporal gaps in the interleaved display
    private func loadMoreItems() {
        guard let appState = appState,
              let liveActivitiesEvent = liveActivitiesEvent,
              let coordinates = liveActivitiesEvent.coordinateTag,
              !isLoadingPage,
              hasMoreItems
        else { return }
        
        isLoadingPage = true
        
        // Find the OLDEST item currently displayed (last in chatItems since DESCENDING)
        guard let oldestItem = chatItems.last else {
            isLoadingPage = false
            return
        }
        let oldestTimestamp = oldestItem.createdAt
        
        // Get all available data from AppState
        let allMessages = appState.liveChatMessagesEvents[coordinates] ?? []
        let allZaps = appState.zapReceiptEvents[coordinates] ?? []
        let allRaids = appState.raidEvents[coordinates] ?? []
        
        // Find messages older than our oldest visible timestamp (and not already in table)
        // Use chatItemIds (not seenMessageIds) because seenMessageIds tracks ALL processed messages
        let olderMessages = allMessages.filter { 
            $0.createdAt < oldestTimestamp && !chatItemIds.contains($0.id)
        }
        
        // Find zaps older than our oldest visible timestamp (and not already in table)
        let olderZaps = allZaps.filter { 
            $0.createdAt < oldestTimestamp && !chatItemIds.contains($0.id)
        }
        
        // Find raids older than our oldest visible timestamp (and not already in table)
        let olderRaids = allRaids.filter {
            $0.createdAt < oldestTimestamp && !chatItemIds.contains("raid-\($0.id)")
        }
        
        // Combine into LiveChatItems and sort ASCENDING (oldest first) for date separator insertion
        var olderItems: [LiveChatItem] = []
        olderItems.append(contentsOf: olderMessages.map { LiveChatItem.message($0) })
        olderItems.append(contentsOf: olderZaps.map { LiveChatItem.zapReceipt($0) })
        olderItems.append(contentsOf: olderRaids.map { LiveChatItem.raid($0) })
        olderItems.sort { $0.createdAt < $1.createdAt }  // ASCENDING for date separators
        
        // Take only pageSize items (the oldest items first, then reverse for display)
        let pageToLoadRaw = Array(olderItems.suffix(pageSize))  // Get newest of the older items
        
        guard !pageToLoadRaw.isEmpty else {
            hasMoreItems = false
            isLoadingPage = false
            return
        }
        
        // Insert date separators into the page
        let pageWithSeparators = insertDateSeparatorsForPagination(pageToLoadRaw, existingItems: chatItems)
        
        // Update local caches (for liveChatMessages/liveZapReceipts arrays)
        var pubkeysToFetch = Set<String>()
        
        for item in pageToLoadRaw {
            switch item {
            case .message(let msg):
                liveChatMessages.insert(msg, at: 0)  // Older items go at beginning
                pubkeysToFetch.insert(msg.pubkey)
                
            case .raid(let raid):
                // Raids are separate events, fetch metadata for source/target hosts
                pubkeysToFetch.insert(raid.pubkey)
                if let sourceRef = raid.sourceStreamReference {
                    pubkeysToFetch.insert(sourceRef.pubkey)
                }
                if let targetRef = raid.targetStreamReference {
                    pubkeysToFetch.insert(targetRef.pubkey)
                }
                // Also look up the actual host pubkeys from LiveActivitiesEvents (per NIP-53)
                if let sourceCoord = raid.sourceStreamCoordinate,
                   let sourceEvent = appState.liveActivitiesEvents[sourceCoord]?.first {
                    pubkeysToFetch.insert(sourceEvent.hostPubkeyHex)
                }
                if let targetCoord = raid.targetStreamCoordinate,
                   let targetEvent = appState.liveActivitiesEvents[targetCoord]?.first {
                    pubkeysToFetch.insert(targetEvent.hostPubkeyHex)
                }
                
            case .zapReceipt(let zap):
                liveZapReceipts.insert(zap, at: 0)
                if let sender = zap.zapSenderPubkey { pubkeysToFetch.insert(sender) }
                if let recipient = zap.recipientPubkey { pubkeysToFetch.insert(recipient) }
                
            case .dateSeparator:
                break  // Date separators don't need cache updates
            case .pendingMessage, .pendingZap:
                break  // Pending items won't appear in pagination
            }
        }
        
        // Insert items with separators (this updates chatItemIds)
        insertNewChatItems(pageWithSeparators)
        
        // THEN check if there are more items to load (items older than what we just loaded)
        // Must be done AFTER insertNewChatItems so chatItemIds is up to date
        if let oldestLoaded = pageToLoadRaw.first {  // First item is oldest (sorted ascending)
            let oldestLoadedTimestamp = oldestLoaded.createdAt
            let remainingMessages = allMessages.contains { $0.createdAt < oldestLoadedTimestamp && !chatItemIds.contains($0.id) }
            let remainingZaps = allZaps.contains { $0.createdAt < oldestLoadedTimestamp && !chatItemIds.contains($0.id) }
            hasMoreItems = remainingMessages || remainingZaps
        } else {
            hasMoreItems = false
        }
        
        // Fetch metadata for new pubkeys
        if !pubkeysToFetch.isEmpty {
            pubkeysToPullMetadata.formUnion(pubkeysToFetch)
            scheduleMetadataPull()
        }
        
        isLoadingPage = false
    }
    
    // MARK: - Background Preloading
    
    /// Starts background loading to preload items up to maxPreloadItems (1000)
    /// Called after initial load completes to ensure smooth scrolling experience
    private func startBackgroundLoading() {
        guard !isBackgroundLoading,
              hasMoreItems,
              chatItems.count < maxPreloadItems
        else { return }
        
        isBackgroundLoading = true
        loadMoreItemsInBackground()
    }
    
    /// Loads more items in background without blocking UI
    /// Continues until maxPreloadItems reached or no more items available
    private func loadMoreItemsInBackground() {
        guard let appState = appState,
              let liveActivitiesEvent = liveActivitiesEvent,
              let coordinates = liveActivitiesEvent.coordinateTag,
              hasMoreItems,
              chatItems.count < maxPreloadItems
        else {
            isBackgroundLoading = false
            return
        }
        
        // Find the OLDEST item currently displayed
        guard let oldestItem = chatItems.last else {
            isBackgroundLoading = false
            return
        }
        let oldestTimestamp = oldestItem.createdAt
        
        // Get all available data from AppState
        let allMessages = appState.liveChatMessagesEvents[coordinates] ?? []
        let allZaps = appState.zapReceiptEvents[coordinates] ?? []
        let allRaids = appState.raidEvents[coordinates] ?? []
        
        // Find older items not already loaded
        let olderMessages = allMessages.filter { 
            $0.createdAt < oldestTimestamp && !chatItemIds.contains($0.id)
        }
        let olderZaps = allZaps.filter { 
            $0.createdAt < oldestTimestamp && !chatItemIds.contains($0.id)
        }
        let olderRaids = allRaids.filter {
            $0.createdAt < oldestTimestamp && !chatItemIds.contains("raid-\($0.id)")
        }
        
        // Combine and sort
        var olderItems: [LiveChatItem] = []
        olderItems.append(contentsOf: olderMessages.map { LiveChatItem.message($0) })
        olderItems.append(contentsOf: olderZaps.map { LiveChatItem.zapReceipt($0) })
        olderItems.append(contentsOf: olderRaids.map { LiveChatItem.raid($0) })
        olderItems.sort { $0.createdAt < $1.createdAt }  // ASCENDING for date separators
        
        // Calculate how many more we can load (respect maxPreloadItems limit)
        let remainingCapacity = maxPreloadItems - chatItems.count
        let batchSize = min(pageSize, remainingCapacity)
        let pageToLoadRaw = Array(olderItems.suffix(batchSize))  // Get newest of the older items
        
        guard !pageToLoadRaw.isEmpty else {
            hasMoreItems = false
            isBackgroundLoading = false
            return
        }
        
        // Insert date separators
        let pageWithSeparators = insertDateSeparatorsForPagination(pageToLoadRaw, existingItems: chatItems)
        
        // Update local caches
        var pubkeysToFetch = Set<String>()
        for item in pageToLoadRaw {
            switch item {
            case .message(let msg):
                liveChatMessages.insert(msg, at: 0)
                pubkeysToFetch.insert(msg.pubkey)
            case .raid(let raid):
                // Raids are separate events, fetch metadata for source/target hosts
                pubkeysToFetch.insert(raid.pubkey)
                if let sourceRef = raid.sourceStreamReference {
                    pubkeysToFetch.insert(sourceRef.pubkey)
                }
                if let targetRef = raid.targetStreamReference {
                    pubkeysToFetch.insert(targetRef.pubkey)
                }
                // Also look up the actual host pubkeys from LiveActivitiesEvents (per NIP-53)
                if let sourceCoord = raid.sourceStreamCoordinate,
                   let sourceEvent = appState.liveActivitiesEvents[sourceCoord]?.first {
                    pubkeysToFetch.insert(sourceEvent.hostPubkeyHex)
                }
                if let targetCoord = raid.targetStreamCoordinate,
                   let targetEvent = appState.liveActivitiesEvents[targetCoord]?.first {
                    pubkeysToFetch.insert(targetEvent.hostPubkeyHex)
                }
            case .zapReceipt(let zap):
                liveZapReceipts.insert(zap, at: 0)
                if let sender = zap.zapSenderPubkey { pubkeysToFetch.insert(sender) }
                if let recipient = zap.recipientPubkey { pubkeysToFetch.insert(recipient) }
            case .dateSeparator:
                break  // Date separators don't need cache updates
            case .pendingMessage, .pendingZap:
                break  // Pending items won't appear in background loading
            }
        }
        
        // Insert items with separators (updates chatItemIds)
        insertNewChatItems(pageWithSeparators)
        
        // Update hasMoreItems
        if let oldestLoaded = pageToLoadRaw.first {  // First is oldest (sorted ascending)
            let oldestLoadedTimestamp = oldestLoaded.createdAt
            let remainingMessages = allMessages.contains { $0.createdAt < oldestLoadedTimestamp && !chatItemIds.contains($0.id) }
            let remainingZaps = allZaps.contains { $0.createdAt < oldestLoadedTimestamp && !chatItemIds.contains($0.id) }
            let remainingRaids = allRaids.contains { $0.createdAt < oldestLoadedTimestamp && !chatItemIds.contains("raid-\($0.id)") }
            hasMoreItems = remainingMessages || remainingZaps || remainingRaids
        } else {
            hasMoreItems = false
        }
        
        // Fetch metadata
        if !pubkeysToFetch.isEmpty {
            pubkeysToPullMetadata.formUnion(pubkeysToFetch)
            scheduleMetadataPull()
        }
        
        // Continue loading if more items available and under limit
        if hasMoreItems && chatItems.count < maxPreloadItems {
            // Small delay to avoid blocking main thread
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.loadMoreItemsInBackground()
            }
        } else {
            isBackgroundLoading = false
        }
    }
}

extension LiveChatController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging, chatItems.count > 20 else { return }

        let offset = scrollView.contentOffset.y
        
        // Support both GenericLivePlayerController and ControlPanelViewController
        videoController?.chatControllerRequestMiniPlayer(offset > 10)
        miniPlayerController?.chatControllerRequestMiniPlayer(offset > 10)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Pause animated emotes during scroll for performance
        for cell in commentsTable.visibleCells {
            if let msgCell = cell as? LiveChatMessageCell {
                msgCell.emoteAnimationsPaused = true
            }
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { resumeEmoteAnimations() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        resumeEmoteAnimations()
    }

    private func resumeEmoteAnimations() {
        for cell in commentsTable.visibleCells {
            if let msgCell = cell as? LiveChatMessageCell {
                msgCell.emoteAnimationsPaused = false
            }
        }
    }

    func tableView(
        _ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath
    ) {
        // Trigger pagination when reaching the visual TOP (oldest messages)
        // For flipped table: high row index = visual top = oldest
        let threshold = chatItems.count - 5  // Load more when 5 items from oldest
        
        if indexPath.row >= threshold, !isLoadingPage, hasMoreItems {
            loadMoreItems()
        }
    }
}

extension LiveChatController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chatItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let appState = appState else {
            return tableView.dequeueReusableCell(withIdentifier: "messageCell", for: indexPath)
        }

        let item = chatItems[indexPath.row]

        switch item {
        case .zapReceipt(let zapReceipt):
            let cell =
                tableView.dequeueReusableCell(withIdentifier: "zapCell", for: indexPath)
                as! LiveChatZapCell
            cell.configure(with: zapReceipt, appState: appState)
            cell.onProfileTap = { [weak self] pubkeyHex in
                self?.handleProfileTap(pubkeyHex: pubkeyHex)
            }
            return cell

        case .message(let message):
            let cell =
                tableView.dequeueReusableCell(withIdentifier: "messageCell", for: indexPath)
                as! LiveChatMessageCell
            cell.configure(with: message, appState: appState)
            cell.onProfileTap = { [weak self] pubkeyHex in
                self?.handleProfileTap(pubkeyHex: pubkeyHex)
            }
            // Handle @mention taps in message text
            cell.onMentionTap = { [weak self] pubkeyHex in
                self?.handleProfileTap(pubkeyHex: pubkeyHex)
            }
            return cell
            
        case .raid(let raid):
            let cell =
                tableView.dequeueReusableCell(withIdentifier: "raidCell", for: indexPath)
                as! LiveChatRaidCell
            // Pass current stream coordinate so cell can determine raid direction
            let currentCoordinate = liveActivitiesEvent?.coordinateTag
            cell.configure(with: raid, appState: appState, currentStreamCoordinate: currentCoordinate)
            cell.onProfileTap = { [weak self] pubkeyHex in
                self?.handleProfileTap(pubkeyHex: pubkeyHex)
            }
            cell.onJoinRaid = { [weak self] targetCoordinate in
                self?.handleJoinRaid(targetStreamCoordinate: targetCoordinate)
            }
            return cell
            
        case .dateSeparator(let date):
            let cell =
                tableView.dequeueReusableCell(withIdentifier: "dateSeparatorCell", for: indexPath)
                as! DateSeparatorCell
            cell.configure(with: date)
            return cell
            
        case .pendingMessage(let pending):
            let cell = tableView.dequeueReusableCell(withIdentifier: "messageCell", for: indexPath)
                as! LiveChatMessageCell
            cell.configurePending(with: pending, appState: appState)
            cell.onRetryTap = { [weak self] in
                self?.retryPendingMessage(localId: pending.localId)
            }
            return cell
            
        case .pendingZap(let pending):
            let cell = tableView.dequeueReusableCell(withIdentifier: "zapCell", for: indexPath)
                as! LiveChatZapCell
            cell.configurePending(with: pending, appState: appState)
            cell.onRetryTap = { [weak self] in
                self?.retryPendingZap(localId: pending.localId)
            }
            return cell
        }
    }
    
    /// Handles profile tap from chat cells - minimizes player and navigates to profile
    private func handleProfileTap(pubkeyHex: String) {
        print("📱 handleProfileTap called with pubkey: \(pubkeyHex.prefix(16))...")
        
        guard let appState = appState else {
            print("📱 ❌ No appState available")
            return
        }
        
        // Don't navigate to own profile
        guard pubkeyHex != appState.publicKey?.hex else {
            print("📱 ❌ Tapped own profile, ignoring")
            return
        }
        
        print("📱 ✅ Proceeding with profile navigation")
        
        // Dismiss keyboard first
        view.endEditing(true)
        
        // Request mini player mode (minimize the video)
        miniPlayerController?.chatControllerRequestMiniPlayer(true)
        
        // Dismiss the player and navigate to profile
        if let playerController = videoController {
            print("📱 Dismissing video controller and navigating...")
            playerController.dismiss(animated: true) { [weak self] in
                self?.navigateToProfile(pubkeyHex: pubkeyHex)
            }
        } else {
            // If no video controller (e.g., camera streaming chat), just navigate
            print("📱 No video controller, navigating directly...")
            navigateToProfile(pubkeyHex: pubkeyHex)
        }
    }
    
    /// Handles "Join Raid" button tap - navigates to the target stream
    /// - Parameter targetStreamCoordinate: The event coordinate of the target stream (e.g., "30311:pubkey:identifier")
    private func handleJoinRaid(targetStreamCoordinate: String) {
        print("🌊 handleJoinRaid called for coordinate: \(targetStreamCoordinate)")
        
        guard let appState = appState else {
            print("🌊 ❌ No appState available")
            return
        }
        
        // Parse the coordinate to extract pubkey and identifier
        // Format: "30311:pubkey:identifier"
        let components = targetStreamCoordinate.split(separator: ":")
        guard components.count >= 3 else {
            print("🌊 ❌ Invalid stream coordinate format")
            return
        }
        
        let targetPubkey = String(components[1])
        let targetIdentifier = String(components[2])
        
        // Find the target stream in liveActivitiesEvents by matching coordinate
        let targetStream = appState.getAllEvents().first { event in
            // Match by pubkey and d-tag identifier
            event.pubkey == targetPubkey && event.identifier == targetIdentifier
        }
        
        guard let targetStream = targetStream else {
            print("🌊 ❌ Could not find stream for coordinate: \(targetStreamCoordinate)")
            // Could show an alert here
            return
        }
        
        print("🌊 ✅ Found target stream: \(targetStream.title ?? "Untitled")")
        
        // Dismiss keyboard
        view.endEditing(true)
        
        // Dismiss current player and open target stream
        if let playerController = videoController {
            playerController.dismiss(animated: true) { [weak self] in
                self?.navigateToStream(targetStream)
            }
        } else {
            navigateToStream(targetStream)
        }
    }
    
    /// Navigates to a live stream
    private func navigateToStream(_ event: LiveActivitiesEvent) {
        guard let appState = appState else { return }
        
        // Create LiveStream from LiveActivitiesEvent using the extension method
        let liveStream = event.toLiveStream()
        
        // Find the root view controller
        let rootVC = RootViewController.instance
        
        // Present the new stream player
        let playerVC = GenericLivePlayerController(
            liveStream: liveStream,
            liveActivitiesEvent: event,
            appState: appState
        )
        playerVC.modalPresentationStyle = .fullScreen
        
        // Small delay to ensure dismiss animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            rootVC.present(playerVC, animated: true)
        }
    }
    
    /// Navigates to a profile by finding the tab bar controller and pushing
    private func navigateToProfile(pubkeyHex: String) {
        guard let appState = appState else { return }
        
        // Find the root view controller and navigate
        let rootVC = RootViewController.instance
        
        // Find the tab bar controller in the hierarchy
        func findTabBarController(in vc: UIViewController) -> UITabBarController? {
            if let tabBar = vc as? UITabBarController {
                return tabBar
            }
            for child in vc.children {
                if let found = findTabBarController(in: child) {
                    return found
                }
            }
            if let presented = vc.presentedViewController {
                return findTabBarController(in: presented)
            }
            return nil
        }
        
        // Get the tab bar controller
        guard let tabBarController = findTabBarController(in: rootVC) else {
            print("⚠️ Could not find tab bar controller for profile navigation")
            return
        }
        
        // Get the home tab's navigation controller (index 1: [wallet, home, profile])
        guard tabBarController.viewControllers?.count ?? 0 > 1,
              let homeNav = tabBarController.viewControllers?[1] as? UINavigationController else {
            print("⚠️ Home tab is not wrapped in UINavigationController")
            return
        }
        
        // Switch to home tab (index 1)
        tabBarController.selectedIndex = 1
        
        // Create and push the profile view controller
        let profileVC = ProfileViewController(appState: appState, publicKeyHex: pubkeyHex)
        profileVC.showBackButton = true
        
        // Small delay to ensure tab switch animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            homeNav.pushViewController(profileVC, animated: true)
        }
    }
}

// MARK: - UITextViewDelegate

extension LiveChatController: UITextViewDelegate {
    // Add any text view delegate methods if needed in the future
}

// MARK: - UIGestureRecognizerDelegate

extension LiveChatController {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow tap gesture to work alongside scroll/pan gestures
        // This preserves the interactive keyboard dismissal while adding tap-to-dismiss
        return true
    }
}

// MARK: - Chat Skeleton Row View

/// A skeleton loading row that mimics a chat message layout
final class ChatSkeletonRowView: UIView {
    
    private let avatarSkeleton = SkeletonView()
    private let nameSkeleton = SkeletonView()
    private let messageSkeleton = SkeletonView()
    
    private let messageWidthRatio: CGFloat
    
    init(messageWidthRatio: CGFloat = 0.7) {
        self.messageWidthRatio = messageWidthRatio
        super.init(frame: .zero)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        self.messageWidthRatio = 0.7
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // Avatar skeleton (circular)
        avatarSkeleton.layer.cornerRadius = 12
        avatarSkeleton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarSkeleton)
        
        // Name skeleton
        nameSkeleton.layer.cornerRadius = 4
        nameSkeleton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameSkeleton)
        
        // Message skeleton
        messageSkeleton.layer.cornerRadius = 4
        messageSkeleton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageSkeleton)
        
        NSLayoutConstraint.activate([
            // Avatar - 24x24 circle on the left
            avatarSkeleton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            avatarSkeleton.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            avatarSkeleton.widthAnchor.constraint(equalToConstant: 24),
            avatarSkeleton.heightAnchor.constraint(equalToConstant: 24),
            
            // Name - next to avatar
            nameSkeleton.leadingAnchor.constraint(equalTo: avatarSkeleton.trailingAnchor, constant: 8),
            nameSkeleton.centerYAnchor.constraint(equalTo: avatarSkeleton.centerYAnchor),
            nameSkeleton.widthAnchor.constraint(equalToConstant: 80),
            nameSkeleton.heightAnchor.constraint(equalToConstant: 14),
            
            // Message - below name, variable width
            messageSkeleton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 52),
            messageSkeleton.topAnchor.constraint(equalTo: nameSkeleton.bottomAnchor, constant: 6),
            messageSkeleton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            messageSkeleton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: messageWidthRatio, constant: -72),
            messageSkeleton.heightAnchor.constraint(equalToConstant: 14),
            messageSkeleton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }
    
    func startAnimating() {
        avatarSkeleton.startAnimating()
        nameSkeleton.startAnimating()
        messageSkeleton.startAnimating()
    }
    
    func stopAnimating() {
        avatarSkeleton.stopAnimating()
        nameSkeleton.stopAnimating()
        messageSkeleton.stopAnimating()
    }
}


// MARK: - Date Separator Cell

/// A simple cell that displays a date label centered in the chat
final class DateSeparatorCell: UITableViewCell {
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
        view.layer.cornerRadius = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .systemBackground
        
        // Flip for rotated table
        transform = CGAffineTransform(rotationAngle: .pi)
        
        contentView.addSubview(containerView)
        containerView.addSubview(dateLabel)
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            dateLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            dateLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
            dateLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
        ])
    }
    
    func configure(with date: Date) {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            dateLabel.text = "Today"
        } else if calendar.isDateInYesterday(date) {
            dateLabel.text = "Yesterday"
        } else {
            dateLabel.text = Self.dateFormatter.string(from: date)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        dateLabel.text = nil
    }
}
