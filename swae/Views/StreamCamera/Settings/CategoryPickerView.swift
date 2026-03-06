//
//  CategoryPickerView.swift
//  swae
//
//  Category pills + conditional IGDB game search for stream setup.
//  Replaces the plain-text tags field with structured category selection.
//

import Kingfisher
import SwiftUI

struct CategoryPickerView: View {
    @Binding var selectedCategory: StreamCategory?
    @Binding var selectedGameId: String?
    @Binding var selectedGameName: String?
    @Binding var additionalTags: String

    @StateObject private var searchVM = GameSearchViewModel()
    @State private var selectedGameCoverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Category Pills
            categorySection

            // MARK: - Game Search (Gaming only)
            if selectedCategory?.id == "gaming" {
                gameSection
            }

            // MARK: - Additional Tags
            additionalTagsSection
        }
        .task {
            // Fetch game info if we have a gameId but no name (restoring from saved tags)
            if let gameId = selectedGameId, selectedGameName == nil {
                if let info = await GameDatabaseService.shared.getGame(id: gameId) {
                    selectedGameName = info.name
                    selectedGameCoverURL = info.coverURL
                }
            }
        }
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StreamCategory.all) { category in
                        CategoryPill(
                            category: category,
                            isSelected: selectedCategory?.id == category.id
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedCategory?.id == category.id {
                                    selectedCategory = nil
                                    // Clear game if deselecting gaming
                                    if category.id == "gaming" {
                                        clearGame()
                                    }
                                } else {
                                    selectedCategory = category
                                    // Clear game when switching away from gaming
                                    if category.id != "gaming" {
                                        clearGame()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Game Section

    private var gameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Game (optional)")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            if let gameId = selectedGameId, let gameName = selectedGameName {
                // Selected game chip
                selectedGameChip(id: gameId, name: gameName)
            } else {
                // Search field + results
                gameSearchField
            }
        }
    }

    private func selectedGameChip(id: String, name: String) -> some View {
        HStack(spacing: 10) {
            if let url = selectedGameCoverURL {
                KFImage(url)
                    .resizable()
                    .placeholder { Color.gray.opacity(0.3) }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation { clearGame() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("\(name), selected. Double tap to remove.")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    private var gameSearchField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                TextField("Search for a game...", text: $searchVM.searchText)
                    .font(.body)
                    .submitLabel(.done)
                    .onSubmit {
                        // If user hits return with text but no results, use it as custom name
                        useCustomGameName()
                    }

                if searchVM.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )

            // Search results dropdown
            if !searchVM.results.isEmpty || showUseCustomOption {
                VStack(spacing: 0) {
                    // IGDB results
                    ForEach(searchVM.results, id: \.id) { game in
                        Button {
                            selectGame(game)
                        } label: {
                            HStack(spacing: 10) {
                                if let url = game.coverURL {
                                    KFImage(url)
                                        .resizable()
                                        .placeholder {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.gray.opacity(0.3))
                                        }
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    Image(systemName: "gamecontroller.fill")
                                        .frame(width: 28, height: 28)
                                        .foregroundColor(.secondary)
                                }

                                Text(game.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .accessibilityLabel(game.name)

                        Divider().padding(.leading, 50)
                    }

                    // "Use custom name" option — shown when search completed
                    if showUseCustomOption {
                        Button {
                            useCustomGameName()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle")
                                    .frame(width: 28, height: 28)
                                    .foregroundColor(.accentColor)

                                Text("Use \"\(searchVM.searchText.trimmingCharacters(in: .whitespaces))\"")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .accessibilityLabel("Use custom game name: \(searchVM.searchText)")
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
                .padding(.top, 4)
            }
        }
    }

    /// Show the "Use custom name" row when the user has typed something and search is done.
    private var showUseCustomOption: Bool {
        let trimmed = searchVM.searchText.trimmingCharacters(in: .whitespaces)
        return searchVM.hasSearched && !searchVM.isSearching && trimmed.count >= 2
    }

    // MARK: - Additional Tags Section

    private var additionalTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Additional Tags")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            TextField("fishing, san diego, english", text: $additionalTags)
                .font(.body)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )

            Text("Comma-separated tags for extra discoverability")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func selectGame(_ game: GameInfo) {
        selectedGameId = game.id
        selectedGameName = game.name
        selectedGameCoverURL = game.coverURL
        searchVM.clear()
    }

    /// Use whatever the user typed as a plain-text game tag (no IGDB ID, no cover art).
    private func useCustomGameName() {
        let name = searchVM.searchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Use "custom:" prefix so CategoryTagsHelper.parse() recognises it as a
        // prefixed game tag and doesn't dump it into additional tags.
        selectedGameId = "custom:\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
        selectedGameName = name
        selectedGameCoverURL = nil
        searchVM.clear()
    }

    private func clearGame() {
        selectedGameId = nil
        selectedGameName = nil
        selectedGameCoverURL = nil
        searchVM.clear()
    }
}

// MARK: - Category Pill

private struct CategoryPill: View {
    let category: StreamCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.name)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? categoryGradient : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
        }
        .accessibilityLabel("\(category.name) category\(isSelected ? ", selected" : "")")
    }

    private var categoryGradient: AnyShapeStyle {
        let colors = category.gradientColors.map { Color($0) }
        return AnyShapeStyle(
            LinearGradient(
                colors: colors,
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}
