//
//  FollowingListViewController.swift
//  swae
//
//  Displays the list of users that a profile is following
//  Optimized for performance with skeleton loading and batched updates
//

import Combine
import UIKit

final class FollowingListViewController: UIViewController {
    
    // MARK: - Dependencies
    private let appState: AppState
    private let publicKeyHex: String
    private let profileName: String
    
    // MARK: - UI Components
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()
    private let emptyImageView = UIImageView()
    private let emptyTitleLabel = UILabel()
    private let emptySubtitleLabel = UILabel()
    
    // MARK: - Data
    private var followingPubkeys: [String] = []
    private var isLoading = true
    private var cancellables = Set<AnyCancellable>()
    
    // Debounce timer for metadata updates
    private var metadataUpdateTimer: Timer?
    private var pendingMetadataUpdate = false
    
    // Cache for computed values to avoid repeated lookups
    private var ownPubkey: String?
    private var followedPubkeysCache: Set<String> = []
    
    // MARK: - Initialization
    init(appState: AppState, publicKeyHex: String, profileName: String) {
        self.appState = appState
        self.publicKeyHex = publicKeyHex
        self.profileName = profileName
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        metadataUpdateTimer?.invalidate()
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Cache values that don't change
        ownPubkey = appState.appSettings?.activeProfile?.publicKeyHex
        followedPubkeysCache = appState.followedPubkeys
        
        setupUI()
        setupTableView()
        setupEmptyState()
        
        // Load data asynchronously to not block the main thread
        DispatchQueue.main.async { [weak self] in
            self?.loadFollowingList()
            self?.observeChanges()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Following"
        
        navigationItem.largeTitleDisplayMode = .never
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.prefetchDataSource = self
        tableView.register(FollowingUserCell.self, forCellReuseIdentifier: FollowingUserCell.reuseIdentifier)
        tableView.register(FollowingSkeletonCell.self, forCellReuseIdentifier: FollowingSkeletonCell.reuseIdentifier)
        tableView.rowHeight = 64
        tableView.estimatedRowHeight = 64
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 0)
        
        // Pull to refresh
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        view.addSubview(emptyStateView)
        
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .light)
        emptyImageView.image = UIImage(systemName: "person.2.slash", withConfiguration: config)
        emptyImageView.tintColor = .tertiaryLabel
        emptyImageView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(emptyImageView)
        
        emptyTitleLabel.text = "Not Following Anyone"
        emptyTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        emptyTitleLabel.textColor = .label
        emptyTitleLabel.textAlignment = .center
        emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(emptyTitleLabel)
        
        emptySubtitleLabel.text = "When \(profileName) follows people, they'll appear here."
        emptySubtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        emptySubtitleLabel.textColor = .secondaryLabel
        emptySubtitleLabel.textAlignment = .center
        emptySubtitleLabel.numberOfLines = 0
        emptySubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(emptySubtitleLabel)
        
        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            emptyImageView.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyImageView.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            
            emptyTitleLabel.topAnchor.constraint(equalTo: emptyImageView.bottomAnchor, constant: 16),
            emptyTitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyTitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            
            emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
            emptySubtitleLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptySubtitleLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            emptySubtitleLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    private func loadFollowingList() {
        // Get follow list for this profile (fast dictionary lookup)
        if publicKeyHex == ownPubkey {
            followingPubkeys = appState.activeFollowList?.followedPubkeys ?? []
        } else {
            followingPubkeys = appState.followListEvents[publicKeyHex]?.followedPubkeys ?? []
        }
        
        // Show content immediately
        isLoading = false
        tableView.reloadData()
        updateEmptyState()
        
        // Fetch metadata only for initially visible cells
        fetchMetadataForVisibleCells()
    }
    
