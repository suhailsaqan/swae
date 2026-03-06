//
//  SeeAllViewController.swift
//  swae
//
//  Full grid view for a home feed section (tapped from "See All")
//

import NostrSDK
import UIKit

final class SeeAllViewController: UIViewController {

    // MARK: - Dependencies
    private let appState: AppState
    private let sectionTitle: String
    private let events: [LiveActivitiesEvent]

    // MARK: - Callbacks
    var onEventSelected: ((LiveActivitiesEvent) -> Void)?
    var onHostTapped: ((String) -> Void)?

    // MARK: - UI
    private let collectionView: UICollectionView
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    // MARK: - Data Source
    private lazy var dataSource = makeDataSource()

    // MARK: - Init

    init(appState: AppState, sectionTitle: String, events: [LiveActivitiesEvent]) {
        self.appState = appState
        self.sectionTitle = sectionTitle
        self.events = events
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.createGridLayout())
        super.init(nibName: nil, bundle: nil)
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
        applySnapshot()
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

        // Back button
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: config), for: .normal)
        backButton.tintColor = .label
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(backButton)

        // Title
        titleLabel.text = sectionTitle
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
        collectionView.register(StreamCardCell.self, forCellWithReuseIdentifier: StreamCardCell.reuseIdentifier)
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Layout

    private static func createGridLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.5),
            heightDimension: .estimated(180)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .estimated(180)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 16, trailing: 10)

        return UICollectionViewCompositionalLayout { _, _ in section }
    }

    // MARK: - Data Source

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Int, String> {
        UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, _ in
            guard let self = self else { return UICollectionViewCell() }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: StreamCardCell.reuseIdentifier, for: indexPath
            ) as! StreamCardCell

            let event = self.events[indexPath.item]
            cell.applyConfiguration(.default)
            cell.configure(with: event, appState: self.appState)
            cell.onTap = { [weak self] in
                self?.onEventSelected?(event)
            }
            cell.onHostTap = { [weak self] pubkeyHex in
                self?.onHostTapped?(pubkeyHex)
            }
            return cell
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        let ids = events.enumerated().map { index, event in
            event.id ?? "event-\(index)"
        }
        snapshot.appendItems(ids, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

// MARK: - UICollectionViewDelegate
extension SeeAllViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < events.count else { return }
        onEventSelected?(events[indexPath.item])
    }
}
