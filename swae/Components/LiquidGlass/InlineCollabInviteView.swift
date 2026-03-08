import Combine
import Kingfisher
import UIKit

/// Inline view for inviting a guest to a collab call.
/// Shows follow list when search is empty, global Profilestr search when typing.
/// Supports npub/hex paste via paste button. Profile pics, followers, NIP-05 checkmarks.
///
/// Performance notes:
/// - Uses UITableView with cell reuse instead of a UIStackView, so only visible rows
///   are ever in memory regardless of follow count (Fix 2).
/// - The SearchViewModel subscription to metadataEvents is started in activate() and
///   cancelled in deactivate() so it doesn't persist after the view is hidden (Fix 4).
/// - searchChanged() only sets searchViewModel.searchText; the SearchViewModel's own
///   Combine pipeline drives both local and API search (Fix 3).
class InlineCollabInviteView: UIView, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {

    struct FollowItem {
        let pubkey: String
        let displayName: String
        let username: String?
        let pictureURL: URL?
        let followersCount: Int
        let nip05Domain: String?
        let trustDot: String
        /// Pre-computed truncated npub so makeProfileRow never does bech32 work (Fix 6).
        let truncatedNpub: String
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onInvite: ((String) -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let searchField = UITextField()
    private let pasteButton = UIButton(type: .system)
    private let tableView = UITableView()
    private let emptyLabel = UILabel()
    private let spinnerView = UIActivityIndicatorView(style: .medium)

    // MARK: - State

    private var allFollows: [FollowItem] = []
    private var filteredFollows: [FollowItem] = []
    private var searchResults: [SearchViewModel.SearchResult] = []
    private let searchViewModel = SearchViewModel()
    private var cancellables = Set<AnyCancellable>()
    private weak var boundAppState: AppState?
    private var isShowingSearchResults = false

    private static let followCellId = "FollowCell"
    private static let searchCellId = "SearchCell"

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear

        // Back button
        backButton.translatesAutoresizingMaskIntoConstraints = false
        let backConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "INVITE GUEST"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        // Spinner
        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        spinnerView.color = .white
        spinnerView.hidesWhenStopped = true
        addSubview(spinnerView)

        // Paste button
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        let pasteConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        pasteButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: pasteConfig), for: .normal)
        pasteButton.tintColor = UIColor(white: 1.0, alpha: 0.6)
        pasteButton.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
        addSubview(pasteButton)

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search name, npub, or hex..."
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = .white
        searchField.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        searchField.layer.cornerRadius = 10
        searchField.leftView = makeSearchIcon()
        searchField.leftViewMode = .always
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        addSubview(searchField)

        // Table view — replaces the old UIStackView + UIScrollView (Fix 2)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ProfileRowCell.self, forCellReuseIdentifier: Self.followCellId)
        tableView.register(ProfileRowCell.self, forCellReuseIdentifier: Self.searchCellId)
        addSubview(tableView)

