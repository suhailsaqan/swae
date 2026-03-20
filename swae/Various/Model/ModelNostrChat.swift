import Combine
import Foundation
import NostrSDK

extension Model {
    private func resolveDisplayName(pubkey: String, appState: AppState) -> String {
        if let metadata = appState.metadataEvents[pubkey] {
            let userMetadata = metadata.userMetadata
            return userMetadata?.displayName?.trimmedOrNilIfEmpty
                ?? userMetadata?.name?.trimmedOrNilIfEmpty
                ?? String(pubkey.prefix(8))
        }
        return String(pubkey.prefix(8))
    }

    private func parseZapAmount(from zap: LightningZapsReceiptEvent) -> Int64 {
        guard let bolt11 = zap.bolt11 else { return 0 }
        return parseBolt11Amount(bolt11)
    }

    private func parseBolt11Amount(_ bolt11: String) -> Int64 {
        let lower = bolt11.lowercased()
        guard lower.hasPrefix("lnbc") else { return 0 }
        let afterPrefix = lower.dropFirst(4)
        var digits = ""
        var multiplier: Character?
        for char in afterPrefix {
            if char.isNumber {
                digits.append(char)
            } else {
                multiplier = char
                break
            }
        }
        guard let amount = Int64(digits) else { return 0 }
        switch multiplier {
        case "m": return amount * 100_000
        case "u": return amount * 100
        case "n": return amount / 10
        case "p": return amount / 10_000
        default: return amount * 100_000_000
        }
    }

    // MARK: - Nostr Chat Bridge (feeds NostrChatEffect from AppState directly)

    /// Starts observing AppState for the user's live event and chat data.
    /// Called when nostrChatEffects becomes non-empty.
    /// Safe to call multiple times — returns immediately if already running.
    func startNostrChatBridge() {
        guard nostrChatBridgeCancellables.isEmpty else {
            print("🔌 NostrChatBridge: Already running, skipping start")
            return
        }
        guard isStreaming() else {
            print("🔌 NostrChatBridge: Not streaming, skipping start")
            return
        }
        guard let appState = appState else {
            print("⚠️ NostrChatBridge: appState is nil, cannot start")
            return
        }
        guard stream.zapStreamCoreEnabled else {
            print("⚠️ NostrChatBridge: zapStreamCoreEnabled is false, cannot start")
            return
        }

        print("🔌 NostrChatBridge: Starting bridge with \(nostrChatEffects.count) effects")

        // Step 1: Watch for the user's LiveActivitiesEvent to appear in AppState.
        // When found, call subscribeToLiveChat (idempotent — no-op if already subscribed).
        // Pick the most recent live event (highest createdAt) to avoid latching onto
        // stale events from previous streams that haven't been marked "ended" yet.
        appState.$liveActivitiesEvents
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] allEvents in
                guard let self = self,
                      let appState = self.appState else { return }
                guard let userPubkey = appState.keypair?.publicKey.hex else {
                    print("⚠️ NostrChatBridge: No user keypair available")
                    return
                }

                // Find the most recent live event for this user (not just the first match).
                // Multiple live events can exist if the server crashed without sending "ended"
                // for a previous stream, or if relay propagation is delayed.
                let allLiveEvents: [LiveActivitiesEvent] = allEvents.values.flatMap { $0 }
                let userLiveEvents = allLiveEvents.filter {
                    $0.hostPubkeyHex == userPubkey && $0.status == .live
                }
                let userLiveEvent = userLiveEvents.max(by: { $0.createdAt < $1.createdAt })

                guard let event = userLiveEvent,
                      let coordinate = event.coordinateTag else {
                    return
                }

