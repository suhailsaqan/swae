//
//  VideoListViewController.swift
//  swae
//
//  Created by Suhail Saqan on 11/24/24.
//

import AVKit
import Combine
import Kingfisher
import NostrSDK
import UIKit

/// A modern, engaging video discovery interface with a hero section and horizontal carousels
final class VideoListViewController: UIViewController {

    // MARK: - Dependencies
    private let appState: AppState
    private let orientationMonitor: OrientationMonitor

    // MARK: - UI Components
    // Hero header (Spotify-style: appears fixed but moves with parallax)
    private let heroHeader = HeroHeaderView(frame: .zero)
    private let collectionView: UICollectionView
    
    // Instagram-style header bar (fixed at top, above hero)
    private let headerBar = SwaeHeaderBar()
    private let headerBarHeight: CGFloat = 44
    
    // Search results overlay (liquid glass covering feed)
    private var searchResultsOverlay: GlassContainerView?
    private var searchOverlayBottomConstraint: NSLayoutConstraint?
    
    // Search
    private let searchViewModel = SearchViewModel()
    private var searchTableView: UITableView?
    private var searchCancellables = Set<AnyCancellable>()

    // Hero height reference
    private var heroHeight: CGFloat { LayoutMetrics.heroHeight }

    // MARK: - Scroll Tracking (Tab Bar)
    private var barsMaxTransform: CGFloat = 100
    private var prevPosition: CGFloat = 0
    private var prevTransform: CGFloat = 0

    // MARK: - Data
    private var cancellables = Set<AnyCancellable>()
    private var sections: [ContentSection] = []
    private var sectionStyles: [ContentSection.SectionStyle] = []  // Parallel array for layout closure
    private var hasSetInitialInset = false
    private var isLoadingInitialData = true
    private var isRebuildingSections = false
    private var needsRebuild = false

    // MARK: - Layout
    private enum LayoutMetrics {
        static var heroHeight: CGFloat {
            let screenBounds = UIScreen.main.bounds
            let screenWidth = min(screenBounds.width, screenBounds.height)  // Portrait width
            let screenHeight = max(screenBounds.width, screenBounds.height)
            let effectiveWidth = screenWidth - 32  // Paddings
            let aspectHeight = effectiveWidth * (9.0 / 16.0)
            let proportionalHeight = min(aspectHeight + 24, screenHeight * 0.5)  // +24 paddings, cap at 40% height

            // Approximate safe top (or use view.safeAreaInsets.top if computed post-layout)
            let approxSafeTop: CGFloat = screenWidth > 400 ? 59 : (screenWidth < 380 ? 20 : 47)  // Pro Max:59, SE:20, others:47

            var minHeight: CGFloat = 280
            var maxHeight: CGFloat = 330
            if screenWidth < 380 {  // Compact (e.g., SE)
                minHeight = 220
                maxHeight = 280
            } else if screenWidth > 400 {  // Large (e.g., Pro Max)
                maxHeight = 350
            }

            let finalHeight = min(max(proportionalHeight + approxSafeTop / 2, minHeight), maxHeight)  // Partial safe add for buffer under notch

            return finalHeight
        }

        static let carouselHeight: CGFloat = 228
        static let sectionHeaderHeight: CGFloat = 60
        static let spacing: CGFloat = 16
        static let cardCornerRadius: CGFloat = 16
    }

    // MARK: - Data Models
    struct ContentSection {
        let title: String
        let subtitle: String?
        let events: [LiveActivitiesEvent]
        let style: SectionStyle
        let categoryStats: [CategoryStat]
        let categories: [StreamCategory]
        let clips: [LiveStreamClipEvent]
        let shorts: [VideoEvent]
        let allEvents: [LiveActivitiesEvent]?

        init(title: String, subtitle: String? = nil, events: [LiveActivitiesEvent] = [],
             style: SectionStyle, categoryStats: [CategoryStat] = [],
             categories: [StreamCategory] = [],
             clips: [LiveStreamClipEvent] = [],
             shorts: [VideoEvent] = [],
             allEvents: [LiveActivitiesEvent]? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.events = events
            self.style = style
            self.categoryStats = categoryStats
            self.categories = categories
            self.clips = clips
            self.shorts = shorts
            self.allEvents = allEvents
        }

        enum SectionStyle {
            case categoryPills   // Horizontal category navigation
            case carousel        // Horizontal scrolling stream cards
            case categoryGrid    // Horizontal category tiles with gradients
            case mediaCarousel   // Horizontal clips/videos cards
        }
    }