        // Empty label
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No results"
        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            spinnerView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            spinnerView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),

            pasteButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            pasteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            pasteButton.widthAnchor.constraint(equalToConstant: 32),
            pasteButton.heightAnchor.constraint(equalToConstant: 32),

            searchField.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 40),
        ])
    }

    private func makeSearchIcon() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 32, height: 36))
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = UIColor(white: 1.0, alpha: 0.5)
        icon.frame = CGRect(x: 10, y: 10, width: 16, height: 16)
        container.addSubview(icon)
        return container
    }

    // MARK: - Lifecycle (Fix 4)

    /// Call when the view becomes visible. Starts the metadata observer and re-binds
    /// the search pipeline so it's active only while the view is on screen.
    func activate(appState: AppState) {
        bindAppState(appState)
        bindSearchViewModel()
    }

    /// Call when the view is hidden. Cancels the metadata observer and any in-flight
    /// searches so they don't keep running in the background.
    func deactivate() {
        cancellables.removeAll()
        searchViewModel.unbind()
        // Reset search state so the next open starts fresh
        searchField.text = ""
        isShowingSearchResults = false
        searchResults = []
        tableView.reloadData()
        emptyLabel.isHidden = true
    }

    // MARK: - Combine Binding

    private func bindSearchViewModel() {
        // Cancel any existing subscriptions before re-binding
        cancellables.removeAll()

        searchViewModel.$searchResults
            .receive(on: DispatchQueue.main)
            .sink { [weak self] results in
                guard let self, self.isShowingSearchResults else { return }
                self.searchResults = results
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !results.isEmpty || self.searchViewModel.isSearching
            }
            .store(in: &cancellables)

        searchViewModel.$isSearching
            .receive(on: DispatchQueue.main)
            .sink { [weak self] searching in
                if searching {
                    self?.spinnerView.startAnimating()
                } else {
                    self?.spinnerView.stopAnimating()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    func configure(follows: [FollowItem]) {
        allFollows = follows
        applyFollowFilter()
    }

    func bindAppState(_ appState: AppState) {
        guard boundAppState == nil || boundAppState !== appState else { return }
        boundAppState = appState
        searchViewModel.bind(appState: appState)
    }

    // MARK: - Filtering

    private func applyFollowFilter() {
        guard !isShowingSearchResults else { return }
        let query = (searchField.text ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredFollows = allFollows
        } else {
            filteredFollows = allFollows.filter {
                $0.displayName.lowercased().contains(query) ||
                ($0.username?.lowercased().contains(query) ?? false) ||
                $0.pubkey.lowercased().contains(query)
            }
        }
        tableView.reloadData()
        emptyLabel.isHidden = !filteredFollows.isEmpty
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isShowingSearchResults {
            return searchResults.count
        }
        return filteredFollows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: isShowingSearchResults ? Self.searchCellId : Self.followCellId,
            for: indexPath
        ) as! ProfileRowCell

        if isShowingSearchResults {
            let result = searchResults[indexPath.row]
            cell.configure(
                pubkey: result.pubkey,
                displayName: result.displayName,
                username: result.username,
                pictureURL: result.pictureURL,
                nip05Domain: result.nip05Domain,
                trustDot: result.trustDot,
                truncatedNpub: result.pubkey.prefix(10) + "..."
            )
        } else {
            let item = filteredFollows[indexPath.row]
            cell.configure(
                pubkey: item.pubkey,
                displayName: item.displayName,
                username: item.username,
                pictureURL: item.pictureURL,
                nip05Domain: item.nip05Domain,
                trustDot: item.trustDot,
                truncatedNpub: item.truncatedNpub
            )
        }
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let pubkey: String
        if isShowingSearchResults {
            pubkey = searchResults[indexPath.row].pubkey
        } else {
            pubkey = filteredFollows[indexPath.row].pubkey
        }
        endEditing(true)
        onInvite?(pubkey)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        endEditing(true)
        searchViewModel.cancelSearch()
        onBack?()
    }

    @objc private func pasteTapped() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        searchField.text = text
        searchChanged()
    }

    /// Fix 3: only sets searchViewModel.searchText — the SearchViewModel's own Combine
    /// pipeline drives both the instant local search and the debounced API search.
    /// No direct call to search(query:appState:) here.
    @objc private func searchChanged() {
        let text = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            isShowingSearchResults = false
            searchViewModel.cancelSearch()
            searchViewModel.searchText = ""
            applyFollowFilter()
        } else {
            isShowingSearchResults = true
            // Setting searchText triggers the SearchViewModel's Combine pipeline:
            // - instant local search fires immediately via $searchText sink
            // - debounced API search fires 300ms later via $debouncedSearchText sink
            searchViewModel.searchText = text
        }
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if !searchResults.isEmpty, isShowingSearchResults {
            onInvite?(searchResults[0].pubkey)
        }
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - ProfileRowCell

/// Reusable table view cell for a follow or search result row.
/// Replaces the per-row UIView factory that created 7 subviews + 10 constraints each time.
private final class ProfileRowCell: UITableViewCell {

    private let pfp = UIImageView()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let nip05Label = UILabel()
    private let inviteIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none
        contentView.backgroundColor = .clear

        pfp.translatesAutoresizingMaskIntoConstraints = false
        pfp.contentMode = .scaleAspectFill
        pfp.clipsToBounds = true
        pfp.layer.cornerRadius = 18
        pfp.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        contentView.addSubview(pfp)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(nameLabel)

        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        usernameLabel.font = .systemFont(ofSize: 12, weight: .regular)
        usernameLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        usernameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(usernameLabel)

        nip05Label.translatesAutoresizingMaskIntoConstraints = false
        nip05Label.font = .systemFont(ofSize: 11, weight: .regular)
        nip05Label.textColor = UIColor.systemPurple.withAlphaComponent(0.8)
        nip05Label.isHidden = true
        contentView.addSubview(nip05Label)

        inviteIcon.translatesAutoresizingMaskIntoConstraints = false
        inviteIcon.image = UIImage(systemName: "paperplane.fill")
        inviteIcon.tintColor = .systemBlue
        contentView.addSubview(inviteIcon)

        NSLayoutConstraint.activate([
            pfp.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            pfp.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pfp.widthAnchor.constraint(equalToConstant: 36),
            pfp.heightAnchor.constraint(equalToConstant: 36),

            inviteIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            inviteIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            inviteIcon.widthAnchor.constraint(equalToConstant: 18),
            inviteIcon.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: pfp.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: inviteIcon.leadingAnchor, constant: -8),

            usernameLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            usernameLabel.trailingAnchor.constraint(lessThanOrEqualTo: inviteIcon.leadingAnchor, constant: -8),

            nip05Label.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            nip05Label.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 1),
            nip05Label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            nip05Label.trailingAnchor.constraint(lessThanOrEqualTo: inviteIcon.leadingAnchor, constant: -8),

            // When nip05 is hidden, pin usernameLabel bottom to contentView
            usernameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),
        ])

        // Minimum row height
        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    func configure(
        pubkey: String,
        displayName: String,
        username: String?,
        pictureURL: URL?,
        nip05Domain: String?,
        trustDot: String,
        truncatedNpub: String
    ) {
        // Profile picture — Kingfisher handles caching and background decode
        pfp.kf.cancelDownloadTask()
        if let url = pictureURL {
            pfp.kf.setImage(with: url, options: [
                .transition(.none),
                .cacheOriginalImage,
                .processor(DownsamplingImageProcessor(size: CGSize(width: 72, height: 72))),
                .scaleFactor(UIScreen.main.scale),
                .backgroundDecode,
            ])
        } else {
            pfp.image = UIImage(systemName: "person.circle.fill")
            pfp.tintColor = .gray
        }

        // Name
        let nameText = trustDot.isEmpty ? displayName : "\(trustDot) \(displayName)"
        nameLabel.text = nameText.isEmpty ? truncatedNpub : nameText

        // Username
        if let un = username, !un.isEmpty {
            usernameLabel.text = "@\(un)"
        } else {
            usernameLabel.text = truncatedNpub
        }

        // NIP-05
        if let domain = nip05Domain {
            nip05Label.text = "✓ \(domain)"
            nip05Label.isHidden = false
        } else {
            nip05Label.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pfp.kf.cancelDownloadTask()
        pfp.image = nil
        nameLabel.text = nil
        usernameLabel.text = nil
        nip05Label.text = nil
        nip05Label.isHidden = true
    }
}
