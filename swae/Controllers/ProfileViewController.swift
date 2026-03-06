//
//  ProfileViewController.swift
//  swae
//
//  Twitter/X-style profile view controller
//  Banner is fixed at top, profile pic shrinks and slides under banner on scroll
//

import Combine
import Kingfisher
import NostrSDK
import SwiftUI
import UIKit

final class ProfileViewController: UIViewController {

    // MARK: - Dependencies
    private let appState: AppState
    private var viewModel: ProfileViewModel
    private let isViewingActiveProfile: Bool
    
    /// Whether to show a back button (true when pushed onto navigation stack, false when root of tab)
    var showBackButton: Bool = false

    // MARK: - Layout Constants
    private enum Layout {
        static let bannerHeight: CGFloat = 75  // 25% shorter than original 100pt
        static let profilePicSize: CGFloat = 88
        static let profilePicMinSize: CGFloat = 32
        static let profilePicBorderWidth: CGFloat = 4
        static let horizontalPadding: CGFloat = 16
        static let streamCardHeight: CGFloat = 260  // Legacy - kept for reference
        static let profilePicOverlap: CGFloat = 33 // How much profile pic overlaps banner (proportional to banner height)
        
        // Carousel layout (matches VideoListViewController)
        static let carouselCardWidth: CGFloat = 280
        static let carouselCardHeight: CGFloat = 240
        static let carouselHeaderHeight: CGFloat = 50
    }

    // MARK: - Default Images
    private lazy var defaultBannerImage = UIImage(named: "swae") ?? UIImage()
    private lazy var defaultProfileImage = UIImage(named: "swae") ?? UIImage()

    // MARK: - UI Components

    // Banner - FIXED at top, outside scroll view
    private let bannerContainerView = UIView()
    private let bannerImageView = UIImageView()
    private let bannerSkeletonView = SkeletonView()
    private var bannerHeightConstraint: NSLayoutConstraint!
    
    // Banner blur effect (for scroll-based blur)
    private let bannerBlurView = UIVisualEffectView(effect: nil)
    private var bannerBlurAnimator: UIViewPropertyAnimator?
    
    // Banner name label (shows when scrolled down)
    private let bannerNameLabel = UILabel()
    
    // Banner mini profile pic and verified badge (shows with name when scrolled)
    private let bannerMiniProfilePic = UIImageView()
    private let bannerVerifiedBadge = UILabel()
    private let bannerNameStackView = UIStackView()  // Container to center the group

    // Scroll view - content scrolls under banner
    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()

    // Profile section (inside scroll view)
    private let profileSectionView = UIView()
    
    // Profile pic - SEPARATE from scroll view for z-ordering control
    private let profilePicContainerView = UIView()
    private let profilePicImageView = UIImageView()
    private let profilePicSkeletonView = SkeletonView()
    private var profilePicTopConstraint: NSLayoutConstraint!
    private var profilePicLeadingConstraint: NSLayoutConstraint!
    private var profilePicWidthConstraint: NSLayoutConstraint!
    private var profilePicHeightConstraint: NSLayoutConstraint!

    // Action buttons with liquid glass blur backgrounds (created lazily)
    private var actionGlassView: GlassContainerView?
    private let actionButton = UIButton(type: .system)
    private var editGlassView: GlassContainerView?
    private let editProfileButton = UIButton(type: .system)
    private var settingsGlassView: GlassContainerView?
    private var zapGlassView: GlassContainerView?
    private let profileZapButton = UIButton(type: .system)
    private var activeZapModal: MorphingZapModal?
    private var qrGlassView: GlassContainerView?
    private let profileQRButton = UIButton(type: .system)
    private var activeQRModal: MorphingQRModal?
    private let followsYouBadge = PaddedLabel()
    
    // Constraint for action button container width (toggled for own profile)
    private var actionContainerWidthConstraint: NSLayoutConstraint!
    private var actionContainerCollapseConstraint: NSLayoutConstraint!
    
    // QR button trailing constraints (mutually exclusive, toggled in updateActionButton)
    private var qrTrailingToZap: NSLayoutConstraint!
    private var qrTrailingToAction: NSLayoutConstraint!
    private var qrTrailingToSettings: NSLayoutConstraint!

    private let displayNameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let nip05Label = UILabel()
    private let bioLabel = UILabel()
    private let showMoreButton = UIButton(type: .system)
    private let websiteButton = UIButton(type: .system)
    private let statsStackView = UIStackView()
    private let followingCountLabel = UILabel()
    private let followersCountLabel = UILabel()

    // Enriched stats from Profilestr API (zaps received)
    private let zapsStatLabel = UILabel()

    // Streams section
    private let streamsSectionView = UIView()
    private var streamsCollectionView: UICollectionView!

    // Settings button with liquid glass
    private let settingsButton = UIButton(type: .system)

    // Skeleton views
    private let nameSkeleton = SkeletonView()
    private let usernameSkeleton = SkeletonView()
    private let bioSkeleton = SkeletonView()
    private let bioSkeleton2 = SkeletonView()
    private let followingSkeleton = SkeletonView()

    // MARK: - Guest Overlay (SwiftUI)
    private var guestHostingController: UIHostingController<AnyView>?

    // MARK: - State
    private var cancellables = Set<AnyCancellable>()
    private var liveStreams: [LiveActivitiesEvent] = []
    private var pastStreams: [LiveActivitiesEvent] = []
    private var isLoadingInitialData = true
    private var isShowingSkeleton = true
    private var isBioExpanded = false
    private var hasSetupGuestOverlay = false
    private var lastSeenMetadata: UserMetadata?
    
    // Track scroll position for profile pic animation
    private var initialProfilePicY: CGFloat = 0
    
    // MARK: - Profile Stream Sections
    enum ProfileStreamSection: Int, CaseIterable {
        case liveNow = 0
        case pastStreams = 1
        
        var title: String {
            switch self {
            case .liveNow: return "Live Now"
            case .pastStreams: return "Past Streams"
            }
        }
    }
    private var hasCalculatedInitialPosition = false
    private var isProfilePicUnderBanner = false

    // MARK: - Zap
    private let zapService: ZapService

    // MARK: - Initialization
    init(appState: AppState, publicKeyHex: String? = nil) {
        self.appState = appState
        let resolvedPublicKeyHex = publicKeyHex ?? appState.appSettings?.activeProfile?.publicKeyHex ?? ""
        self.isViewingActiveProfile = publicKeyHex == nil
        self.viewModel = ProfileViewModel(appState: appState, publicKeyHex: resolvedPublicKeyHex)
        self.zapService = ZapService(appState: appState)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // Must stop and finish the animator before deallocation
        if let animator = bannerBlurAnimator {
            if animator.state == .active {
                animator.stopAnimation(true)
                animator.finishAnimation(at: .current)
            } else if animator.state == .stopped {
                animator.finishAnimation(at: .current)
            }
        }
        bannerBlurAnimator = nil
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        
        // Setup UI synchronously (fast)
        setupScrollView()
        setupBanner()
        setupProfilePic()
        setupProfileSection()
        setupStreamsSection()
        setupSettingsButton()
        setupBackButton()
        
        // Guest overlay is created lazily in configureInitialState() only when needed
        
        // Defer heavy work to next run loop for instant navigation
        DispatchQueue.main.async { [weak self] in
            self?.materializeGlassViews()
            self?.setupObservers()
            self?.configureInitialState()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        
        if isLoadingInitialData {
            restartSkeletonAnimations()
        }
        
        // Recreate blur animator if needed
        if bannerBlurAnimator == nil || bannerBlurAnimator?.state == .stopped {
            setupBannerBlurAnimator()
        }
        
        // Defer network calls to not block animation
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appState.pullMissingEventsFromPubkeysAndFollows([self.viewModel.publicKeyHex])
            self.appState.subscribeToProfile(for: self.viewModel.publicKeyHex)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appState.unsubscribeFromProfile(for: viewModel.publicKeyHex)
        
        // Stop and finish blur animator to prevent crash on dealloc
        if let animator = bannerBlurAnimator {
            if animator.state == .active {
                animator.stopAnimation(true)
                animator.finishAnimation(at: .current)
            } else if animator.state == .stopped {
                animator.finishAnimation(at: .current)
            }
        }
        bannerBlurAnimator = nil
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Calculate initial profile pic position after layout
        if !hasCalculatedInitialPosition {
            let bannerBottom = Layout.bannerHeight + view.safeAreaInsets.top
            initialProfilePicY = bannerBottom - Layout.profilePicOverlap
            profilePicTopConstraint.constant = initialProfilePicY
            hasCalculatedInitialPosition = true
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateScrollViewInsets()
        
        // Recalculate initial position when safe area changes
        let bannerBottom = Layout.bannerHeight + view.safeAreaInsets.top
        initialProfilePicY = bannerBottom - Layout.profilePicOverlap
        
        // Update banner height
        bannerHeightConstraint.constant = Layout.bannerHeight + view.safeAreaInsets.top
    }
    
    private func updateScrollViewInsets() {
        // Content starts below banner, but profile section has padding for profile pic
        let topInset = Layout.bannerHeight + view.safeAreaInsets.top
        scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: 100, right: 0)
        scrollView.scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: 100, right: 0)
    }

    // MARK: - Setup: Scroll View
    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStackView.axis = .vertical
        contentStackView.spacing = 0
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    // MARK: - Setup: Banner (FIXED at top)
    private func setupBanner() {
        bannerContainerView.clipsToBounds = true
        bannerContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerContainerView)

        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.backgroundColor = .systemGray5
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainerView.addSubview(bannerImageView)

        bannerSkeletonView.layer.cornerRadius = 0
        bannerSkeletonView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainerView.addSubview(bannerSkeletonView)
        bannerSkeletonView.startAnimating()

        bannerHeightConstraint = bannerContainerView.heightAnchor.constraint(
            equalToConstant: Layout.bannerHeight + view.safeAreaInsets.top)

        NSLayoutConstraint.activate([
            bannerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            bannerContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bannerContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerHeightConstraint,

            // Banner image fills container and uses scaleAspectFill to crop edges
            bannerImageView.topAnchor.constraint(equalTo: bannerContainerView.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: bannerContainerView.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: bannerContainerView.trailingAnchor),
            bannerImageView.bottomAnchor.constraint(equalTo: bannerContainerView.bottomAnchor),

            bannerSkeletonView.topAnchor.constraint(equalTo: bannerContainerView.topAnchor),
            bannerSkeletonView.leadingAnchor.constraint(equalTo: bannerContainerView.leadingAnchor),
            bannerSkeletonView.trailingAnchor.constraint(equalTo: bannerContainerView.trailingAnchor),
            bannerSkeletonView.bottomAnchor.constraint(equalTo: bannerContainerView.bottomAnchor),
        ])
        
