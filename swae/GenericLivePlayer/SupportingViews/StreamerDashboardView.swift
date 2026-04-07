//
//  StreamerDashboardView.swift
//  swae
//
//  Streamer Admin Dashboard - shows stream stats, top zappers, and activity metrics
//  Supports compact (single line) and expanded (full dashboard) modes
//

import Combine
import Kingfisher
import NostrSDK
import UIKit

// MARK: - Zapper Info Model

struct ZapperInfo {
    let pubkey: String
    let displayName: String
    let profilePicURL: URL?
    let totalSats: Int64
}

// MARK: - Dashboard State

enum DashboardState {
    case compact
    case expanded
    case dragging(progress: CGFloat)
}

// MARK: - Dashboard Mode

enum DashboardMode {
    case streamer  // Shows activity metrics, no profile pic (user is streaming)
    case viewer    // Shows streamer profile pic + follow button (watching someone else)
}

// MARK: - StreamerDashboardView

class StreamerDashboardView: UIView {
    
    // MARK: - State
    
    private(set) var currentState: DashboardState = .compact
    private var animator: UIViewPropertyAnimator?
    
    /// Dashboard mode - streamer (broadcasting) or viewer (watching)
    var mode: DashboardMode = .streamer {
        didSet { updateForMode() }
    }
    
    // MARK: - Data
    
    weak var appState: AppState?
    var liveActivitiesEvent: LiveActivitiesEvent?
    var cancellables = Set<AnyCancellable>()
    
    // Streamer pubkey (for viewer mode)
    private var streamerPubkey: String?
    
    // Local tracking
    private var peakViewers: Int = 0
    private var uniqueChatters: Set<String> = []
    private var messageTimestamps: [Date] = []
    private var zapTotalsBySender: [String: Int64] = [:]
    private var cachedTopZappers: [ZapperInfo] = []
    private var topZappersDebounceWorkItem: DispatchWorkItem?
    
    // Duration timer
    private var durationTimer: Timer?
    private var streamStartTime: ContinuousClock.Instant?
    
    // MARK: - Layout Constants
    
    private let compactHeight: CGFloat = 52
    private var expandedContentHeight: CGFloat = 140
    
    /// Safe area top inset - set by parent controller for transform-based layouts
    var safeAreaTopInset: CGFloat = 0 {
        didSet {
            // Update height constraint to include safe area
            updateHeightForSafeArea()
        }
    }
    
    /// Whether expand/collapse is enabled (disabled for streamer mode)
    var isExpandCollapseEnabled: Bool = true
    
    // MARK: - Constraints
    
    private var heightConstraint: NSLayoutConstraint!
    private var compactContainerTopConstraint: NSLayoutConstraint!
    
    // Glass background
    private var glassBackground: GlassContainerView?
    
    // MARK: - Callbacks
    
    var onExpandToggle: ((Bool) -> Void)?
    var onFollowTapped: ((String) -> Void)?  // Passes streamer pubkey
    var onProfileTapped: ((String) -> Void)? // Passes streamer pubkey
    
    // MARK: - Views
    
    // Compact bar (always visible)
    private let compactContainer = UIView()
    private let titleLabel = UILabel()
    private let statsStackView = UIStackView()  // Horizontal stack for all stats
    private let liveIndicator = UIView()
    private let liveLabel = UILabel()
    private let viewerIcon = UIImageView()
    private let viewerLabel = UILabel()
    private let zapIcon = UIImageView()
    private let zapLabel = UILabel()
    private let durationIcon = UIImageView()
    private let durationLabel = UILabel()
    private let chevronButton = UIButton(type: .system)
    
    // Viewer mode - profile pic in compact bar (replaces title)
    private let streamerProfilePic = UIImageView()
    private let streamerNameLabel = UILabel()
    private let compactStreamTitleLabel = UILabel()  // Stream title below name in compact bar
    
    // Expanded content (animated)
    private let expandedContainer = UIView()
    private let topZappersSection = UIView()
    private let topZappersTitleLabel = UILabel()
    private let topZappersStack = UIStackView()
    private let activitySection = UIView()
    private let peakViewersLabel = UILabel()
    private let uniqueChattersLabel = UILabel()
    private let messagesPerMinLabel = UILabel()
    
    // Viewer mode - expanded content (profile + follow + stream info)
    private let viewerExpandedSection = UIView()
    private let expandedProfilePic = UIImageView()
    private let expandedNameLabel = UILabel()
    private let followButton = UIButton(type: .system)
    private let streamTitleLabel = UILabel()
    private let streamSummaryLabel = UILabel()
    private var viewerZappersContainer: UIView?
    private let viewerZappersStack = UIStackView()
    private var isFollowing: Bool = false
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    deinit {
        durationTimer?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = true
        
        // Add liquid glass background
        setupGlassBackground()
        
        setupCompactBar()
        setupExpandedContent()
        setupConstraints()
        setupGestures()
        
        // Height constraint - will be updated when mode is set
        heightConstraint = heightAnchor.constraint(equalToConstant: compactHeight + safeAreaTopInset)
        heightConstraint.isActive = true
    }
    
    private func setupGlassBackground() {
        let glass = GlassFactory.makeGlassView(cornerRadius: 0)
        glass.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(glass, at: 0)
        
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        glassBackground = glass
    }
    