    // MARK: - Initialization
    init(appState: AppState, orientationMonitor: OrientationMonitor) {
        self.appState = appState
        self.orientationMonitor = orientationMonitor

        // Use a temporary layout — real layout set after super.init (needs self for sectionStyles)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

        super.init(nibName: nil, bundle: nil)

        // Now self is available — set the real compositional layout
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self = self, sectionIndex < self.sectionStyles.count else {
                return VideoListViewController.createCarouselSection()
            }
            switch self.sectionStyles[sectionIndex] {
            case .categoryPills:
                return VideoListViewController.createCategoryPillsSection()
            case .categoryGrid:
                return VideoListViewController.createCategoryGridSection()
            case .carousel:
                return VideoListViewController.createCarouselSection()
            case .mediaCarousel:
                return VideoListViewController.createMediaCarouselSection()
            }
        }
        collectionView.setCollectionViewLayout(layout, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCollectionView()
        setupObservers()
        rebuildSections()

        // Show cached hero preview while waiting for relay data
        if let cachedHero = CachedHeroData.load() {
            heroHeader.configureFromCache(cachedHero)
        }

        // No entrance animation - instant display for snappiness
        collectionView.alpha = 1
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        
        // Reset header bar scroll state when view appears
        headerBar.resetScrollState()
        
        // Keep tab bar hidden while search is active (e.g. returning from a pushed profile)
        if headerBar.searchState == .expanded {
            mainTabBarController?.setCustomTabBarHidden(true, animated: false)
        }
        
        // Restart skeleton animations if still in loading state
        if isLoadingInitialData {
            restartSkeletonAnimations()
        }

        // Resume hero video when feed becomes visible
        heroHeader.resumeVideo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Set content inset so content starts below header (Spotify-style)
        if !hasSetInitialInset {
            // Initialize hero header frame - extends into safe area
            // Account for header bar height in total header calculation
            let safeTop = view.safeAreaInsets.top
            let totalHeaderHeight = heroHeight + safeTop + headerBarHeight

            heroHeader.frame = CGRect(
                x: 0,
                y: -totalHeaderHeight,  // Position above content inside the scroll view
                width: view.bounds.width,
                height: totalHeaderHeight  // Include safe area and header bar in height
            )
            heroHeader.setNeedsLayout()
            heroHeader.layoutIfNeeded()

            print(
                "🎯 Setting up hero header - frame: \(heroHeader.frame), heroHeight: \(heroHeight), safeTop: \(safeTop), headerBarHeight: \(headerBarHeight)"
            )
            print("🎯 Hero header isHidden: \(heroHeader.isHidden), alpha: \(heroHeader.alpha)")

            collectionView.contentInset = .init(
                top: totalHeaderHeight,  // Content starts below header + safe area + header bar
                left: 0,
                bottom: 150,  // Bottom padding for tab bar
                right: 0
            )

            // Set scroll indicator insets
            collectionView.scrollIndicatorInsets = .init(
                top: totalHeaderHeight,
                left: 0,
                bottom: 150,
                right: 0
            )

            // Set initial offset to show header
            collectionView.contentOffset = CGPoint(x: 0, y: -totalHeaderHeight)

            // Ensure hero header is visible and on top
            heroHeader.isHidden = false
            heroHeader.alpha = 1.0
            collectionView.bringSubviewToFront(heroHeader)

            hasSetInitialInset = true

            // Signal the SceneDelegate that the feed is laid out and ready to be shown.
            NotificationCenter.default.post(name: .feedDidFinishInitialLayout, object: nil)
        } else {
            // Update hero header width on rotation/size changes (maintain current height/y)
            var frame = heroHeader.frame
            frame.size.width = view.bounds.width
            heroHeader.frame = frame
            heroHeader.setNeedsLayout()
            heroHeader.layoutIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause hero video when leaving the feed
        heroHeader.pauseVideo()

        // Always show tab bar when leaving
        if prevTransform != 0 {
            if animated {
                animateTabBarToVisible()
            } else {
                setTabBarToTransform(0)
            }
        }
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground  // Match hero video background

        // 1. Setup collection view first (will be behind hero header)
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.canCancelContentTouches = true
        // Make collection view transparent so hero header shows through
        collectionView.backgroundView = UIView()
        collectionView.backgroundView?.backgroundColor = .clear
        view.addSubview(collectionView)

        // 2. Add hero header inside the collection view so scroll feels native
        heroHeader.translatesAutoresizingMaskIntoConstraints = true  // Use frame-based layout
        heroHeader.clipsToBounds = false
        heroHeader.backgroundColor = .systemBackground  // Ensure it has a background
        collectionView.addSubview(heroHeader)

        // 3. Add header bar ON TOP of collection view (AFTER adding collection view)
        // This ensures it stays fixed while collection view scrolls
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerBar)
        
        // 4. Constraints
        NSLayoutConstraint.activate([
            // Collection view fills entire view
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Header bar pinned to safe area top
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: headerBarHeight),
        ])
        
        // 5. Setup header bar callbacks
        headerBar.onCameraTapped = { [weak self] in
            self?.revealCamera()
        }
        
        // Search callbacks
        searchViewModel.bind(appState: appState)
        
        headerBar.onSearchActivated = { [weak self] in
            self?.showSearchOverlay(animated: true)
        }
        
        headerBar.onSearchDeactivated = { [weak self] in
            self?.hideSearchOverlay(animated: true)
        }
        
        headerBar.onSearchTextChanged = { [weak self] text in
            guard let self = self else { return }
            self.searchViewModel.searchText = text
            self.searchViewModel.search(query: text, appState: self.appState)
        }

