//
//  NostrTextParser.swift
//  swae
//
//  Parses Nostr text content and extracts references (mentions, events, etc.)
//

import Foundation
import NostrSDK

// MARK: - Data Types

/// Represents a parsed Nostr reference from text content
public enum NostrReference: Equatable, Hashable {
    /// Profile reference (npub or nprofile)
    case profile(pubkeyHex: String, relayHints: [String])
    
    /// Event reference (note or nevent)
    case event(eventId: String, relayHints: [String], authorPubkey: String?, kind: UInt32?)
    
    /// Replaceable event address (naddr)
    case address(kind: UInt32, pubkeyHex: String, identifier: String, relayHints: [String])
    
    /// The hex public key if this reference contains one
    public var pubkeyHex: String? {
        switch self {
        case .profile(let pubkey, _):
            return pubkey
        case .event(_, _, let author, _):
            return author
        case .address(_, let pubkey, _, _):
            return pubkey
        }
    }
    
    /// The event ID if this is an event reference
    public var eventId: String? {
        switch self {
        case .event(let id, _, _, _):
            return id
        default:
            return nil
        }
    }
}

/// Represents a segment of parsed text
public enum NostrTextSegment: Equatable {
    /// Plain text that doesn't contain any Nostr references
    case text(String)
    
    /// A Nostr reference with its original string and parsed data
    case reference(original: String, parsed: NostrReference)
    
    /// A NIP-30 custom emoji shortcode (e.g. "KEKW" from ":KEKW:")
    case customEmoji(shortcode: String)
}


// MARK: - Parser

/// Parses Nostr text content and extracts references
public struct NostrTextParser: MetadataCoding {
    
    /// Bech32 character set for matching
    private static let bech32Chars = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    
    /// Regex for NIP-30 custom emoji shortcodes like :KEKW: or :pepe_hands:
    private static let emojiShortcodeRegex: NSRegularExpression? = {
        let pattern = ":([_a-zA-Z0-9]+):"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()
    
    /// Shared regex instance (compiled once for performance)
    private static let nostrRegex: NSRegularExpression? = {
        // Pattern matches nostr: or @ prefix followed by valid bech32 identifiers
        // Using character class [a-z0-9] since bech32 uses lowercase alphanumeric
        let pattern = "(?:nostr:|@)(npub1[a-z0-9]{58}|nprofile1[a-z0-9]+|note1[a-z0-9]{58}|nevent1[a-z0-9]+|naddr1[a-z0-9]+)"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            #if DEBUG
            print("[NostrTextParser] Regex compiled successfully")
            #endif
            return regex
        } catch {
            #if DEBUG
            print("[NostrTextParser] Failed to compile regex: \(error)")
            #endif
            return nil
        }
    }()
    
    /// Parses content and returns an array of text segments
    /// - Parameter content: The raw text content to parse
    /// - Returns: Array of segments (plain text and references)
    public static func parse(_ content: String) -> [NostrTextSegment] {
        let cleanedContent = cleanContent(content)
        
        guard let regex = nostrRegex else {
            print("[NostrTextParser] Regex failed to compile")
            return [.text(cleanedContent)]
        }
        
        var segments: [NostrTextSegment] = []
        var lastIndex = cleanedContent.startIndex
        
        let nsRange = NSRange(cleanedContent.startIndex..., in: cleanedContent)
        let matches = regex.matches(in: cleanedContent, options: [], range: nsRange)
        
        #if DEBUG
        if matches.isEmpty && (cleanedContent.contains("npub1") || cleanedContent.contains("nostr:")) {
            print("[NostrTextParser] No matches found in content that appears to contain nostr references")
            print("[NostrTextParser] Content preview: \(String(cleanedContent.prefix(200)))")
        }
        #endif
        
        for match in matches {
            guard let matchRange = Range(match.range, in: cleanedContent),
                  let identifierRange = Range(match.range(at: 1), in: cleanedContent) else {
                continue
            }
            
            // Add text before this match
            if lastIndex < matchRange.lowerBound {
                let textBefore = String(cleanedContent[lastIndex..<matchRange.lowerBound])
                if !textBefore.isEmpty {
                    segments.append(.text(textBefore))
                }
            }
            
            // Parse the identifier
            let identifier = String(cleanedContent[identifierRange])
            let originalMatch = String(cleanedContent[matchRange])
            
            #if DEBUG
            print("[NostrTextParser] Found match: \(originalMatch)")
            #endif
            
            if let reference = decodeReference(identifier) {
                segments.append(.reference(original: originalMatch, parsed: reference))
                #if DEBUG
                print("[NostrTextParser] Successfully decoded reference")
                #endif
            } else {
                // Failed to decode, keep as plain text
                segments.append(.text(originalMatch))
                #if DEBUG
                print("[NostrTextParser] Failed to decode identifier: \(identifier)")
                #endif
            }
            
            lastIndex = matchRange.upperBound
        }
        
        // Add remaining text after last match
        if lastIndex < cleanedContent.endIndex {
            let remainingText = String(cleanedContent[lastIndex...])
            if !remainingText.isEmpty {
                segments.append(.text(remainingText))
            }
        }
        
        // If no matches found, return entire content as text
        if segments.isEmpty {
            return emojifySegments([.text(cleanedContent)])
        }
        
        // Post-process: split .text segments on :shortcode: patterns (NIP-30)
        return emojifySegments(segments)
    }
    
