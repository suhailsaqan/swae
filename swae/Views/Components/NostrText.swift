//
//  NostrText.swift
//  swae
//
//  SwiftUI view that renders Nostr-aware text with tappable mentions
//

import SwiftUI
import NostrSDK

/// A SwiftUI view that renders Nostr-aware text with tappable mentions
struct NostrText: View {
    
    // MARK: - Properties
    
    let content: String
    @ObservedObject var appState: AppState
    var onProfileTap: ((String) -> Void)?
    var onEventTap: ((String) -> Void)?
    var mentionColor: Color = .purple
    var textColor: Color = .primary
    var textFont: Font = .subheadline
    
    // MARK: - Initialization
    
    init(
        content: String,
        appState: AppState,
        onProfileTap: ((String) -> Void)? = nil,
        onEventTap: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.appState = appState
        self.onProfileTap = onProfileTap
        self.onEventTap = onEventTap
    }
    
    /// Computed segments - parsed on demand
    private var parsedSegments: [NostrTextSegment] {
        NostrTextParser.parse(content)
    }
    
    // MARK: - Body
    
    var body: some View {
        textContent
            .onAppear {
                fetchMissingProfiles()
            }
            .onChange(of: content) { _, _ in
                fetchMissingProfiles()
            }
    }
    
    @ViewBuilder
    private var textContent: some View {
        let segments = parsedSegments
        if segments.isEmpty {
            Text(content)
                .font(textFont)
                .foregroundColor(textColor)
        } else {
            segments.reduce(Text("")) { result, segment in
                result + textForSegment(segment)
            }
            .font(textFont)
        }
    }