        // Set initial frame for hero header (will be updated in viewDidLayoutSubviews)
        // Start with a temporary frame - will be properly set in viewDidLayoutSubviews
        heroHeader.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width,
            height: heroHeight
        )

        // Ensure hero header is on top within the scroll view
        collectionView.bringSubviewToFront(heroHeader)
    }
    
    // MARK: - Camera Navigation
    
    /// Reveals the camera by finding InstagramNavigationController in the responder chain
    private func revealCamera() {
        var responder: UIResponder? = self
        while let current = responder {
            if let instagramNav = current as? InstagramNavigationController {
                instagramNav.revealCamera()
                return
            }
            responder = current.next
        }
        print("⚠️ Could not find InstagramNavigationController in responder chain")
    }
    
    // MARK: - Profile Navigation
    
    /// Navigates to a user's profile by pushing ProfileViewController
    private func navigateToProfile(pubkeyHex: String) {
        // Don't navigate to own profile from home feed
        guard pubkeyHex != appState.publicKey?.hex else { return }
        
        heroHeader.pauseVideo()
        
        let profileVC = ProfileViewController(appState: appState, publicKeyHex: pubkeyHex)
        profileVC.showBackButton = true
        
        navigationController?.pushViewController(profileVC, animated: true)
    }

    /// Pushes the "See All" grid for a given section
    private func showSeeAllScreen(for section: ContentSection) {
        let seeAllVC = SeeAllViewController(
            appState: appState,
            sectionTitle: section.title,
            events: section.allEvents ?? section.events
        )
        seeAllVC.onEventSelected = { [weak self] event in
            self?.didSelectEvent(event)
        }
        seeAllVC.onHostTapped = { [weak self] pubkeyHex in
            self?.navigateToProfile(pubkeyHex: pubkeyHex)
        }
        navigationController?.pushViewController(seeAllVC, animated: true)
    }
    
    // MARK: - Search Overlay
    
    /// Creates and adds the search results overlay to the view hierarchy
    private func setupSearchOverlay() {
        guard searchResultsOverlay == nil else { return }
        
        let overlay = GlassFactory.makeGlassView(cornerRadius: 0)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlay.isHidden = true
        
        // Remove border and inner shadow for full-screen overlay
        overlay.removeEdgeStyling()
        
        // Dark tint over the glass for a deeper, moodier search backdrop
        let darkTint = UIView()
        darkTint.backgroundColor = UIColor(white: 0, alpha: 0.35)
        darkTint.translatesAutoresizingMaskIntoConstraints = false
        darkTint.isUserInteractionEnabled = false
        overlay.glassContentView.addSubview(darkTint)
        NSLayoutConstraint.activate([
            darkTint.leadingAnchor.constraint(equalTo: overlay.glassContentView.leadingAnchor),
            darkTint.trailingAnchor.constraint(equalTo: overlay.glassContentView.trailingAnchor),
            darkTint.topAnchor.constraint(equalTo: overlay.glassContentView.topAnchor),
            darkTint.bottomAnchor.constraint(equalTo: overlay.glassContentView.bottomAnchor),
        ])
        
        // Insert between collectionView and headerBar
        view.insertSubview(overlay, belowSubview: headerBar)
        
        // Bottom constraint stored for keyboard avoidance
        let bottomConstraint = overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            // Extend to top of screen (over safe area) for seamless full-screen effect
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint
        ])
        
        searchResultsOverlay = overlay
        searchOverlayBottomConstraint = bottomConstraint
        
        // Add tap gesture to dismiss — only fires on empty areas, not on table cells
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(searchOverlayTapped))
        tapGesture.delegate = self
        overlay.addGestureRecognizer(tapGesture)
        
        // Setup search table view inside the glass overlay
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.reuseIdentifier)
        tableView.register(SearchSkeletonCell.self, forCellReuseIdentifier: SearchSkeletonCell.reuseIdentifier)
        
        overlay.glassContentView.addSubview(tableView)
        
        // No top content inset needed — table view starts below the header bar via constraints
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: overlay.glassContentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: overlay.glassContentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: overlay.glassContentView.bottomAnchor),
        ])
        
        searchTableView = tableView
        
        // Observe search results
        searchViewModel.$searchResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadSearchTableAnimated()
            }
            .store(in: &searchCancellables)
        
        searchViewModel.$discoveryProfiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadSearchTableAnimated()
            }
            .store(in: &searchCancellables)
        
        searchViewModel.$isSearching
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadSearchTableAnimated()
            }
            .store(in: &searchCancellables)
    }
    
    /// Cross-fade reload to avoid jarring skeleton → results flash.
    private func reloadSearchTableAnimated() {
        guard let tableView = searchTableView else { return }
        UIView.transition(with: tableView, duration: 0.25, options: .transitionCrossDissolve, animations: {
            tableView.reloadData()
        })
    }
    
    @objc private func searchOverlayTapped() {
        headerBar.collapseSearch(animated: true)
    }
    
    private func showSearchOverlay(animated: Bool) {
        // Create overlay lazily
        setupSearchOverlay()
        
        guard let overlay = searchResultsOverlay else { return }
        
        overlay.isHidden = false
        
        // Load discovery profiles for empty state
        searchViewModel.loadDiscoveryProfiles()
        
        overlay.isHidden = false
        
        // Subscribe to keyboard notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        
        // Hide the tab bar so it doesn't overlap the search overlay
        mainTabBarController?.setCustomTabBarHidden(true, animated: animated)
        
        let animations = {
            overlay.alpha = 1
            overlay.transform = .identity
        }
        
        if animated && !UIAccessibility.isReduceMotionEnabled {
            overlay.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
            // Match search bar animation: duration 0.5, same spring parameters
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5,
                options: .allowUserInteraction,
                animations: animations
            )
        } else {
            animations()
        }
    }
    
    private func hideSearchOverlay(animated: Bool) {
        guard let overlay = searchResultsOverlay else { return }
        
        // Unsubscribe from keyboard notifications
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // DON'T clear search results yet — let the overlay fade out with content still visible.
        // Clearing now causes the table view to flash empty during the fade-out animation.
        
        let animations = {
            overlay.alpha = 0
        }
        
        let completion: (Bool) -> Void = { _ in
            overlay.isHidden = true
            overlay.transform = .identity
            
            // Clear search state AFTER the overlay is fully hidden
            self.searchViewModel.searchText = ""
            self.searchViewModel.searchResults = []
            self.searchViewModel.isSearching = false
        }
        
        if animated && !UIAccessibility.isReduceMotionEnabled {
            // Delay tab bar appearance so it doesn't pop in while the overlay is still fading
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.mainTabBarController?.setCustomTabBarHidden(false, animated: true)
            }
            
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction],
                animations: animations,
                completion: completion
            )
        } else {
            mainTabBarController?.setCustomTabBarHidden(false, animated: false)
            animations()
            completion(true)
        }
    }
    
    // MARK: - Keyboard Handling
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        // No-op: let the keyboard overlay on top of the search results
        // instead of pushing the overlay up.
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        // No-op: overlay stays pinned to the bottom of the view.
    }

    // Removed manual pan forwarding; scrolling is now handled natively by the collection view

    private func setupCollectionView() {
        // Register cells
        collectionView.register(
            StreamCardCell.self, forCellWithReuseIdentifier: StreamCardCell.reuseIdentifier)
        collectionView.register(
            CarouselSkeletonCell.self, forCellWithReuseIdentifier: CarouselSkeletonCell.reuseIdentifier)
        collectionView.register(
            CategoryPillCell.self, forCellWithReuseIdentifier: CategoryPillCell.reuseIdentifier)
        collectionView.register(
            CategoryTileCell.self, forCellWithReuseIdentifier: CategoryTileCell.reuseIdentifier)
        collectionView.register(
            MediaCardCell.self, forCellWithReuseIdentifier: MediaCardCell.reuseIdentifier)
        collectionView.register(
            MediaSkeletonCell.self, forCellWithReuseIdentifier: MediaSkeletonCell.reuseIdentifier)

        // Register supplementary views (only section headers, no hero header)
        collectionView.register(
            SectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: SectionHeaderView.reuseIdentifier)
    }

    // MARK: - Compositional Layout
    private static func createCategoryPillsSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .estimated(100),
            heightDimension: .absolute(36)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 8
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 16, bottom: 16, trailing: 16)
        // No section header for pills
        return section
    }

    private static func createCategoryGridSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(140),
            heightDimension: .absolute(180)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(140),
            heightDimension: .absolute(180)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: 16, bottom: 32, trailing: 16)

        // Section header
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(LayoutMetrics.sectionHeaderHeight)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]
        return section
    }

    private static func createCarouselSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(300),
            heightDimension: .absolute(LayoutMetrics.carouselHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 14
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: 16, bottom: 32, trailing: 16)

        // Add section header
        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(LayoutMetrics.sectionHeaderHeight)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]

        return section
    }

    private static func createMediaCarouselSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalHeight(1.0)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .absolute(220),
            heightDimension: .absolute(190)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: 16, bottom: 32, trailing: 16)

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(LayoutMetrics.sectionHeaderHeight)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]

        return section
    }

    // MARK: - Observers
    private func setupObservers() {
        // MARK: Initial sync completion — single rebuild when data is ready
        // This fires when isInitialSyncInProgress transitions from true → false,
        // either via relay EOSE or fallback timer.
        appState.$isInitialSyncInProgress
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] inProgress in
                guard let self = self else { return }
                if !inProgress {
                    // Instagram-style transition: cross-dissolve the collection view
                    // from skeleton cells to real content. The cross-dissolve captures
                    // the current skeleton appearance as a snapshot and smoothly fades
                    // to the new layout, preventing any jarring jump or blank flash.
                    // rebuildSections() updates both the data model and collection view
                    // inside this transition block.
                    UIView.transition(
                        with: self.collectionView,
                        duration: 0.35,
                        options: [.transitionCrossDissolve, .allowUserInteraction]
                    ) {
                        self.rebuildSections()
                    }
                }
            }
            .store(in: &cancellables)
        
        // MARK: Live data observers — suppressed during initial sync
        appState.$liveActivitiesEvents
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.appState.isInitialSyncInProgress else { return }
                self.rebuildSections()
            }
            .store(in: &cancellables)

        appState.$followedPubkeys
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.appState.isInitialSyncInProgress else { return }
                self.rebuildSections()
            }
            .store(in: &cancellables)

        appState.$clipEvents
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.appState.isInitialSyncInProgress else { return }
                self.rebuildSections()
            }
            .store(in: &cancellables)

        appState.$shortEvents
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.appState.isInitialSyncInProgress else { return }
                self.rebuildSections()
            }
            .store(in: &cancellables)

        // MARK: Feed visibility and background/foreground — unchanged
        handle_notify(.feed_visibility)
            .sink { [weak self] visible in
                if visible {
                    self?.heroHeader.resumeVideo()
                    // Run deferred rebuild if data changed while player was open
                    if self?.needsRebuild == true {
                        self?.needsRebuild = false
                        self?.rebuildSections()
                    }
                }
                else { self?.heroHeader.pauseVideo() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.heroHeader.pauseVideo() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.heroHeader.resumeVideo() }
            .store(in: &cancellables)
    }

    // MARK: - Image Prefetching
    private func prefetchImagesForVisibleCells() {
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        var urlsToPrefetch: [URL] = []
        
        for indexPath in visibleIndexPaths {
            guard indexPath.section < sections.count else { continue }
            let section = sections[indexPath.section]
            guard indexPath.item < section.events.count else { continue }
            let event = section.events[indexPath.item]
            
            if let imageURL = event.image {
                urlsToPrefetch.append(imageURL)
            }
        }
        
        if !urlsToPrefetch.isEmpty {
            ImagePrefetcher(urls: urlsToPrefetch).start()
        }
    }
    
    // MARK: - Data Management
    
    /// Limits streams per HOST to prevent spam (max 2 streams per streamer)
    /// Uses the host pubkey from NIP-53 `p` tag, NOT the event author (which is often the platform)
    private func limitPerPubkey(_ events: [LiveActivitiesEvent], max: Int = 2) -> [LiveActivitiesEvent] {
        var counts: [String: Int] = [:]
        return events.filter { event in
            // Get host pubkey - per NIP-53, host is in `p` tag with role "host"
            // Fallback to event.pubkey if no host tag (for backwards compatibility)
            let hostPubkey = event.hostPubkeyHex
            
            let count = counts[hostPubkey, default: 0]
            guard count < max else { return false }
            counts[hostPubkey] = count + 1
            return true
        }
    }
    
    private func rebuildSections() {
        // Skip rebuilds while a player is covering the feed — defer until player dismisses.
        // RootViewController.currentPlayerController is non-nil when a video is open.
        if RootViewController.instance.currentPlayerController != nil {
            needsRebuild = true
            return
        }

        // Reentrancy guard: if we're already inside a batch update, defer the rebuild
        if isRebuildingSections {
            needsRebuild = true
            return
        }
        isRebuildingSections = true
        defer {
            isRebuildingSections = false
            if needsRebuild {
                needsRebuild = false
                rebuildSections()
            }
        }

        let allEvents = appState.getAllEvents()
        
        // OPTIMIZATION: Single-pass filtering instead of two separate filter calls
        // SAFETY: Every event must appear somewhere - no invisible streams allowed
        var liveEvents: [LiveActivitiesEvent] = []
        var replayEvents: [LiveActivitiesEvent] = []
        for event in allEvents {
            if event.isActuallyLive {
                liveEvents.append(event)
            } else if event.isReplay {
                replayEvents.append(event)
            } else {
                replayEvents.append(event)
            }
        }

        // HOME FEED ONLY: Exclude replays without a recording URL.
        // These are ended streams with no saved VOD — not useful to display.
        // They still appear on profile pages and category detail pages (those use getAllEvents() directly).
        replayEvents.removeAll { $0.recording == nil }

        var newSections: [ContentSection] = []
        
        // Check if we have any real data
        let hasRealData = !allEvents.isEmpty
        if hasRealData {
            isLoadingInitialData = false
        }

        // OPTIMIZATION: Sort once, reuse for hero and Live Now
        let sortedByViewers = liveEvents.sorted { $0.currentParticipants > $1.currentParticipants }
        let heroEvent = sortedByViewers.first
        let heroEventId = heroEvent?.id

        // 0. Configure hero header directly (fixed, not in collection view)
        if let topLiveEvent = heroEvent {
            if heroHeader.frame.height == 0 || heroHeader.frame.width == 0 {
                let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
                heroHeader.frame = CGRect(x: 0, y: 0, width: width, height: heroHeight)
            }
            heroHeader.configure(with: topLiveEvent, appState: appState)
            heroHeader.onTap = { [weak self] in
                guard let self else { return }
                self.didSelectEvent(topLiveEvent,
                                    sourceView: self.heroHeader.transitionSourceView,
                                    thumbnailImage: self.heroHeader.transitionThumbnailImage)
            }
            heroHeader.setNeedsLayout()
            heroHeader.layoutIfNeeded()
            heroHeader.isHidden = false
            collectionView.bringSubviewToFront(heroHeader)
        } else {
            heroHeader.isHidden = false
            collectionView.bringSubviewToFront(heroHeader)
            CachedHeroData.clear()
        }

        // 1. Category pills (always first, shows all primary categories + "All")
        newSections.append(
            ContentSection(
                title: "", subtitle: nil,
                style: .categoryPills,
                categories: StreamCategory.primaryCategories
            ))

        // 2. Live Now (excluding hero from carousel, but See All gets all streams)
        let liveNowCarouselEvents = sortedByViewers.filter { $0.id != heroEventId }
        if !liveNowCarouselEvents.isEmpty {
            newSections.append(
                ContentSection(
                    title: "Live Now",
                    subtitle: "\(sortedByViewers.count) streams",
                    events: liveNowCarouselEvents,
                    style: .carousel,
                    allEvents: sortedByViewers
                ))
        }

        // 3. Following (if logged in + follows are live)
        if appState.publicKey != nil {
            let followedPubkeys = appState.followedPubkeys
            let followedEvents = sortedByViewers.filter { event in
                if followedPubkeys.contains(event.pubkey) { return true }
                return followedPubkeys.contains(event.hostPubkeyHex)
            }
            if !followedEvents.isEmpty {
                newSections.append(
                    ContentSection(
                        title: "Following",
                        subtitle: "\(followedEvents.count) live",
                        events: followedEvents,
                        style: .carousel
                    ))
            }
        }

        // 4. Popular Categories (includes all content: live, replays, clips, shorts)
        let stats = computeCategoryStats(
            from: liveEvents,
            replayEvents: replayEvents,
            clipEvents: AppState.clipsAndShortsEnabled ? appState.clipEvents : [],
            shortEvents: AppState.clipsAndShortsEnabled ? appState.shortEvents : []
        )
        if !stats.isEmpty {
            newSections.append(
                ContentSection(
                    title: "Popular",
                    subtitle: nil,
                    style: .categoryGrid,
                    categoryStats: stats
                ))
        }

        // 5. Recent Clips (kind 1313)
        if AppState.clipsAndShortsEnabled {
            let recentClips = Array(appState.clipEvents.prefix(10))
            if !recentClips.isEmpty {
                newSections.append(
                    ContentSection(
                        title: "Recent Clips",
                        subtitle: "\(recentClips.count) clips",
                        style: .mediaCarousel,
                        clips: recentClips
                    ))
            }
        }

        // 6. Latest Shorts (kind 22 + legacy 34236)
        if AppState.clipsAndShortsEnabled {
            let recentShorts = Array(appState.shortEvents.prefix(10))
            if !recentShorts.isEmpty {
                newSections.append(
                    ContentSection(
                        title: "Latest Shorts",
                        subtitle: "\(recentShorts.count) shorts",
                        style: .mediaCarousel,
                        shorts: recentShorts
                    ))
            }
        }

        // 7. Recent Replays (all have recording URLs — filtered upstream)
        if !replayEvents.isEmpty {
            let sortedReplays = replayEvents.sorted { $0.createdAt > $1.createdAt }
            let limitedReplays = limitPerPubkey(sortedReplays, max: 2)
            if !limitedReplays.isEmpty {
                newSections.append(
                    ContentSection(
                        title: "Recent Replays",
                        subtitle: "\(replayEvents.count) available",
                        events: limitedReplays,
                        style: .carousel
                    ))
            }
        }

        // If no real data, create skeleton sections with real section names
        if newSections.count <= 1 && isLoadingInitialData {
            newSections.append(ContentSection(title: "Live Now", subtitle: nil, events: [], style: .carousel))
            if AppState.clipsAndShortsEnabled {
                newSections.append(ContentSection(title: "Recent Clips", subtitle: nil, style: .mediaCarousel))
                newSections.append(ContentSection(title: "Latest Shorts", subtitle: nil, style: .mediaCarousel))
            }
            newSections.append(ContentSection(title: "Recent Replays", subtitle: nil, events: [], style: .carousel))
        }

        let oldSections = sections
        sections = newSections
        sectionStyles = newSections.map { $0.style }

        // Targeted reload: avoid reloading the pills section to preserve its scroll offset.
        // Pills section (always index 0) has a fixed item count, so we can reconfigure in-place.
        let oldCount = oldSections.count
        let newCount = newSections.count
        let pillsSectionIndex = 0  // Pills are always first
        let hasPillsSection = newSections.first?.style == .categoryPills
        let hadPillsSection = oldSections.first?.style == .categoryPills

        if hasPillsSection && hadPillsSection && oldCount > 0 && newCount > 0 {
            // We can do a targeted reload: skip the pills section, reload everything else
            collectionView.collectionViewLayout.invalidateLayout()

            collectionView.performBatchUpdates {
                // Handle section count changes (sections after pills)
                let oldNonPillsCount = oldCount - 1
                let newNonPillsCount = newCount - 1

                // Delete removed sections
                if oldNonPillsCount > newNonPillsCount {
                    let range = (newNonPillsCount + 1)..<(oldNonPillsCount + 1)
                    collectionView.deleteSections(IndexSet(range))
                }
                // Insert added sections
                if newNonPillsCount > oldNonPillsCount {
                    let range = (oldNonPillsCount + 1)..<(newNonPillsCount + 1)
                    collectionView.insertSections(IndexSet(range))
                }
                // Reload existing non-pills sections
                let commonCount = min(oldNonPillsCount, newNonPillsCount)
                if commonCount > 0 {
                    collectionView.reloadSections(IndexSet(1...commonCount))
                }
            }

            // Reconfigure visible pills cells in-place (no section reload = no scroll reset)
            let pillsItemCount = collectionView.numberOfItems(inSection: pillsSectionIndex)
            for item in 0..<pillsItemCount {
                let indexPath = IndexPath(item: item, section: pillsSectionIndex)
                if let cell = collectionView.cellForItem(at: indexPath) as? CategoryPillCell {
                    let catIndex = item
                    if catIndex < newSections[pillsSectionIndex].categories.count {
                        let cat = newSections[pillsSectionIndex].categories[catIndex]
                        cell.configure(with: cat, isActive: false)
                    }
                }
            }
        } else {
            // Fallback: full reload (first load, or structural change in pills)
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
        }
        
        // Prefetch images for visible cells after reload
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.prefetchImagesForVisibleCells()
        }
    }

    // MARK: - Category Stats Computation

    /// Aggregates viewer/stream counts per category across all content types.
    /// O(n × t) where n = total events, t = avg tags per event (typically ~3). O(1) per tag lookup.
    private func computeCategoryStats(
        from liveEvents: [LiveActivitiesEvent],
        replayEvents: [LiveActivitiesEvent],
        clipEvents: [LiveStreamClipEvent],
        shortEvents: [VideoEvent]
    ) -> [CategoryStat] {
        var stats: [String: CategoryStat] = [:]

        // 1. Live streams — contribute viewerCount, liveCount, streamCount, and IGDB tags
        for event in liveEvents {
            let igdbTag = event.hashtags.first { tag in
                let lower = tag.lowercased()
                return lower.contains(":")
                    && !lower.hasPrefix("internal:")
                    && lower.range(of: "^[a-z-]+:[a-z0-9-]+$", options: .regularExpression) != nil
            }

            for cat in event.matchedCategories {
                var stat = stats[cat.id] ?? CategoryStat(
                    category: cat, viewerCount: 0, streamCount: 0, liveCount: 0)
                stat.streamCount += 1
                stat.liveCount += 1
                stat.viewerCount += event.currentParticipants
                if stat.igdbGameId == nil, let igdbTag {
                    stat.igdbGameId = igdbTag
                }
                stats[cat.id] = stat
            }
        }

        // 2. Replays — contribute streamCount and IGDB tags (no live viewers)
        for event in replayEvents {
            let igdbTag: String? = {
                guard stats.values.contains(where: { $0.igdbGameId == nil }) else { return nil }
                return event.hashtags.first { tag in
                    let lower = tag.lowercased()
                    return lower.contains(":")
                        && !lower.hasPrefix("internal:")
                        && lower.range(of: "^[a-z-]+:[a-z0-9-]+$", options: .regularExpression) != nil
                }
            }()

            for cat in event.matchedCategories {
                var stat = stats[cat.id] ?? CategoryStat(
                    category: cat, viewerCount: 0, streamCount: 0, liveCount: 0)
                stat.streamCount += 1
                if stat.igdbGameId == nil, let igdbTag {
                    stat.igdbGameId = igdbTag
                }
                stats[cat.id] = stat
            }
        }

        // 3. Clips — contribute streamCount only
        for clip in clipEvents {
            for cat in StreamCategory.categories(forHashtags: clip.hashtags) {
                var stat = stats[cat.id] ?? CategoryStat(
                    category: cat, viewerCount: 0, streamCount: 0, liveCount: 0)
                stat.streamCount += 1
                stats[cat.id] = stat
            }
        }

        // 4. Shorts — contribute streamCount only
        for short in shortEvents {
            for cat in StreamCategory.categories(forHashtags: short.hashtags) {
                var stat = stats[cat.id] ?? CategoryStat(
                    category: cat, viewerCount: 0, streamCount: 0, liveCount: 0)
                stat.streamCount += 1
                stats[cat.id] = stat
            }
        }

        return Array(
            stats.values
                .sorted { $0.streamCount > $1.streamCount }
                .prefix(8)
        )
    }

    // MARK: - Category Navigation

    private func navigateToCategory(_ category: StreamCategory) {
        let detailVC = CategoryDetailViewController(
            category: category,
            appState: appState
        )
        navigationController?.pushViewController(detailVC, animated: true)
    }

    // MARK: - Skeleton Management
    private func restartSkeletonAnimations() {
        heroHeader.restartSkeletonAnimations()
        for cell in collectionView.visibleCells {
            if let skeletonCell = cell as? CarouselSkeletonCell {
                skeletonCell.restartAnimations()
            } else if let mediaSkeletonCell = cell as? MediaSkeletonCell {
                mediaSkeletonCell.restartAnimations()
            }
        }
    }

    /// Animates visible cells in with a staggered waterfall effect.
    private func animateStaggeredReveal() {
        if UIAccessibility.isReduceMotionEnabled {
            return
        }

        collectionView.layoutIfNeeded()

        let visibleCells = collectionView.visibleCells.sorted { cell1, cell2 in
            guard let ip1 = collectionView.indexPath(for: cell1),
                  let ip2 = collectionView.indexPath(for: cell2) else { return false }
            if ip1.section != ip2.section { return ip1.section < ip2.section }
            return ip1.item < ip2.item
        }

        for cell in visibleCells {
            cell.alpha = 0
            cell.transform = CGAffineTransform(translationX: 0, y: 24)
        }

        for (index, cell) in visibleCells.enumerated() {
            let delay = Double(index) * 0.05
            UIView.animate(
                withDuration: 0.4,
                delay: delay,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.5,
                options: [.allowUserInteraction]
            ) {
                cell.alpha = 1
                cell.transform = .identity
            }
        }

        for sectionIndex in 0..<sections.count {
            let indexPath = IndexPath(item: 0, section: sectionIndex)
            if let header = collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: indexPath
            ) {
                header.alpha = 0
                header.transform = CGAffineTransform(translationX: 0, y: 16)
                UIView.animate(
                    withDuration: 0.35,
                    delay: Double(sectionIndex) * 0.08,
                    usingSpringWithDamping: 0.9,
                    initialSpringVelocity: 0.3,
                    options: [.allowUserInteraction]
                ) {
                    header.alpha = 1
                    header.transform = .identity
                }
            }
        }
    }

    // MARK: - Actions
    private func didSelectEvent(_ event: LiveActivitiesEvent,
                                sourceView: UIView? = nil,
                                thumbnailImage: UIImage? = nil) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        heroHeader.pauseVideo()

        appState.openStream(event, sourceView: sourceView, thumbnailImage: thumbnailImage)
    }

    private func didSelectClip(_ clip: LiveStreamClipEvent) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        guard let clipURL = clip.clipURL else { return }
        heroHeader.pauseVideo()
        let player = AVPlayer(url: clipURL)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        present(playerVC, animated: true) {
            player.play()
        }
    }

    private func didSelectShort(_ short: VideoEvent) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        guard let videoURL = short.videoURL else { return }
        heroHeader.pauseVideo()
        let player = AVPlayer(url: videoURL)
        let playerVC = AVPlayerViewController()
        playerVC.player = player
        present(playerVC, animated: true) {
            player.play()
        }
    }

    // MARK: - Tab Bar Transform Methods

    private func setTabBarToTransform(_ transform: CGFloat) {
        prevTransform = transform
        mainTabBarController?.vStack.transform = .init(translationX: 0, y: -transform)
    }

    private func animateTabBarToTransform(_ transform: CGFloat) {
        prevTransform = transform
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            self.mainTabBarController?.vStack.transform = .init(translationX: 0, y: -transform)
        }
    }

    private func animateTabBarToVisible() {
        animateTabBarToTransform(0)
    }

    private func animateTabBarToInvisible() {
        animateTabBarToTransform(-barsMaxTransform)
    }

    private func setTabBarDependingOnPosition() {
        // Don't snap - let the tab bar stay where it is based on scroll position
        // This allows it to hide when scrolling down and show when scrolling up
        // Only snap if we're at the very top of the scroll view
        if collectionView.contentOffset.y <= 0 {
            print("scrolling")
            animateTabBarToVisible()
        }
    }
}

