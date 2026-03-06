//
//  SearchViewModel.swift
//  swae
//
//  Created by Suhail Saqan on 11/24/24.
//

import Combine
import Foundation
import NostrSDK

class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var discoveryProfiles: [ProfilestrUser] = []

    private var searchTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    // Separate cancellable for the metadataEvents subscription so it can be
    // independently cancelled when the view is hidden (Fix 4).
    private var metadataCancellable: AnyCancellable?
    private weak var boundAppState: AppState?

    /// When a pubkey search is active, this holds the hex pubkey we're waiting on from relays.
    private var pendingPubkeyLookup: String?

    // MARK: - Search Result

    struct SearchResult: Identifiable {
        let id: String          // pubkey hex
        let pubkey: String
        let metadata: UserMetadata?
        let profilestrUser: ProfilestrUser?
        let isLocalMatch: Bool

        var displayName: String {
            if let pUser = profilestrUser {
                return pUser.displayName ?? pUser.name ?? String(pubkey.prefix(8))
            }
            return metadata?.displayName ?? metadata?.name ?? String(pubkey.prefix(8))
        }

        var username: String? {
            if let pUser = profilestrUser {
                return pUser.name
            }
            return metadata?.name
        }

        var pictureURL: URL? {
            if let urlStr = profilestrUser?.picture, let url = URL(string: urlStr) {
                return url
            }
            return metadata?.pictureURL
        }

        var followersCount: Int {
            profilestrUser?.followersCount ?? 0
        }

        var nip05Domain: String? {
            if let nip05 = profilestrUser?.nip05 ?? metadata?.nostrAddress {
                let parts = nip05.split(separator: "@")
                return parts.count == 2 ? String(parts[1]) : nip05
            }
            return nil
        }

        var trustDot: String {
            guard let scores = profilestrUser?.trustScores,
                  let level = scores.combined?.level else { return "" }
            switch level.lowercased() {
            case "high": return "🟢"
            case "medium": return "🟡"
            case "low": return "🔴"
            default: return ""
            }
        }

        var trustScore: Int? {
            profilestrUser?.trustScores?.combined?.score
        }
    }

    // MARK: - Init

    init() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .assign(to: &$debouncedSearchText)

        // Debounced API search — only fires after the user pauses typing
        $debouncedSearchText
            .sink { [weak self] text in
                guard let self = self, let appState = self.boundAppState else { return }
                self.apiSearch(query: text, appState: appState)
            }
            .store(in: &cancellables)

        // Instant local search on every keystroke — no debounce needed, it's cheap
        // and gives immediate feedback while the API call is in flight.
        // Fix 3: local search is driven entirely from here; the view no longer calls
        // search(query:appState:) directly on every keystroke.
        $searchText
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self, let appState = self.boundAppState else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    // Cleared — reset state (apiSearch handles the empty debounced path)
                    self.searchResults = []
                    self.isSearching = false
                    self.pendingPubkeyLookup = nil
                    return
                }
                // Run the instant local/pubkey search
                self.search(query: trimmed, appState: appState)
            }
            .store(in: &cancellables)
    }

    // MARK: - Bind / Unbind AppState

    /// Call this when the invite view becomes visible to start the metadata observer.
    func bind(appState: AppState) {
        self.boundAppState = appState
        subscribeToMetadataEvents(appState: appState)
    }

    /// Call this when the invite view is hidden to stop the metadata observer and
    /// cancel any in-flight searches. Prevents the persistent hot subscription that
    /// caused the freeze-after-dismiss (Fix 4).
    func unbind() {
        metadataCancellable?.cancel()
        metadataCancellable = nil
        cancelSearch()
        searchResults = []
        isSearching = false
    }

    private func subscribeToMetadataEvents(appState: AppState) {
        // Cancel any existing subscription before creating a new one
        metadataCancellable?.cancel()

        // Observe relay metadata arrivals so pubkey lookups resolve when the relay responds.
        // This subscription is intentionally kept separate from `cancellables` so it can be
        // cancelled independently via unbind() without tearing down the whole pipeline.
        metadataCancellable = appState.$metadataEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metadataEvents in
                guard let self = self,
                      let pubkey = self.pendingPubkeyLookup,
                      let metadataEvent = metadataEvents[pubkey] else { return }

                // Relay delivered the metadata we were waiting for
                self.pendingPubkeyLookup = nil

                // Merge with any existing results (profilestr may have already returned)
                let existing = self.searchResults
                if existing.contains(where: { $0.pubkey == pubkey }) {
                    // Already have a result for this pubkey — enrich it with relay metadata
                    self.searchResults = existing.map { result in
                        guard result.pubkey == pubkey else { return result }
                        return SearchResult(
                            id: result.id,
                            pubkey: result.pubkey,
                            metadata: metadataEvent.userMetadata,
                            profilestrUser: result.profilestrUser,
                            isLocalMatch: true
                        )
                    }
                } else {
                    // No result yet — add the relay result
                    let result = SearchResult(
                        id: pubkey,
                        pubkey: pubkey,
                        metadata: metadataEvent.userMetadata,
                        profilestrUser: nil,
                        isLocalMatch: true
                    )
                    self.searchResults = [result] + existing
                }
                self.isSearching = false
            }
    }

    // MARK: - Pubkey Detection

    /// Resolves a hex pubkey from the query if it's a valid 64-char hex string or npub.
    /// Returns nil if the query is a normal text search.
    private func resolvedPubkeyHex(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // npub bech32 format
        if trimmed.lowercased().hasPrefix("npub1"),
           let pk = PublicKey(npub: trimmed) {
            return pk.hex
        }

        // 64-char hex pubkey
        if trimmed.count == 64,
           trimmed.allSatisfy({ $0.isHexDigit }),
           PublicKey(hex: trimmed) != nil {
            return trimmed.lowercased()
        }

        return nil
    }

    // MARK: - Search

    /// Instant local search — called from the $searchText sink on every keystroke.
    /// Also callable directly for paste/programmatic input.
    func search(query: String, appState: AppState) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            pendingPubkeyLookup = nil
            return
        }

        isSearching = true

        // Pubkey / npub detection — direct lookup instead of name search
        if let hexPubkey = resolvedPubkeyHex(from: trimmed) {
            if let metadataEvent = appState.metadataEvents[hexPubkey] {
                // Already cached locally — show immediately
                pendingPubkeyLookup = nil
                searchResults = [SearchResult(
                    id: hexPubkey,
                    pubkey: hexPubkey,
                    metadata: metadataEvent.userMetadata,
                    profilestrUser: nil,
                    isLocalMatch: true
                )]
            } else {
                // Not cached — request from relays, show skeleton until it arrives
                pendingPubkeyLookup = hexPubkey
                searchResults = []
                appState.pullMissingEventsFromPubkeysAndFollows([hexPubkey])
            }
            return
        }

        // Normal text search
        pendingPubkeyLookup = nil
        let lowered = trimmed.lowercased()
        searchResults = localSearch(query: lowered, appState: appState)
    }

    /// Debounced API search — called after the user stops typing for 300ms.
    private func apiSearch(query: String, appState: AppState) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            pendingPubkeyLookup = nil
            return
        }

        // Pubkey / npub — fetch single user from profilestr for enrichment
        if let hexPubkey = resolvedPubkeyHex(from: trimmed) {
            isSearching = true

            searchTask = Task { [weak self] in
                let startTime = ContinuousClock.now
                let apiUser = await ProfilestrAPIClient.shared.fetchUser(pubkey: hexPubkey)
                guard !Task.isCancelled else { return }

                // Minimum skeleton display time
                let elapsed = ContinuousClock.now - startTime
                let minDisplay = Duration.milliseconds(400)
                if elapsed < minDisplay {
                    try? await Task.sleep(for: minDisplay - elapsed)
                }
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self = self else { return }
                    let localMeta = appState.metadataEvents[hexPubkey]?.userMetadata

                    if apiUser != nil || localMeta != nil {
                        // We have data from at least one source
                        self.pendingPubkeyLookup = nil
                        self.searchResults = [SearchResult(
                            id: hexPubkey,
                            pubkey: hexPubkey,
                            metadata: localMeta,
                            profilestrUser: apiUser,
                            isLocalMatch: localMeta != nil
                        )]
                        self.isSearching = false
                    } else if self.pendingPubkeyLookup == hexPubkey {
                        // Neither source has data yet — keep waiting for relay
                        // (isSearching stays true, skeleton keeps showing)
                    } else {
                        // No pending relay lookup either — show empty
                        self.searchResults = []
                        self.isSearching = false
                    }
                }
            }
            return
        }

        // Normal text search
        isSearching = true
        let lowered = trimmed.lowercased()
        let localResults = localSearch(query: lowered, appState: appState)

        searchTask = Task { [weak self] in
            let startTime = ContinuousClock.now
            let apiUsers = await ProfilestrAPIClient.shared.searchUsers(query: trimmed, limit: 15)
            guard !Task.isCancelled else { return }

            // Ensure skeletons show for at least 400ms to avoid a jarring flash
            let elapsed = ContinuousClock.now - startTime
            let minDisplay = Duration.milliseconds(400)
            if elapsed < minDisplay {
                try? await Task.sleep(for: minDisplay - elapsed)
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self = self else { return }
                let merged = self.mergeResults(local: localResults, api: apiUsers)
                self.searchResults = merged
                self.isSearching = false
            }
        }
    }

    // MARK: - Local Search

    private func localSearch(query: String, appState: AppState) -> [SearchResult] {
        var results: [SearchResult] = []
        var seen = Set<String>()

        for (pubkey, metadataEvent) in appState.metadataEvents {
            guard let userMeta = metadataEvent.userMetadata else { continue }

            let nameMatch = userMeta.name?.lowercased().contains(query) == true
            let displayMatch = userMeta.displayName?.lowercased().contains(query) == true
            let nip05Match = userMeta.nostrAddress?.lowercased().contains(query) == true

            if nameMatch || displayMatch || nip05Match {
                guard !seen.contains(pubkey) else { continue }
                seen.insert(pubkey)
                results.append(SearchResult(
                    id: pubkey,
                    pubkey: pubkey,
                    metadata: userMeta,
                    profilestrUser: nil,
                    isLocalMatch: true
                ))
            }

            // Cap local results for performance
            if results.count >= 20 { break }
        }

        return results
    }

    // MARK: - Merge & Deduplicate

    private func mergeResults(local: [SearchResult], api: [ProfilestrUser]) -> [SearchResult] {
        var merged: [SearchResult] = []
        var seen = Set<String>()

        // API results first (they have richer data: followers, trust scores)
        for user in api {
            guard !seen.contains(user.pubkey) else { continue }
            seen.insert(user.pubkey)

            // Find matching local metadata if available
            let localMatch = local.first(where: { $0.pubkey == user.pubkey })
            merged.append(SearchResult(
                id: user.pubkey,
                pubkey: user.pubkey,
                metadata: localMatch?.metadata,
                profilestrUser: user,
                isLocalMatch: localMatch != nil
            ))
        }

        // Then local-only results (not in API response)
        for result in local {
            guard !seen.contains(result.pubkey) else { continue }
            seen.insert(result.pubkey)
            merged.append(result)
        }

        return merged
    }

    // MARK: - Discovery

    func loadDiscoveryProfiles() {
        guard discoveryProfiles.isEmpty else { return }

        discoveryTask = Task { [weak self] in
            let users = await ProfilestrAPIClient.shared.fetchRandomUsers(limit: 15)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.discoveryProfiles = users
            }
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        discoveryTask?.cancel()
        pendingPubkeyLookup = nil
    }
}