    /// Splits `.text` segments on `:shortcode:` patterns, producing `.customEmoji` segments.
    /// Runs AFTER nostr reference parsing so shortcodes inside references are not matched.
    private static func emojifySegments(_ segments: [NostrTextSegment]) -> [NostrTextSegment] {
        guard let regex = emojiShortcodeRegex else { return segments }
        
        var result: [NostrTextSegment] = []
        result.reserveCapacity(segments.count)
        
        for segment in segments {
            guard case .text(let text) = segment else {
                result.append(segment)
                continue
            }
            
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)
            
            if matches.isEmpty {
                result.append(segment)
                continue
            }
            
            var lastIndex = text.startIndex
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let shortcodeRange = Range(match.range(at: 1), in: text) else {
                    continue
                }
                
                // Text before this shortcode
                if lastIndex < fullRange.lowerBound {
                    let before = String(text[lastIndex..<fullRange.lowerBound])
                    if !before.isEmpty {
                        result.append(.text(before))
                    }
                }
                
                result.append(.customEmoji(shortcode: String(text[shortcodeRange])))
                lastIndex = fullRange.upperBound
            }
            
            // Remaining text after last shortcode
            if lastIndex < text.endIndex {
                let remaining = String(text[lastIndex...])
                if !remaining.isEmpty {
                    result.append(.text(remaining))
                }
            }
        }
        
        return result
    }
    
    /// Decodes a bech32 identifier into a NostrReference
    /// - Parameter identifier: The bech32 identifier (npub1..., nprofile1..., etc.)
    /// - Returns: Decoded reference or nil if invalid
    public static func decodeReference(_ identifier: String) -> NostrReference? {
        let lowercased = identifier.lowercased()
        
        if lowercased.hasPrefix("npub1") {
            return decodeNpub(identifier)
        } else if lowercased.hasPrefix("nprofile1") {
            return decodeNprofile(identifier)
        } else if lowercased.hasPrefix("note1") {
            return decodeNote(identifier)
        } else if lowercased.hasPrefix("nevent1") {
            return decodeNevent(identifier)
        } else if lowercased.hasPrefix("naddr1") {
            return decodeNaddr(identifier)
        }
        
        return nil
    }
    
    // MARK: - Private Decoders
    
    private static func decodeNpub(_ identifier: String) -> NostrReference? {
        guard let publicKey = PublicKey(npub: identifier) else {
            return nil
        }
        return .profile(pubkeyHex: publicKey.hex, relayHints: [])
    }
    
    private static func decodeNprofile(_ identifier: String) -> NostrReference? {
        let parser = NostrTextParser()
        guard let metadata = try? parser.decodedMetadata(from: identifier),
              let pubkey = metadata.pubkey else {
            return nil
        }
        return .profile(pubkeyHex: pubkey, relayHints: metadata.relays ?? [])
    }
    
    private static func decodeNote(_ identifier: String) -> NostrReference? {
        // note1 is a bare event ID without metadata
        // We need to decode the bech32 to get the event ID hex
        guard let eventIdHex = decodeBech32ToHex(identifier, expectedPrefix: "note") else {
            return nil
        }
        return .event(eventId: eventIdHex, relayHints: [], authorPubkey: nil, kind: nil)
    }
    
    // MARK: - Bech32 Decoding Helper
    
    /// Decodes a bech32 string to hex (for note1 identifiers)
    /// This is a minimal implementation since the SDK's Bech32 class is internal
    private static func decodeBech32ToHex(_ bech32: String, expectedPrefix: String) -> String? {
        let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        let charsetArray = Array(charset)
        let charsetMap: [Character: UInt8] = Dictionary(uniqueKeysWithValues: charsetArray.enumerated().map { (charsetArray[$0.offset], UInt8($0.offset)) })
        
        let lowercased = bech32.lowercased()
        
        // Find separator
        guard let separatorIndex = lowercased.lastIndex(of: "1") else {
            return nil
        }
        
        let hrp = String(lowercased[..<separatorIndex])
        guard hrp == expectedPrefix else {
            return nil
        }
        
        let dataPartStart = lowercased.index(after: separatorIndex)
        let dataPart = String(lowercased[dataPartStart...])
        
        // Decode data part
        var values: [UInt8] = []
        for char in dataPart {
            guard let value = charsetMap[char] else {
                return nil
            }
            values.append(value)
        }
        
        // Remove checksum (last 6 characters)
        guard values.count > 6 else {
            return nil
        }
        let dataValues = Array(values.dropLast(6))
        
        // Convert from base5 to base8
        guard let base8Data = convertBits(data: dataValues, fromBits: 5, toBits: 8, pad: false) else {
            return nil
        }
        
        // Convert to hex string
        return base8Data.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Converts data between bit sizes
    private static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc: UInt32 = 0
        var bits: Int = 0
        var result: [UInt8] = []
        let maxv: UInt32 = (1 << toBits) - 1
        
        for value in data {
            acc = (acc << fromBits) | UInt32(value)
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        
        return result
    }
    
    private static func decodeNevent(_ identifier: String) -> NostrReference? {
        let parser = NostrTextParser()
        guard let metadata = try? parser.decodedMetadata(from: identifier),
              let eventId = metadata.eventId else {
            return nil
        }
        return .event(
            eventId: eventId,
            relayHints: metadata.relays ?? [],
            authorPubkey: metadata.pubkey,
            kind: metadata.kind
        )
    }
    
    private static func decodeNaddr(_ identifier: String) -> NostrReference? {
        let parser = NostrTextParser()
        guard let metadata = try? parser.decodedMetadata(from: identifier),
              let kind = metadata.kind,
              let pubkey = metadata.pubkey,
              let addrIdentifier = metadata.identifier else {
            return nil
        }
        return .address(
            kind: kind,
            pubkeyHex: pubkey,
            identifier: addrIdentifier,
            relayHints: metadata.relays ?? []
        )
    }
}


