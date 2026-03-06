//
//  GameDatabaseService.swift
//  swae
//
//  IGDB game info fetcher using zap.stream's API proxy.
//  Actor-based for thread safety with in-memory cache.
//

import Foundation

struct GameInfo: Sendable {
    let id: String
    let name: String
    let coverURL: URL?
}

actor GameDatabaseService {
    static let shared = GameDatabaseService()

    private let baseURL = "https://api-core.zap.stream/api/v1"
    private var cache: [String: GameInfo] = [:]
    private var inFlight: [String: Task<GameInfo?, Never>] = [:]

    /// Fetches game info for an IGDB game ID. Returns cached result if available.
    /// Coalesces concurrent requests for the same ID.
    func getGame(id: String) async -> GameInfo? {
        let igdbId = id.hasPrefix("igdb:") ? String(id.dropFirst(5)) : id

        if let cached = cache[igdbId] { return cached }

        // Coalesce duplicate in-flight requests
        if let existing = inFlight[igdbId] {
            return await existing.value
        }

        let task = Task<GameInfo?, Never> {
            defer { inFlight[igdbId] = nil }
            guard let url = URL(string: "\(baseURL)/games/\(igdbId)") else { return nil }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else { return nil }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let name = json["name"] as? String else { return nil }

                var coverURL: URL?
                if let cover = json["cover"] as? [String: Any],
                   let imageId = cover["image_id"] as? String {
                    coverURL = URL(string: "https://images.igdb.com/igdb/image/upload/t_cover_big/\(imageId).jpg")
                }

                let info = GameInfo(id: igdbId, name: name, coverURL: coverURL)
                cache[igdbId] = info
                return info
            } catch {
                return nil
            }
        }

        inFlight[igdbId] = task
        return await task.value
    }

    /// Searches IGDB for games matching the query. Uses the same zap.stream API proxy.
    /// Returns GameInfo with prefixed IDs (e.g. "igdb:1942") matching the Nostr tag format.
    func searchGames(query: String, limit: Int = 10) async -> [GameInfo] {
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/games/search?q=\(encoded)&limit=\(limit)")
        else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let games = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }

            return games.compactMap { json -> GameInfo? in
                guard let name = json["name"] as? String else { return nil }

                // The API may return id as Int or String. The zap.stream web app
                // stores the raw value and the consumer-side regex expects "prefix:value"
                // format (e.g. "igdb:1942"). Ensure we always produce that format.
                let gameId: String
                if let idInt = json["id"] as? Int {
                    gameId = "igdb:\(idInt)"
                } else if let idStr = json["id"] as? String {
                    gameId = idStr.contains(":") ? idStr : "igdb:\(idStr)"
                } else {
                    return nil
                }

                var coverURL: URL?
                if let cover = json["cover"] as? [String: Any],
                   let imageId = cover["image_id"] as? String {
                    coverURL = URL(string: "https://images.igdb.com/igdb/image/upload/t_cover_big/\(imageId).jpg")
                }

                let info = GameInfo(id: gameId, name: name, coverURL: coverURL)
                cache[gameId] = info
                return info
            }
        } catch {
            return []
        }
    }
}
