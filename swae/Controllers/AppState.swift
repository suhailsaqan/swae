//
//  AppState.swift
//  swae
//
//  Created by Suhail Saqan on 8/22/24.
//

import Foundation
import NostrSDK
import OrderedCollections
import SwiftData
import SwiftTrie

class AppState: ObservableObject, Hashable, RelayURLValidating, EventCreating {
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static let defaultRelayURLString = "wss://relay.damus.io"

    let id = UUID()

    let privateKeySecureStorage = PrivateKeySecureStorage()

    let modelContext: ModelContext
    
    let nostrWalletConnectStorage = NostrWalletConnectKeyStorage()

    @Published var relayReadPool: RelayPool = RelayPool(relays: [])
    @Published var relayWritePool: RelayPool = RelayPool(relays: [])

    @Published var followListEvents: [String: FollowListEvent] = [:]
    @Published var metadataEvents: [String: MetadataEvent] = [:]
    @Published var liveActivitiesEvents: [String: [LiveActivitiesEvent]] = [:]
    @Published var liveChatMessagesEvents: [String: [LiveChatMessageEvent]] = [:]
    @Published var zapReceiptEvents: [String: [LightningZapsReceiptEvent]] = [:]
    @Published var eventZapTotals: [String: Int64] = [:]
    @Published var deletedEventIds = Set<String>()
    @Published var deletedEventCoordinates = [String: Date]()

    @Published var followedPubkeys = Set<String>()

    @Published var eventsTrie = Trie<String>()
    @Published var liveActivitiesTrie = Trie<String>()
    @Published var pubkeyTrie = Trie<String>()
    
    @Published var playerConfig: PlayerConfig = .init()
    
    @Published var wallet: WalletModel?

    // Keep track of relay pool active subscriptions and the until filter so that we can limit the scope of how much we query from the relay pools.
    var metadataSubscriptionCounts = [String: Int]()
    var bootstrapSubscriptionCounts = [String: Int]()
    var liveActivityEventSubscriptionCounts = [String: Int]()
    var liveChatSubscriptionCounts: [String: String] = [:]
    var followListEventSubscriptionCounts: [String: String] = [:]
    