// MARK: - UICollectionViewDataSource
extension VideoListViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
        -> Int
    {
        guard section < sections.count else { return 0 }
        let contentSection = sections[section]
        switch contentSection.style {
        case .categoryPills:
            return contentSection.categories.count
        case .categoryGrid:
            return contentSection.categoryStats.count
        case .carousel:
            let eventCount = contentSection.events.count
            return eventCount > 0 ? eventCount : (isLoadingInitialData ? 5 : 0)
        case .mediaCarousel:
            let count = contentSection.clips.count + contentSection.shorts.count
            return count > 0 ? count : (isLoadingInitialData ? 4 : 0)
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        guard indexPath.section < sections.count else {
            // Data source changed mid-layout; return a blank cell to avoid crash
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: CarouselSkeletonCell.reuseIdentifier, for: indexPath)
        }
        let section = sections[indexPath.section]

        switch section.style {
        case .categoryPills:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CategoryPillCell.reuseIdentifier, for: indexPath)
                as! CategoryPillCell
            guard indexPath.item < section.categories.count else { return cell }
            let category = section.categories[indexPath.item]
            cell.configure(with: category, isActive: false)
            return cell

        case .categoryGrid:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CategoryTileCell.reuseIdentifier, for: indexPath)
                as! CategoryTileCell
            guard indexPath.item < section.categoryStats.count else { return cell }
            let stat = section.categoryStats[indexPath.item]
            cell.configure(with: stat)
            cell.onTap = { [weak self] in
                self?.navigateToCategory(stat.category)
            }
            return cell

        case .carousel:
            // Show skeleton cells if loading
            if section.events.isEmpty && isLoadingInitialData {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: CarouselSkeletonCell.reuseIdentifier, for: indexPath)
                    as! CarouselSkeletonCell
                return cell
            }
            
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: StreamCardCell.reuseIdentifier, for: indexPath)
                as! StreamCardCell
            guard indexPath.item < section.events.count else { return cell }
            let event = section.events[indexPath.item]
            cell.applyConfiguration(.default)
            cell.configure(with: event, appState: appState)
            cell.onTap = { [weak self, weak cell] in
                guard let self, let cell else { return }
                self.didSelectEvent(event,
                                    sourceView: cell.transitionSourceView,
                                    thumbnailImage: cell.transitionThumbnailImage)
            }
            cell.onHostTap = { [weak self] pubkeyHex in
                self?.navigateToProfile(pubkeyHex: pubkeyHex)
            }
            return cell

        case .mediaCarousel:
            // Show skeleton cells if loading
            if (section.clips.isEmpty && section.shorts.isEmpty) && isLoadingInitialData {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: MediaSkeletonCell.reuseIdentifier, for: indexPath)
                    as! MediaSkeletonCell
                return cell
            }
            
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: MediaCardCell.reuseIdentifier, for: indexPath)
                as! MediaCardCell

            if !section.clips.isEmpty, indexPath.item < section.clips.count {
                let clip = section.clips[indexPath.item]
                cell.configureAsClip(
                    thumbnailURL: clip.thumbnailURL,
                    title: clip.clipTitle,
                    subtitle: nil
                )
                cell.onTap = { [weak self] in
                    self?.didSelectClip(clip)
                }
            } else if !section.shorts.isEmpty, indexPath.item < section.shorts.count {
                let short = section.shorts[indexPath.item]
                cell.configureAsShort(
                    thumbnailURL: short.thumbnailURL,
                    title: short.videoTitle,
                    subtitle: nil
                )
                cell.onTap = { [weak self] in
                    self?.didSelectShort(short)
                }
            }
            return cell
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }

        let section = sections[indexPath.section]
        let header =
            collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: SectionHeaderView.reuseIdentifier,
                for: indexPath
            ) as! SectionHeaderView

        // Category pills have no header
        if section.style == .categoryPills {
            header.configure(title: "", subtitle: nil)
            header.isHidden = true
            return header
        }

        header.isHidden = false
        let showSeeAll = section.style == .carousel && !section.events.isEmpty
        header.configure(title: section.title, subtitle: section.subtitle, showSeeAll: showSeeAll)
        if showSeeAll {
            header.onSeeAllTapped = { [weak self] in
                guard let self = self else { return }
                self.showSeeAllScreen(for: section)
            }
        }
        // Media carousels don't have See All yet (Phase 3)
        return header
    }
}