        // Blur view - on top of skeleton, starts invisible (NO blur by default)
        bannerBlurView.translatesAutoresizingMaskIntoConstraints = false
        bannerBlurView.alpha = 0
        bannerContainerView.addSubview(bannerBlurView)
        
        // Stack view to hold profile pic + name + badge (for proper centering)
        bannerNameStackView.axis = .horizontal
        bannerNameStackView.alignment = .center
        bannerNameStackView.spacing = 6
        bannerNameStackView.alpha = 0  // Hidden by default
        bannerNameStackView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainerView.addSubview(bannerNameStackView)
        
        // Mini profile pic - small circular image
        bannerMiniProfilePic.contentMode = .scaleAspectFill
        bannerMiniProfilePic.clipsToBounds = true
        bannerMiniProfilePic.layer.cornerRadius = 14  // 28pt / 2
        bannerMiniProfilePic.backgroundColor = .systemGray5
        bannerMiniProfilePic.isUserInteractionEnabled = false  // Not clickable
        bannerMiniProfilePic.translatesAutoresizingMaskIntoConstraints = false
        bannerNameStackView.addArrangedSubview(bannerMiniProfilePic)
        
        // Name label
        bannerNameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        bannerNameLabel.textColor = .white
        bannerNameLabel.textAlignment = .left
        bannerNameLabel.setContentHuggingPriority(.required, for: .horizontal)
        bannerNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bannerNameStackView.addArrangedSubview(bannerNameLabel)
        
        // Verified badge - checkmark shown if NIP-05 verified
        bannerVerifiedBadge.text = "✓"
        bannerVerifiedBadge.font = .systemFont(ofSize: 14, weight: .bold)
        bannerVerifiedBadge.textColor = .accentPurple
        bannerVerifiedBadge.isHidden = true  // Hidden if not verified
        bannerVerifiedBadge.setContentHuggingPriority(.required, for: .horizontal)
        bannerNameStackView.addArrangedSubview(bannerVerifiedBadge)
        
