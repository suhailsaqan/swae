//
//  SearchViewModel.swift
//  gibbe
//
//  Created by Suhail Saqan on 11/24/24.
//

import Foundation

class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var debouncedSearchText = ""

    init() {
        // Debounce the search text
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .assign(to: &$debouncedSearchText)
    }
}