                if coordinate != self.nostrChatBridgeCoordinate {
                    let oldCoordinate = self.nostrChatBridgeCoordinate
                    print("🔌 NostrChatBridge: Found live event, coordinate=\(coordinate)" +
                          (oldCoordinate != nil ? " (switching from \(oldCoordinate!))" : ""))
                    self.nostrChatBridgeCoordinate = coordinate
                    self.nostrChatBridgeSessionStart = event.startsAt ?? event.createdDate

                    // Clear stale messages from the previous coordinate so the widget
                    // doesn't flash old chat while the new subscription loads.
                    if oldCoordinate != nil {
                        for effect in self.nostrChatEffects.values {
                            effect.replaceAllMessages([])
                        }
                    }

                    appState.subscribeToLiveChat(for: event)
                }
            }
            .store(in: &nostrChatBridgeCancellables)

        // Step 2: Watch for chat messages and zaps arriving in AppState.
        let messagesPublisher = appState.$liveChatMessagesEvents
        let zapsPublisher = appState.$zapReceiptEvents
        Publishers.CombineLatest(messagesPublisher, zapsPublisher)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] (messagesDict, zapsDict) in
                guard let self = self,
                      let appState = self.appState,
                      let coordinate = self.nostrChatBridgeCoordinate,
                      !self.nostrChatEffects.isEmpty else { return }

                let messages = messagesDict[coordinate] ?? []
                let zaps = zapsDict[coordinate] ?? []

                let totalCount = messages.count + zaps.count
                if totalCount > 0 {
                    print("🔌 NostrChatBridge: Processing \(messages.count) msgs + \(zaps.count) zaps for coordinate")
                }

                self.updateNostrChatFromAppState(
                    messages: messages,
                    zaps: zaps,
                    appState: appState
                )
            }
            .store(in: &nostrChatBridgeCancellables)
    }

    /// Ensures the bridge is running if conditions are met.
    /// Unlike startNostrChatBridge(), this is safe to call from any context
    /// (e.g., sceneUpdatedOn, stream start) and will start the bridge
    /// if it's not already running and conditions are now satisfied.
    func ensureNostrChatBridge() {
        guard !nostrChatEffects.isEmpty else { return }
        guard nostrChatBridgeCancellables.isEmpty else { return }
        // Conditions may have changed since last attempt — try starting
        startNostrChatBridge()
    }

    /// Stops the bridge Combine sinks. Does NOT unsubscribe from AppState relay
    /// (the subscription is shared with LiveChatController and stays alive).
    func stopNostrChatBridge() {
        if !nostrChatBridgeCancellables.isEmpty {
            print("🔌 NostrChatBridge: Stopping bridge")
        }
        nostrChatBridgeCancellables.removeAll()
        nostrChatBridgeCoordinate = nil
        nostrChatBridgeSessionStart = nil
    }

    /// Converts raw AppState events directly to NostrChatDisplayItems.
    private func updateNostrChatFromAppState(
        messages: [LiveChatMessageEvent],
        zaps: [LightningZapsReceiptEvent],
        appState: AppState
    ) {
        guard !nostrChatEffects.isEmpty else { return }

        // Client-side filter: only include messages from the current session.
        // Defense in depth — the relay filter already uses `since`, but some
        // relays may not fully respect it, or locally cached events may predate it.
        let sessionStartEpoch: Int64 = {
            guard let sessionStart = nostrChatBridgeSessionStart else { return 0 }
            return max(0, Int64(sessionStart.timeIntervalSince1970) - 60)
        }()

        let filteredMessages = sessionStartEpoch > 0
            ? messages.filter { $0.createdAt >= sessionStartEpoch }
            : messages
        let filteredZaps = sessionStartEpoch > 0
            ? zaps.filter { $0.createdAt >= sessionStartEpoch }
            : zaps

        var displayItems: [NostrChatDisplayItem] = []
        displayItems.reserveCapacity(filteredMessages.count + filteredZaps.count)

        for msg in filteredMessages {
            // Extract NIP-30 custom emoji map from event tags
            let emojiMap: [String: URL] = {
                var map: [String: URL] = [:]
                for emoji in msg.customEmojis { map[emoji.shortcode] = emoji.imageURL }
                return map
            }()
            displayItems.append(NostrChatDisplayItem(
                id: msg.id,
                displayName: resolveDisplayName(pubkey: msg.pubkey, appState: appState),
                pubkeyColorSeed: msg.pubkey.hashValue,
                content: msg.content,
                isZap: false,
                zapAmount: nil,
                timestamp: Date(timeIntervalSince1970: TimeInterval(msg.createdAt)),
                customEmojis: emojiMap
            ))
        }

        for zap in filteredZaps {
            let senderPubkey = zap.zapSenderPubkey ?? zap.pubkey
            let zapAmount = parseZapAmount(from: zap)
            let zapMessage = zap.zapRequest?.content ?? ""
            displayItems.append(NostrChatDisplayItem(
                id: zap.id,
                displayName: resolveDisplayName(pubkey: senderPubkey, appState: appState),
                pubkeyColorSeed: senderPubkey.hashValue,
                content: zapMessage.isEmpty ? "Zapped ⚡\(zapAmount)" : zapMessage,
                isZap: true,
                zapAmount: zapAmount,
                timestamp: Date(timeIntervalSince1970: TimeInterval(zap.createdAt)),
                customEmojis: [:]
            ))
        }

        displayItems.sort { $0.timestamp < $1.timestamp }

        print("🔌 NostrChatBridge: Pushing \(displayItems.count) items to \(nostrChatEffects.count) effects")
        for effect in nostrChatEffects.values {
            effect.replaceAllMessages(displayItems)
        }
    }
}