        NSLayoutConstraint.activate([
            // Blur view fills banner
            bannerBlurView.topAnchor.constraint(equalTo: bannerContainerView.topAnchor),
            bannerBlurView.leadingAnchor.constraint(equalTo: bannerContainerView.leadingAnchor),
            bannerBlurView.trailingAnchor.constraint(equalTo: bannerContainerView.trailingAnchor),
            bannerBlurView.bottomAnchor.constraint(equalTo: bannerContainerView.bottomAnchor),
            
            // Mini profile pic size
            bannerMiniProfilePic.widthAnchor.constraint(equalToConstant: 28),
            bannerMiniProfilePic.heightAnchor.constraint(equalToConstant: 28),
            
            // Stack view - centered horizontally and vertically in visible banner area
            bannerNameStackView.centerXAnchor.constraint(equalTo: bannerContainerView.centerXAnchor),
            bannerNameStackView.centerYAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Layout.bannerHeight / 2
            ),
            // Max width to prevent overflow
            bannerNameStackView.widthAnchor.constraint(lessThanOrEqualTo: bannerContainerView.widthAnchor, constant: -100),
        ])
        
        // Blur animator will be created lazily in viewWillAppear
    }
    
    private func setupBannerBlurAnimator() {
        // Clean up existing animator if any
        if let existingAnimator = bannerBlurAnimator {
            if existingAnimator.state == .active {
                existingAnimator.stopAnimation(true)
                existingAnimator.finishAnimation(at: .current)
            } else if existingAnimator.state == .stopped {
                existingAnimator.finishAnimation(at: .current)
            }
        }
        
        bannerBlurView.effect = nil
        bannerBlurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.bannerBlurView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        }
        bannerBlurAnimator?.pausesOnCompletion = true
        bannerBlurAnimator?.fractionComplete = 0
    }
    
    // MARK: - Setup: Profile Pic (Separate layer for z-ordering)
    private func setupProfilePic() {
        // Profile pic container - positioned absolutely in the view
        profilePicContainerView.backgroundColor = .clear
        profilePicContainerView.alpha = 1.0  // Ensure visible on load
        profilePicContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add ABOVE the banner so it shows over the banner initially
        view.insertSubview(profilePicContainerView, aboveSubview: bannerContainerView)

        // Profile pic image
        profilePicImageView.contentMode = .scaleAspectFill
        profilePicImageView.clipsToBounds = true
        profilePicImageView.layer.cornerRadius = Layout.profilePicSize / 2
        profilePicImageView.layer.borderWidth = Layout.profilePicBorderWidth
        profilePicImageView.layer.borderColor = UIColor.systemBackground.cgColor
        profilePicImageView.backgroundColor = .systemGray5
        profilePicImageView.translatesAutoresizingMaskIntoConstraints = false
        profilePicContainerView.addSubview(profilePicImageView)

        // Profile pic skeleton
        profilePicSkeletonView.layer.cornerRadius = Layout.profilePicSize / 2
        profilePicSkeletonView.translatesAutoresizingMaskIntoConstraints = false
        profilePicContainerView.addSubview(profilePicSkeletonView)
        profilePicSkeletonView.startAnimating()

        // Initial position (will be updated in viewDidLayoutSubviews)
        let initialTop = Layout.bannerHeight - Layout.profilePicOverlap
        profilePicTopConstraint = profilePicContainerView.topAnchor.constraint(equalTo: view.topAnchor, constant: initialTop)
        profilePicLeadingConstraint = profilePicContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalPadding)
        profilePicWidthConstraint = profilePicContainerView.widthAnchor.constraint(equalToConstant: Layout.profilePicSize)
        profilePicHeightConstraint = profilePicContainerView.heightAnchor.constraint(equalToConstant: Layout.profilePicSize)

        NSLayoutConstraint.activate([
            profilePicTopConstraint,
            profilePicLeadingConstraint,
            profilePicWidthConstraint,
            profilePicHeightConstraint,

            profilePicImageView.topAnchor.constraint(equalTo: profilePicContainerView.topAnchor),
            profilePicImageView.leadingAnchor.constraint(equalTo: profilePicContainerView.leadingAnchor),
            profilePicImageView.trailingAnchor.constraint(equalTo: profilePicContainerView.trailingAnchor),
            profilePicImageView.bottomAnchor.constraint(equalTo: profilePicContainerView.bottomAnchor),

            profilePicSkeletonView.topAnchor.constraint(equalTo: profilePicImageView.topAnchor),
            profilePicSkeletonView.leadingAnchor.constraint(equalTo: profilePicImageView.leadingAnchor),
            profilePicSkeletonView.trailingAnchor.constraint(equalTo: profilePicImageView.trailingAnchor),
            profilePicSkeletonView.bottomAnchor.constraint(equalTo: profilePicImageView.bottomAnchor),
        ])
    }


    // MARK: - Setup: Profile Section
    private func setupProfileSection() {
        profileSectionView.backgroundColor = .systemBackground
        profileSectionView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(profileSectionView)

        // Action button (Zap / Follow) — glass deferred to materializeGlassViews()
        let actionContainer = UIView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        actionContainer.tag = 1001  // Tag for later lookup
        profileSectionView.addSubview(actionContainer)
        
        actionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        actionButton.backgroundColor = .clear
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        actionContainer.addSubview(actionButton)

        // Edit Profile button — glass deferred
        let editContainer = UIView()
        editContainer.translatesAutoresizingMaskIntoConstraints = false
        editContainer.isHidden = true
        editContainer.tag = 1002
        profileSectionView.addSubview(editContainer)
        
        editProfileButton.setTitle("Edit", for: .normal)
        editProfileButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        editProfileButton.setTitleColor(.label, for: .normal)
        editProfileButton.backgroundColor = .clear
        editProfileButton.translatesAutoresizingMaskIntoConstraints = false
        editProfileButton.addTarget(self, action: #selector(editProfileTapped), for: .touchUpInside)
        editContainer.addSubview(editProfileButton)
        
        // Settings button — glass deferred
        let settingsContainer = UIView()
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.isHidden = true
        settingsContainer.tag = 1003
        profileSectionView.addSubview(settingsContainer)
        
        let settingsConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        settingsButton.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: settingsConfig), for: .normal)
        settingsButton.tintColor = .label
        settingsButton.backgroundColor = .clear
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        settingsContainer.addSubview(settingsButton)

        // Zap button — for other users' profiles (glass deferred)
        let zapContainer = UIView()
        zapContainer.translatesAutoresizingMaskIntoConstraints = false
        zapContainer.isHidden = true
        zapContainer.tag = 1005
        profileSectionView.addSubview(zapContainer)

        profileZapButton.setTitle("⚡ Zap", for: .normal)
        profileZapButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        profileZapButton.setTitleColor(.systemOrange, for: .normal)
        profileZapButton.backgroundColor = .clear
        profileZapButton.translatesAutoresizingMaskIntoConstraints = false
        profileZapButton.addTarget(self, action: #selector(profileZapTapped), for: .touchUpInside)
        zapContainer.addSubview(profileZapButton)

        // QR code button — always visible on all profiles (glass deferred)
        let qrContainer = UIView()
        qrContainer.translatesAutoresizingMaskIntoConstraints = false
        qrContainer.tag = 1006
        profileSectionView.addSubview(qrContainer)

        let qrConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        profileQRButton.setImage(UIImage(systemName: "qrcode", withConfiguration: qrConfig), for: .normal)
        profileQRButton.tintColor = .label
        profileQRButton.backgroundColor = .clear
        profileQRButton.translatesAutoresizingMaskIntoConstraints = false
        profileQRButton.addTarget(self, action: #selector(profileQRTapped), for: .touchUpInside)
        qrContainer.addSubview(profileQRButton)

        // Follows you badge
        followsYouBadge.text = "Follows you"
        followsYouBadge.font = .systemFont(ofSize: 11, weight: .medium)
        followsYouBadge.textColor = .secondaryLabel
        followsYouBadge.backgroundColor = .tertiarySystemFill
        followsYouBadge.layer.cornerRadius = 4
        followsYouBadge.clipsToBounds = true
        followsYouBadge.translatesAutoresizingMaskIntoConstraints = false
        followsYouBadge.isHidden = true
        profileSectionView.addSubview(followsYouBadge)

        // Display name
        displayNameLabel.font = .systemFont(ofSize: 24, weight: .bold)
        displayNameLabel.textColor = .label
        displayNameLabel.translatesAutoresizingMaskIntoConstraints = false
        profileSectionView.addSubview(displayNameLabel)

        // Username + NIP-05 row
        usernameLabel.font = .systemFont(ofSize: 15, weight: .regular)
        usernameLabel.textColor = .secondaryLabel
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        profileSectionView.addSubview(usernameLabel)
        
        // NIP-05 verification
        nip05Label.font = .systemFont(ofSize: 14, weight: .regular)
        nip05Label.textColor = .accentPurple
        nip05Label.translatesAutoresizingMaskIntoConstraints = false
        nip05Label.isHidden = true
        profileSectionView.addSubview(nip05Label)

        // Bio
        bioLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bioLabel.textColor = .label
        bioLabel.numberOfLines = 3
        bioLabel.translatesAutoresizingMaskIntoConstraints = false
        bioLabel.isUserInteractionEnabled = true
        let bioTapGesture = UITapGestureRecognizer(target: self, action: #selector(bioLabelTapped(_:)))
        bioLabel.addGestureRecognizer(bioTapGesture)
        profileSectionView.addSubview(bioLabel)

        // Show more button - will be added to info stack
        showMoreButton.setTitle("more", for: .normal)
        showMoreButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        showMoreButton.setTitleColor(.secondaryLabel, for: .normal)
        showMoreButton.contentHorizontalAlignment = .left
        showMoreButton.addTarget(self, action: #selector(showMoreTapped), for: .touchUpInside)
        showMoreButton.isHidden = true
        
        // Info stack for show more + website + lightning (collapses when hidden)
        let infoStack = UIStackView()
        infoStack.axis = .vertical
        infoStack.spacing = 4
        infoStack.alignment = .leading
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        profileSectionView.addSubview(infoStack)
        
        // Add show more to stack first
        infoStack.addArrangedSubview(showMoreButton)
        
        // Website button
        websiteButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        websiteButton.setTitleColor(.accentPurple, for: .normal)
        websiteButton.contentHorizontalAlignment = .left
        websiteButton.addTarget(self, action: #selector(websiteTapped), for: .touchUpInside)
        websiteButton.isHidden = true
        
        let linkIcon = UIImage(systemName: "link", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        websiteButton.setImage(linkIcon, for: .normal)
        websiteButton.tintColor = .accentPurple
        websiteButton.configuration = {
            var config = UIButton.Configuration.plain()
            config.imagePadding = 4
            config.contentInsets = .zero
            return config
        }()
        infoStack.addArrangedSubview(websiteButton)

        // Stats row (following / followers)
        statsStackView.axis = .horizontal
        statsStackView.spacing = 16
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        profileSectionView.addSubview(statsStackView)
        
        followingCountLabel.font = .systemFont(ofSize: 14, weight: .regular)
        followingCountLabel.textColor = .label
        followingCountLabel.isUserInteractionEnabled = true
        followingCountLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(followingTapped)))
        statsStackView.addArrangedSubview(followingCountLabel)
        
        followersCountLabel.font = .systemFont(ofSize: 14, weight: .regular)
        followersCountLabel.textColor = .label
        followersCountLabel.isUserInteractionEnabled = true
        followersCountLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(followersTapped)))
        statsStackView.addArrangedSubview(followersCountLabel)

        setupProfileSkeletons()

        // Profile section starts with padding for the profile pic overlap area
        let profilePicAreaHeight = Layout.profilePicSize - Layout.profilePicOverlap + 12

        NSLayoutConstraint.activate([
            // Action button (Zap) - top right with container (glass deferred)
            actionContainer.topAnchor.constraint(equalTo: profileSectionView.topAnchor, constant: 12),
            actionContainer.trailingAnchor.constraint(equalTo: profileSectionView.trailingAnchor, constant: -Layout.horizontalPadding),
            actionContainer.heightAnchor.constraint(equalToConstant: 36),
            
            actionButton.topAnchor.constraint(equalTo: actionContainer.topAnchor),
            actionButton.leadingAnchor.constraint(equalTo: actionContainer.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: actionContainer.trailingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: actionContainer.bottomAnchor),

            // Edit profile button with container
            editContainer.topAnchor.constraint(equalTo: profileSectionView.topAnchor, constant: 12),
            editContainer.trailingAnchor.constraint(equalTo: actionContainer.leadingAnchor, constant: -8),
            editContainer.widthAnchor.constraint(equalToConstant: 56),
            editContainer.heightAnchor.constraint(equalToConstant: 36),
            
            editProfileButton.topAnchor.constraint(equalTo: editContainer.topAnchor),
            editProfileButton.leadingAnchor.constraint(equalTo: editContainer.leadingAnchor),
            editProfileButton.trailingAnchor.constraint(equalTo: editContainer.trailingAnchor),
            editProfileButton.bottomAnchor.constraint(equalTo: editContainer.bottomAnchor),
            
            // Settings button with container
            settingsContainer.topAnchor.constraint(equalTo: profileSectionView.topAnchor, constant: 12),
            settingsContainer.trailingAnchor.constraint(equalTo: editContainer.leadingAnchor, constant: -8),
            settingsContainer.widthAnchor.constraint(equalToConstant: 36),
            settingsContainer.heightAnchor.constraint(equalToConstant: 36),
            
            settingsButton.topAnchor.constraint(equalTo: settingsContainer.topAnchor),
            settingsButton.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: settingsContainer.trailingAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: settingsContainer.bottomAnchor),

            // Zap button container — left of action button (for other users' profiles)
            zapContainer.topAnchor.constraint(equalTo: profileSectionView.topAnchor, constant: 12),
            zapContainer.trailingAnchor.constraint(equalTo: actionContainer.leadingAnchor, constant: -8),
            zapContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            zapContainer.heightAnchor.constraint(equalToConstant: 36),

            profileZapButton.topAnchor.constraint(equalTo: zapContainer.topAnchor),
            profileZapButton.leadingAnchor.constraint(equalTo: zapContainer.leadingAnchor),
            profileZapButton.trailingAnchor.constraint(equalTo: zapContainer.trailingAnchor),
            profileZapButton.bottomAnchor.constraint(equalTo: zapContainer.bottomAnchor),

            // QR button container
            qrContainer.topAnchor.constraint(equalTo: profileSectionView.topAnchor, constant: 12),
            qrContainer.widthAnchor.constraint(equalToConstant: 36),
            qrContainer.heightAnchor.constraint(equalToConstant: 36),

            profileQRButton.topAnchor.constraint(equalTo: qrContainer.topAnchor),
            profileQRButton.leadingAnchor.constraint(equalTo: qrContainer.leadingAnchor),
            profileQRButton.trailingAnchor.constraint(equalTo: qrContainer.trailingAnchor),
            profileQRButton.bottomAnchor.constraint(equalTo: qrContainer.bottomAnchor),

            // Follows you badge
            followsYouBadge.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            followsYouBadge.trailingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: -8),

            // Display name
            displayNameLabel.topAnchor.constraint(equalTo: profileSectionView.topAnchor, constant: profilePicAreaHeight),
            displayNameLabel.leadingAnchor.constraint(equalTo: profileSectionView.leadingAnchor, constant: Layout.horizontalPadding),
            displayNameLabel.trailingAnchor.constraint(equalTo: profileSectionView.trailingAnchor, constant: -Layout.horizontalPadding),

            // Username
            usernameLabel.topAnchor.constraint(equalTo: displayNameLabel.bottomAnchor, constant: 2),
            usernameLabel.leadingAnchor.constraint(equalTo: displayNameLabel.leadingAnchor),
            
            // NIP-05 (after username)
            nip05Label.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            nip05Label.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 8),
            nip05Label.trailingAnchor.constraint(lessThanOrEqualTo: profileSectionView.trailingAnchor, constant: -Layout.horizontalPadding),

            // Bio
            bioLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 12),
            bioLabel.leadingAnchor.constraint(equalTo: displayNameLabel.leadingAnchor),
            bioLabel.trailingAnchor.constraint(equalTo: displayNameLabel.trailingAnchor),
            
            // Info stack (showMore + website + lightning) - directly after bio
            infoStack.topAnchor.constraint(equalTo: bioLabel.bottomAnchor, constant: 6),
            infoStack.leadingAnchor.constraint(equalTo: displayNameLabel.leadingAnchor),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: profileSectionView.trailingAnchor, constant: -Layout.horizontalPadding),

            // Stats row
            statsStackView.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 12),
            statsStackView.leadingAnchor.constraint(equalTo: displayNameLabel.leadingAnchor),
            statsStackView.bottomAnchor.constraint(equalTo: profileSectionView.bottomAnchor, constant: -20),
        ])

        // Create the action container width constraints (toggled for own profile)
        if let actionContainer = profileSectionView.viewWithTag(1001) {
            actionContainerWidthConstraint = actionContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
            actionContainerWidthConstraint.isActive = true
            actionContainerCollapseConstraint = actionContainer.widthAnchor.constraint(equalToConstant: 0)
            actionContainerCollapseConstraint.isActive = false
        }

        // Create QR button trailing constraints (mutually exclusive)
        if let qrContainer = profileSectionView.viewWithTag(1006),
           let zapContainer = profileSectionView.viewWithTag(1005),
           let actionContainer = profileSectionView.viewWithTag(1001),
           let settingsContainer = profileSectionView.viewWithTag(1003) {
            qrTrailingToZap = qrContainer.trailingAnchor.constraint(equalTo: zapContainer.leadingAnchor, constant: -8)
            qrTrailingToAction = qrContainer.trailingAnchor.constraint(equalTo: actionContainer.leadingAnchor, constant: -8)
            qrTrailingToSettings = qrContainer.trailingAnchor.constraint(equalTo: settingsContainer.leadingAnchor, constant: -8)
            // Default: will be set properly in updateActionButton()
        }

        // Add zaps label to the stats row (hidden until API data arrives)
        zapsStatLabel.font = .systemFont(ofSize: 14, weight: .regular)
        zapsStatLabel.textColor = .label
        zapsStatLabel.isHidden = true
        statsStackView.addArrangedSubview(zapsStatLabel)
    }

    private func setupProfileSkeletons() {
        for skeleton in [nameSkeleton, usernameSkeleton, bioSkeleton, bioSkeleton2, followingSkeleton] {
            skeleton.layer.cornerRadius = 6
            skeleton.translatesAutoresizingMaskIntoConstraints = false
            profileSectionView.addSubview(skeleton)
            skeleton.startAnimating()
        }

        let profilePicAreaHeight = Layout.profilePicSize - Layout.profilePicOverlap + 8

        NSLayoutConstraint.activate([
            nameSkeleton.topAnchor.constraint(equalTo: profileSectionView.topAnchor, constant: profilePicAreaHeight),
            nameSkeleton.leadingAnchor.constraint(equalTo: profileSectionView.leadingAnchor, constant: Layout.horizontalPadding),
            nameSkeleton.widthAnchor.constraint(equalToConstant: 150),
            nameSkeleton.heightAnchor.constraint(equalToConstant: 20),

            usernameSkeleton.topAnchor.constraint(equalTo: nameSkeleton.bottomAnchor, constant: 6),
            usernameSkeleton.leadingAnchor.constraint(equalTo: nameSkeleton.leadingAnchor),
            usernameSkeleton.widthAnchor.constraint(equalToConstant: 100),
            usernameSkeleton.heightAnchor.constraint(equalToConstant: 16),

            bioSkeleton.topAnchor.constraint(equalTo: usernameSkeleton.bottomAnchor, constant: 12),
            bioSkeleton.leadingAnchor.constraint(equalTo: nameSkeleton.leadingAnchor),
            bioSkeleton.trailingAnchor.constraint(equalTo: profileSectionView.trailingAnchor, constant: -Layout.horizontalPadding),
            bioSkeleton.heightAnchor.constraint(equalToConstant: 14),

            bioSkeleton2.topAnchor.constraint(equalTo: bioSkeleton.bottomAnchor, constant: 6),
            bioSkeleton2.leadingAnchor.constraint(equalTo: nameSkeleton.leadingAnchor),
            bioSkeleton2.widthAnchor.constraint(equalToConstant: 200),
            bioSkeleton2.heightAnchor.constraint(equalToConstant: 14),

            followingSkeleton.topAnchor.constraint(equalTo: bioSkeleton2.bottomAnchor, constant: 12),
            followingSkeleton.leadingAnchor.constraint(equalTo: nameSkeleton.leadingAnchor),
            followingSkeleton.widthAnchor.constraint(equalToConstant: 120),
            followingSkeleton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func updateEnrichedStats() {
        guard let user = viewModel.profilestrUser else {
            zapsStatLabel.isHidden = true
            return
        }

        let zapAmount = user.totalAmountReceived ?? 0
        let zapText = Self.abbreviatedCount(zapAmount)
        let zapsCombined = NSMutableAttributedString()
        zapsCombined.append(NSAttributedString(
            string: "\(zapText) ",
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .bold)]
        ))
        zapsCombined.append(NSAttributedString(
            string: "⚡ received",
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
        ))
        zapsStatLabel.attributedText = zapsCombined
        zapsStatLabel.isHidden = false
    }

    private func updateTrustBadge() {
        guard let user = viewModel.profilestrUser else { return }

        // Update NIP-05 label with trust-aware display
        if let combined = user.trustScores?.combined {
            let dot = Self.trustDot(for: combined.score ?? 0)
            let level = combined.level ?? "New"

            if let nip05 = viewModel.profileMetadata?.nostrAddress, !nip05.isEmpty {
                let domain = nip05.components(separatedBy: "@").last ?? nip05
                nip05Label.text = "\(dot) \(level) · \(domain)"
            } else {
                nip05Label.text = "\(dot) \(level)"
            }
            nip05Label.isHidden = false
        }

        // Update banner verified badge — only show if NIP-05 is actually validated
        let isValidated = viewModel.isNip05Validated
        let hasNip05 = viewModel.profileMetadata?.nostrAddress?.isEmpty == false
        bannerVerifiedBadge.isHidden = !(isValidated || hasNip05)
    }

    private static func trustDot(for score: Int) -> String {
        switch score {
        case 76...100: return "🟣"
        case 51...75: return "🟢"
        case 26...50: return "🟡"
        default: return "⚪"
        }
    }

    private static func abbreviatedCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private static func statAttributedString(value: String, label: String, icon: String?) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let icon = icon {
            let attachment = NSTextAttachment()
            let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            attachment.image = UIImage(systemName: icon, withConfiguration: config)?.withTintColor(.secondaryLabel)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }

        result.append(NSAttributedString(
            string: value,
            attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .bold)]
        ))
        result.append(NSAttributedString(
            string: " \(label)",
            attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
        ))
        return result
    }

    // MARK: - Setup: Streams Section
    private func setupStreamsSection() {
        streamsSectionView.backgroundColor = .systemBackground
        streamsSectionView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(streamsSectionView)

        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            self?.createStreamsLayout(for: sectionIndex)
        }

        streamsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        streamsCollectionView.backgroundColor = .clear
        streamsCollectionView.isScrollEnabled = false
        streamsCollectionView.delegate = self
        streamsCollectionView.dataSource = self
        streamsCollectionView.translatesAutoresizingMaskIntoConstraints = false

        // Register shared StreamCardCell instead of ProfileStreamCell
        streamsCollectionView.register(StreamCardCell.self, forCellWithReuseIdentifier: StreamCardCell.reuseIdentifier)
        streamsCollectionView.register(CarouselSkeletonCell.self, forCellWithReuseIdentifier: CarouselSkeletonCell.reuseIdentifier)
        streamsCollectionView.register(ProfileEmptyCell.self, forCellWithReuseIdentifier: ProfileEmptyCell.reuseIdentifier)
        
        // Register section header
        streamsCollectionView.register(
            ProfileSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ProfileSectionHeaderView.reuseIdentifier
        )

        streamsSectionView.addSubview(streamsCollectionView)

        // Set initial height for skeleton section (horizontal carousel)
        // Cards (240) + bottom padding (16)
        let initialHeight = Layout.carouselCardHeight + 16

        NSLayoutConstraint.activate([
            streamsCollectionView.topAnchor.constraint(equalTo: streamsSectionView.topAnchor),
            streamsCollectionView.leadingAnchor.constraint(equalTo: streamsSectionView.leadingAnchor),
            streamsCollectionView.trailingAnchor.constraint(equalTo: streamsSectionView.trailingAnchor),
            streamsCollectionView.bottomAnchor.constraint(equalTo: streamsSectionView.bottomAnchor),
            streamsSectionView.heightAnchor.constraint(equalToConstant: initialHeight),
        ])
    }

    private func createStreamsLayout(for sectionIndex: Int) -> NSCollectionLayoutSection {
        // Check if this section shows the empty state
        let resolvedSection = getSectionType(for: sectionIndex)
        let isEmpty = resolvedSection == .pastStreams && pastStreams.isEmpty && !isLoadingInitialData

        // Item fills group
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let group: NSCollectionLayoutGroup
        if isEmpty {
            // Full-width layout for empty state so content is centered
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(240)
            )
            group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        } else {
            // Fixed size group (matches main page exactly: 280×240)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(Layout.carouselCardWidth),
                heightDimension: .absolute(Layout.carouselCardHeight)
            )
            group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        }

        let section = NSCollectionLayoutSection(group: group)
        if !isEmpty {
            section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary  // Horizontal scroll
            section.interGroupSpacing = 12
        }
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: isEmpty ? 0 : 16, bottom: 16, trailing: isEmpty ? 0 : 16)

        // Add section header (only when not loading)
        if !isLoadingInitialData {
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(Layout.carouselHeaderHeight)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
        }

        return section
    }

    // MARK: - Setup: Settings Button
    private func setupSettingsButton() {
        // Settings button is now part of the profile section button row
        // Setup is handled in setupProfileSection
    }
    
    // MARK: - Setup: Back Button
    private var backGlassView: GlassContainerView?
    
    private func setupBackButton() {
        guard showBackButton else { return }
        
        // Create a lightweight placeholder container — glass deferred to materializeGlassViews()
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.tag = 1004  // Tag for later lookup
        
        // Create the button inside the container (will be re-parented into glass later)
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.setImage(UIImage(systemName: "chevron.left", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        
        container.addSubview(button)
        view.addSubview(container)
        view.bringSubviewToFront(container)
        
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            container.widthAnchor.constraint(equalToConstant: 40),
            container.heightAnchor.constraint(equalToConstant: 40),
            
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
    
    @objc private func backButtonTapped() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Deferred Glass Materialization
    private func materializeGlassViews() {
        // Action glass
        if actionGlassView == nil, let container = profileSectionView.viewWithTag(1001) {
            let glass = GlassFactory.makeGlassView(cornerRadius: 18)
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(glass, at: 0)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            // Re-parent button into glass contentView
            actionButton.removeFromSuperview()
            glass.glassContentView.addSubview(actionButton)
            NSLayoutConstraint.activate([
                actionButton.topAnchor.constraint(equalTo: glass.topAnchor),
                actionButton.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                actionButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                actionButton.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            actionGlassView = glass
        }
        
        // Edit glass
        if editGlassView == nil, let container = profileSectionView.viewWithTag(1002) {
            let glass = GlassFactory.makeGlassView(cornerRadius: 18)
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(glass, at: 0)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            editProfileButton.removeFromSuperview()
            glass.glassContentView.addSubview(editProfileButton)
            NSLayoutConstraint.activate([
                editProfileButton.topAnchor.constraint(equalTo: glass.topAnchor),
                editProfileButton.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                editProfileButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                editProfileButton.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            editGlassView = glass
        }
        
        // Settings glass
        if settingsGlassView == nil, let container = profileSectionView.viewWithTag(1003) {
            let glass = GlassFactory.makeGlassView(cornerRadius: 18)
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(glass, at: 0)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            settingsButton.removeFromSuperview()
            glass.glassContentView.addSubview(settingsButton)
            NSLayoutConstraint.activate([
                settingsButton.topAnchor.constraint(equalTo: glass.topAnchor),
                settingsButton.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                settingsButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                settingsButton.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            settingsGlassView = glass
        }
        
        // Zap glass
        if zapGlassView == nil, let container = profileSectionView.viewWithTag(1005) {
            let glass = GlassFactory.makeGlassView(cornerRadius: 18)
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(glass, at: 0)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            profileZapButton.removeFromSuperview()
            glass.glassContentView.addSubview(profileZapButton)
            NSLayoutConstraint.activate([
                profileZapButton.topAnchor.constraint(equalTo: glass.topAnchor),
                profileZapButton.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                profileZapButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                profileZapButton.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            zapGlassView = glass
        }
        
        // QR glass
        if qrGlassView == nil, let container = profileSectionView.viewWithTag(1006) {
            let glass = GlassFactory.makeGlassView(cornerRadius: 18)
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(glass, at: 0)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            profileQRButton.removeFromSuperview()
            glass.glassContentView.addSubview(profileQRButton)
            NSLayoutConstraint.activate([
                profileQRButton.topAnchor.constraint(equalTo: glass.topAnchor),
                profileQRButton.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                profileQRButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                profileQRButton.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            qrGlassView = glass
        }

        // Back button glass
        if backGlassView == nil, let container = view.viewWithTag(1004) {
            let glass = GlassFactory.makeGlassView(cornerRadius: 20)
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(glass, at: 0)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            // Re-parent the back button into glass contentView
            if let backButton = container.subviews.first(where: { $0 is UIButton }) {
                backButton.removeFromSuperview()
                glass.glassContentView.addSubview(backButton)
                NSLayoutConstraint.activate([
                    backButton.topAnchor.constraint(equalTo: glass.topAnchor),
                    backButton.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                    backButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                    backButton.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
                ])
            }
            backGlassView = glass
        }
    }

    // MARK: - Setup: Guest Overlay (SwiftUI)
    private func setupGuestOverlay() {
        let guestView = GuestProfileOverlay(appState: appState)
        let hostingController = UIHostingController(rootView: AnyView(guestView.environmentObject(appState)))
        hostingController.view.backgroundColor = .systemBackground
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.isHidden = true

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        guestHostingController = hostingController
    }

    // MARK: - Setup: Observers
    private func setupObservers() {
        // Observe profile metadata changes — skip initial value (configureInitialState handles it)
        // Filter to only react when OUR profile's metadata actually changed
        appState.$metadataEvents
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metadataEvents in
                guard let self = self else { return }
                let newMetadata = metadataEvents[self.viewModel.publicKeyHex]?.userMetadata
                let oldMetadata = self.lastSeenMetadata
                
                // Check if visual profile fields changed
                let profileChanged = newMetadata?.displayName != oldMetadata?.displayName
                    || newMetadata?.name != oldMetadata?.name
                    || newMetadata?.about != oldMetadata?.about
                    || newMetadata?.pictureURL != oldMetadata?.pictureURL
                    || newMetadata?.bannerPictureURL != oldMetadata?.bannerPictureURL
                
                // Check if lightning address changed (affects zap button visibility)
                let lightningChanged = newMetadata?.lightningAddress != oldMetadata?.lightningAddress
                
                if profileChanged || lightningChanged {
                    self.lastSeenMetadata = newMetadata
                }
                if profileChanged {
                    self.updateProfileInfo()
                }
                if lightningChanged {
                    self.updateActionButton()
                }
            }
            .store(in: &cancellables)

        // Observe follow list changes — skip initial value
        appState.$followListEvents
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFollowingCount()
            }
            .store(in: &cancellables)

        // Observe live activities — skip initial value, debounce rapid updates
        appState.$liveActivitiesEvents
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] (_: [String: [LiveActivitiesEvent]]) in
                self?.rebuildStreams()
            }
            .store(in: &cancellables)

        // Observe follow state changes
        viewModel.$followState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateActionButton()
            }
            .store(in: &cancellables)

        // Observe Profilestr API data (followers count, stats, trust scores)
        viewModel.$profilestrUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFollowingCount()
                self?.updateEnrichedStats()
                self?.updateTrustBadge()
            }
            .store(in: &cancellables)
        
        // Listen for followed notifications to update state
        handle_notify(.followed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] followedPubkeys in
                guard let self = self else { return }
                if followedPubkeys.contains(self.viewModel.publicKeyHex) {
                    self.viewModel.followState = .follows
                }
            }
            .store(in: &cancellables)
        
        // Listen for unfollowed notifications to update state
        handle_notify(.unfollowed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] unfollowedPubkeys in
                guard let self = self else { return }
                if !unfollowedPubkeys.contains(self.viewModel.publicKeyHex) {
                    self.viewModel.followState = .unfollows
                }
            }
            .store(in: &cancellables)

        // Observe active profile changes
        appState.$activeProfileId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newActiveProfileId in
                guard let self = self, self.isViewingActiveProfile else { return }
                
                // Handle the new profile ID (could be nil for guest, empty string, or a valid hex)
                let newPublicKeyHex = newActiveProfileId ?? ""
                
                // Only update if the profile actually changed
                guard newPublicKeyHex != self.viewModel.publicKeyHex else { return }
                
                // Unsubscribe from old profile if it was valid
                if !self.viewModel.publicKeyHex.isEmpty {
                    self.appState.unsubscribeFromProfile(for: self.viewModel.publicKeyHex)
                }
                
                // Update view model with new profile
                self.viewModel.updatePublicKeyHex(newPublicKeyHex)
                
                // Reset UI state for new profile
                self.resetForNewProfile()
                
                // Fetch data for new profile if it's not a guest
                if !newPublicKeyHex.isEmpty {
                    self.appState.pullMissingEventsFromPubkeysAndFollows([newPublicKeyHex])
                    self.appState.subscribeToProfile(for: newPublicKeyHex)
                }
                
                // Update UI
                self.configureInitialState()
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration
    private func configureInitialState() {
        let isGuest = viewModel.publicKeyHex.isEmpty
        
        if isGuest {
            setupGuestOverlayIfNeeded()
        }
        
        guestHostingController?.view.isHidden = !isGuest
        scrollView.isHidden = isGuest
        bannerContainerView.isHidden = isGuest
        profilePicContainerView.isHidden = isGuest

        guard !isGuest else { return }

        updateBanner()
        updateProfileInfo()
        updateActionButton()
        rebuildStreams()
        viewModel.fetchProfilestrData()
    }
    
    private func setupGuestOverlayIfNeeded() {
        guard !hasSetupGuestOverlay else { return }
        hasSetupGuestOverlay = true
        setupGuestOverlay()
    }

    private func updateBanner() {
        // Check if this is a guest profile (no public key)
        let isGuestProfile = viewModel.publicKeyHex.isEmpty
        
        if isGuestProfile {
            // Guest profile - show default banner immediately
            bannerSkeletonView.stopAnimating()
            bannerSkeletonView.isHidden = true
            bannerImageView.image = defaultBannerImage
            return
        }
        
        guard let metadata = viewModel.profileMetadata else {
            // No metadata yet - keep showing skeleton (still loading metadata)
            bannerSkeletonView.isHidden = false
            bannerSkeletonView.startAnimating()
            return
        }

        if let bannerURL = metadata.bannerPictureURL {
            // Has banner URL - show skeleton while loading image
            bannerSkeletonView.isHidden = false
            bannerSkeletonView.startAnimating()
            
            bannerImageView.kf.setImage(
                with: bannerURL,
                options: [
                    .transition(.fade(0.3)),
                    .cacheOriginalImage,
                    .backgroundDecode,
                ]
            ) { [weak self] result in
                self?.bannerSkeletonView.stopAnimating()
                self?.bannerSkeletonView.isHidden = true
                if case .failure = result {
                    self?.bannerImageView.image = self?.defaultBannerImage
                }
            }
        } else {
            // No banner URL - show default image immediately (no skeleton needed)
            bannerSkeletonView.stopAnimating()
            bannerSkeletonView.isHidden = true
            bannerImageView.image = defaultBannerImage
        }
    }

    private func updateProfileInfo() {
        // Check if this is a guest profile (no public key)
        let isGuestProfile = viewModel.publicKeyHex.isEmpty
        
        // For guest profiles or when we have metadata, hide skeletons and show content
        if isGuestProfile {
            // Guest profile - show default guest UI
            hideSkeleton()
            
            // Show default profile picture
            profilePicSkeletonView.stopAnimating()
            profilePicSkeletonView.isHidden = true
            profilePicImageView.image = defaultProfileImage
            
            // Show guest display name
            displayNameLabel.text = "Guest"
            usernameLabel.text = "@guest"
            usernameLabel.isHidden = false
            
            // Hide all optional fields for guest
            nip05Label.isHidden = true
            bioLabel.isHidden = true
            showMoreButton.isHidden = true
            websiteButton.isHidden = true
            followsYouBadge.isHidden = true
            
            // Update following count (will be 0 for guest)
            updateFollowingCount()
            
            // Update banner to default
            updateBanner()
            
            // Update banner name for guest
            bannerNameLabel.text = "Guest"
            bannerMiniProfilePic.image = defaultProfileImage
            bannerVerifiedBadge.isHidden = true
            return
        }
        
        guard let metadata = viewModel.profileMetadata else {
            // No metadata yet — still hide skeletons so blank bars don't linger
            hideSkeleton()
            displayNameLabel.text = ""
            usernameLabel.isHidden = true
            bioLabel.isHidden = true
            showMoreButton.isHidden = true
            websiteButton.isHidden = true
            nip05Label.isHidden = true
            updateFollowingCount()
            updateBanner()
            return
        }

        // Hide skeletons, show real content
        hideSkeleton()

        // Profile picture
        if let pictureURL = metadata.pictureURL {
            // Has picture URL - show skeleton while loading image
            profilePicSkeletonView.isHidden = false
            profilePicSkeletonView.startAnimating()
            
            profilePicImageView.kf.setImage(
                with: pictureURL,
                options: [
                    .transition(.fade(0.2)),
                    .cacheOriginalImage,
                    .processor(DownsamplingImageProcessor(size: CGSize(width: Layout.profilePicSize * 2, height: Layout.profilePicSize * 2))),
                    .backgroundDecode,
                ]
            ) { [weak self] result in
                self?.profilePicSkeletonView.stopAnimating()
                self?.profilePicSkeletonView.isHidden = true
                if case .failure = result {
                    self?.profilePicImageView.image = self?.defaultProfileImage
                }
            }
        } else {
            // No picture URL - show default image immediately (no skeleton needed)
            profilePicSkeletonView.stopAnimating()
            profilePicSkeletonView.isHidden = true
            profilePicImageView.image = defaultProfileImage
        }

        // Display name
        displayNameLabel.text = metadata.displayName?.truncate(maxLength: 25) ?? metadata.name?.truncate(maxLength: 25) ?? "Anonymous"

        // Username
        if let name = metadata.name {
            usernameLabel.text = "@\(name.truncate(maxLength: 25))"
            usernameLabel.isHidden = false
        } else {
            usernameLabel.isHidden = true
        }
        
        // NIP-05 verification
        if let nip05 = metadata.nostrAddress, !nip05.isEmpty {
            // Show checkmark + domain part
            let domain = nip05.components(separatedBy: "@").last ?? nip05
            nip05Label.text = "✓ \(domain)"
            nip05Label.isHidden = false
        } else {
            nip05Label.isHidden = true
        }

        // Bio
        if let about = metadata.about, !about.isEmpty {
            bioLabel.attributedText = buildAttributedBio(about)
            bioLabel.isHidden = false
            updateShowMoreButton()
            
            // Fetch metadata for any mentioned pubkeys in the bio
            fetchBioMentionMetadata(about)
        } else {
            bioLabel.isHidden = true
            showMoreButton.isHidden = true
        }
        
        // Website
        if let website = metadata.website {
            let displayURL = website.absoluteString
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            websiteButton.setTitle(displayURL, for: .normal)
            websiteButton.isHidden = false
        } else {
            websiteButton.isHidden = true
        }
        
        // Follows you badge - hide if viewing own profile
        followsYouBadge.isHidden = isViewingActiveProfile || !viewModel.followsYou

        // Following count
        updateFollowingCount()

        // Update banner
        updateBanner()
        
        // Update banner name label
        bannerNameLabel.text = metadata.displayName ?? metadata.name ?? "Anonymous"
        
        // Update banner mini profile pic (reuse the same image as main profile pic)
        if let pictureURL = metadata.pictureURL {
            bannerMiniProfilePic.kf.setImage(
                with: pictureURL,
                options: [
                    .transition(.fade(0.2)),
                    .cacheOriginalImage,
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 56, height: 56))),
                    .backgroundDecode,
                ]
            )
        } else {
            bannerMiniProfilePic.image = defaultProfileImage
        }
        
        // Update banner verified badge (show if NIP-05 verified)
        if let nip05 = metadata.nostrAddress, !nip05.isEmpty {
            bannerVerifiedBadge.isHidden = false
        } else {
            bannerVerifiedBadge.isHidden = true
        }
        
        // Cache metadata for change detection in observers
        lastSeenMetadata = metadata
    }

    private func updateFollowingCount() {
        // Following count
        let followingCount = viewModel.profileFollowList.count
        let followingCountString = NSAttributedString(
            string: "\(followingCount.formatted()) ",
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .bold)]
        )
        let followingText = NSAttributedString(
            string: "following",
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
        )
        let followingCombined = NSMutableAttributedString()
        followingCombined.append(followingCountString)
        followingCombined.append(followingText)
        followingCountLabel.attributedText = followingCombined
        
        // Followers count (from viewModel if available)
        let followersCount = viewModel.followersCount
        let followersCountString = NSAttributedString(
            string: "\(followersCount.formatted()) ",
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .bold)]
        )
        let followersText = NSAttributedString(
            string: "followers",
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
        )
        let followersCombined = NSMutableAttributedString()
        followersCombined.append(followersCountString)
        followersCombined.append(followersText)
        followersCountLabel.attributedText = followersCombined
    }

    private func updateActionButton() {
        let isOwnProfile = viewModel.publicKeyHex == appState.appSettings?.activeProfile?.publicKeyHex
        let isLoading = viewModel.followState == .following || viewModel.followState == .unfollowing

        // Show/hide edit and settings buttons based on own profile
        editGlassView?.isHidden = !isOwnProfile
        settingsGlassView?.isHidden = !isOwnProfile
        // Also toggle the containers (glass may not be materialized yet)
        profileSectionView.viewWithTag(1002)?.isHidden = !isOwnProfile
        profileSectionView.viewWithTag(1003)?.isHidden = !isOwnProfile
        
        // Show/hide zap button — only for OTHER users who have a lightning address
        let hasLightningAddress = viewModel.profileMetadata?.lightningAddress?.isEmpty == false
        let showZap = !isOwnProfile && hasLightningAddress
        zapGlassView?.isHidden = !showZap
        profileSectionView.viewWithTag(1005)?.isHidden = !showZap

        // QR button — always visible, position depends on which buttons are showing
        qrTrailingToZap?.isActive = false
        qrTrailingToAction?.isActive = false
        qrTrailingToSettings?.isActive = false
        if isOwnProfile {
            qrTrailingToSettings?.isActive = true
        } else if showZap {
            qrTrailingToZap?.isActive = true
        } else {
            qrTrailingToAction?.isActive = true
        }

        if isOwnProfile {
            // Hide the action button entirely for own profile
            // Collapse width to 0 so it doesn't leave a gap
            actionButton.isHidden = true
            profileSectionView.viewWithTag(1001)?.isHidden = true
            actionContainerWidthConstraint.isActive = false
            actionContainerCollapseConstraint.isActive = true
        } else {
            // Show follow/unfollow button — restore width
            actionButton.isHidden = false
            profileSectionView.viewWithTag(1001)?.isHidden = false
            actionContainerCollapseConstraint.isActive = false
            actionContainerWidthConstraint.isActive = true
            actionButton.isEnabled = !isLoading

            // Show follow/unfollow button with visual feedback for loading states
            switch viewModel.followState {
            case .follows:
                actionButton.setTitle("Following", for: .normal)
                actionButton.setTitleColor(.label, for: .normal)
                actionButton.alpha = 1.0
            case .unfollows:
                actionButton.setTitle("Follow", for: .normal)
                actionButton.setTitleColor(.accentPurple, for: .normal)
                actionButton.alpha = 1.0
            case .following:
                actionButton.setTitle("Following...", for: .normal)
                actionButton.setTitleColor(.accentPurple, for: .normal)
                actionButton.alpha = 0.6  // Dimmed to show loading
            case .unfollowing:
                actionButton.setTitle("Unfollowing...", for: .normal)
                actionButton.setTitleColor(.secondaryLabel, for: .normal)
                actionButton.alpha = 0.6  // Dimmed to show loading
            }
        }
    }

    private func updateShowMoreButton() {
        // Check if bio is truncated
        let maxLayoutWidth = view.bounds.width - (Layout.horizontalPadding * 2)
        let boundingRect = bioLabel.text?.boundingRect(
            with: CGSize(width: maxLayoutWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bioLabel.font as Any],
            context: nil
        )

        let lineHeight = bioLabel.font.lineHeight
        let maxLines: CGFloat = 3
        let isTruncated = (boundingRect?.height ?? 0) > (lineHeight * maxLines)

        // Show button if bio is truncatable (either to show "more" or "less")
        showMoreButton.isHidden = !isTruncated
        
        // Update button text based on current state
        if isBioExpanded {
            showMoreButton.setTitle("less", for: .normal)
        } else {
            showMoreButton.setTitle("more", for: .normal)
        }
    }

    // MARK: - Skeleton Management
    private func hideSkeleton() {
        isShowingSkeleton = false
        isLoadingInitialData = false

        [nameSkeleton, usernameSkeleton, bioSkeleton, bioSkeleton2, followingSkeleton].forEach {
            $0.stopAnimating()
            $0.isHidden = true
        }

        displayNameLabel.isHidden = false
        usernameLabel.isHidden = false
        bioLabel.isHidden = false
        followingCountLabel.isHidden = false
    }

    private func restartSkeletonAnimations() {
        guard isShowingSkeleton else { return }

        bannerSkeletonView.startAnimating()
        profilePicSkeletonView.startAnimating()
        [nameSkeleton, usernameSkeleton, bioSkeleton, bioSkeleton2, followingSkeleton].forEach {
            $0.startAnimating()
        }

        // Restart stream skeleton animations
        for cell in streamsCollectionView.visibleCells {
            if let skeletonCell = cell as? CarouselSkeletonCell {
                skeletonCell.restartAnimations()
            }
        }
    }
    
    private func resetForNewProfile() {
        // Reset loading state
        isLoadingInitialData = true
        isShowingSkeleton = true
        isBioExpanded = false
        liveStreams = []
        pastStreams = []
        lastSeenMetadata = nil
        
        // Show skeletons again
        [nameSkeleton, usernameSkeleton, bioSkeleton, bioSkeleton2, followingSkeleton].forEach {
            $0.isHidden = false
            $0.startAnimating()
        }
        
        // Hide content labels while loading
        displayNameLabel.isHidden = true
        usernameLabel.isHidden = true
        bioLabel.isHidden = true
        followingCountLabel.isHidden = true
        showMoreButton.isHidden = true
        followsYouBadge.isHidden = true
        zapsStatLabel.isHidden = true
        
        // Reset images to default/skeleton
        bannerImageView.image = nil
        bannerSkeletonView.isHidden = false
        bannerSkeletonView.startAnimating()
        
        profilePicImageView.image = nil
        profilePicSkeletonView.isHidden = false
        profilePicSkeletonView.startAnimating()
        profilePicContainerView.alpha = 1.0  // Ensure profile pic is visible
        
        // Reset profile pic size and position
        profilePicWidthConstraint.constant = Layout.profilePicSize
        profilePicHeightConstraint.constant = Layout.profilePicSize
        profilePicImageView.layer.cornerRadius = Layout.profilePicSize / 2
        profilePicSkeletonView.layer.cornerRadius = Layout.profilePicSize / 2
        
        // Reset bio expansion
        bioLabel.numberOfLines = 3
        
        // Reset blur and name
        bannerBlurAnimator?.fractionComplete = 0
        bannerBlurView.alpha = 0
        bannerNameStackView.alpha = 0
        bannerNameLabel.text = nil
        bannerMiniProfilePic.image = nil
        bannerVerifiedBadge.isHidden = true
        
        // Reload streams collection to show skeletons
        streamsCollectionView.reloadData()
        updateCollectionViewHeight()
    }

    // MARK: - Streams Management
    private func rebuildStreams() {
        let allEvents: [LiveActivitiesEvent] = appState.getAllEvents()
        let pubkey = viewModel.publicKeyHex
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Filter by pubkey as author OR as host participant (per NIP-53)
            let filtered = allEvents.filter { event in
                event.pubkey == pubkey
                    || event.hostPubkeyHex == pubkey
            }
            
            let live = filtered.filter { $0.isActuallyLive }
                .sorted { $0.currentParticipants > $1.currentParticipants }
            
            let past = filtered.filter { !$0.isActuallyLive }
                .sorted { (event1, event2) -> Bool in
                    let date1 = event1.startsAt ?? Date.distantPast
                    let date2 = event2.startsAt ?? Date.distantPast
                    return date1 > date2
                }
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.liveStreams = live
                self.pastStreams = past
                
                if !live.isEmpty || !past.isEmpty {
                    self.isLoadingInitialData = false
                }
                
                self.streamsCollectionView.reloadData()
                self.updateCollectionViewHeight()
            }
        }
    }
    
    /// Helper to determine section type based on section index
    private func getSectionType(for section: Int) -> ProfileStreamSection {
        if !liveStreams.isEmpty {
            return section == 0 ? .liveNow : .pastStreams
        }
        return .pastStreams
    }
    
    /// Navigate to stream player
    private func didSelectStream(_ event: LiveActivitiesEvent?) {
        guard let event = event else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        // Show player UI immediately
        appState.playerConfig.selectedLiveActivitiesEvent = event
        appState.playerConfig.showMiniPlayer = true
    }

    private func updateCollectionViewHeight() {
        streamsCollectionView.layoutIfNeeded()

        let contentHeight: CGFloat
        if isLoadingInitialData {
            // Skeleton section: cards (240) + padding (16)
            contentHeight = Layout.carouselCardHeight + 16
        } else if liveStreams.isEmpty && pastStreams.isEmpty {
            // Show empty state
            contentHeight = 240
        } else {
            // Each section: header (50) + cards (240) + padding (16) = 306
            var sectionCount = 0
            if !liveStreams.isEmpty { sectionCount += 1 }
            if !pastStreams.isEmpty { sectionCount += 1 }
            contentHeight = CGFloat(max(sectionCount, 1)) * (Layout.carouselHeaderHeight + Layout.carouselCardHeight + 16)
        }

        // Update height constraint
        if let existingConstraint = streamsSectionView.constraints.first(where: { $0.firstAttribute == .height }) {
            existingConstraint.constant = contentHeight
        } else {
            streamsSectionView.heightAnchor.constraint(equalToConstant: contentHeight).isActive = true
        }
    }

    // MARK: - Actions
    @objc private func settingsTapped() {
        let settingsVC = UIHostingController(rootView: AppSettingsView(appState: appState).environmentObject(appState))
        let navController = UINavigationController(rootViewController: settingsVC)
        present(navController, animated: true)
    }

    @objc private func actionButtonTapped() {
        // Action button is now only visible for other users' profiles (follow/unfollow)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.followButtonAction(target: [viewModel.publicKeyHex])
    }

    @objc private func profileZapTapped() {
        guard let window = view.window else { return }

        let hasWallet: Bool = {
            if let wallet = appState.wallet,
               case .existing = wallet.connect_state { return true }
            return false
        }()

        // Present the morphing zap modal from the zap button
        activeZapModal = MorphingZapModal.present(
            from: profileZapButton,
            in: window,
            targetPubkey: viewModel.publicKeyHex,
            eventCoordinate: nil,
            noWallet: !hasWallet
        )

        // If no wallet, wire up the "Set Up Wallet" button
        if !hasWallet {
            activeZapModal?.onSetupWallet = { [weak self] in
                self?.navigateToWalletTab()
            }
        }

        // Collapse back to the pill shape of the zap button (not a 40×40 circle)
        activeZapModal?.collapsesToSourceButton = true
        activeZapModal?.confirmTitle = "Send Zap"

        activeZapModal?.onSendZap = { [weak self] amount in
            guard let self = self else { return false }
            return await self.zapService.sendZap(
                amount: amount,
                targetPubkey: self.viewModel.publicKeyHex,
                eventCoordinate: nil,
                content: nil
            )
        }

        activeZapModal?.onDismissed = { [weak self] in
            self?.profileZapButton.alpha = 1
            self?.activeZapModal = nil
        }

        activeZapModal?.onMorphProgress = { [weak self] progress in
            self?.profileZapButton.alpha = 1 - progress
        }
    }

    private func sendProfileZap(amount: Int64) {
        Task {
            let success = await zapService.sendZap(
                amount: amount,
                targetPubkey: viewModel.publicKeyHex,
                eventCoordinate: nil,
                content: nil
            )

            await MainActor.run {
                if success {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func navigateToWalletTab() {
        // Try the direct parent chain first
        if let tabBar = mainTabBarController {
            tabBar.switchToTab(.wallet, open: nil)
            return
        }
        
        // Fallback: find tab bar from root VC (e.g. when profile is presented modally from player)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        
        func findMainTabBar(in vc: UIViewController) -> (UIViewController & MainTabBarProtocol)? {
            if let tabBar = vc as? (UIViewController & MainTabBarProtocol) { return tabBar }
            for child in vc.children {
                if let found = findMainTabBar(in: child) { return found }
            }
            return nil
        }
        
        if let presented = rootVC.presentedViewController {
            presented.dismiss(animated: true) {
                findMainTabBar(in: rootVC)?.switchToTab(.wallet, open: nil)
            }
        } else {
            findMainTabBar(in: rootVC)?.switchToTab(.wallet, open: nil)
        }
    }

    @objc private func profileQRTapped() {
        guard let window = view.window else { return }

        let metadata = viewModel.profileMetadata
        activeQRModal = MorphingQRModal.present(
            from: profileQRButton,
            in: window,
            pubkeyHex: viewModel.publicKeyHex,
            displayName: metadata?.displayName ?? metadata?.name,
            pictureURL: metadata?.pictureURL
        )

        activeQRModal?.onProfileScanned = { [weak self] hexPubkey in
            guard let self = self else { return }
            // Don't navigate to own profile
            guard hexPubkey != self.viewModel.publicKeyHex else { return }
            let profileVC = ProfileViewController(appState: self.appState, publicKeyHex: hexPubkey)
            profileVC.showBackButton = true
            self.navigationController?.pushViewController(profileVC, animated: true)
        }

        activeQRModal?.onDismissed = { [weak self] in
            self?.profileQRButton.alpha = 1
            self?.activeQRModal = nil
        }

        activeQRModal?.onMorphProgress = { [weak self] progress in
            self?.profileQRButton.alpha = 1 - progress
        }
    }

    @objc private func showMoreTapped() {
        isBioExpanded.toggle()
        
        if isBioExpanded {
            bioLabel.numberOfLines = 0
            showMoreButton.setTitle("less", for: .normal)
        } else {
            bioLabel.numberOfLines = 3
            showMoreButton.setTitle("more", for: .normal)
        }
        
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Bio Nostr Mention Handling
    
    /// Fetches metadata for pubkeys mentioned in the bio
    private func fetchBioMentionMetadata(_ bioText: String) {
        let segments = NostrTextParser.parse(bioText)
        let pubkeys = NostrTextParser.extractPubkeys(from: segments)
        let missingPubkeys = pubkeys.filter { appState.metadataEvents[$0] == nil }
        
        #if DEBUG
        if !pubkeys.isEmpty {
            print("[ProfileVC] Bio mentions \(pubkeys.count) pubkey(s)")
            print("[ProfileVC] Missing metadata for \(missingPubkeys.count) pubkey(s)")
        }
        #endif
        
        if !missingPubkeys.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(Array(missingPubkeys))
        }
    }
    
    /// Builds an attributed string for the bio with highlighted Nostr mentions
    private func buildAttributedBio(_ text: String) -> NSAttributedString {
        let segments = NostrTextParser.parse(text)
        let attributedString = NSMutableAttributedString()
        
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: UIColor.label
        ]
        
        let mentionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor.systemPurple
        ]
        
        for segment in segments {
            switch segment {
            case .text(let string):
                attributedString.append(NSAttributedString(string: string, attributes: normalAttributes))
                
            case .reference(_, let reference):
                switch reference {
                case .profile(let pubkeyHex, _):
                    let displayName = NostrTextParser.resolveDisplayName(
                        pubkeyHex: pubkeyHex,
                        metadataEvents: appState.metadataEvents
                    )
                    #if DEBUG
                    let hasMetadata = appState.metadataEvents[pubkeyHex] != nil
                    print("[ProfileVC] Resolving mention: \(pubkeyHex.prefix(12))... -> \(displayName) (hasMetadata: \(hasMetadata))")
                    #endif
                    var attrs = mentionAttributes
                    attrs[.link] = "nostr:profile:\(pubkeyHex)"
                    attributedString.append(NSAttributedString(string: "@\(displayName)", attributes: attrs))
                    
                case .event(let eventId, _, _, _):
                    let truncated = String(eventId.prefix(8)) + "..."
                    var attrs = mentionAttributes
                    attrs[.foregroundColor] = UIColor.systemBlue
                    attrs[.link] = "nostr:event:\(eventId)"
                    attributedString.append(NSAttributedString(string: "📝\(truncated)", attributes: attrs))
                    
                case .address(_, let pubkey, let identifier, _):
                    var attrs = mentionAttributes
                    attrs[.foregroundColor] = UIColor.systemBlue
                    attrs[.link] = "nostr:address:\(pubkey):\(identifier)"
                    attributedString.append(NSAttributedString(string: "📄\(identifier)", attributes: attrs))
                }
            
            case .customEmoji(let shortcode):
                // Render shortcode as text in profile bio (no image loading needed here)
                attributedString.append(NSAttributedString(string: ":\(shortcode):", attributes: normalAttributes))
            }
        }
        
        return attributedString
    }
    
    /// Handles taps on the bio label to detect mention taps
    @objc private func bioLabelTapped(_ gesture: UITapGestureRecognizer) {
        guard let attributedText = bioLabel.attributedText else { return }
        
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize.zero)
        let textStorage = NSTextStorage(attributedString: attributedText)
        
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        
        textContainer.lineFragmentPadding = 0.0
        textContainer.lineBreakMode = bioLabel.lineBreakMode
        textContainer.maximumNumberOfLines = bioLabel.numberOfLines
        textContainer.size = bioLabel.bounds.size
        
        let locationOfTouchInLabel = gesture.location(in: bioLabel)
        let textBoundingBox = layoutManager.usedRect(for: textContainer)
        let textContainerOffset = CGPoint(
            x: (bioLabel.bounds.size.width - textBoundingBox.size.width) * 0.5 - textBoundingBox.origin.x,
            y: (bioLabel.bounds.size.height - textBoundingBox.size.height) * 0.5 - textBoundingBox.origin.y
        )
        let locationOfTouchInTextContainer = CGPoint(
            x: locationOfTouchInLabel.x - textContainerOffset.x,
            y: locationOfTouchInLabel.y - textContainerOffset.y
        )
        let indexOfCharacter = layoutManager.characterIndex(
            for: locationOfTouchInTextContainer,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        
        // Check if tapped character has a link attribute
        if indexOfCharacter < attributedText.length {
            let attributes = attributedText.attributes(at: indexOfCharacter, effectiveRange: nil)
            if let link = attributes[.link] as? String {
                handleBioLink(link)
            }
        }
    }
    
    /// Handles a tapped link in the bio
    private func handleBioLink(_ link: String) {
        let components = link.components(separatedBy: ":")
        guard components.count >= 2 else { return }
        
        let type = components[1]
        
        switch type {
        case "profile":
            if components.count >= 3 {
                let pubkeyHex = components[2]
                navigateToProfile(pubkeyHex: pubkeyHex)
            }
        case "event":
            if components.count >= 3 {
                let eventId = components[2]
                print("Event tapped: \(eventId)")
                // TODO: Navigate to event view
            }
        case "address":
            print("Address tapped: \(link)")
            // TODO: Handle address navigation
        default:
            break
        }
    }
    
    /// Navigates to a profile by pubkey
    private func navigateToProfile(pubkeyHex: String) {
        // Don't navigate to self
        guard pubkeyHex != viewModel.publicKeyHex else { return }
        
        let profileVC = ProfileViewController(appState: appState, publicKeyHex: pubkeyHex)
        profileVC.showBackButton = true  // Show back button on pushed profiles
        navigationController?.pushViewController(profileVC, animated: true)
    }

    @objc private func editProfileTapped() {
        let editProfileVC = EditProfileViewController(appState: appState)
        let navController = UINavigationController(rootViewController: editProfileVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
    
    @objc private func websiteTapped() {
        guard let metadata = viewModel.profileMetadata,
              let website = metadata.website else { return }
        UIApplication.shared.open(website)
    }
    
    @objc private func followingTapped() {
        let profileName = viewModel.profileMetadata?.displayName
            ?? viewModel.profileMetadata?.name
            ?? "This user"
        
        let followingVC = FollowingListViewController(
            appState: appState,
            publicKeyHex: viewModel.publicKeyHex,
            profileName: profileName
        )
        navigationController?.pushViewController(followingVC, animated: true)
    }
    
    @objc private func followersTapped() {
        // TODO: Navigate to followers list
        // This requires querying relays for kind 3 events that contain this pubkey
    }
}

// MARK: - UIScrollViewDelegate
extension ProfileViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let topInset = Layout.bannerHeight + view.safeAreaInsets.top
        let bannerBottom = topInset
        
        // scrollAmount: 0 at rest, positive when scrolling up, negative when pulling down
        let scrollAmount = offsetY + topInset
        
        // BANNER STRETCH EFFECT (when pulling down)
        if scrollAmount < 0 {
            bannerHeightConstraint.constant = topInset - scrollAmount
        } else {
            bannerHeightConstraint.constant = topInset
        }
        
        // ─── BANNER BLUR + NAME EFFECT ───
        // Blur spans the full journey: starts when pic begins shrinking (scrollAmount=0)
        // and completes when pic is fully hidden behind the banner.
        let shrinkDist = Layout.profilePicOverlap + (Layout.profilePicSize - Layout.profilePicMinSize) / 2
        let visibleAtShrinkEnd = (Layout.profilePicSize + Layout.profilePicMinSize) / 2 - Layout.profilePicOverlap
        let blurTotalDistance = shrinkDist + visibleAtShrinkEnd  // full range: shrink + slide
        
        if scrollAmount <= 0 {
            bannerBlurAnimator?.fractionComplete = 0
            bannerBlurView.alpha = 0
            bannerNameStackView.alpha = 0
        } else if scrollAmount >= blurTotalDistance {
            bannerBlurAnimator?.fractionComplete = 1.0
            bannerBlurView.alpha = 1.0
            bannerNameStackView.alpha = 1.0
        } else {
            let progress = scrollAmount / blurTotalDistance
            bannerBlurAnimator?.fractionComplete = progress
            bannerBlurView.alpha = progress
            
            // Name fades in during second half
            let nameProgress = max(0, (progress - 0.5) * 2)
            bannerNameStackView.alpha = nameProgress
        }
        
        // PROFILE PIC - Twitter-style behavior:
        // 1. At rest: profile pic overlaps banner, visual center at restingY + picSize/2
        // 2. Pull down: profile pic moves DOWN with content, full size
        // 3. Scroll up: profile pic SHRINKS from center (visual center stays stable)
        // 4. Continue scrolling: fully shrunk pic slides UP under banner
        
        let restingY = bannerBottom - Layout.profilePicOverlap
        
        let shrinkScrollDistance = Layout.profilePicOverlap + (Layout.profilePicSize - Layout.profilePicMinSize) / 2
        
        let currentSize: CGFloat
        let profilePicY: CGFloat
        
        if scrollAmount <= 0 {
            // PULL DOWN: full size, moves down with content
            currentSize = Layout.profilePicSize
            profilePicY = restingY - scrollAmount
        } else if scrollAmount <= shrinkScrollDistance {
            // SHRINK PHASE: shrinks from center so visual center stays stable
            let shrinkProgress = scrollAmount / shrinkScrollDistance
            currentSize = Layout.profilePicSize - (shrinkProgress * (Layout.profilePicSize - Layout.profilePicMinSize))
            let centerOffset = (Layout.profilePicSize - currentSize) / 2
            profilePicY = restingY + centerOffset
        } else {
            // SLIDE UNDER: fully shrunk at min size, slides up under banner
            currentSize = Layout.profilePicMinSize
            let shrinkEndY = restingY + (Layout.profilePicSize - Layout.profilePicMinSize) / 2
            let extraScroll = scrollAmount - shrinkScrollDistance
            profilePicY = shrinkEndY - extraScroll
        }
        
        // Update size
        profilePicWidthConstraint.constant = currentSize
        profilePicHeightConstraint.constant = currentSize
        profilePicImageView.layer.cornerRadius = currentSize / 2
        profilePicSkeletonView.layer.cornerRadius = currentSize / 2
        
        // Border scales with size
        let borderScale = currentSize / Layout.profilePicSize
        profilePicImageView.layer.borderWidth = Layout.profilePicBorderWidth * borderScale
        
        // Update position
        profilePicTopConstraint.constant = profilePicY
        
        // Keep horizontal center stable as size changes
        // At rest, center is at horizontalPadding + profilePicSize/2
        // As size shrinks, offset leading so center stays put
        let horizontalCenterOffset = (Layout.profilePicSize - currentSize) / 2
        profilePicLeadingConstraint.constant = Layout.horizontalPadding + horizontalCenterOffset
        
        // Z-ORDERING: Only change when state transitions (not every frame)
        let shouldBeUnder = scrollAmount > shrinkScrollDistance
        if shouldBeUnder != isProfilePicUnderBanner {
            isProfilePicUnderBanner = shouldBeUnder
            if shouldBeUnder {
                view.insertSubview(profilePicContainerView, belowSubview: bannerContainerView)
            } else {
                view.insertSubview(profilePicContainerView, aboveSubview: bannerContainerView)
            }
        }
        
        // Always fully visible (banner occludes it when behind)
        profilePicContainerView.alpha = 1.0
    }
}

// MARK: - UICollectionViewDataSource
extension ProfileViewController: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if isLoadingInitialData {
            return 1  // Just show skeleton
        }
        
        var sections = 0
        if !liveStreams.isEmpty { sections += 1 }
        if !pastStreams.isEmpty || liveStreams.isEmpty { sections += 1 }  // Show past or empty state
        return max(sections, 1)
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isLoadingInitialData {
            return 5 // Show 5 horizontal skeleton cards
        }
        
        let sectionType = getSectionType(for: section)
        switch sectionType {
        case .liveNow:
            return liveStreams.count
        case .pastStreams:
            return pastStreams.isEmpty ? 1 : pastStreams.count  // 1 for empty state
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isLoadingInitialData {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CarouselSkeletonCell.reuseIdentifier, for: indexPath) as! CarouselSkeletonCell
            cell.restartAnimations()
            return cell
        }
        
        let sectionType = getSectionType(for: indexPath.section)
        
        switch sectionType {
        case .liveNow:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StreamCardCell.reuseIdentifier, for: indexPath) as! StreamCardCell
            cell.applyConfiguration(.profile)  // Hide host info
            cell.configure(with: liveStreams[indexPath.item], appState: appState)
            cell.onTap = { [weak self] in
                self?.didSelectStream(self?.liveStreams[indexPath.item])
            }
            return cell
            
        case .pastStreams:
            if pastStreams.isEmpty {
                return collectionView.dequeueReusableCell(withReuseIdentifier: ProfileEmptyCell.reuseIdentifier, for: indexPath)
            }
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StreamCardCell.reuseIdentifier, for: indexPath) as! StreamCardCell
            cell.applyConfiguration(.profile)  // Hide host info
            cell.configure(with: pastStreams[indexPath.item], appState: appState)
            cell.onTap = { [weak self] in
                self?.didSelectStream(self?.pastStreams[indexPath.item])
            }
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader, !isLoadingInitialData else {
            return UICollectionReusableView()
        }
        
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: ProfileSectionHeaderView.reuseIdentifier,
            for: indexPath
        ) as! ProfileSectionHeaderView
        
        let sectionType = getSectionType(for: indexPath.section)
        let isLive = sectionType == .liveNow
        let count = isLive ? liveStreams.count : pastStreams.count
        header.configure(title: sectionType.title, count: count, isLive: isLive)
        
        return header
    }
}

// MARK: - UICollectionViewDelegate
extension ProfileViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isLoadingInitialData else { return }
        
        let sectionType = getSectionType(for: indexPath.section)
        
        switch sectionType {
        case .liveNow:
            guard indexPath.item < liveStreams.count else { return }
            didSelectStream(liveStreams[indexPath.item])
        case .pastStreams:
            guard !pastStreams.isEmpty, indexPath.item < pastStreams.count else { return }
            didSelectStream(pastStreams[indexPath.item])
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
    }
}

// MARK: - PaddedLabel Helper
final class PaddedLabel: UILabel {
    var textInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }
}