// MARK: - UICollectionViewDelegate
extension VideoListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let section = sections[indexPath.section]

        switch section.style {
        case .categoryPills:
            let category = section.categories[indexPath.item]
            navigateToCategory(category)

        case .categoryGrid:
            let stat = section.categoryStats[indexPath.item]
            navigateToCategory(stat.category)

        case .carousel:
            guard !section.events.isEmpty, indexPath.item < section.events.count else { return }
            let event = section.events[indexPath.item]
            didSelectEvent(event)

        case .mediaCarousel:
            if !section.clips.isEmpty, indexPath.item < section.clips.count {
                didSelectClip(section.clips[indexPath.item])
            } else if !section.shorts.isEmpty, indexPath.item < section.shorts.count {
                didSelectShort(section.shorts[indexPath.item])
            }
        }
    }

    // MARK: - Scroll Handling (Spotify-style)

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let safeTop = view.safeAreaInsets.top
        let totalHeaderHeight = heroHeight + safeTop + headerBarHeight
        let adjustedOffset = offsetY + totalHeaderHeight  // Adjust for content inset

        // Disable animations for smooth frame updates
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Inside the scroll view:
        // - When pulling down (offsetY < -totalHeaderHeight): keep header's bottom pinned to content start (y+height = 0)
        //   by setting y = offsetY and height = -offsetY. This stretches exactly as much as the pull without overlap.
        // - When scrolling up: keep fixed height and anchor at -totalHeaderHeight.
        if offsetY < -totalHeaderHeight {
            heroHeader.frame = CGRect(
                x: 0,
                y: offsetY,
                width: view.bounds.width,
                height: -offsetY
            )
        } else {
            heroHeader.frame = CGRect(
                x: 0,
                y: -totalHeaderHeight,
                width: view.bounds.width,
                height: totalHeaderHeight
            )
        }
        heroHeader.setNeedsLayout()

        CATransaction.commit()

        // Trigger layout immediately for smooth updates
        heroHeader.layoutIfNeeded()

        // ── Update blur based on scroll position (Spotify-style) ─────────────
        heroHeader.updateBlurForScrollOffset(adjustedOffset)
        
        // ── Instagram-style header bar hide/show ─────────────
        // Header bar is over the gradient when we're still within the hero header area
        // heroHeight is the content height of the hero (excluding safe area and header bar in the calculation)
        let isOverGradient = adjustedOffset < heroHeight
        headerBar.updateForScroll(currentOffset: adjustedOffset, isOverGradient: isOverGradient)

        // Tab bar transforms - DISABLED FOR NOW
        // TODO: Fix tab bar hiding/showing on scroll
        /*
        let newPosition = offsetY
        let delta = newPosition - prevPosition
        prevPosition = newPosition

        guard abs(delta) <= 50 else { return }

        let theoreticalNewTransform = (prevTransform - delta).clamped(to: -barsMaxTransform...0)
        let isInRefreshArea = adjustedOffset < 10
        let newTransform = isInRefreshArea ? 0 : theoreticalNewTransform
        
        setTabBarToTransform(newTransform)
        */
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // Tab bar snapping disabled
        // if !decelerate {
        //     setTabBarDependingOnPosition()
        // }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Tab bar snapping disabled
        // setTabBarDependingOnPosition()
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        // Always show tab bar when tapping status bar to scroll to top
        animateTabBarToVisible()
        return true
    }
}

