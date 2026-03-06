//
//  ProfilestrAPIClient.swift
//  swae
//
//  API client for profilestr.com — provides follower counts, search, and trust scores
//  that cannot be efficiently computed from Nostr relays alone.
//

import Foundation

// MARK: - Response Models

struct ProfilestrUser: Codable, Identifiable {
    var id: String { pubkey }

    let pubkey: String
    let name: String?
    let displayName: String?
    let about: String?
    let picture: String?
    let banner: String?
    let nip05: String?
    let lud16: String?
    let followersCount: Int
    let followsCount: Int
    let noteCount: Int
    let replyCount: Int
    let zapCount: Int
    let totalSatsZapped: Int?
    let totalAmountSent: Int?
    let totalAmountReceived: Int?
    let mediaCount: Int?
    let timeJoined: Int?
    let npub: String?
    let trustScores: ProfilestrTrustScores?
}

struct ProfilestrTrustScores: Codable {
    let combined: CombinedTrustScore?
    let profilestr: ProfilestrScore?
    let vertex: VertexScore?
    let relatr: RelatrScore?
}

struct CombinedTrustScore: Codable {
    let score: Int?
    let level: String?
    let description: String?
}

struct ProfilestrScore: Codable {
    let score: Int?
    let level: String?
}

struct VertexScore: Codable {
    let rank: Double?
    let nodes: Int?
}

struct RelatrScore: Codable {
    let score: Double?
    let percentage: Int?
    let components: RelatrComponents?
}

struct RelatrComponents: Codable {
    let validators: RelatrValidators?
    let socialDistance: Int?
}

struct RelatrValidators: Codable {
    let nip05Valid: Int?
    let isRootNip05: Int?
    let reciprocity: Int?
    let lightningAddress: Int?
}

private struct ProfilestrResponse: Codable {
    let users: [ProfilestrUser]?
}

// MARK: - API Client

actor ProfilestrAPIClient {
    static let shared = ProfilestrAPIClient()

    private let baseURL = "https://profilestr.com/api"
    private let session: URLSession

    // Cache
    private var userCache: [String: (user: ProfilestrUser, fetchedAt: Date)] = [:]
    private var searchCache: [String: (users: [ProfilestrUser], fetchedAt: Date)] = [:]

    private let userTTL: TimeInterval = 300       // 5 minutes
    private let searchTTL: TimeInterval = 3600    // 1 hour
    private let maxUserCache = 500
    private let maxSearchCache = 50

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Fetch a single user by hex pubkey. Returns nil on any failure.
    func fetchUser(pubkey: String) async -> ProfilestrUser? {
        // Cache check
        if let cached = userCache[pubkey], Date().timeIntervalSince(cached.fetchedAt) < userTTL {
            return cached.user
        }

        guard let url = URL(string: "\(baseURL)/users/\(pubkey)") else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(ProfilestrResponse.self, from: data)
            guard let user = decoded.users?.first else { return nil }

            evictUserCacheIfNeeded()
            userCache[pubkey] = (user, Date())
            return user
        } catch {
            return nil
        }
    }

    /// Search users by display name. Returns empty array on failure.
    func searchUsers(query: String, limit: Int = 10) async -> [ProfilestrUser] {
        let cacheKey = "\(query)|\(limit)"
        if let cached = searchCache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < searchTTL {
            return cached.users
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/users/\(encodedQuery)?limit=\(limit)&includeNpub=true")
        else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(ProfilestrResponse.self, from: data)
            let users = decoded.users ?? []

            evictSearchCacheIfNeeded()
            searchCache[cacheKey] = (users, Date())

            // Also populate user cache from search results
            for user in users {
                userCache[user.pubkey] = (user, Date())
            }
            return users
        } catch {
            return []
        }
    }

    /// Batch-fetch users by hex pubkeys. Cache-first, parallel fetch for misses.
    /// Returns dictionary keyed by pubkey hex.
    func fetchUsers(pubkeys: [String]) async -> [String: ProfilestrUser] {
        var result: [String: ProfilestrUser] = [:]
        var uncached: [String] = []

        for pk in pubkeys {
            if let cached = userCache[pk], Date().timeIntervalSince(cached.fetchedAt) < userTTL {
                result[pk] = cached.user
            } else {
                uncached.append(pk)
            }
        }

        guard !uncached.isEmpty else { return result }

        await withTaskGroup(of: (String, ProfilestrUser?).self) { group in
            for pk in uncached {
                group.addTask {
                    let user = await self.fetchUser(pubkey: pk)
                    return (pk, user)
                }
            }
            for await (pk, user) in group {
                if let user {
                    result[pk] = user
                }
            }
        }

        return result
    }

    /// Fetch random users for discovery. Returns empty array on failure.
    func fetchRandomUsers(limit: Int = 10) async -> [ProfilestrUser] {
        guard let url = URL(string: "\(baseURL)/users/random?limit=\(limit)&includeNpub=true") else { return [] }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(ProfilestrResponse.self, from: data)
            let users = decoded.users ?? []

            // Populate user cache from random results
            for user in users {
                userCache[user.pubkey] = (user, Date())
            }
            return users
        } catch {
            return []
        }
    }

    // MARK: - Cache Eviction

    private func evictUserCacheIfNeeded() {
        guard userCache.count >= maxUserCache else { return }
        let sorted = userCache.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
        let removeCount = maxUserCache / 5 // Remove oldest 20%
        for (key, _) in sorted.prefix(removeCount) {
            userCache.removeValue(forKey: key)
        }
    }

    private func evictSearchCacheIfNeeded() {
        guard searchCache.count >= maxSearchCache else { return }
        let sorted = searchCache.sorted { $0.value.fetchedAt < $1.value.fetchedAt }
        let removeCount = maxSearchCache / 5
        for (key, _) in sorted.prefix(removeCount) {
            searchCache.removeValue(forKey: key)
        }
    }
}
