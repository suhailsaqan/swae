//
//  CategoryTagsHelper.swift
//  swae
//
//  Utility to parse/combine structured category tags for stream setup.
//  Converts between the flat [String] tag array and the structured
//  (category, gameId, gameName, additionalTags) representation.
//

import Foundation

enum CategoryTagsHelper {
    /// Regex matching prefixed game tags like "igdb:1942", "internal:gaming"
    private static let prefixedTagRegex = /^[a-z-]+:[a-z0-9-]+$/

    /// All known category match tags (lowercased).
    private static let allCategoryTags: Set<String> = {
        Set(StreamCategory.all.flatMap { $0.matchTags })
    }()

    /// Parse a flat tags array into structured components.
    struct ParsedTags {
        var category: StreamCategory?
        var gameId: String?
        var gameName: String?  // Will be nil until fetched
        var additionalTags: String
    }

    static func parse(tags: [String]) -> ParsedTags {
        var category: StreamCategory?
        var gameId: String?
        var additional: [String] = []

        for tag in tags {
            let lower = tag.lowercased()

            // Check if it's a prefixed tag (e.g. "igdb:1942")
            if lower.wholeMatch(of: prefixedTagRegex) != nil {
                // It's a game/structured tag — keep the first one as gameId
                if gameId == nil {
                    gameId = tag
                }
                continue
            }

            // Check if it matches a known category
            if let cats = StreamCategory.tagLookup[lower], !cats.isEmpty {
                if category == nil {
                    category = cats[0]
                }
                // Don't add category tags to additional
                continue
            }

            // Everything else is an additional tag
            additional.append(tag)
        }

        return ParsedTags(
            category: category,
            gameId: gameId,
            gameName: nil,
            additionalTags: additional.joined(separator: ", ")
        )
    }

    /// Combine structured components back into a flat tags array.
    static func combine(
        category: StreamCategory?,
        gameId: String?,
        additionalTags: String
    ) -> [String] {
        var result: [String] = []

        if let cat = category {
            result.append(cat.matchTags[0])
        }

        if let gid = gameId, !gid.isEmpty {
            result.append(gid)
        }

        let extras = additionalTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        result.append(contentsOf: extras)

        return result
    }
}