// MARK: - UIGestureRecognizerDelegate (Search Overlay)
extension VideoListViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't fire the overlay dismiss tap when touching table view cells
        if let touchedView = touch.view,
           touchedView.isDescendant(of: searchTableView ?? UIView()) {
            return false
        }
        return true
    }
}

// MARK: - Search Table View DataSource & Delegate
extension VideoListViewController: UITableViewDataSource, UITableViewDelegate {
    
    /// Determines what the search table should show based on current state
    private enum SearchTableMode {
        case skeleton       // Loading indicator
        case results        // Search results
        case discovery      // Random profiles (empty search text)
        case empty          // No results
    }
    
    private var searchTableMode: SearchTableMode {
        let hasText = !searchViewModel.debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        // Show skeletons whenever API is still fetching (Instagram-style)
        if hasText && searchViewModel.isSearching {
            return .skeleton
        }
        if hasText && !searchViewModel.searchResults.isEmpty {
            return .results
        }
        if !hasText && !searchViewModel.discoveryProfiles.isEmpty {
            return .discovery
        }
        if hasText && searchViewModel.searchResults.isEmpty && !searchViewModel.isSearching {
            return .empty
        }
        // Default: show discovery or skeleton while loading
        return searchViewModel.discoveryProfiles.isEmpty ? .skeleton : .discovery
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch searchTableMode {
        case .skeleton: return 6
        case .results: return searchViewModel.searchResults.count
        case .discovery: return searchViewModel.discoveryProfiles.count
        case .empty: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch searchTableMode {
        case .skeleton:
            let cell = tableView.dequeueReusableCell(withIdentifier: SearchSkeletonCell.reuseIdentifier, for: indexPath)
            return cell
            
        case .results:
            let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseIdentifier, for: indexPath) as! SearchResultCell
            let result = searchViewModel.searchResults[indexPath.row]
            cell.configure(with: result)
            return cell
            
        case .discovery:
            let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.reuseIdentifier, for: indexPath) as! SearchResultCell
            let user = searchViewModel.discoveryProfiles[indexPath.row]
            let result = SearchViewModel.SearchResult(
                id: user.pubkey,
                pubkey: user.pubkey,
                metadata: nil,
                profilestrUser: user,
                isLocalMatch: false
            )
            cell.configure(with: result)
            return cell
            
        case .empty:
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Capture pubkey BEFORE collapsing search — collapseSearch clears searchResults
        var pubkeyHex: String?
        
        let hasText = !searchViewModel.debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if hasText, indexPath.row < searchViewModel.searchResults.count {
            pubkeyHex = searchViewModel.searchResults[indexPath.row].pubkey
        } else if !hasText, indexPath.row < searchViewModel.discoveryProfiles.count {
            pubkeyHex = searchViewModel.discoveryProfiles[indexPath.row].pubkey
        }
        
        guard let hex = pubkeyHex else { return }
        
        // Show tab bar for the profile view, then navigate
        mainTabBarController?.setCustomTabBarHidden(false, animated: true)
        navigateToProfile(pubkeyHex: hex)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 64
    }
}