    private func textForSegment(_ segment: NostrTextSegment) -> Text {
        switch segment {
        case .text(let string):
            return Text(string)
                .foregroundColor(textColor)
            
        case .customEmoji(let shortcode):
            return Text(":\(shortcode):")
                .foregroundColor(textColor)
            
        case .reference(_, let reference):
            switch reference {
            case .profile(let pubkeyHex, _):
                let displayName = NostrTextParser.resolveDisplayName(
                    pubkeyHex: pubkeyHex,
                    metadataEvents: appState.metadataEvents
                )
                return Text("@\(displayName)")
                    .foregroundColor(mentionColor)
                
            case .event(let eventId, _, _, _):
                let truncated = String(eventId.prefix(8)) + "..."
                return Text("📝\(truncated)")
                    .foregroundColor(.blue)
                
            case .address(_, _, let identifier, _):
                return Text("📄\(identifier)")
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func fetchMissingProfiles() {
        let pubkeys = NostrTextParser.extractPubkeys(from: parsedSegments)
        let missingPubkeys = pubkeys.filter { appState.metadataEvents[$0] == nil }
        
        if !missingPubkeys.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(Array(missingPubkeys))
        }
    }
}

// MARK: - Modifiers

extension NostrText {
    
    func mentionColor(_ color: Color) -> NostrText {
        var copy = self
        copy.mentionColor = color
        return copy
    }
    
    func textColor(_ color: Color) -> NostrText {
        var copy = self
        copy.textColor = color
        return copy
    }
    
    func font(_ font: Font) -> NostrText {
        var copy = self
        copy.textFont = font
        return copy
    }
}


// MARK: - Tappable Version with AttributedString

/// A version of NostrText that supports tapping on individual mentions
struct TappableNostrText: View {
    
    let content: String
    @ObservedObject var appState: AppState
    var onProfileTap: ((String) -> Void)?
    var onEventTap: ((String) -> Void)?
    var mentionColor: Color = .purple
    var textColor: Color = .primary
    var textFont: Font = .subheadline
    
    init(
        content: String,
        appState: AppState,
        onProfileTap: ((String) -> Void)? = nil,
        onEventTap: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.appState = appState
        self.onProfileTap = onProfileTap
        self.onEventTap = onEventTap
    }
    
    var body: some View {
        // Force re-render when metadataEvents changes by accessing it directly
        let _ = relevantMetadata
        
        Text(buildAttributedString())
            .font(textFont)
            .environment(\.openURL, OpenURLAction { url in
                handleURL(url)
            })
            .onAppear {
                fetchMissingProfiles()
            }
            .onChange(of: content) { _, _ in
                fetchMissingProfiles()
            }
    }
    
    /// Computed segments - parsed on demand
    private var parsedSegments: [NostrTextSegment] {
        NostrTextParser.parse(content)
    }
    
    /// Access relevant metadata to trigger re-renders when it changes
    private var relevantMetadata: [String: MetadataEvent] {
        let pubkeys = NostrTextParser.extractPubkeys(from: parsedSegments)
        var result: [String: MetadataEvent] = [:]
        for pubkey in pubkeys {
            if let metadata = appState.metadataEvents[pubkey] {
                result[pubkey] = metadata
            }
        }
        return result
    }
    
    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        
        let segments = parsedSegments
        
        #if DEBUG
        if content.contains("nostr:") || content.contains("npub1") {
            print("[TappableNostrText] Content contains nostr reference")
            print("[TappableNostrText] Segments count: \(segments.count)")
            for (i, seg) in segments.enumerated() {
                switch seg {
                case .text(let s):
                    print("[TappableNostrText] Segment \(i): text(\(s.prefix(50))...)")
                case .reference(let orig, _):
                    print("[TappableNostrText] Segment \(i): reference(\(orig))")
                case .customEmoji(let shortcode):
                    print("[TappableNostrText] Segment \(i): emoji(\(shortcode))")
                }
            }
        }
        #endif
        
        for segment in segments {
            switch segment {
            case .text(let string):
                var text = AttributedString(string)
                text.foregroundColor = textColor
                result.append(text)
            
            case .customEmoji(let shortcode):
                var text = AttributedString(":\(shortcode):")
                text.foregroundColor = textColor
                result.append(text)
                
            case .reference(_, let reference):
                var mentionText = AttributedString()
                
                switch reference {
                case .profile(let pubkeyHex, _):
                    let displayName = NostrTextParser.resolveDisplayName(
                        pubkeyHex: pubkeyHex,
                        metadataEvents: appState.metadataEvents
                    )
                    mentionText = AttributedString("@\(displayName)")
                    mentionText.foregroundColor = mentionColor
                    mentionText.link = URL(string: "swae://profile/\(pubkeyHex)")
                    
                case .event(let eventId, _, _, _):
                    let truncated = String(eventId.prefix(8)) + "..."
                    mentionText = AttributedString("📝\(truncated)")
                    mentionText.foregroundColor = .blue
                    mentionText.link = URL(string: "swae://event/\(eventId)")
                    
                case .address(_, let pubkey, let identifier, _):
                    mentionText = AttributedString("📄\(identifier)")
                    mentionText.foregroundColor = .blue
                    mentionText.link = URL(string: "swae://address/\(pubkey)/\(identifier)")
                }
                
                result.append(mentionText)
            }
        }
        
        return result
    }
    
    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "swae" else {
            return .systemAction
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let type = pathComponents.first else {
            return .discarded
        }
        
        switch type {
        case "profile":
            if let pubkeyHex = pathComponents.dropFirst().first {
                onProfileTap?(pubkeyHex)
                return .handled
            }
        case "event":
            if let eventId = pathComponents.dropFirst().first {
                onEventTap?(eventId)
                return .handled
            }
        case "address":
            // Handle address taps if needed
            return .handled
        default:
            break
        }
        
        return .discarded
    }
    
    private func fetchMissingProfiles() {
        let pubkeys = NostrTextParser.extractPubkeys(from: parsedSegments)
        let missingPubkeys = pubkeys.filter { appState.metadataEvents[$0] == nil }
        if !missingPubkeys.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(Array(missingPubkeys))
        }
    }
}

// MARK: - TappableNostrText Modifiers

extension TappableNostrText {
    
    func mentionColor(_ color: Color) -> TappableNostrText {
        var copy = self
        copy.mentionColor = color
        return copy
    }
    
    func textColor(_ color: Color) -> TappableNostrText {
        var copy = self
        copy.textColor = color
        return copy
    }
    
    func font(_ font: Font) -> TappableNostrText {
        var copy = self
        copy.textFont = font
        return copy
    }
}