    private func fetchMetadataForVisibleCells() {
        // Only fetch metadata for cells that are currently visible
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else { return }
        
        let pubkeysToFetch = visibleIndexPaths.compactMap { indexPath -> String? in
            guard indexPath.row < followingPubkeys.count else { return nil }
            let pubkey = followingPubkeys[indexPath.row]
            return appState.metadataEvents[pubkey] == nil ? pubkey : nil
        }
        
        if !pubkeysToFetch.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(pubkeysToFetch)
        }
    }
    
    @objc private func refreshData() {
        // Re-fetch follow list from relays
        appState.pullMissingEventsFromPubkeysAndFollows([publicKeyHex])
        
        // Reload after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadFollowingList()
            self?.tableView.refreshControl?.endRefreshing()
        }
    }
    
    private func observeChanges() {
        // Observe metadata changes with debouncing
        appState.$metadataEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleMetadataUpdate()
            }
            .store(in: &cancellables)
        
        // Observe follow list changes (less frequent, no debounce needed)
        appState.$followListEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadFollowingList()
            }
            .store(in: &cancellables)
        
        // Observe own follow state changes
        appState.$followedPubkeys
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newFollowed in
                self?.followedPubkeysCache = newFollowed
                self?.reloadVisibleCells()
            }
            .store(in: &cancellables)
    }
    
    private func scheduleMetadataUpdate() {
        pendingMetadataUpdate = true
        metadataUpdateTimer?.invalidate()
        
        // Debounce: wait 0.2s before updating to batch rapid changes
        metadataUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self, self.pendingMetadataUpdate else { return }
            self.pendingMetadataUpdate = false
            self.reloadVisibleCells()
        }
    }
    
    private func reloadVisibleCells() {
        // Only reload visible cells for performance
        guard let visibleIndexPaths = tableView.indexPathsForVisibleRows else { return }
        tableView.reloadRows(at: visibleIndexPaths, with: .none)
    }
    
    private func updateEmptyState() {
        let isEmpty = followingPubkeys.isEmpty && !isLoading
        emptyStateView.isHidden = !isEmpty
        tableView.isHidden = isEmpty
    }
    
    // MARK: - Follow Actions
    private func handleFollowToggle(pubkey: String, shouldFollow: Bool) {
        var currentFollows = appState.activeFollowList?.followedPubkeys ?? []
        
        if shouldFollow {
            if !currentFollows.contains(pubkey) {
                currentFollows.append(pubkey)
            }
            notify(.follow(currentFollows))
        } else {
            currentFollows.removeAll { $0 == pubkey }
            notify(.unfollow(currentFollows))
        }
    }
    
    // MARK: - Navigation
    private func navigateToProfile(pubkeyHex: String) {
        let profileVC = ProfileViewController(appState: appState, publicKeyHex: pubkeyHex)
        profileVC.showBackButton = true
        navigationController?.pushViewController(profileVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension FollowingListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return isLoading ? 10 : followingPubkeys.count // Show 10 skeleton cells while loading
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Show skeleton while loading
        if isLoading {
            let cell = tableView.dequeueReusableCell(withIdentifier: FollowingSkeletonCell.reuseIdentifier, for: indexPath) as! FollowingSkeletonCell
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: FollowingUserCell.reuseIdentifier, for: indexPath) as! FollowingUserCell
        let pubkey = followingPubkeys[indexPath.row]
        
        // Use cached metadata lookup
        let metadata = appState.metadataEvents[pubkey]?.userMetadata
        let isFollowing = followedPubkeysCache.contains(pubkey)
        let isOwnProfile = pubkey == ownPubkey
        
        cell.configure(with: pubkey, metadata: metadata, isFollowing: isFollowing, isOwnProfile: isOwnProfile)
        cell.onFollowToggle = { [weak self] pubkey, shouldFollow in
            self?.handleFollowToggle(pubkey: pubkey, shouldFollow: shouldFollow)
        }
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension FollowingListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard !isLoading else { return }
        
        let pubkey = followingPubkeys[indexPath.row]
        navigateToProfile(pubkeyHex: pubkey)
    }
}

// MARK: - UITableViewDataSourcePrefetching
extension FollowingListViewController: UITableViewDataSourcePrefetching {
    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        guard !isLoading else { return }
        
        // Prefetch metadata for upcoming cells
        let pubkeysToFetch = indexPaths.compactMap { indexPath -> String? in
            guard indexPath.row < followingPubkeys.count else { return nil }
            let pubkey = followingPubkeys[indexPath.row]
            return appState.metadataEvents[pubkey] == nil ? pubkey : nil
        }
        
        if !pubkeysToFetch.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(pubkeysToFetch)
        }
    }
}