extension NSLayoutConstraint {
    func with(priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - Section Header View
private final class SectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "SectionHeaderView"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let liveDot = UIView()
    private let seeAllButton = UIButton(type: .system)

    var onSeeAllTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        // Live dot (red circle, shown only for "Live Now")
        liveDot.backgroundColor = .systemRed
        liveDot.layer.cornerRadius = 3
        liveDot.isHidden = true
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liveDot)

        // "See All" button with chevron
        var config = UIButton.Configuration.plain()
        config.title = "See All"
        config.baseForegroundColor = .secondaryLabel
        config.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
        let transformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            return outgoing
        }
        config.titleTextAttributesTransformer = transformer
        seeAllButton.configuration = config
        seeAllButton.translatesAutoresizingMaskIntoConstraints = false
        seeAllButton.addTarget(self, action: #selector(seeAllTapped), for: .touchUpInside)
        addSubview(seeAllButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            liveDot.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            liveDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            liveDot.widthAnchor.constraint(equalToConstant: 6),
            liveDot.heightAnchor.constraint(equalToConstant: 6),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            seeAllButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            seeAllButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    @objc private func seeAllTapped() {
        onSeeAllTapped?()
    }

    func configure(title: String, subtitle: String?, showSeeAll: Bool = false) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        liveDot.isHidden = title != "Live Now"
        onSeeAllTapped = nil
        seeAllButton.isHidden = !showSeeAll
    }
}
