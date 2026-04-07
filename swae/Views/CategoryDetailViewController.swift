//
//  CategoryDetailViewController.swift
//  swae
//
//  Full category detail page pushed from homepage pill/tile tap.
//  Shows category banner, top streamers, live streams grid, and replays grid.
//

import Combine
import Kingfisher
import NostrSDK
import UIKit

final class CategoryDetailViewController: UIViewController {

    // MARK: - Dependencies
    private let category: StreamCategory
    private let appState: AppState

    // MARK: - UI
    private let collectionView: UICollectionView
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    // MARK: - Data
    private var cancellables = Set<AnyCancellable>()
    private var sections: [Section] = []
    private var sectionKinds: [SectionKind] = []
    private var activeAPITask: Task<Void, Never>?
    private var hasLoadedAPIStreamers = false
    private var cachedAPIStreamers: [TopStreamer] = []

    // MARK: - Section Model

    private enum SectionKind {
        case banner
        case topStreamers
        case liveGrid
        case replayGrid
    }

    private struct Section {
        let kind: SectionKind
        let title: String
        let subtitle: String?
        let events: [LiveActivitiesEvent]
        let streamers: [TopStreamer]

        init(kind: SectionKind, title: String = "", subtitle: String? = nil,
             events: [LiveActivitiesEvent] = [], streamers: [TopStreamer] = []) {
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.events = events
            self.streamers = streamers
        }
    }

    struct TopStreamer {
        let pubkey: String
        let totalSats: Int64
        let avatarURL: URL?
        let displayName: String
    }

    // MARK: - Init

