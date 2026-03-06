//
//  GameSearchViewModel.swift
//  swae
//
//  Debounced IGDB game search for the category picker.
//

import Combine
import Foundation

@MainActor
class GameSearchViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var results: [GameInfo] = []
    @Published var isSearching = false
    /// True after at least one search has completed (distinguishes "no results" from "hasn't searched")
    @Published var hasSearched = false

    private var searchTask: Task<Void, Never>?

    init() {
        // Debounce via Combine → async bridge
        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func performSearch(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            hasSearched = false
            return
        }

        isSearching = true
        searchTask = Task {
            let games = await GameDatabaseService.shared.searchGames(query: trimmed, limit: 8)
            guard !Task.isCancelled else { return }
            results = games
            isSearching = false
            hasSearched = true
        }
    }

    func clear() {
        searchText = ""
        results = []
        isSearching = false
        hasSearched = false
        searchTask?.cancel()
    }
}
