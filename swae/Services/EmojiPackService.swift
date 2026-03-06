//
//  EmojiPackService.swift
//  swae
//
//  Loads and merges NIP-30/NIP-51 emoji packs from user + streamer.
//  Populates AppState.emojiPackCache for shortcode resolution when sending.
//

import Combine
import Foundation
import NostrSDK
import SDWebImage

struct EmojiPack: Identifiable {
    let id: String           // "30030:<pubkey>:<d-tag>"
    let name: String         // d-tag value
    let authorPubkey: String
    let emojis: [CustomEmoji]
}

final class EmojiPackService {
    private var cancellables = Set<AnyCancellable>()
    private weak var appState: AppState?
    
    /// All loaded packs (user + streamer, deduplicated)
    private(set) var packs: [EmojiPack] = []
    
    /// Flat lookup: shortcode → imageURL (for fast resolution)
    private(set) var shortcodeLookup: [String: URL] = [:]
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    // MARK: - Pack Loading
    
    /// Subscribes to kind 10030 for the given pubkeys, then resolves kind 30030 references.
    func loadPacks(userPubkey: String?, streamerPubkey: String?) {
        guard let appState else { return }
        
        var pubkeys: [String] = []
        if let u = userPubkey { pubkeys.append(u) }
        if let s = streamerPubkey, s != userPubkey { pubkeys.append(s) }
        guard !pubkeys.isEmpty else { return }
        
        print("🎨 EmojiPackService: Loading packs for \(pubkeys.count) pubkeys: \(pubkeys.map { $0.prefix(8) })")
        
        // Subscribe to kind 10030 (emoji list) for each pubkey
        for pubkey in pubkeys {
            guard let filter = Filter(
                authors: [pubkey],
                kinds: [EventKind.emojiList.rawValue],
                limit: 1
            ) else { continue }
            appState.relayReadPool.subscribe(with: filter)
        }
    }
    
    /// Called when a kind 10030 event is received. Extracts emoji packs and resolves set references.
    func didReceiveEmojiList(_ event: EmojiListEvent) {
        guard let appState else { return }
        
        print("🎨 EmojiPackService: Received kind 10030 from \(event.pubkey.prefix(8))... with \(event.tags.count) tags")
        
        // Extract inline emojis directly from the 10030 event
        let inlineEmojis = event.customEmojis
        if !inlineEmojis.isEmpty {
            let inlinePack = EmojiPack(
                id: "inline:\(event.pubkey)",
                name: "Custom",
                authorPubkey: event.pubkey,
                emojis: inlineEmojis
            )
            mergePack(inlinePack)
        }
        
        // Resolve kind 30030 set references
        let setRefs = event.emojiSetReferences
        guard !setRefs.isEmpty else { return }
        
        let authors = setRefs.map { $0.pubkey }
        let identifiers = setRefs.map { $0.identifier }
        
        guard let filter = Filter(
            authors: authors,
            kinds: [EventKind.emojiSet.rawValue],
            tags: [Character("d"): identifiers],
            limit: setRefs.count * 2
        ) else { return }
        
        appState.relayReadPool.subscribe(with: filter)
    }
    
    /// Called when a kind 30030 event is received.
    func didReceiveEmojiSet(_ event: EmojiSetEvent) {
        let emojis = event.customEmojis
        guard !emojis.isEmpty, let identifier = event.identifier else { return }
        
        print("🎨 EmojiPackService: Received kind 30030 '\(identifier)' from \(event.pubkey.prefix(8))... with \(emojis.count) emojis")
        
        let pack = EmojiPack(
            id: event.coordinate ?? "30030:\(event.pubkey):\(identifier)",
            name: identifier,
            authorPubkey: event.pubkey,
            emojis: emojis
        )
        mergePack(pack)
    }
    
    // MARK: - Lookup
    
    func findEmoji(shortcode: String) -> CustomEmoji? {
        guard let url = shortcodeLookup[shortcode] else { return nil }
        return CustomEmoji(shortcode: shortcode, imageURL: url)
    }
    
    func allEmojis() -> [CustomEmoji] {
        packs.flatMap { $0.emojis }
    }
    
    // MARK: - Private
    
    private func mergePack(_ pack: EmojiPack) {
        // Deduplicate by pack ID
        if let idx = packs.firstIndex(where: { $0.id == pack.id }) {
            packs[idx] = pack
        } else {
            packs.append(pack)
        }
        
        rebuildLookup()
    }
    
    private func rebuildLookup() {
        var lookup: [String: URL] = [:]
        for pack in packs {
            for emoji in pack.emojis {
                lookup[emoji.shortcode] = emoji.imageURL
            }
        }
        shortcodeLookup = lookup
        
        print("🎨 EmojiPackService: Rebuilt lookup — \(packs.count) packs, \(lookup.count) total emojis")
        
        // Sync to AppState for use by LiveChatController.sendMessageWithText
        appState?.emojiPackCache = lookup
        
        // Prefetch all emote images via centralized cache
        EmoteImageCache.shared.prefetch(urls: Array(lookup.values))
    }
}