    init(category: StreamCategory, appState: AppState) {
        self.category = category
        self.appState = appState
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        super.init(nibName: nil, bundle: nil)

        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self = self, sectionIndex < self.sectionKinds.count else {
                return Self.createGridSection(environment: environment)
            }
            switch self.sectionKinds[sectionIndex] {
            case .banner:
                return Self.createBannerSection()
            case .topStreamers:
                return Self.createTopStreamersSection()
            case .liveGrid, .replayGrid:
                return Self.createGridSection(environment: environment)
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
        view.backgroundColor = .systemBackground
        setupHeader()
        setupCollectionView()
        setupObservers()
        rebuildSections()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    // MARK: - Header

    private func setupHeader() {
        headerView.backgroundColor = .systemBackground
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: config), for: .normal)
        backButton.tintColor = .label
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        titleLabel.text = category.name
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            backButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -16),
        ])
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Collection View

    private func setupCollectionView() {
        collectionView.backgroundColor = .systemBackground
        collectionView.showsVerticalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.alwaysBounceVertical = true
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        collectionView.register(CategoryBannerCell.self, forCellWithReuseIdentifier: CategoryBannerCell.reuseIdentifier)
        collectionView.register(TopStreamerCell.self, forCellWithReuseIdentifier: TopStreamerCell.reuseIdentifier)
        collectionView.register(StreamCardCell.self, forCellWithReuseIdentifier: StreamCardCell.reuseIdentifier)
        collectionView.register(
            CategoryDetailHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: CategoryDetailHeaderView.reuseIdentifier)
    }

    // MARK: - Layout Sections

    private static func createBannerSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(120))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16)
        return section
    }

    private static func createTopStreamersSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(80), heightDimension: .absolute(100))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(80), heightDimension: .absolute(100))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 24, trailing: 16)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(44))
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        section.boundarySupplementaryItems = [header]
        return section
    }

    private static func createGridSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let availableWidth = environment.container.effectiveContentSize.width - 48  // 16 leading + 16 trailing + 16 interitem
        let itemWidth = availableWidth / 2.0
        let itemHeight = itemWidth * 0.75 + 50  // 4:3 thumbnail + info area

        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(itemWidth), heightDimension: .absolute(itemHeight))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(itemHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 2)
        group.interItemSpacing = .fixed(16)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 16
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 32, trailing: 16)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(44))
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
        section.boundarySupplementaryItems = [header]
        return section
    }

    // MARK: - Observers

    private func setupObservers() {
        appState.$liveActivitiesEvents
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildSections() }
            .store(in: &cancellables)

        appState.$eventZapTotals
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildSections() }
            .store(in: &cancellables)
    }

    // MARK: - Data

    private func rebuildSections() {
        let allEvents = appState.getAllEvents()
        let matchTags = Set(category.matchTags)

        // Filter to this category
        let categoryEvents = allEvents.filter { event in
            event.hashtags.contains(where: { matchTags.contains($0.lowercased()) })
        }

        var liveEvents: [LiveActivitiesEvent] = []
        var replayEvents: [LiveActivitiesEvent] = []
        for event in categoryEvents {
            if event.isActuallyLive {
                liveEvents.append(event)
            } else if event.isReplay {
                replayEvents.append(event)
            }
        }

        // Filter out replays without a recording URL — these are ended/ghost streams
        // with no saved VOD. They show "ENDED" badge and cause infinite spinner when tapped.
        replayEvents.removeAll { $0.recording == nil }

        let sortedLive = liveEvents.sorted { $0.currentParticipants > $1.currentParticipants }
        let totalViewers = liveEvents.reduce(0) { $0 + $1.currentParticipants }

        var newSections: [Section] = []

        // 1. Banner
        newSections.append(Section(
            kind: .banner,
            title: category.name,
            subtitle: "\(liveEvents.count) live · \(totalViewers) viewers"
        ))

        // 2. Top Streamers — use cached API data if available, otherwise local
        let topStreamers = hasLoadedAPIStreamers ? cachedAPIStreamers : computeTopStreamersLocal(from: categoryEvents)
        if !topStreamers.isEmpty {
            newSections.append(Section(kind: .topStreamers, title: "Most Zapped Streamers", streamers: topStreamers))
        }

        // 3. Live Streams
        if !sortedLive.isEmpty {
            newSections.append(Section(
                kind: .liveGrid,
                title: "Live Now",
                subtitle: "\(sortedLive.count) streams",
                events: sortedLive
            ))
        }

        // 4. Replays
        let sortedReplays = replayEvents
            .sorted { a, b in
                let aHasRec = a.recording != nil
                let bHasRec = b.recording != nil
                if aHasRec != bHasRec { return aHasRec }
                return a.createdAt > b.createdAt
            }
            .prefix(20)

        if !sortedReplays.isEmpty {
            newSections.append(Section(
                kind: .replayGrid,
                title: "Replays",
                subtitle: "\(replayEvents.count) available",
                events: Array(sortedReplays)
            ))
        }

        sections = newSections
        sectionKinds = newSections.map { $0.kind }
        collectionView.reloadData()

        // Only fetch from API once per view lifecycle — no need to re-fetch on every zap update
        guard !hasLoadedAPIStreamers else { return }

        // Cancel any in-flight API task before starting a new one
        activeAPITask?.cancel()
        let eventsForAsync = categoryEvents
        activeAPITask = Task { [weak self] in
            guard let self else { return }
            let apiStreamers = await self.computeTopStreamersFromAPI(from: eventsForAsync)
            guard !Task.isCancelled, !apiStreamers.isEmpty else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.hasLoadedAPIStreamers = true
                self.cachedAPIStreamers = apiStreamers

                if let idx = self.sections.firstIndex(where: { $0.kind == .topStreamers }) {
                    self.sections[idx] = Section(kind: .topStreamers, title: "Most Zapped Streamers", streamers: apiStreamers)
                    self.collectionView.reloadSections(IndexSet(integer: idx))
                } else {
                    // Insert after banner
                    let insertIdx = self.sections.firstIndex(where: { $0.kind != .banner }) ?? self.sections.endIndex
                    self.sections.insert(Section(kind: .topStreamers, title: "Most Zapped Streamers", streamers: apiStreamers), at: insertIdx)
                    self.sectionKinds = self.sections.map { $0.kind }
                    self.collectionView.insertSections(IndexSet(integer: insertIdx))
                }
            }
        }
    }

    // MARK: - Top Streamers Computation

    /// Synchronous local-only computation using session eventZapTotals. Used as immediate/fallback data.
    private func computeTopStreamersLocal(from events: [LiveActivitiesEvent]) -> [TopStreamer] {
        var pubkeyZaps: [String: Int64] = [:]

        for event in events {
            guard let coord = event.replaceableEventCoordinates()?.tag.value else { continue }
            let hostPubkey = event.hostPubkeyHex
            let zaps = appState.eventZapTotals[coord] ?? 0
            if zaps > 0 {
                pubkeyZaps[hostPubkey, default: 0] += zaps
            }
        }

        return pubkeyZaps
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { (pubkey, millisats) in
                let metadata = appState.metadataEvents[pubkey]
                let name = metadata?.userMetadata?.displayName
                    ?? metadata?.userMetadata?.name
                    ?? String(pubkey.prefix(8))
                let avatarURL = metadata?.userMetadata?.pictureURL
                return TopStreamer(pubkey: pubkey, totalSats: millisats / 1000, avatarURL: avatarURL, displayName: name)
            }
    }

    /// Async computation using Profilestr API for lifetime zap data. Falls back to local.
    private func computeTopStreamersFromAPI(from events: [LiveActivitiesEvent]) async -> [TopStreamer] {
        var hostPubkeys = Set<String>()
        for event in events {
            let hostPubkey = event.hostPubkeyHex
            hostPubkeys.insert(hostPubkey)
        }

        guard !hostPubkeys.isEmpty else { return [] }

        let pubkeysToFetch = Array(hostPubkeys.prefix(20))
        let profilestrData = await ProfilestrAPIClient.shared.fetchUsers(pubkeys: pubkeysToFetch)

        var apiStreamers: [TopStreamer] = []
        for pk in hostPubkeys {
            if let user = profilestrData[pk] {
                let sats = Int64(user.totalAmountReceived ?? 0)
                guard sats > 0 else { continue }
                let name = user.displayName ?? user.name ?? String(pk.prefix(8))
                let avatarURL = user.picture.flatMap { URL(string: $0) }
                apiStreamers.append(TopStreamer(pubkey: pk, totalSats: sats, avatarURL: avatarURL, displayName: name))
            }
        }

        guard !apiStreamers.isEmpty else { return [] }
        return Array(apiStreamers.sorted { $0.totalSats > $1.totalSats }.prefix(8))
    }

    // MARK: - Actions

    private func didSelectEvent(_ event: LiveActivitiesEvent) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        appState.openStream(event)
    }

    private func navigateToProfile(pubkeyHex: String) {
        guard pubkeyHex != appState.publicKey?.hex else { return }
        let profileVC = ProfileViewController(appState: appState, publicKeyHex: pubkeyHex)
        profileVC.showBackButton = true
        navigationController?.pushViewController(profileVC, animated: true)
    }
}