    // Create a queue for batching database operations
    private let dbQueue = DispatchQueue(label: "com.app.dbQueue", qos: .utility)
    private var pendingEvents = [NostrEvent]()
    private let batchSize = 50
    private var batchTimer: Timer?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        if let publicKey = self.publicKey {
            self.wallet = WalletModel(publicKey: publicKey)
        } else {
            print("set to nil")
            self.wallet = nil
        }
    }

    var publicKey: PublicKey? {
        if let publicKeyHex = appSettings?.activeProfile?.publicKeyHex {
            PublicKey(hex: publicKeyHex)
        } else {
            nil
        }
    }

    var keypair: Keypair? {
        guard let publicKey else {
            return nil
        }
        return privateKeySecureStorage.keypair(for: publicKey)
    }

    private var allEvents: [LiveActivitiesEvent] {
        liveActivitiesEvents.values.flatMap { $0 }
    }

    var allUpcomingEvents: [LiveActivitiesEvent] {
        upcomingEvents(allEvents)
    }

    var allPastEvents: [LiveActivitiesEvent] {
        return pastEvents(allEvents)
    }

    var activeFollowList: FollowListEvent? {
        guard let publicKeyHex = publicKey?.hex else {
            return nil
        }

        return followListEvents[publicKeyHex]
    }

    func refreshFollowedPubkeys() {
        followedPubkeys.removeAll()
        if let publicKey {
            followedPubkeys.insert(publicKey.hex)
            if let activeFollowList {
                followedPubkeys.formUnion(activeFollowList.followedPubkeys)
            }
        }
    }

    /// Events that were created by follow list.
    private var followedEvents: [LiveActivitiesEvent] {
        guard publicKey != nil else {
            return []
        }

        let allEvents = liveActivitiesEvents.values.flatMap { $0 }

        // Filter events that have a start time and are from followed pubkeys
        return allEvents.filter { event in
            event.startsAt != nil && followedPubkeys.contains(event.pubkey)
        }
    }

    var upcomingFollowedEvents: [LiveActivitiesEvent] {
        upcomingEvents(followedEvents)
    }

    var pastFollowedEvents: [LiveActivitiesEvent] {
        pastEvents(followedEvents)
    }

    private func profileEvents(_ publicKeyHex: String) -> [LiveActivitiesEvent] {
        let allEvents = liveActivitiesEvents.values.flatMap { $0 }

        // Filter events that have a start time and match the specified pubkey
        return allEvents.filter { event in
            event.startsAt != nil && event.pubkey == publicKeyHex
        }
    }

    func upcomingProfileEvents(_ publicKeyHex: String) -> [LiveActivitiesEvent] {
        upcomingEvents(profileEvents(publicKeyHex))
    }

    func pastProfileEvents(_ publicKeyHex: String) -> [LiveActivitiesEvent] {
        pastEvents(profileEvents(publicKeyHex))
    }

    func upcomingEvents(_ events: [LiveActivitiesEvent]) -> [LiveActivitiesEvent] {
        return events.filter { $0.isUpcoming }
            .sorted(using: LiveActivitiesEventSortComparator(order: .forward))
    }

    func pastEvents(_ events: [LiveActivitiesEvent]) -> [LiveActivitiesEvent] {
        return events.filter { $0.isPast }
            .sorted(using: LiveActivitiesEventSortComparator(order: .reverse))
    }

    func updateRelayPool() {
        let relaySettings = relayPoolSettings?.relaySettingsList ?? []

        let readRelays =
            relaySettings
            .filter { $0.read }
            .compactMap { URL(string: $0.relayURLString) }
            .compactMap { try? Relay(url: $0) }

        let writeRelays =
            relaySettings
            .filter { $0.read }
            .compactMap { URL(string: $0.relayURLString) }
            .compactMap { try? Relay(url: $0) }

        let readRelaySet = Set(readRelays)
        let writeRelaySet = Set(writeRelays)

        let oldReadRelays = relayReadPool.relays.subtracting(readRelaySet)
        let newReadRelays = readRelaySet.subtracting(relayReadPool.relays)

        relayReadPool.delegate = self

        oldReadRelays.forEach {
            relayReadPool.remove(relay: $0)
        }
        newReadRelays.forEach {
            relayReadPool.add(relay: $0)
        }

        let oldWriteRelays = relayWritePool.relays.subtracting(writeRelaySet)
        let newWriteRelays = writeRelaySet.subtracting(relayWritePool.relays)

        relayWritePool.delegate = self

        oldWriteRelays.forEach {
            relayWritePool.remove(relay: $0)
        }
        newWriteRelays.forEach {
            relayWritePool.add(relay: $0)
        }
    }

    func persistentNostrEvent(_ eventId: String) -> PersistentNostrEvent? {
        var descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    var unpublishedPersistentNostrEvents: [PersistentNostrEvent] {
        let descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.relays == [] }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var relaySubscriptionMetadata: RelaySubscriptionMetadata? {
        let publicKeyHex = publicKey?.hex
        var descriptor = FetchDescriptor<RelaySubscriptionMetadata>(
            predicate: #Predicate { $0.publicKeyHex == publicKeyHex }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    var relayPoolSettings: RelayPoolSettings? {
        let publicKeyHex = publicKey?.hex
        var descriptor = FetchDescriptor<RelayPoolSettings>(
            predicate: #Predicate { $0.publicKeyHex == publicKeyHex }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func addRelay(relayURL: URL) {
        guard let relayPoolSettings,
            relayPoolSettings.relaySettingsList.allSatisfy({
                $0.relayURLString != relayURL.absoluteString
            })
        else {
            return
        }

        relayPoolSettings.relaySettingsList.append(
            RelaySettings(relayURLString: relayURL.absoluteString))

        updateRelayPool()
    }

    func removeRelaySettings(relaySettings: RelaySettings) {
        relayPoolSettings?.relaySettingsList.removeAll(where: { $0 == relaySettings })
        updateRelayPool()
    }

    func deleteProfile(_ profile: Profile) {
        guard let publicKeyHex = profile.publicKeyHex,
            let newProfile = profiles.first(where: { $0 != profile })
        else {
            return
        }

        if let publicKey = PublicKey(hex: publicKeyHex) {
            privateKeySecureStorage.delete(for: publicKey)
        }
        if let appSettings, appSettings.activeProfile == profile {
            updateActiveProfile(newProfile)
            refreshFollowedPubkeys()
        }
        modelContext.delete(profile)
    }

    func updateActiveProfile(_ profile: Profile) {
        guard let appSettings, appSettings.activeProfile != profile else {
            return
        }

        appSettings.activeProfile = profile

        followedPubkeys.removeAll()

        if profile.publicKeyHex == nil {
            // empty for now
        } else if publicKey != nil {
            refreshFollowedPubkeys()
        }

        updateRelayPool()
        refresh(hardRefresh: true)
    }

    func signIn(keypair: Keypair, relayURLs: [URL]) {
        signIn(publicKey: keypair.publicKey, relayURLs: relayURLs)
        privateKeySecureStorage.store(for: keypair)
    }

    func signIn(publicKey: PublicKey, relayURLs: [URL]) {
        guard let appSettings, appSettings.activeProfile?.publicKeyHex != publicKey.hex else {
            return
        }

        let validatedRelayURLStrings = OrderedSet<String>(
            relayURLs.compactMap { try? validateRelayURL($0).absoluteString })

        if let profile = profiles.first(where: { $0.publicKeyHex == publicKey.hex }) {
            print("Found existing profile settings for \(publicKey.npub)")
            if let relayPoolSettings = profile.profileSettings?.relayPoolSettings {
                let existingRelayURLStrings = Set(
                    relayPoolSettings.relaySettingsList.map { $0.relayURLString })
                let newRelayURLStrings = validatedRelayURLStrings.subtracting(
                    existingRelayURLStrings)
                if !newRelayURLStrings.isEmpty {
                    relayPoolSettings.relaySettingsList += newRelayURLStrings.map {
                        RelaySettings(relayURLString: $0)
                    }
                }
            }
            appSettings.activeProfile = profile
        } else {
            print("Creating new profile settings for \(publicKey.npub)")
            let profile = Profile(publicKeyHex: publicKey.hex)
            modelContext.insert(profile)
            do {
                try modelContext.save()
            } catch {
                print("Unable to save new profile \(publicKey.npub)")
            }
            if let relayPoolSettings = profile.profileSettings?.relayPoolSettings {
                relayPoolSettings.relaySettingsList += validatedRelayURLStrings.map {
                    RelaySettings(relayURLString: $0)
                }
            }
            appSettings.activeProfile = profile

            // Remove private key from secure storage in case for whatever reason it was not cleaned up previously.
            privateKeySecureStorage.delete(for: publicKey)
        }

        refreshFollowedPubkeys()
        updateRelayPool()
        pullMissingEventsFromPubkeysAndFollows([publicKey.hex])
        refresh()
    }

    var profiles: [Profile] {
        let profileDescriptor = FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.publicKeyHex)])
        return (try? modelContext.fetch(profileDescriptor)) ?? []
    }

    var appSettings: AppSettings? {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    var appearanceSettings: AppearanceSettings? {
        var descriptor = FetchDescriptor<AppearanceSettings>()
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    func relayState(relayURLString: String) -> Relay.State? {
        let readRelay = relayReadPool.relays.first(where: {
            $0.url.absoluteString == relayURLString
        })
        let writeRelay = relayWritePool.relays.first(where: {
            $0.url.absoluteString == relayURLString
        })

        switch (readRelay?.state, writeRelay?.state) {
        case (nil, nil):
            return nil
        case (_, .error):
            return writeRelay?.state
        case (.error, _):
            return readRelay?.state
        case (_, .notConnected), (.notConnected, _):
            return .notConnected
        case (_, .connecting), (.connecting, _):
            return .connecting
        case (_, .connected), (.connected, _):
            return .connected
        }
    }
}

extension AppState: EventVerifying, RelayDelegate {
//    func relay(_ relay: NostrSDK.Relay, didReceive response: NostrSDK.RelayResponse) {
//        return
//    }

    func relayStateDidChange(_ relay: Relay, state: Relay.State) {
        guard relayReadPool.relays.contains(relay) || relayWritePool.relays.contains(relay) else {
            print("Relay \(relay.url.absoluteString) changed state to \(state) but it is not in the read or write relay pool. Doing nothing.")
            return
        }

        print("Relay \(relay.url.absoluteString) changed state to \(state)")
        switch state {
        case .connected:
            refresh(relay: relay)
        case .notConnected, .error:
            relay.connect()
        default:
            break
        }
    }

    func pullMissingEventsFromPubkeysAndFollows(_ pubkeys: [String]) {
        // There has to be at least one connected relay to be able to pull metadata.
        guard
            !relayReadPool.relays.isEmpty
                && relayReadPool.relays.contains(where: { $0.state == .connected })
        else {
            return
        }

        let until = Date.now

        let allPubkeysSet = Set(pubkeys)
        let pubkeysToFetchMetadata = allPubkeysSet.filter { self.metadataEvents[$0] == nil }
        if !pubkeysToFetchMetadata.isEmpty {
            guard
                let missingMetadataFilter = Filter(
                    authors: Array(pubkeysToFetchMetadata),
                    kinds: [
                        EventKind.metadata.rawValue,
//                        EventKind.liveActivities.rawValue,
//                        EventKind.deletion.rawValue,
                    ],
//                    since: Int(
                    until: Int(until.timeIntervalSince1970)
                )
            else {
                print("Unable to create missing metadata filter for \(pubkeysToFetchMetadata).")
                return
            }

            _ = relayReadPool.subscribe(with: missingMetadataFilter)
        }

        if !metadataSubscriptionCounts.isEmpty {
            // Do not refresh metadata if one is already in progress.
            return
        }

        let since: Int?
        if let lastPulledEventsFromFollows = relaySubscriptionMetadata?.lastPulledEventsFromFollows
            .values.min()
        {
            since = Int(lastPulledEventsFromFollows.timeIntervalSince1970) + 1
        } else {
            since = nil
        }

        let pubkeysToRefresh = allPubkeysSet.subtracting(pubkeysToFetchMetadata)
        guard
            let metadataRefreshFilter = Filter(
                authors: Array(pubkeysToRefresh),
                kinds: [
                    EventKind.metadata.rawValue,
                    EventKind.liveActivities.rawValue,
//                    EventKind.deletion.rawValue,
                ],
                since: since,
                until: Int(until.timeIntervalSince1970)
            )
        else {
            print("Unable to create refresh metadata filter for \(pubkeysToRefresh).")
            return
        }

        relayReadPool.relays.forEach {
            relaySubscriptionMetadata?.lastPulledEventsFromFollows[$0.url] = until
        }
        _ = relayReadPool.subscribe(with: metadataRefreshFilter)

    }

    /// Subscribe with filter to relay if provided, or use relay read pool if not.
    func subscribe(filter: Filter, relay: Relay? = nil) throws -> String? {
        if let relay {
            do {
                return try relay.subscribe(with: filter)
            } catch {
                print("Could not subscribe to relay with filter.")
                return nil
            }
        } else {
            return relayReadPool.subscribe(with: filter)
        }
    }

    func refresh(relay: Relay? = nil, hardRefresh: Bool = false) {
        guard
            (relay == nil && !relayReadPool.relays.isEmpty
                && relayReadPool.relays.contains(where: { $0.state == .connected }))
                || relay?.state == .connected
        else {
            return
        }

        let relaySubscriptionMetadata = relaySubscriptionMetadata
        let until = Date.now

        if bootstrapSubscriptionCounts.isEmpty {
            let authors = profiles.compactMap({ $0.publicKeyHex })
            if !authors.isEmpty {
                let since: Int?
                if let relaySubscriptionMetadata, !hardRefresh {
                    if let relayURL = relay?.url,
                        let lastBootstrapped = relaySubscriptionMetadata.lastBootstrapped[relayURL]
                    {
                        since = Int(lastBootstrapped.timeIntervalSince1970) + 1
                    } else if let lastBootstrapped = relaySubscriptionMetadata.lastBootstrapped
                        .values.min()
                    {
                        since = Int(lastBootstrapped.timeIntervalSince1970) + 1
                    } else {
                        since = nil
                    }
                } else {
                    since = nil
                }

                guard
                    let bootstrapFilter = Filter(
                        authors: authors,
                        kinds: [
                            EventKind.metadata.rawValue,
                            EventKind.followList.rawValue,
                            EventKind.liveActivities.rawValue,
//                            EventKind.deletion.rawValue,
                        ],
                        since: since,
                        until: Int(until.timeIntervalSince1970)
                    )
                else {
                    print("Unable to create the boostrap filter.")
                    return
                }

                do {
                    if let bootstrapSubscriptionId = try subscribe(
                        filter: bootstrapFilter, relay: relay), relay == nil
                    {
                        if let bootstrapSubscriptionCount = bootstrapSubscriptionCounts[
                            bootstrapSubscriptionId]
                        {
                            bootstrapSubscriptionCounts[bootstrapSubscriptionId] =
                                bootstrapSubscriptionCount + 1
                        } else {
                            bootstrapSubscriptionCounts[bootstrapSubscriptionId] = 1
                        }
                    }
                } catch {
                    print("Could not subscribe to relay with the boostrap filter.")
                }
            }
        }

        if liveActivityEventSubscriptionCounts.isEmpty {
            let since: Int?
            if let relaySubscriptionMetadata, !hardRefresh {
                if let relayURL = relay?.url,
                    let lastPulledLiveActivityEvents =
                        relaySubscriptionMetadata.lastPulledLiveActivityEvents[relayURL]
                {
                    since = Int(lastPulledLiveActivityEvents.timeIntervalSince1970) + 1
                } else if let lastPulledLiveActivityEvents = relaySubscriptionMetadata
                    .lastBootstrapped.values.min()
                {
                    since = Int(lastPulledLiveActivityEvents.timeIntervalSince1970) + 1
                } else {
                    since = nil
                }
            } else {
                since = nil
            }

            guard
                let liveActivityEventFilter = Filter(
                    kinds: [EventKind.liveActivities.rawValue],
                    since: since,
                    until: Int(until.timeIntervalSince1970)
                )
            else {
                print("Unable to create the live activity event filter.")
                return
            }

            do {
                if let liveActivityEventSubscriptionId = try subscribe(
                    filter: liveActivityEventFilter, relay: relay)
                {
                    if let liveActivityEventSubscriptionCount = liveActivityEventSubscriptionCounts[
                        liveActivityEventSubscriptionId]
                    {
                        liveActivityEventSubscriptionCounts[liveActivityEventSubscriptionId] =
                            liveActivityEventSubscriptionCount + 1
                    } else {
                        liveActivityEventSubscriptionCounts[liveActivityEventSubscriptionId] = 1
                    }
                }
            } catch {
                print("Could not subscribe to relay with the live activity event filter.")
            }
        }

        publishUnpublishedEvents()
    }

    private func publishUnpublishedEvents() {
        for persistentNostrEvent in unpublishedPersistentNostrEvents {
            relayWritePool.publishEvent(persistentNostrEvent.nostrEvent)
        }
    }

    private func didReceiveFollowListEvent(
        _ followListEvent: FollowListEvent, shouldPullMissingEvents: Bool = false
    ) {
        if let existingFollowList = self.followListEvents[followListEvent.pubkey] {
            if existingFollowList.createdAt < followListEvent.createdAt {
                cache(followListEvent, shouldPullMissingEvents: shouldPullMissingEvents)
            }
        } else {
            cache(followListEvent, shouldPullMissingEvents: shouldPullMissingEvents)
        }
    }

    private func cache(_ followListEvent: FollowListEvent, shouldPullMissingEvents: Bool) {
        self.followListEvents[followListEvent.pubkey] = followListEvent

        if shouldPullMissingEvents {
            pullMissingEventsFromPubkeysAndFollows(followListEvent.followedPubkeys)
        }

        if followListEvent.pubkey == publicKey?.hex {
            refreshFollowedPubkeys()
        }
    }

    private func didReceiveMetadataEvent(_ metadataEvent: MetadataEvent) {
        // Capture new metadata values
        let newUserMetadata = metadataEvent.userMetadata
        let newName = newUserMetadata?.name?.trimmedOrNilIfEmpty
        let newDisplayName = newUserMetadata?.displayName?.trimmedOrNilIfEmpty

        // Offload the heavy comparison and processing work to a background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if let existingMetadataEvent = self.metadataEvents[metadataEvent.pubkey] {
                if existingMetadataEvent.createdAt < metadataEvent.createdAt {
                    if let existingUserMetadata = existingMetadataEvent.userMetadata {
                        if let existingName = existingUserMetadata.name?.trimmedOrNilIfEmpty,
                            existingName != newName {
                            // Since trie updates might need to be thread-safe, dispatch back to main if required
                            DispatchQueue.main.async {
                                self.pubkeyTrie.remove(key: existingName, value: existingMetadataEvent.pubkey)
                            }
                        }
                        if let existingDisplayName = existingUserMetadata.displayName?.trimmedOrNilIfEmpty,
                            existingDisplayName != newDisplayName {
                            DispatchQueue.main.async {
                                self.pubkeyTrie.remove(key: existingDisplayName, value: existingMetadataEvent.pubkey)
                            }
                        }
                    }
                } else {
                    return
                }
            }
            
            // Update the metadata dictionary on the main thread (assuming it is used for UI)
            DispatchQueue.main.async {
                self.metadataEvents[metadataEvent.pubkey] = metadataEvent
            }
            
            // Offload trie insertions if possible. If your trie is not thread‑safe, you must do these on the main thread.
            // Here we assume the trie operations are lightweight, so we dispatch them on main:
            DispatchQueue.main.async {
                if let userMetadata = metadataEvent.userMetadata {
                    if let name = userMetadata.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        _ = self.pubkeyTrie.insert(
                            key: name,
                            value: metadataEvent.pubkey,
                            options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]
                        )
                    }
                    if let displayName = userMetadata.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        _ = self.pubkeyTrie.insert(
                            key: displayName,
                            value: metadataEvent.pubkey,
                            options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]
                        )
                    }
                }
                if let publicKey = PublicKey(hex: metadataEvent.pubkey) {
                    _ = self.pubkeyTrie.insert(key: publicKey.npub, value: metadataEvent.pubkey)
                }
            }
        }
    }

    private func didReceiveLiveActivitiesEvent(_ liveActivitiesEvent: LiveActivitiesEvent) {
        guard let eventCoordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value,
              let startTimestamp = liveActivitiesEvent.startsAt,
              startTimestamp <= liveActivitiesEvent.endsAt ?? startTimestamp,
              startTimestamp.timeIntervalSince1970 > 0
        else {
            return
        }

        // Replace direct assignment with the new method
        self.addLiveActivity(liveActivitiesEvent, toEventCoordinate: eventCoordinates)
        
        // Update the trie (if needed)
        updateLiveActivitiesTrie(newEvent: liveActivitiesEvent)
    }
    
    private func addLiveActivity(_ activity: LiveActivitiesEvent, toEventCoordinate coordinate: String) {
        // Initialize the array if it doesn't exist
        if liveActivitiesEvents[coordinate] == nil {
            liveActivitiesEvents[coordinate] = []
        }
        
        guard var activities = liveActivitiesEvents[coordinate] else { return }
        
        // Prevent duplicates
        if !activities.contains(where: { $0.id == activity.id }) {
            activities.append(activity)
            
            // Enforce memory limits by trimming oldest events
            if activities.count > CollectionLimits.maxLiveActivitiesEvents {
                // Sort by creation date (newest first)
                activities.sort { $0.createdAt > $1.createdAt }
                // Keep only the latest events
                activities = Array(activities.prefix(CollectionLimits.maxLiveActivitiesEvents))
            }
            
            liveActivitiesEvents[coordinate] = activities
        }
    }

    private func didReceiveZapReceiptEvent(_ zapReceipt: LightningZapsReceiptEvent) {
        guard let eventCoordinate = zapReceipt.eventCoordinate else { return }
        
        DispatchQueue.main.async {
            // Continue maintaining your original collection if needed
            if self.zapReceiptEvents[eventCoordinate] == nil {
                self.zapReceiptEvents[eventCoordinate] = []
            }
            
            // Prevent duplicates using event ID
            if !self.zapReceiptEvents[eventCoordinate]!.contains(where: { $0.id == zapReceipt.id }) {
                self.zapReceiptEvents[eventCoordinate]!.append(zapReceipt)
                
                // Update the total amount - handle the optional properly
                if let amount = zapReceipt.description?.amount {
                    self.eventZapTotals[eventCoordinate, default: 0] += Int64(amount)
                }
            }
        }
    }
    
    func subscribeToLiveChat(for event: LiveActivitiesEvent) {
        guard let eventCoordinate = event.replaceableEventCoordinates()?.tag.value,
              !liveChatSubscriptionCounts.values.contains(eventCoordinate) else { return }
        
        // Create filter with proper tag structure
        guard let filter = Filter(
            kinds: [EventKind.liveChatMessage.rawValue, /*EventKind.zapRequest.rawValue,*/ EventKind.zapReceipt.rawValue],
            tags: ["a": [eventCoordinate]],  // Note the array of arrays
            since: 0
        ) else {
            print("Failed to create live chat filter")
            return
        }
        
        // Add time constraints to get historical messages
        //        if let liveEventStart = event.startsAt {
        //            filter.since = Int(liveEventStart.timeIntervalSince1970)
        //        }
        
        let subscriptionId = relayReadPool.subscribe(with: filter)
        liveChatSubscriptionCounts[subscriptionId] = eventCoordinate
        print("Subscribed to live chat \(eventCoordinate) with ID: \(subscriptionId)")
    }

    func unsubscribeFromLiveChat(for event: LiveActivitiesEvent) {
        guard let eventCoordinate = event.replaceableEventCoordinates()?.tag.value else { return }
        
        liveChatSubscriptionCounts
            .filter { $0.value == eventCoordinate }
            .keys
            .forEach { subscriptionId in
                relayReadPool.closeSubscription(with: subscriptionId)
                liveChatSubscriptionCounts.removeValue(forKey: subscriptionId)
                liveChatMessagesEvents.removeValue(forKey: eventCoordinate)
                zapReceiptEvents.removeValue(forKey: eventCoordinate)
            }
    }
    
    func subscribeToProfile(for publicKeyHex: String) {
        guard !followListEventSubscriptionCounts.values.contains(publicKeyHex) else { return }
        
        // Create filter with proper tag structure
        guard let filter = Filter(
            authors: [publicKeyHex, appSettings?.activeProfile?.publicKeyHex].compactMap { $0 },
            kinds: [
                EventKind.metadata.rawValue,
                EventKind.followList.rawValue,
//                EventKind.liveActivities.rawValue,
//                    EventKind.deletion.rawValue
            ]
        ) else {
            print("Unable to create profile filter.")
            return
        }
        
        // Add time constraints to get historical messages
        //        if let liveEventStart = event.startsAt {
        //            filter.since = Int(liveEventStart.timeIntervalSince1970)
        //        }
        
        let subscriptionId = relayReadPool.subscribe(with: filter)
        followListEventSubscriptionCounts[subscriptionId] = publicKeyHex
        print("Subscribed to profile \(publicKeyHex) with ID: \(subscriptionId)")
    }
    
    func unsubscribeFromProfile(for publicKeyHex: String) {
        followListEventSubscriptionCounts
            .filter { $0.value == publicKeyHex }
            .keys
            .forEach { subscriptionId in
                relayReadPool.closeSubscription(with: subscriptionId)
                followListEventSubscriptionCounts.removeValue(forKey: subscriptionId)
//                followListEvents.removeValue(forKey: publicKeyHex)
            }
    }
    
    private func didReceiveLiveChatMessage(_ message: LiveChatMessageEvent) {
        print("received live chat message", self.liveChatMessagesEvents.count)
        guard let eventReference = message.liveEventReference else { return }
        let eventCoordinate = "\(eventReference.liveEventKind):\(eventReference.pubkey):\(eventReference.d)"
        
        DispatchQueue.main.async {
            self.addChatMessage(message, toEventCoordinate: eventCoordinate)
        }
    }
    
    private func addChatMessage(_ message: LiveChatMessageEvent, toEventCoordinate coordinate: String) {
        if self.liveChatMessagesEvents[coordinate] == nil {
            self.liveChatMessagesEvents[coordinate] = []
        }
        
        var messages = self.liveChatMessagesEvents[coordinate]!
        
        // Prevent duplicates
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
            
            // Enforce memory limits by trimming oldest messages
            if messages.count > CollectionLimits.maxChatMessagesPerEvent {
                messages = Array(messages.suffix(CollectionLimits.maxChatMessagesPerEvent))
            }
            
            self.liveChatMessagesEvents[coordinate] = messages
        }
    }

    func delete(events: [NostrEvent]) {
        guard let keypair else {
            return
        }

        let deletableEvents = events.filter { $0.pubkey == keypair.publicKey.hex }
        guard !deletableEvents.isEmpty else {
            return
        }

        let replaceableEvents = deletableEvents.compactMap { $0 as? ReplaceableEvent }

        do {
            let deletionEvent = try delete(
                events: deletableEvents, replaceableEvents: replaceableEvents, signedBy: keypair)
            relayWritePool.publishEvent(deletionEvent)
            _ = didReceive(nostrEvent: deletionEvent)
        } catch {
            print(
                "Unable to delete NostrEvents. [\(events.map { "{ id=\($0.id), kind=\($0.kind)}" }.joined(separator: ", "))]"
            )
        }
    }

    private func didReceiveDeletionEvent(_ deletionEvent: DeletionEvent) {
        deleteFromEventCoordinates(deletionEvent)
        deleteFromEventIds(deletionEvent)
    }

    func relay(_ relay: Relay, didReceive event: RelayEvent) {
        // Offload heavy processing to a background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let nostrEvent = event.event
            
            // Perform verification on background thread
            do {
                try self.verifyEvent(nostrEvent)
            } catch {
                print("Event verification failed: \(error)")
                return
            }
            
            // Dispatch updates to published properties on the main thread
            DispatchQueue.main.async {
                _ = self.didReceive(nostrEvent: nostrEvent, relay: relay)
            }
        }
    }

    func didReceive(nostrEvent: NostrEvent, relay: Relay? = nil) -> PersistentNostrEvent? {
        // Process the event with your existing event-specific handlers.
        switch nostrEvent {
        case let followListEvent as FollowListEvent:
            self.didReceiveFollowListEvent(followListEvent, shouldPullMissingEvents: nostrEvent.pubkey == appSettings?.activeProfile?.publicKeyHex)
        case let metadataEvent as MetadataEvent:
            self.didReceiveMetadataEvent(metadataEvent)
        case let liveActivitiesEvent as LiveActivitiesEvent:
            self.didReceiveLiveActivitiesEvent(liveActivitiesEvent)
        case let liveChatMessageEvent as LiveChatMessageEvent:
            self.didReceiveLiveChatMessage(liveChatMessageEvent)
        case let zapReceiptEvent as LightningZapsReceiptEvent:
            self.didReceiveZapReceiptEvent(zapReceiptEvent)
        case let deletionEvent as DeletionEvent:
            self.didReceiveDeletionEvent(deletionEvent)
        default:
            break
        }
        
        // Check if the event already exists in persistent storage.
        if let existingEvent = self.persistentNostrEvent(nostrEvent.id) {
            if let relay, !existingEvent.relays.contains(where: { $0 == relay.url }) {
                existingEvent.relays.append(relay.url)
            }
            return existingEvent
        } else {
            // Instead of immediately inserting and saving, enqueue the event for batch processing.
            self.enqueueEvent(nostrEvent)
            return nil // The persistent event will be created asynchronously.
        }
    }
    
    /// Enqueues an incoming event for batch processing.
    private func enqueueEvent(_ event: NostrEvent) {
        DispatchQueue.main.async {
            self.pendingEvents.append(event)
            // If we have reached the batch size, process immediately.
            if self.pendingEvents.count >= self.batchSize {
                self.processPendingEvents()
                self.batchTimer?.invalidate()
                self.batchTimer = nil
            } else if self.batchTimer == nil {
                // Otherwise, set up a timer to process after a short delay (e.g., 1 second).
                self.batchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    self?.processPendingEvents()
                    self?.batchTimer = nil
                }
            }
        }
    }

    func loadPersistentNostrEvents(_ persistentNostrEvents: [PersistentNostrEvent]) {
        for persistentNostrEvent in persistentNostrEvents {
            switch persistentNostrEvent.nostrEvent {
            case let liveActivitiesEvent as LiveActivitiesEvent:
                self.didReceiveLiveActivitiesEvent(liveActivitiesEvent)
            case let followListEvent as FollowListEvent:
                self.didReceiveFollowListEvent(followListEvent)
            case let metadataEvent as MetadataEvent:
                self.didReceiveMetadataEvent(metadataEvent)
            case let deletionEvent as DeletionEvent:
                self.didReceiveDeletionEvent(deletionEvent)
            default:
                break
            }
        }

        if let publicKey, let followListEvent = followListEvents[publicKey.hex] {
            pullMissingEventsFromPubkeysAndFollows(followListEvent.followedPubkeys)
        }
    }

    func relay(_ relay: Relay, didReceive response: RelayResponse) {
        DispatchQueue.main.async {
            switch response {
            case let .eose(subscriptionId):
                if self.liveChatSubscriptionCounts.keys.contains(subscriptionId) || self.followListEventSubscriptionCounts.keys.contains(subscriptionId) {
                    // Maintain live chat subscription for real-time updates
                    print("Maintaining subscription: \(subscriptionId)")
                } else {
                    try? relay.closeSubscription(with: subscriptionId)
                    self.updateRelaySubscriptionCounts(closedSubscriptionId: subscriptionId)
                }
                
            case let .closed(subscriptionId, _):
                self.liveChatSubscriptionCounts.removeValue(forKey: subscriptionId)
                self.followListEventSubscriptionCounts.removeValue(forKey: subscriptionId)
                self.updateRelaySubscriptionCounts(closedSubscriptionId: subscriptionId)
            case let .ok(eventId, success, message):
                if success {
                    if let persistentNostrEvent = self.persistentNostrEvent(eventId), !persistentNostrEvent.relays.contains(relay.url) {
                        persistentNostrEvent.relays.append(relay.url)
                    }
                } else if message.prefix == .rateLimited {
                    // TODO retry with exponential backoff.
                }
            default:
                break
            }
        }
    }

    func updateRelaySubscriptionCounts(closedSubscriptionId: String) {
        // Handle metadata subscription counts
        if let metadataSubscriptionCount = metadataSubscriptionCounts[closedSubscriptionId] {
            if metadataSubscriptionCount <= 1 {
                metadataSubscriptionCounts.removeValue(forKey: closedSubscriptionId)
            } else {
                metadataSubscriptionCounts[closedSubscriptionId] = metadataSubscriptionCount - 1
            }
        }

        // Handle bootstrap subscription counts
        if let bootstrapSubscriptionCount = bootstrapSubscriptionCounts[closedSubscriptionId] {
            if bootstrapSubscriptionCount <= 1 {
                bootstrapSubscriptionCounts.removeValue(forKey: closedSubscriptionId)
            } else {
                bootstrapSubscriptionCounts[closedSubscriptionId] = bootstrapSubscriptionCount - 1
            }
        }

        // Handle live activity event subscription counts
        if let liveActivityEventSubscriptionCount = liveActivityEventSubscriptionCounts[closedSubscriptionId] {
            if liveActivityEventSubscriptionCount <= 1 {
                liveActivityEventSubscriptionCounts.removeValue(forKey: closedSubscriptionId)

                // Flatten the nested arrays before accessing properties
                let allLiveActivities = liveActivitiesEvents.values.flatMap { $0 }

                // Fetch metadata for all unique pubkeys in live activities
                let uniquePubkeys = Set(allLiveActivities.map { $0.pubkey })
                pullMissingEventsFromPubkeysAndFollows(Array(uniquePubkeys))

                // Fetch metadata for hosts of live activities
                let hostPubkeys = allLiveActivities.compactMap { activity in
                    activity.participants.first(where: { $0.role == "host" })?.pubkey?.hex
                }
                pullMissingEventsFromPubkeysAndFollows(hostPubkeys)
            } else {
                liveActivityEventSubscriptionCounts[closedSubscriptionId] = liveActivityEventSubscriptionCount - 1
            }
        }
    }

    func updateLiveActivitiesTrie(oldEvent: LiveActivitiesEvent? = nil, newEvent: LiveActivitiesEvent) {
        // First, get the event coordinate. If missing, nothing to do.
        guard let eventCoordinates = newEvent.replaceableEventCoordinates()?.tag.value else {
            return
        }
        
        // Ignore new events that are older or equal to an existing one.
        if let oldEvent, oldEvent.createdAt >= newEvent.createdAt {
            return
        }
        
        // Offload key extraction and decision-making to a background queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Extract new values.
            let newTitle = newEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty
            let newSummary = newEvent.firstValueForRawTagName("summary")?.trimmedOrNilIfEmpty
            
            // Prepare removals based on differences from the old event.
            var removals = [(key: String, value: String)]()
            if let oldEvent = oldEvent {
                if let oldTitle = oldEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty,
                   oldTitle != newTitle {
                    removals.append((key: oldTitle, value: eventCoordinates))
                }
                if let oldSummary = oldEvent.firstValueForRawTagName("summary")?.trimmedOrNilIfEmpty,
                   oldSummary != newSummary {
                    removals.append((key: oldSummary, value: eventCoordinates))
                }
            }
            
            // Prepare insertions for all keys.
            var insertions = [(key: String, options: TrieInsertionOptions?)]()
            insertions.append((key: newEvent.id, options: nil))
            insertions.append((key: newEvent.pubkey, options: nil))
            if let identifier = newEvent.firstValueForRawTagName("identifier") {
                insertions.append((key: identifier, options: nil))
            }
            if let newTitle = newTitle {
                insertions.append((key: newTitle, options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]))
            }
            if let newSummary = newSummary {
                insertions.append((key: newSummary, options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]))
            }
            
            // Dispatch the trie modifications back to the main thread.
            DispatchQueue.main.async {
                // Remove outdated entries.
                for removal in removals {
                    self.liveActivitiesTrie.remove(key: removal.key, value: removal.value)
                }
                
                // Insert new entries.
                for insertion in insertions {
                    if let options = insertion.options {
                        _ = self.liveActivitiesTrie.insert(key: insertion.key, value: eventCoordinates, options: options)
                    } else {
                        _ = self.liveActivitiesTrie.insert(key: insertion.key, value: eventCoordinates)
                    }
                }
            }
        }
    }

    private func deleteFromEventCoordinates(_ deletionEvent: DeletionEvent) {
        let deletedEventCoordinates = deletionEvent.eventCoordinates.filter {
            $0.pubkey?.hex == deletionEvent.pubkey
        }

        for deletedEventCoordinate in deletedEventCoordinates {
            // Update the deletion timestamp for the event coordinate
            if let existingDeletedEventCoordinateDate = self.deletedEventCoordinates[deletedEventCoordinate.tag.value] {
                if existingDeletedEventCoordinateDate < deletionEvent.createdDate {
                    self.deletedEventCoordinates[deletedEventCoordinate.tag.value] = deletionEvent.createdDate
                } else {
                    continue
                }
            } else {
                self.deletedEventCoordinates[deletedEventCoordinate.tag.value] = deletionEvent.createdDate
            }

            // Handle deletion based on event kind
            switch deletedEventCoordinate.kind {
            case .liveActivities:
                if let liveActivitiesArray = liveActivitiesEvents[deletedEventCoordinate.tag.value] {
                    // Find the most recent event in the array
                    if let mostRecentEvent = liveActivitiesArray.max(by: { $0.createdAt < $1.createdAt }),
                       mostRecentEvent.createdAt <= deletionEvent.createdAt {
                        // Remove the entire array of events for this coordinate
                        liveActivitiesEvents.removeValue(forKey: deletedEventCoordinate.tag.value)
                    }
                }
            default:
                continue
            }
        }
    }

    private func deleteFromEventIds(_ deletionEvent: DeletionEvent) {
        for deletedEventId in deletionEvent.deletedEventIds {
            if let persistentNostrEvent = persistentNostrEvent(deletedEventId) {
                let nostrEvent = persistentNostrEvent.nostrEvent

                // Ensure the event belongs to the same pubkey as the deletion event
                guard nostrEvent.pubkey == deletionEvent.pubkey else {
                    continue
                }

                switch nostrEvent {
                case _ as FollowListEvent:
                    // Remove the follow list event for the pubkey
                    followListEvents.removeValue(forKey: nostrEvent.pubkey)

                case _ as MetadataEvent:
                    // Remove the metadata event for the pubkey
                    metadataEvents.removeValue(forKey: nostrEvent.pubkey)

                case let liveActivitiesEvent as LiveActivitiesEvent:
                    // Check if the event coordinates exist in the dictionary
                    if let eventCoordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value {
                        // Filter out the event with the matching ID from the array
                        liveActivitiesEvents[eventCoordinates]?.removeAll { $0.id == liveActivitiesEvent.id }

                        // If the array is now empty, remove the coordinate entry entirely
                        if liveActivitiesEvents[eventCoordinates]?.isEmpty == true {
                            liveActivitiesEvents.removeValue(forKey: eventCoordinates)
                        }
                    }

                default:
                    continue
                }

                // Delete the persistent event from the model context
                modelContext.delete(persistentNostrEvent)
                do {
                    try modelContext.save()
                } catch {
                    print("Unable to delete PersistentNostrEvent with id \(deletedEventId)")
                }
            }
        }
    }
    
    func saveFollowList(pubkeys: [String]) -> Bool {
        // Make sure pubkeys is not empty.
        guard pubkeys.count > 0 else { return false }
        // Make sure we have an appState keypair.
        guard let keypair = keypair else {
            print("no keypair")
            return false
        }

        do {
            let liveChatMessageEvent = try followList(
                withPubkeys: pubkeys,
                signedBy: keypair
            )
            // Publish the event.
            relayWritePool.publishEvent(liveChatMessageEvent)
            return true
        } catch {
            print("Unable to save event: \(error)")
        }
        return false
    }
    
    private func updateCollectionsWithBatchResults(_ persistentEvents: [PersistentNostrEvent]) {
        for persistentEvent in persistentEvents {
            let nostrEvent = persistentEvent.nostrEvent
            switch nostrEvent {
            case let followListEvent as FollowListEvent:
                // Update follow list events using the pubkey as key.
                self.followListEvents[followListEvent.pubkey] = followListEvent
            case let metadataEvent as MetadataEvent:
                // Update metadata events keyed by pubkey.
                self.metadataEvents[metadataEvent.pubkey] = metadataEvent
            case let liveActivitiesEvent as LiveActivitiesEvent:
                // Use event coordinates as the key (if available).
                if let eventCoordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value {
                    self.addLiveActivity(liveActivitiesEvent, toEventCoordinate: eventCoordinates)
                }
            default:
                break
            }
        }
    }

    /// Processes the pending events in batches.
    /// Heavy work (creating persistent objects) is done on a background queue,
    /// while all ModelContext modifications occur on the main thread.
    private func processPendingEvents() {
        // Guard against an empty pendingEvents array.
        guard !pendingEvents.isEmpty else { return }
        
        // Take a batch of events up to the batch size.
        let batch = Array(pendingEvents.prefix(batchSize))
        pendingEvents.removeFirst(min(batchSize, pendingEvents.count))
        
        // Offload heavy processing to a background queue.
        dbQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create persistent objects for each event in the background.
            let persistentEvents = batch.map { PersistentNostrEvent(nostrEvent: $0) }
            
            // Now switch to the main thread to modify the ModelContext.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Insert all persistent events into the model context.
                for event in persistentEvents {
                    self.modelContext.insert(event)
                }
                
                // Save the batch with a single database write.
                do {
                    try self.modelContext.save()
                } catch {
                    print("Error saving batch of events: \(error)")
                }
                
                // Update UI/in-memory collections on the main thread.
                self.updateCollectionsWithBatchResults(persistentEvents)
            }
        }
    }
}

struct CollectionLimits {
    static let maxChatMessagesPerEvent = 500
    static let maxZapReceiptsPerEvent = 200
    static let maxLiveActivitiesEvents = 200
}
