//
//  CachedHeroData.swift
//  swae
//
//  Caches the last-seen hero stream data for instant startup preview.
//  Loaded from UserDefaults before relay data arrives.
//

import Foundation

struct CachedHeroData: Codable {
    let eventId: String
    let title: String
    let hostPubkeyHex: String
    let hostDisplayName: String?
    let thumbnailURLString: String?
    let viewerCount: Int
    let isLive: Bool
    let streamingURLString: String?
    let recordingURLString: String?

    static let userDefaultsKey = "cachedHeroData"

    static func save(_ data: CachedHeroData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    static func load() -> CachedHeroData? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CachedHeroData.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
