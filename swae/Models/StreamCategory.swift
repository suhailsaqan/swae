//
//  StreamCategory.swift
//  swae
//
//  Phase 1: Static category definitions for homepage reorganization.
//  Maps Nostr `t` tags to display categories with icons and gradients.
//

import UIKit

struct StreamCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String            // SF Symbol name
    let matchTags: [String]     // Lowercase t-tag values that map to this category
    let priority: Int           // 0 = primary (shown in pill bar), 1 = secondary
    let gradientColors: [UIColor]
    let coverImageName: String? // Asset catalog image name, nil = gradient-only

    // MARK: - Static Definitions

    static let all: [StreamCategory] = [
        StreamCategory(
            id: "irl", name: "IRL", icon: "person.fill",
            matchTags: ["irl"],
            priority: 0,
            gradientColors: [UIColor.systemOrange, UIColor.systemRed],
            coverImageName: "category_irl"
        ),
        StreamCategory(
            id: "gaming", name: "Gaming", icon: "gamecontroller.fill",
            matchTags: ["gaming"],
            priority: 0,
            gradientColors: [UIColor.systemPurple, UIColor.systemIndigo],
            coverImageName: "category_gaming"
        ),
        StreamCategory(
            id: "music", name: "Music", icon: "music.note",
            matchTags: ["music", "radio"],
            priority: 0,
            gradientColors: [UIColor.systemPink, UIColor.systemPurple],
            coverImageName: "category_music"
        ),
        StreamCategory(
            id: "talk", name: "Talk", icon: "mic.fill",
            matchTags: ["talk"],
            priority: 0,
            gradientColors: [UIColor.systemTeal, UIColor.systemBlue],
            coverImageName: "category_talk"
        ),
        StreamCategory(
            id: "art", name: "Art", icon: "paintbrush.fill",
            matchTags: ["art"],
            priority: 0,
            gradientColors: [UIColor.systemYellow, UIColor.systemOrange],
            coverImageName: "category_art"
        ),
        StreamCategory(
            id: "gambling", name: "Gambling", icon: "dice.fill",
            matchTags: ["gambling", "casino", "slots"],
            priority: 1,
            gradientColors: [UIColor.systemGreen, UIColor.systemTeal],
            coverImageName: nil
        ),
        StreamCategory(
            id: "science", name: "Science & Tech", icon: "atom",
            matchTags: ["science", "technology", "tech"],
            priority: 1,
            gradientColors: [UIColor.systemBlue, UIColor.systemCyan],
            coverImageName: nil
        ),
    ]

    /// Primary categories shown in the pill bar (priority == 0)
    static let primaryCategories: [StreamCategory] = all.filter { $0.priority == 0 }

    /// Precomputed lookup: lowercased tag → [StreamCategory]
    /// Built once at launch, O(1) lookup per tag during rebuildSections.
    static let tagLookup: [String: [StreamCategory]] = {
        var map: [String: [StreamCategory]] = [:]
        for cat in all {
            for tag in cat.matchTags {
                map[tag, default: []].append(cat)
            }
        }
        return map
    }()

    /// Matches hashtags to categories using the precomputed tagLookup.
    /// Works with any event type that has hashtags (LiveActivitiesEvent, LiveStreamClipEvent, VideoEvent).
    static func categories(forHashtags hashtags: [String]) -> [StreamCategory] {
        var seen = Set<String>()
        var result: [StreamCategory] = []
        for tag in hashtags {
            if let cats = tagLookup[tag.lowercased()] {
                for cat in cats where seen.insert(cat.id).inserted {
                    result.append(cat)
                }
            }
        }
        return result
    }
}