// MARK: - UICollectionViewDataSource
extension CategoryDetailViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let s = sections[section]
        switch s.kind {
        case .banner: return 1
        case .topStreamers: return s.streamers.count
        case .liveGrid, .replayGrid: return s.events.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let section = sections[indexPath.section]

        switch section.kind {
        case .banner:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CategoryBannerCell.reuseIdentifier, for: indexPath) as! CategoryBannerCell
            // Compute live stats from the live grid section if it exists
            let liveSection = sections.first(where: { $0.kind == .liveGrid })
            let liveCount = liveSection?.events.count ?? 0
            let viewerCount = liveSection?.events.reduce(0) { $0 + $1.currentParticipants } ?? 0
            cell.configure(with: category, liveCount: liveCount, viewerCount: viewerCount)
            return cell

        case .topStreamers:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TopStreamerCell.reuseIdentifier, for: indexPath) as! TopStreamerCell
            let streamer = section.streamers[indexPath.item]
            cell.configure(avatarURL: streamer.avatarURL, displayName: streamer.displayName, totalSats: streamer.totalSats)
            cell.onTap = { [weak self] in
                self?.navigateToProfile(pubkeyHex: streamer.pubkey)
            }
            return cell

        case .liveGrid, .replayGrid:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StreamCardCell.reuseIdentifier, for: indexPath) as! StreamCardCell
            let event = section.events[indexPath.item]
            cell.applyConfiguration(.default)
            cell.configure(with: event, appState: appState)
            cell.onTap = { [weak self] in
                self?.didSelectEvent(event)
            }
            cell.onHostTap = { [weak self] pubkeyHex in
                self?.navigateToProfile(pubkeyHex: pubkeyHex)
            }
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }
        let section = sections[indexPath.section]
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: CategoryDetailHeaderView.reuseIdentifier, for: indexPath) as! CategoryDetailHeaderView

        if section.kind == .banner {
            header.configure(title: "", subtitle: nil)
            header.isHidden = true
            return header
        }

        header.isHidden = false
        header.configure(title: section.title, subtitle: section.subtitle)
        return header
    }
}

// MARK: - UICollectionViewDelegate
extension CategoryDetailViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let section = sections[indexPath.section]
        switch section.kind {
        case .topStreamers:
            let streamer = section.streamers[indexPath.item]
            navigateToProfile(pubkeyHex: streamer.pubkey)
        case .liveGrid, .replayGrid:
            guard indexPath.item < section.events.count else { return }
            didSelectEvent(section.events[indexPath.item])
        default:
            break
        }
    }
}

// MARK: - Section Header View
private final class CategoryDetailHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "CategoryDetailHeaderView"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let liveDot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        liveDot.backgroundColor = .systemRed
        liveDot.layer.cornerRadius = 3
        liveDot.isHidden = true
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liveDot)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            liveDot.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            liveDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            liveDot.widthAnchor.constraint(equalToConstant: 6),
            liveDot.heightAnchor.constraint(equalToConstant: 6),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
        ])
    }

    func configure(title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        liveDot.isHidden = title != "Live Now"
    }
}