    private func updateHeightForSafeArea() {
        guard heightConstraint != nil else { return }
        
        let currentProgress: CGFloat
        switch currentState {
        case .compact: currentProgress = 0
        case .expanded: currentProgress = 1
        case .dragging(let p): currentProgress = p
        }
        
        let targetHeight = safeAreaTopInset + compactHeight + (expandedContentHeight * currentProgress)
        heightConstraint.constant = targetHeight
        
        // Update compact container top to be below safe area
        compactContainerTopConstraint?.constant = safeAreaTopInset
        
        superview?.layoutIfNeeded()
    }

    
    private func setupCompactBar() {
        compactContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(compactContainer)
        
        // Viewer mode - profile pic (hidden by default)
        streamerProfilePic.contentMode = .scaleAspectFill
        streamerProfilePic.clipsToBounds = true
        streamerProfilePic.layer.cornerRadius = 16
        streamerProfilePic.backgroundColor = .tertiarySystemFill
        streamerProfilePic.translatesAutoresizingMaskIntoConstraints = false
        streamerProfilePic.isHidden = true
        streamerProfilePic.isUserInteractionEnabled = true
        let profileTap = UITapGestureRecognizer(target: self, action: #selector(profilePicTapped))
        streamerProfilePic.addGestureRecognizer(profileTap)
        compactContainer.addSubview(streamerProfilePic)
        
        // Viewer mode - streamer name (hidden by default)
        streamerNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        streamerNameLabel.textColor = .label
        streamerNameLabel.lineBreakMode = .byTruncatingTail
        streamerNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        streamerNameLabel.translatesAutoresizingMaskIntoConstraints = false
        streamerNameLabel.isHidden = true
        compactContainer.addSubview(streamerNameLabel)
        
        // Viewer mode - stream title below name (hidden by default)
        compactStreamTitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        compactStreamTitleLabel.textColor = .secondaryLabel
        compactStreamTitleLabel.lineBreakMode = .byTruncatingTail
        compactStreamTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        compactStreamTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        compactStreamTitleLabel.isHidden = true
        compactContainer.addSubview(compactStreamTitleLabel)
        
        // Title (for streamer mode)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        compactContainer.addSubview(titleLabel)
        
        // Stats stack view - contains all the stats items
        statsStackView.axis = .horizontal
        statsStackView.spacing = 8
        statsStackView.alignment = .center
        statsStackView.distribution = .fill
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        compactContainer.addSubview(statsStackView)
        
        // Create stat items as mini stacks (icon + label)
        
        // Live indicator stack
        let liveStack = UIStackView()
        liveStack.axis = .horizontal
        liveStack.spacing = 4
        liveStack.alignment = .center
        
        liveIndicator.backgroundColor = .systemRed
        liveIndicator.layer.cornerRadius = 4
        liveIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            liveIndicator.widthAnchor.constraint(equalToConstant: 8),
            liveIndicator.heightAnchor.constraint(equalToConstant: 8),
        ])
        
        liveLabel.text = "LIVE"
        liveLabel.font = .systemFont(ofSize: 10, weight: .bold)
        liveLabel.textColor = .systemRed
        
        liveStack.addArrangedSubview(liveIndicator)
        liveStack.addArrangedSubview(liveLabel)
        statsStackView.addArrangedSubview(liveStack)
        
        // Viewer count stack
        let viewerStack = UIStackView()
        viewerStack.axis = .horizontal
        viewerStack.spacing = 3
        viewerStack.alignment = .center
        