// MARK: - Display Name Resolution

extension NostrTextParser {
    
    /// Resolves a pubkey to a username for @ mentions
    /// - Parameters:
    ///   - pubkeyHex: The hex-encoded public key
    ///   - metadataEvents: Dictionary of cached metadata events keyed by pubkey
    /// - Returns: Username (name), display name, or truncated npub
    public static func resolveDisplayName(
        pubkeyHex: String,
        metadataEvents: [String: MetadataEvent]
    ) -> String {
        if let metadata = metadataEvents[pubkeyHex]?.userMetadata {
            // Priority for @mentions: name (username) > displayName > truncated npub
            if let name = metadata.name?.trimmedOrNilIfEmpty {
                return name
            }
            if let displayName = metadata.displayName?.trimmedOrNilIfEmpty {
                return displayName
            }
        }
        
        return truncatedNpub(for: pubkeyHex)
    }
    
    /// Creates a truncated npub string for display
    /// - Parameter pubkeyHex: The hex-encoded public key
    /// - Returns: Truncated npub like "npub1abc...xyz"
    public static func truncatedNpub(for pubkeyHex: String) -> String {
        if let publicKey = PublicKey(hex: pubkeyHex) {
            let npub = publicKey.npub
            let prefix = String(npub.prefix(10))  // "npub1" + 5 chars
            let suffix = String(npub.suffix(4))
            return "\(prefix)...\(suffix)"
        }
        // Fallback if PublicKey creation fails
        let prefix = String(pubkeyHex.prefix(8))
        return "\(prefix)..."
    }
    
    /// Extracts all unique pubkeys from parsed segments
    /// - Parameter segments: Array of parsed text segments
    /// - Returns: Set of unique hex pubkeys
    public static func extractPubkeys(from segments: [NostrTextSegment]) -> Set<String> {
        var pubkeys = Set<String>()
        for segment in segments {
            if case .reference(_, let reference) = segment,
               let pubkey = reference.pubkeyHex {
                pubkeys.insert(pubkey)
            }
        }
        return pubkeys
    }
    
    /// Extracts all unique event IDs from parsed segments
    /// - Parameter segments: Array of parsed text segments
    /// - Returns: Set of unique event IDs
    public static func extractEventIds(from segments: [NostrTextSegment]) -> Set<String> {
        var eventIds = Set<String>()
        for segment in segments {
            if case .reference(_, let reference) = segment,
               let eventId = reference.eventId {
                eventIds.insert(eventId)
            }
        }
        return eventIds
    }
}

// MARK: - Edge Case Handling

extension NostrTextParser {
    
    /// Cleans content before parsing (handles edge cases)
    public static func cleanContent(_ content: String) -> String {
        var cleaned = content
        // Remove zero-width characters that might break parsing
        cleaned = cleaned.replacingOccurrences(of: "\u{200B}", with: "") // Zero-width space
        cleaned = cleaned.replacingOccurrences(of: "\u{FEFF}", with: "") // BOM
        return cleaned
    }
    
    /// Checks if a string looks like a valid Nostr identifier
    public static func isValidNostrIdentifier(_ string: String) -> Bool {
        let lowercased = string.lowercased()
        let validPrefixes = ["npub1", "nprofile1", "note1", "nevent1", "naddr1"]
        return validPrefixes.contains { lowercased.hasPrefix($0) }
    }
}