        viewerIcon.image = UIImage(systemName: "eye.fill")
        viewerIcon.tintColor = .secondaryLabel
        viewerIcon.contentMode = .scaleAspectFit
        viewerIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            viewerIcon.widthAnchor.constraint(equalToConstant: 14),
            viewerIcon.heightAnchor.constraint(equalToConstant: 14),
        ])
        
        viewerLabel.text = "--"
        viewerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        viewerLabel.textColor = .secondaryLabel
        
        viewerStack.addArrangedSubview(viewerIcon)
        viewerStack.addArrangedSubview(viewerLabel)
        statsStackView.addArrangedSubview(viewerStack)
        
        // Zap total stack
        let zapStack = UIStackView()
        zapStack.axis = .horizontal
        zapStack.spacing = 2
        zapStack.alignment = .center
        
        zapIcon.image = UIImage(systemName: "bolt.fill")
        zapIcon.tintColor = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
        zapIcon.contentMode = .scaleAspectFit
        zapIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            zapIcon.widthAnchor.constraint(equalToConstant: 14),
            zapIcon.heightAnchor.constraint(equalToConstant: 14),
        ])
        
        zapLabel.text = "0"
        zapLabel.font = .systemFont(ofSize: 12, weight: .bold)
        zapLabel.textColor = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
        
        zapStack.addArrangedSubview(zapIcon)
        zapStack.addArrangedSubview(zapLabel)
        statsStackView.addArrangedSubview(zapStack)
        
        // Duration stack
        let durationStack = UIStackView()
        durationStack.axis = .horizontal
        durationStack.spacing = 3
        durationStack.alignment = .center
        
        durationIcon.image = UIImage(systemName: "clock.fill")
        durationIcon.tintColor = .tertiaryLabel
        durationIcon.contentMode = .scaleAspectFit
        durationIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            durationIcon.widthAnchor.constraint(equalToConstant: 14),
            durationIcon.heightAnchor.constraint(equalToConstant: 14),
        ])
        
        durationLabel.text = "0:00"
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        durationLabel.textColor = .tertiaryLabel
        
        durationStack.addArrangedSubview(durationIcon)
        durationStack.addArrangedSubview(durationLabel)
        statsStackView.addArrangedSubview(durationStack)
        
        // Chevron button
        chevronButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
        chevronButton.tintColor = .tertiaryLabel
        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        compactContainer.addSubview(chevronButton)
        
        // Start pulse animation on live indicator
        startLivePulseAnimation()
    }
    
    @objc private func profilePicTapped() {
        guard let pubkey = streamerPubkey else { return }
        onProfileTapped?(pubkey)
    }
    
    private func setupExpandedContent() {
        expandedContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(expandedContainer)
        
        // Top Zappers Section
        topZappersSection.translatesAutoresizingMaskIntoConstraints = false
        expandedContainer.addSubview(topZappersSection)
        
        topZappersTitleLabel.text = "TOP ZAPPERS"
        topZappersTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        topZappersTitleLabel.textColor = .tertiaryLabel
        topZappersTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        topZappersSection.addSubview(topZappersTitleLabel)
        
        topZappersStack.axis = .horizontal
        topZappersStack.spacing = 16
        topZappersStack.alignment = .center
        topZappersStack.distribution = .fill
        topZappersStack.translatesAutoresizingMaskIntoConstraints = false
        topZappersSection.addSubview(topZappersStack)
        
        // Activity Section
        activitySection.translatesAutoresizingMaskIntoConstraints = false
        expandedContainer.addSubview(activitySection)
        
        let activityTitleLabel = UILabel()
        activityTitleLabel.text = "ACTIVITY"
        activityTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        activityTitleLabel.textColor = .tertiaryLabel
        activityTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        activitySection.addSubview(activityTitleLabel)
        
        let activityStack = UIStackView()
        activityStack.axis = .horizontal
        activityStack.spacing = 20
        activityStack.alignment = .center
        activityStack.translatesAutoresizingMaskIntoConstraints = false
        activitySection.addSubview(activityStack)
        
        // Peak viewers
        peakViewersLabel.text = "📈 Peak: --"
        peakViewersLabel.font = .systemFont(ofSize: 13, weight: .medium)
        peakViewersLabel.textColor = .secondaryLabel
        activityStack.addArrangedSubview(peakViewersLabel)
        
        // Unique chatters
        uniqueChattersLabel.text = "👥 0 chatters"
        uniqueChattersLabel.font = .systemFont(ofSize: 13, weight: .medium)
        uniqueChattersLabel.textColor = .secondaryLabel
        activityStack.addArrangedSubview(uniqueChattersLabel)
        
        // Messages per minute
        messagesPerMinLabel.text = "💬 0/min"
        messagesPerMinLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messagesPerMinLabel.textColor = .secondaryLabel
        activityStack.addArrangedSubview(messagesPerMinLabel)
        
        NSLayoutConstraint.activate([
            activityTitleLabel.topAnchor.constraint(equalTo: activitySection.topAnchor),
            activityTitleLabel.leadingAnchor.constraint(equalTo: activitySection.leadingAnchor),
            
            activityStack.topAnchor.constraint(equalTo: activityTitleLabel.bottomAnchor, constant: 8),
            activityStack.leadingAnchor.constraint(equalTo: activitySection.leadingAnchor),
            activityStack.trailingAnchor.constraint(lessThanOrEqualTo: activitySection.trailingAnchor),
            activityStack.bottomAnchor.constraint(equalTo: activitySection.bottomAnchor),
        ])
        
        // Setup viewer mode expanded section
        setupViewerExpandedSection()
    }
    
    private func setupViewerExpandedSection() {
        viewerExpandedSection.translatesAutoresizingMaskIntoConstraints = false
        viewerExpandedSection.isHidden = true
        expandedContainer.addSubview(viewerExpandedSection)
        
        // --- Section 1: Stream Info ---
        streamTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        streamTitleLabel.textColor = .label
        streamTitleLabel.numberOfLines = 2
        streamTitleLabel.lineBreakMode = .byTruncatingTail
        streamTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        viewerExpandedSection.addSubview(streamTitleLabel)
        
        streamSummaryLabel.font = .systemFont(ofSize: 13, weight: .regular)
        streamSummaryLabel.textColor = .secondaryLabel
        streamSummaryLabel.numberOfLines = 2
        streamSummaryLabel.lineBreakMode = .byTruncatingTail
        streamSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        viewerExpandedSection.addSubview(streamSummaryLabel)
        
        // --- Section 2: Top Zappers (viewer mode) ---
        let viewerZappersSection = UIView()
        viewerZappersSection.translatesAutoresizingMaskIntoConstraints = false
        viewerExpandedSection.addSubview(viewerZappersSection)
        self.viewerZappersContainer = viewerZappersSection
        
        let zappersTitleLabel = UILabel()
        zappersTitleLabel.text = "TOP ZAPPERS"
        zappersTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        zappersTitleLabel.textColor = .tertiaryLabel
        zappersTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        viewerZappersSection.addSubview(zappersTitleLabel)
        
        viewerZappersStack.axis = .horizontal
        viewerZappersStack.spacing = 16
        viewerZappersStack.alignment = .center
        viewerZappersStack.distribution = .fill
        viewerZappersStack.translatesAutoresizingMaskIntoConstraints = false
        viewerZappersSection.addSubview(viewerZappersStack)
        
        // Initial empty state
        let emptyZapLabel = UILabel()
        emptyZapLabel.text = "Be the first to zap! ⚡"
        emptyZapLabel.font = .systemFont(ofSize: 13)
        emptyZapLabel.textColor = .tertiaryLabel
        viewerZappersStack.addArrangedSubview(emptyZapLabel)
        
        // --- Constraints ---
        NSLayoutConstraint.activate([
            viewerExpandedSection.topAnchor.constraint(equalTo: expandedContainer.topAnchor),
            viewerExpandedSection.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor),
            viewerExpandedSection.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor),
            viewerExpandedSection.bottomAnchor.constraint(equalTo: expandedContainer.bottomAnchor),
            
            // Stream title
            streamTitleLabel.topAnchor.constraint(equalTo: viewerExpandedSection.topAnchor, constant: 4),
            streamTitleLabel.leadingAnchor.constraint(equalTo: viewerExpandedSection.leadingAnchor),
            streamTitleLabel.trailingAnchor.constraint(equalTo: viewerExpandedSection.trailingAnchor),
            
            // Stream summary (anchored to top since streamTitleLabel is hidden in viewer mode)
            streamSummaryLabel.topAnchor.constraint(equalTo: viewerExpandedSection.topAnchor, constant: 0),
            streamSummaryLabel.leadingAnchor.constraint(equalTo: viewerExpandedSection.leadingAnchor),
            streamSummaryLabel.trailingAnchor.constraint(equalTo: viewerExpandedSection.trailingAnchor),
            
            // Top zappers section (directly after summary)
            viewerZappersSection.topAnchor.constraint(equalTo: streamSummaryLabel.bottomAnchor, constant: 12),
            viewerZappersSection.leadingAnchor.constraint(equalTo: viewerExpandedSection.leadingAnchor),
            viewerZappersSection.trailingAnchor.constraint(equalTo: viewerExpandedSection.trailingAnchor),
            viewerZappersSection.bottomAnchor.constraint(lessThanOrEqualTo: viewerExpandedSection.bottomAnchor),
            
            zappersTitleLabel.topAnchor.constraint(equalTo: viewerZappersSection.topAnchor),
            zappersTitleLabel.leadingAnchor.constraint(equalTo: viewerZappersSection.leadingAnchor),
            
            viewerZappersStack.topAnchor.constraint(equalTo: zappersTitleLabel.bottomAnchor, constant: 8),
            viewerZappersStack.leadingAnchor.constraint(equalTo: viewerZappersSection.leadingAnchor),
            viewerZappersStack.trailingAnchor.constraint(lessThanOrEqualTo: viewerZappersSection.trailingAnchor),
            viewerZappersStack.bottomAnchor.constraint(equalTo: viewerZappersSection.bottomAnchor),
        ])
    }
    
    @objc private func followButtonTapped() {
        guard let pubkey = streamerPubkey else { return }
        
        // Toggle follow state
        isFollowing.toggle()
        updateFollowButtonAppearance()
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Notify delegate
        onFollowTapped?(pubkey)
    }
    
    private func updateFollowButtonAppearance() {
        if isFollowing {
            followButton.setTitle("Following", for: .normal)
            followButton.backgroundColor = .secondarySystemFill
            followButton.setTitleColor(.label, for: .normal)
        } else {
            followButton.setTitle("Follow", for: .normal)
            followButton.backgroundColor = .systemBlue
            followButton.setTitleColor(.white, for: .normal)
        }
    }
    
    private func updateForMode() {
        switch mode {
        case .streamer:
            // Show title, hide profile pic
            titleLabel.isHidden = false
            streamerProfilePic.isHidden = true
            streamerNameLabel.isHidden = true
            compactStreamTitleLabel.isHidden = true
            
            // Show LIVE badge in streamer mode
            liveIndicator.isHidden = false
            liveLabel.isHidden = false
            
            // Show activity section, hide viewer section
            topZappersSection.isHidden = false
            activitySection.isHidden = false
            viewerExpandedSection.isHidden = true
            
            // Always expanded for streamer mode, no toggle
            isExpandCollapseEnabled = false
            chevronButton.isHidden = true
            
            // Force expanded state
            setExpanded(true, animated: false)
            
        case .viewer:
            // Show profile pic + name + stream title in compact bar
            titleLabel.isHidden = true
            streamerProfilePic.isHidden = false
            streamerNameLabel.isHidden = false
            compactStreamTitleLabel.isHidden = false
            
            // Hide LIVE badge — already visible on the video overlay
            liveIndicator.isHidden = true
            liveLabel.isHidden = true
            
            // Hide streamer-mode sections, show viewer section
            topZappersSection.isHidden = true
            activitySection.isHidden = true
            viewerExpandedSection.isHidden = false
            
            // Enable expand/collapse for viewer mode
            isExpandCollapseEnabled = true
            chevronButton.isHidden = false
            
            // Dynamic height — will be recalculated from content
            recalculateExpandedHeight()
        }
    }
    
    /// Calculate the expanded content height based on known viewer section layout.
    func recalculateExpandedHeight() {
        guard mode == .viewer else { return }
        
        // Summary label: measure actual text height
        let summaryWidth = bounds.width > 0 ? bounds.width - 32 : UIScreen.main.bounds.width - 32
        let summaryHeight = streamSummaryLabel.sizeThatFits(
            CGSize(width: summaryWidth, height: .greatestFiniteMagnitude)
        ).height
        
        // Layout:
        //   2pt  top padding
        // + summaryHeight (description text)
        // + 16pt gap
        // + 14pt zappers title
        // + 8pt  gap
        // + 32pt zappers row
        // + 20pt bottom padding
        expandedContentHeight = 2 + summaryHeight + 16 + 14 + 8 + 32 + 20
        
        // If already expanded, update the height constraint immediately
        if case .expanded = currentState {
            heightConstraint.constant = safeAreaTopInset + compactHeight + expandedContentHeight
            superview?.layoutIfNeeded()
        }
    }
    
    private func setupConstraints() {
        // Create compact container top constraint (will be updated with safe area)
        compactContainerTopConstraint = compactContainer.topAnchor.constraint(equalTo: topAnchor, constant: safeAreaTopInset)
        
        NSLayoutConstraint.activate([
            // Compact container - top is offset by safe area
            compactContainerTopConstraint,
            compactContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            compactContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            compactContainer.heightAnchor.constraint(equalToConstant: compactHeight),
            
            // Viewer mode - profile pic in compact bar (left side)
            streamerProfilePic.leadingAnchor.constraint(equalTo: compactContainer.leadingAnchor, constant: 12),
            streamerProfilePic.centerYAnchor.constraint(equalTo: compactContainer.centerYAnchor),
            streamerProfilePic.widthAnchor.constraint(equalToConstant: 32),
            streamerProfilePic.heightAnchor.constraint(equalToConstant: 32),
            
            // Viewer mode - streamer name (after profile pic, top-aligned with profile pic)
            streamerNameLabel.leadingAnchor.constraint(equalTo: streamerProfilePic.trailingAnchor, constant: 8),
            streamerNameLabel.topAnchor.constraint(equalTo: streamerProfilePic.topAnchor),
            streamerNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: statsStackView.leadingAnchor, constant: -8),
            
            // Viewer mode - stream title below name, bottom-aligned with profile pic
            compactStreamTitleLabel.leadingAnchor.constraint(equalTo: streamerProfilePic.trailingAnchor, constant: 8),
            compactStreamTitleLabel.bottomAnchor.constraint(equalTo: streamerProfilePic.bottomAnchor),
            compactStreamTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statsStackView.leadingAnchor, constant: -8),
            
            // Title (left side, for streamer mode - hidden in viewer mode)
            titleLabel.leadingAnchor.constraint(equalTo: compactContainer.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: compactContainer.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statsStackView.leadingAnchor, constant: -8),
            
            // Stats stack view (center-right, before chevron)
            statsStackView.centerYAnchor.constraint(equalTo: compactContainer.centerYAnchor),
            statsStackView.trailingAnchor.constraint(equalTo: chevronButton.leadingAnchor, constant: -4),
            
            // Chevron (right side)
            chevronButton.trailingAnchor.constraint(equalTo: compactContainer.trailingAnchor, constant: -8),
            chevronButton.centerYAnchor.constraint(equalTo: compactContainer.centerYAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: 30),
            chevronButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Expanded container
            expandedContainer.topAnchor.constraint(equalTo: compactContainer.bottomAnchor, constant: 8),
            expandedContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            expandedContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            // Top zappers section
            topZappersSection.topAnchor.constraint(equalTo: expandedContainer.topAnchor),
            topZappersSection.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor),
            topZappersSection.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor),
            
            topZappersTitleLabel.topAnchor.constraint(equalTo: topZappersSection.topAnchor),
            topZappersTitleLabel.leadingAnchor.constraint(equalTo: topZappersSection.leadingAnchor),
            
            topZappersStack.topAnchor.constraint(equalTo: topZappersTitleLabel.bottomAnchor, constant: 8),
            topZappersStack.leadingAnchor.constraint(equalTo: topZappersSection.leadingAnchor),
            topZappersStack.trailingAnchor.constraint(lessThanOrEqualTo: topZappersSection.trailingAnchor),
            topZappersStack.bottomAnchor.constraint(equalTo: topZappersSection.bottomAnchor),
            
            // Activity section
            activitySection.topAnchor.constraint(equalTo: topZappersSection.bottomAnchor, constant: 16),
            activitySection.leadingAnchor.constraint(equalTo: expandedContainer.leadingAnchor),
            activitySection.trailingAnchor.constraint(equalTo: expandedContainer.trailingAnchor),
            activitySection.bottomAnchor.constraint(equalTo: expandedContainer.bottomAnchor),
        ])
    }

    
    private func setupGestures() {
        // Tap chevron to toggle
        chevronButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        
        // Tap anywhere on compact bar to toggle
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        compactContainer.addGestureRecognizer(tapGesture)
        
        // Pan gesture for drag-to-expand
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
    }
    
    // MARK: - Live Pulse Animation
    
    private func startLivePulseAnimation() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        liveIndicator.layer.add(pulse, forKey: "pulse")
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func toggleExpanded() {
        // Don't allow expand/collapse if disabled (streamer mode)
        guard isExpandCollapseEnabled else { return }
        
        let shouldExpand: Bool
        if case .expanded = currentState {
            shouldExpand = false
        } else {
            shouldExpand = true
        }
        setExpanded(shouldExpand, animated: true)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        // Don't allow expand/collapse if disabled (streamer mode)
        guard isExpandCollapseEnabled else {
            gesture.state = .failed
            return
        }
        
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .began:
            animator?.stopAnimation(true)
            
        case .changed:
            let maxDrag = expandedContentHeight
            let progress: CGFloat
            
            if case .compact = currentState {
                // Dragging down to expand
                progress = min(1, max(0, translation.y / maxDrag))
            } else if case .expanded = currentState {
                // Dragging up to collapse
                progress = min(1, max(0, 1 - (-translation.y / maxDrag)))
            } else if case .dragging(let p) = currentState {
                // Continue from current progress
                let delta = translation.y / maxDrag
                progress = min(1, max(0, p + delta))
            } else {
                progress = 0
            }
            
            updateProgress(progress)
            currentState = .dragging(progress: progress)
            
        case .ended, .cancelled:
            let progress: CGFloat
            if case .dragging(let p) = currentState {
                progress = p
            } else if case .expanded = currentState {
                progress = 1
            } else {
                progress = 0
            }
            
            // Determine final state based on progress and velocity
            let shouldExpand: Bool
            if velocity.y > 500 {
                shouldExpand = true
            } else if velocity.y < -500 {
                shouldExpand = false
            } else {
                shouldExpand = progress > 0.4
            }
            
            completeAnimation(expand: shouldExpand)
            
        default:
            break
        }
    }
    
    // MARK: - Animation
    
    private func updateProgress(_ progress: CGFloat) {
        let clampedProgress = max(0, min(1, progress))
        
        // Include safe area in height calculation
        let targetHeight = safeAreaTopInset + compactHeight + (expandedContentHeight * clampedProgress)
        heightConstraint.constant = targetHeight
        
        expandedContainer.alpha = clampedProgress
        chevronButton.transform = CGAffineTransform(rotationAngle: .pi * clampedProgress)
        
        superview?.layoutIfNeeded()
    }
    
    private func completeAnimation(expand: Bool) {
        let targetProgress: CGFloat = expand ? 1 : 0
        
        animator = UIViewPropertyAnimator(
            duration: 0.4,
            dampingRatio: 0.85
        ) { [weak self] in
            self?.updateProgress(targetProgress)
        }
        
        animator?.addCompletion { [weak self] _ in
            self?.currentState = expand ? .expanded : .compact
            self?.onExpandToggle?(expand)
        }
        
        animator?.startAnimation()
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    // MARK: - Public API
    
    func setExpanded(_ expanded: Bool, animated: Bool) {
        if animated {
            completeAnimation(expand: expanded)
        } else {
            updateProgress(expanded ? 1 : 0)
            currentState = expanded ? .expanded : .compact
            onExpandToggle?(expanded)
        }
    }
    
    var isExpanded: Bool {
        if case .expanded = currentState {
            return true
        }
        return false
    }
    
    // MARK: - Data Updates
    
    func configure(
        title: String,
        isLive: Bool,
        streamStartTime: ContinuousClock.Instant?,
        liveActivitiesEvent: LiveActivitiesEvent?,
        appState: AppState?
    ) {
        self.streamStartTime = streamStartTime
        self.liveActivitiesEvent = liveActivitiesEvent
        self.appState = appState
        
        // Update title
        titleLabel.text = title.isEmpty ? "Untitled Stream" : title
        
        // Update live status
        liveIndicator.backgroundColor = isLive ? .systemRed : .systemGray
        liveLabel.text = isLive ? "LIVE" : "OFFLINE"
        liveLabel.textColor = isLive ? .systemRed : .systemGray
        
        if isLive {
            startLivePulseAnimation()
        } else {
            liveIndicator.layer.removeAnimation(forKey: "pulse")
        }
        
        // Start duration timer
        if isLive && streamStartTime != nil {
            startDurationTimer()
        } else {
            durationTimer?.invalidate()
            durationLabel.text = "0:00"
        }
        
        // Update viewer count
        updateViewerCount()
        
        // Subscribe to data updates
        subscribeToUpdates()
        
        // If in viewer mode, load streamer profile
        if mode == .viewer {
            loadStreamerProfile()
        }
    }
    
    /// Configure for viewer mode with streamer pubkey
    func configureForViewer(
        streamerPubkey: String,
        liveActivitiesEvent: LiveActivitiesEvent?,
        appState: AppState?
    ) {
        self.mode = .viewer
        self.streamerPubkey = streamerPubkey
        self.liveActivitiesEvent = liveActivitiesEvent
        self.appState = appState
        
        // Get stream info from event
        let title = liveActivitiesEvent?.title ?? "Live Stream"
        let isLive = liveActivitiesEvent?.status == .live
        let hasRecording = liveActivitiesEvent?.recording != nil
        
        // Calculate stream start time from event's startsAt date
        if let startsAt = liveActivitiesEvent?.startsAt {
            // Convert Date to ContinuousClock.Instant
            // Calculate how long ago the stream started
            let secondsAgo = Date().timeIntervalSince(startsAt)
            self.streamStartTime = .now - .seconds(secondsAgo)
        } else {
            self.streamStartTime = nil
        }
        
        // Update title (used in compact bar for viewer mode)
        titleLabel.text = title
        
        // Update live status — show REPLAY for ended streams with recordings
        if !isLive && hasRecording {
            liveIndicator.backgroundColor = .systemBlue
            liveLabel.text = "REPLAY"
            liveLabel.textColor = .systemBlue
            liveIndicator.layer.removeAnimation(forKey: "pulse")
        } else {
            liveIndicator.backgroundColor = isLive ? .systemRed : .systemGray
            liveLabel.text = isLive ? "LIVE" : "OFFLINE"
            liveLabel.textColor = isLive ? .systemRed : .systemGray
            
            if isLive {
                startLivePulseAnimation()
            } else {
                liveIndicator.layer.removeAnimation(forKey: "pulse")
            }
        }
        
        // Start duration timer for live streams
        if isLive && streamStartTime != nil {
            startDurationTimer()
        } else {
            durationTimer?.invalidate()
            durationLabel.text = "0:00"
        }
        
        // Update viewer count
        updateViewerCount()
        
        // Subscribe to data updates
        subscribeToUpdates()
        
        // Load streamer profile
        loadStreamerProfile()
        
        // Check follow status
        checkFollowStatus()
    }
    
    private func loadStreamerProfile() {
        guard let appState = appState, let pubkey = streamerPubkey else { return }
        
        // Get metadata from AppState
        let metadata = appState.metadataEvents[pubkey]?.userMetadata
        
        let displayName = metadata?.displayName ?? metadata?.name ?? String(pubkey.prefix(8))
        
        // Update compact bar — show profile pic, name, and stream title
        streamerNameLabel.text = displayName
        let streamTitle = liveActivitiesEvent?.title
        compactStreamTitleLabel.text = streamTitle ?? "Live Stream"
        
        // Load profile pic into compact bar
        if let pictureURL = metadata?.pictureURL {
            streamerProfilePic.kf.setImage(with: pictureURL, placeholder: UIImage(systemName: "person.circle.fill"))
        } else {
            streamerProfilePic.image = UIImage(systemName: "person.circle.fill")
            streamerProfilePic.tintColor = .tertiaryLabel
        }
        
        // Update stream summary from the live event (title is in compact bar)
        let streamSummary = liveActivitiesEvent?.summary
        
        streamTitleLabel.isHidden = true
        if let summary = streamSummary, !summary.isEmpty {
            streamSummaryLabel.text = summary
            streamSummaryLabel.font = .systemFont(ofSize: 13, weight: .regular)
            streamSummaryLabel.textColor = .secondaryLabel
        } else {
            streamSummaryLabel.text = "No description"
            streamSummaryLabel.font = .italicSystemFont(ofSize: 13)
            streamSummaryLabel.textColor = .tertiaryLabel
        }
        streamSummaryLabel.isHidden = false
        
        // Recalculate expanded height now that content is set
        recalculateExpandedHeight()
        
        // Subscribe to metadata updates
        appState.$metadataEvents
            .compactMap { $0[pubkey]?.userMetadata }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metadata in
                let name = metadata.displayName ?? metadata.name ?? String(pubkey.prefix(8))
                self?.streamerNameLabel.text = name
                
                if let pictureURL = metadata.pictureURL {
                    self?.streamerProfilePic.kf.setImage(with: pictureURL)
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkFollowStatus() {
        guard let appState = appState, let pubkey = streamerPubkey else { return }
        
        // Check if user is following this streamer
        isFollowing = appState.followedPubkeys.contains(pubkey)
        updateFollowButtonAppearance()
        
        // Subscribe to follow status changes
        appState.$followedPubkeys
            .receive(on: DispatchQueue.main)
            .sink { [weak self] followedPubkeys in
                guard let self = self, let pubkey = self.streamerPubkey else { return }
                self.isFollowing = followedPubkeys.contains(pubkey)
                self.updateFollowButtonAppearance()
            }
            .store(in: &cancellables)
    }
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        updateDuration()
    }
    
    private func updateDuration() {
        guard let startTime = streamStartTime else {
            durationLabel.text = "0:00"
            return
        }
        
        let elapsed = startTime.duration(to: .now)
        let totalSeconds = Int(elapsed.components.seconds)
        
        // For very long durations, show compact format
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if days >= 30 {
            // Show months for 30+ days
            let months = days / 30
            let remainingDays = days % 30
            if remainingDays > 0 {
                durationLabel.text = "\(months)mo \(remainingDays)d"
            } else {
                durationLabel.text = "\(months)mo"
            }
        } else if days >= 1 {
            // Show days + hours for 1+ days
            if hours > 0 {
                durationLabel.text = "\(days)d \(hours)h"
            } else {
                durationLabel.text = "\(days)d"
            }
        } else if hours > 0 {
            // Standard HH:MM:SS for hours
            durationLabel.text = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            // Standard MM:SS for under an hour
            durationLabel.text = String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func updateViewerCount() {
        let viewers = liveActivitiesEvent?.currentParticipants ?? 0
        viewerLabel.text = viewers > 0 ? formatNumber(viewers) : "--"
        
        // Update peak viewers
        if viewers > peakViewers {
            peakViewers = viewers
            peakViewersLabel.text = "📈 Peak: \(formatNumber(peakViewers))"
        }
    }

    
    private func subscribeToUpdates() {
        cancellables.removeAll()
        
        guard let appState = appState,
              let coordinates = liveActivitiesEvent?.coordinateTag else {
            return
        }
        
        // Subscribe to zap receipts and calculate total from actual receipts
        // This is more reliable than incremental counting because:
        // 1. Different relays may return different subsets of zaps
        // 2. Incremental counting can drift if events are missed or duplicated
        appState.$zapReceiptEvents
            .map { $0[coordinates] ?? [] }
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] zapReceipts in
                // Calculate total from actual receipts (source of truth)
                let totalMillisats = zapReceipts.reduce(Int64(0)) { total, receipt in
                    total + Int64(receipt.description?.amount ?? 0)
                }
                let sats = totalMillisats / 1000
                self?.zapLabel.text = self?.formatNumber(Int(sats)) ?? "0"
                
                // Also process for top zappers
                self?.processZapReceipts(zapReceipts)
            }
            .store(in: &cancellables)
        
        // Subscribe to chat messages for activity metrics
        appState.$liveChatMessagesEvents
            .map { $0[coordinates] ?? [] }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.processChatMessages(messages)
            }
            .store(in: &cancellables)
        
        // Subscribe to live activities event updates (for viewer count and status transitions)
        appState.$liveActivitiesEvents
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] events in
                guard let self = self else { return }

                // Match by coordinate (works for both streamer and viewer mode)
                if let eventList = events[coordinates], let updatedEvent = eventList.first {
                    let previousStatus = self.liveActivitiesEvent?.status
                    self.liveActivitiesEvent = updatedEvent
                    self.updateViewerCount()

                    // Detect status transitions for viewer mode dashboard UI
                    if self.mode == .viewer && updatedEvent.status == .ended && previousStatus == .live {
                        let hasRecording = updatedEvent.recording != nil
                        self.liveIndicator.backgroundColor = hasRecording ? .systemBlue : .systemGray
                        self.liveLabel.text = hasRecording ? "REPLAY" : "ENDED"
                        self.liveLabel.textColor = hasRecording ? .systemBlue : .systemGray
                        self.liveIndicator.layer.removeAnimation(forKey: "pulse")
                        self.durationTimer?.invalidate()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func processZapReceipts(_ zapReceipts: [LightningZapsReceiptEvent]) {
        // Update zap totals by sender
        zapTotalsBySender.removeAll()
        
        for receipt in zapReceipts {
            guard let senderPubkey = receipt.zapSenderPubkey,
                  let amount = receipt.description?.amount else { continue }
            zapTotalsBySender[senderPubkey, default: 0] += Int64(amount)
        }
        
        // Debounce top zappers calculation
        topZappersDebounceWorkItem?.cancel()
        topZappersDebounceWorkItem = DispatchWorkItem { [weak self] in
            self?.updateTopZappers()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: topZappersDebounceWorkItem!)
    }
    
    private func updateTopZappers() {
        guard let appState = appState else { return }
        
        // Sort and get top 3
        let sorted = zapTotalsBySender.sorted { $0.value > $1.value }
        let top3 = sorted.prefix(3)
        
        cachedTopZappers = top3.map { pubkey, amountMillisats in
            let metadata = appState.metadataEvents[pubkey]?.userMetadata
            return ZapperInfo(
                pubkey: pubkey,
                displayName: metadata?.displayName ?? metadata?.name ?? String(pubkey.prefix(8)),
                profilePicURL: metadata?.pictureURL,
                totalSats: amountMillisats / 1000
            )
        }
        
        // Update UI
        updateTopZappersUI()
    }
    
    private func updateTopZappersUI() {
        // Clear existing views
        topZappersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        if cachedTopZappers.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No zaps yet"
            emptyLabel.font = .systemFont(ofSize: 13)
            emptyLabel.textColor = .tertiaryLabel
            topZappersStack.addArrangedSubview(emptyLabel)
        } else {
            let medals = ["🥇", "🥈", "🥉"]
            for (index, zapper) in cachedTopZappers.enumerated() {
                let zapperView = createZapperView(
                    medal: medals[index],
                    name: zapper.displayName,
                    sats: zapper.totalSats,
                    profilePicURL: zapper.profilePicURL
                )
                topZappersStack.addArrangedSubview(zapperView)
            }
        }
        
        // Also update viewer mode zappers stack
        updateViewerZappersUI()
    }
    
    private func updateViewerZappersUI() {
        viewerZappersStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        if cachedTopZappers.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "Be the first to zap! ⚡"
            emptyLabel.font = .systemFont(ofSize: 13)
            emptyLabel.textColor = .tertiaryLabel
            viewerZappersStack.addArrangedSubview(emptyLabel)
        } else {
            let medals = ["🥇", "🥈", "🥉"]
            for (index, zapper) in cachedTopZappers.enumerated() {
                let zapperView = createZapperView(
                    medal: medals[index],
                    name: zapper.displayName,
                    sats: zapper.totalSats,
                    profilePicURL: zapper.profilePicURL
                )
                viewerZappersStack.addArrangedSubview(zapperView)
            }
        }
        
        // Recalculate height after zappers content changed (don't animate — height was reserved upfront)
    }
    
    private func createZapperView(medal: String, name: String, sats: Int64, profilePicURL: URL?) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let medalLabel = UILabel()
        medalLabel.text = medal
        medalLabel.font = .systemFont(ofSize: 16)
        medalLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(medalLabel)
        
        let profilePic = UIImageView()
        profilePic.contentMode = .scaleAspectFill
        profilePic.clipsToBounds = true
        profilePic.layer.cornerRadius = 12
        profilePic.backgroundColor = .tertiarySystemFill
        profilePic.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(profilePic)
        
        if let url = profilePicURL {
            profilePic.kf.setImage(with: url, placeholder: UIImage(systemName: "person.circle.fill"))
        } else {
            profilePic.image = UIImage(systemName: "person.circle.fill")
            profilePic.tintColor = .tertiaryLabel
        }
        
        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)
        
        let satsLabel = UILabel()
        satsLabel.text = formatNumber(Int(sats))
        satsLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        satsLabel.textColor = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
        satsLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(satsLabel)
        
        NSLayoutConstraint.activate([
            medalLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            medalLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            profilePic.leadingAnchor.constraint(equalTo: medalLabel.trailingAnchor, constant: 4),
            profilePic.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            profilePic.widthAnchor.constraint(equalToConstant: 24),
            profilePic.heightAnchor.constraint(equalToConstant: 24),
            
            nameLabel.leadingAnchor.constraint(equalTo: profilePic.trailingAnchor, constant: 6),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            satsLabel.leadingAnchor.constraint(equalTo: profilePic.trailingAnchor, constant: 6),
            satsLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            satsLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            
            container.heightAnchor.constraint(equalToConstant: 32),
        ])
        
        return container
    }
    
    private func processChatMessages(_ messages: [LiveChatMessageEvent]) {
        // Track unique chatters
        for message in messages {
            uniqueChatters.insert(message.pubkey)
        }
        uniqueChattersLabel.text = "👥 \(uniqueChatters.count) chatters"
        
        // Track message timestamps for messages/min
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        
        // Add new message timestamps
        for message in messages {
            let messageDate = Date(timeIntervalSince1970: TimeInterval(message.createdAt))
            if messageDate > oneMinuteAgo && !messageTimestamps.contains(messageDate) {
                messageTimestamps.append(messageDate)
            }
        }
        
        // Remove old timestamps
        messageTimestamps.removeAll { $0 < oneMinuteAgo }
        
        // Cap at 100 to prevent unbounded growth
        if messageTimestamps.count > 100 {
            messageTimestamps = Array(messageTimestamps.suffix(100))
        }
        
        messagesPerMinLabel.text = "💬 \(messageTimestamps.count)/min"
    }
    
    // MARK: - Helpers
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
    
    // MARK: - Public Methods for External Updates
    
    func trackNewChatter(_ pubkey: String) {
        uniqueChatters.insert(pubkey)
        uniqueChattersLabel.text = "👥 \(uniqueChatters.count) chatters"
    }
    
    func trackNewMessage() {
        let now = Date()
        messageTimestamps.append(now)
        
        // Trim old entries
        let oneMinuteAgo = now.addingTimeInterval(-60)
        messageTimestamps.removeAll { $0 < oneMinuteAgo }
        
        if messageTimestamps.count > 100 {
            messageTimestamps = Array(messageTimestamps.suffix(100))
        }
        
        messagesPerMinLabel.text = "💬 \(messageTimestamps.count)/min"
    }
    
    func resetStats() {
        peakViewers = 0
        uniqueChatters.removeAll()
        messageTimestamps.removeAll()
        zapTotalsBySender.removeAll()
        cachedTopZappers.removeAll()
        
        peakViewersLabel.text = "📈 Peak: --"
        uniqueChattersLabel.text = "👥 0 chatters"
        messagesPerMinLabel.text = "💬 0/min"
        updateTopZappersUI()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension StreamerDashboardView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Don't interfere with table scroll or keyboard dismiss
        if otherGestureRecognizer.view is UITableView ||
           otherGestureRecognizer.view is UIScrollView {
            return false
        }
        return false
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        
        let velocity = pan.velocity(in: self)
        
        // Only activate for primarily vertical gestures
        let isVertical = abs(velocity.y) > abs(velocity.x) * 1.5
        
        // Only activate if gesture starts in the dashboard area
        let location = pan.location(in: self)
        let isInDashboard = bounds.contains(location)
        
        return isVertical && isInDashboard
    }
    
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Let table scroll take priority
        if otherGestureRecognizer.view is UITableView {
            return true
        }
        return false
    }
}
