//
//  AppState.swift
//  gibbe
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

    @Published var relayReadPool: RelayPool = RelayPool(relays: [])
    @Published var relayWritePool: RelayPool = RelayPool(relays: [])

    @Published var activeTab: HomeTabs = .events

    @Published var followListEvents: [String: FollowListEvent] = [:]
    @Published var metadataEvents: [String: MetadataEvent] = [:]
    @Published var liveActivitiesEvents: [String: LiveActivitiesEvent] = [:]
    @Published var deletedEventIds = Set<String>()
    @Published var deletedEventCoordinates = [String: Date]()

    @Published var followedPubkeys = Set<String>()

    @Published var eventsTrie = Trie<String>()
    @Published var liveActivitiesTrie = Trie<String>()
    @Published var pubkeyTrie = Trie<String>()

    // Keep track of relay pool active subscriptions and the until filter so that we can limit the scope of how much we query from the relay pools.
    var metadataSubscriptionCounts = [String: Int]()
    var bootstrapSubscriptionCounts = [String: Int]()
    var liveActivityEventSubscriptionCounts = [String: Int]()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        Array(liveActivitiesEvents.values)
    }
    
    var allUpcomingEvents: [LiveActivitiesEvent] {
        upcomingEvents(allEvents)
    }

    var allPastEvents: [LiveActivitiesEvent] {
        print("running allPastEvents")
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
    
    /// Events that were created or RSVP'd by follow list.
    private var followedEvents: [LiveActivitiesEvent] {
        guard publicKey != nil else {
            return []
        }

        return liveActivitiesEvents.values.filter { event in
            guard let coordinates = event.replaceableEventCoordinates() else {
                return false
            }

            return event.startsAt != nil
            && followedPubkeys.contains(event.pubkey)
        }
    }

    var upcomingFollowedEvents: [LiveActivitiesEvent] {
        upcomingEvents(followedEvents)
    }

    var pastFollowedEvents: [LiveActivitiesEvent] {
        pastEvents(followedEvents)
    }

    /// Events that were created or RSVP'd by the active profile.
    private func profileEvents(_ publicKeyHex: String) -> [LiveActivitiesEvent] {
        return liveActivitiesEvents.values.filter { event in
            guard let coordinates = event.replaceableEventCoordinates() else {
                return false
            }

            return event.startsAt != nil && event.pubkey == publicKeyHex
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
//        print("here: ", events)
        return events.filter { $0.isPast }
            .sorted(using: LiveActivitiesEventSortComparator(order: .reverse))
    }

    func updateRelayPool() {
        let relaySettings = relayPoolSettings?.relaySettingsList ?? []

        let readRelays = relaySettings
            .filter { $0.read }
            .compactMap { URL(string: $0.relayURLString) }
            .compactMap { try? Relay(url: $0) }

        let writeRelays = relaySettings
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
        guard let relayPoolSettings, relayPoolSettings.relaySettingsList.allSatisfy({ $0.relayURLString != relayURL.absoluteString }) else {
            return
        }

        relayPoolSettings.relaySettingsList.append(RelaySettings(relayURLString: relayURL.absoluteString))

        updateRelayPool()
    }

    func removeRelaySettings(relaySettings: RelaySettings) {
        relayPoolSettings?.relaySettingsList.removeAll(where: { $0 == relaySettings })
        updateRelayPool()
    }

    func deleteProfile(_ profile: Profile) {
        guard let publicKeyHex = profile.publicKeyHex, let newProfile = profiles.first(where: { $0 != profile }) else {
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
            activeTab = .events
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

        let validatedRelayURLStrings = OrderedSet<String>(relayURLs.compactMap { try? validateRelayURL($0).absoluteString })

        if let profile = profiles.first(where: { $0.publicKeyHex == publicKey.hex }) {
            print("Found existing profile settings for \(publicKey.npub)")
            if let relayPoolSettings = profile.profileSettings?.relayPoolSettings {
                let existingRelayURLStrings = Set(relayPoolSettings.relaySettingsList.map { $0.relayURLString })
                let newRelayURLStrings = validatedRelayURLStrings.subtracting(existingRelayURLStrings)
                if !newRelayURLStrings.isEmpty {
                    relayPoolSettings.relaySettingsList += newRelayURLStrings.map { RelaySettings(relayURLString: $0) }
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
                relayPoolSettings.relaySettingsList += validatedRelayURLStrings.map { RelaySettings(relayURLString: $0) }
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
        let readRelay = relayReadPool.relays.first(where: { $0.url.absoluteString == relayURLString })
        let writeRelay = relayWritePool.relays.first(where: { $0.url.absoluteString == relayURLString })

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
    func relay(_ relay: NostrSDK.Relay, didReceive response: NostrSDK.RelayResponse) {
        return
    }
    

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
        guard !relayReadPool.relays.isEmpty && relayReadPool.relays.contains(where: { $0.state == .connected }) else {
            return
        }

        let until = Date.now

        let allPubkeysSet = Set(pubkeys)
        let pubkeysToFetchMetadata = allPubkeysSet.filter { self.metadataEvents[$0] == nil }
        if !pubkeysToFetchMetadata.isEmpty {
            guard let missingMetadataFilter = Filter(
                authors: Array(pubkeysToFetchMetadata),
                kinds: [EventKind.metadata.rawValue, EventKind.liveActivities.rawValue, EventKind.deletion.rawValue],
                until: Int(until.timeIntervalSince1970)
            ) else {
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
        if let lastPulledEventsFromFollows = relaySubscriptionMetadata?.lastPulledEventsFromFollows.values.min() {
            since = Int(lastPulledEventsFromFollows.timeIntervalSince1970) + 1
        } else {
            since = nil
        }

        let pubkeysToRefresh = allPubkeysSet.subtracting(pubkeysToFetchMetadata)
        guard let metadataRefreshFilter = Filter(
            authors: Array(pubkeysToRefresh),
            kinds: [EventKind.metadata.rawValue, EventKind.liveActivities.rawValue, EventKind.deletion.rawValue],
            since: since,
            until: Int(until.timeIntervalSince1970)
        ) else {
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
        guard (relay == nil && !relayReadPool.relays.isEmpty && relayReadPool.relays.contains(where: { $0.state == .connected })) || relay?.state == .connected else {
            return
        }

        let relaySubscriptionMetadata = relaySubscriptionMetadata
        let until = Date.now

        if bootstrapSubscriptionCounts.isEmpty {
            let authors = profiles.compactMap({ $0.publicKeyHex })
            if !authors.isEmpty {
                let since: Int?
                if let relaySubscriptionMetadata, !hardRefresh {
                    if let relayURL = relay?.url, let lastBootstrapped = relaySubscriptionMetadata.lastBootstrapped[relayURL] {
                        since = Int(lastBootstrapped.timeIntervalSince1970) + 1
                    } else if let lastBootstrapped = relaySubscriptionMetadata.lastBootstrapped.values.min() {
                        since = Int(lastBootstrapped.timeIntervalSince1970) + 1
                    } else {
                        since = nil
                    }
                } else {
                    since = nil
                }

                guard let bootstrapFilter = Filter(
                    authors: authors,
                    kinds: [EventKind.metadata.rawValue, EventKind.followList.rawValue, EventKind.liveActivities.rawValue, EventKind.deletion.rawValue],
                    since: since,
                    until: Int(until.timeIntervalSince1970)
                ) else {
                    print("Unable to create the boostrap filter.")
                    return
                }

                do {
                    if let bootstrapSubscriptionId = try subscribe(filter: bootstrapFilter, relay: relay), relay == nil {
                        if let bootstrapSubscriptionCount = bootstrapSubscriptionCounts[bootstrapSubscriptionId] {
                            bootstrapSubscriptionCounts[bootstrapSubscriptionId] = bootstrapSubscriptionCount + 1
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
                if let relayURL = relay?.url, let lastPulledLiveActivityEvents = relaySubscriptionMetadata.lastPulledLiveActivityEvents[relayURL] {
                    since = Int(lastPulledLiveActivityEvents.timeIntervalSince1970) + 1
                } else if let lastPulledLiveActivityEvents = relaySubscriptionMetadata.lastBootstrapped.values.min() {
                    since = Int(lastPulledLiveActivityEvents.timeIntervalSince1970) + 1
                } else {
                    since = nil
                }
            } else {
                since = nil
            }

            guard let liveActivityEventFilter = Filter(
                kinds: [EventKind.liveActivities.rawValue],
                since: since,
                until: Int(until.timeIntervalSince1970)
            ) else {
                print("Unable to create the live activity event filter.")
                return
            }

            do {
                if let liveActivityEventSubscriptionId = try subscribe(filter: liveActivityEventFilter, relay: relay) {
                    if let liveActivityEventSubscriptionCount = liveActivityEventSubscriptionCounts[liveActivityEventSubscriptionId] {
                        liveActivityEventSubscriptionCounts[liveActivityEventSubscriptionId] = liveActivityEventSubscriptionCount + 1
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

    private func didReceiveFollowListEvent(_ followListEvent: FollowListEvent, shouldPullMissingEvents: Bool = false) {
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
        let newUserMetadata = metadataEvent.userMetadata
        let newName = newUserMetadata?.name?.trimmedOrNilIfEmpty
        let newDisplayName = newUserMetadata?.displayName?.trimmedOrNilIfEmpty

        if let existingMetadataEvent = self.metadataEvents[metadataEvent.pubkey] {
            if existingMetadataEvent.createdAt < metadataEvent.createdAt {
                if let existingUserMetadata = existingMetadataEvent.userMetadata {
                    if let existingName = existingUserMetadata.name?.trimmedOrNilIfEmpty, existingName != newName {
                        pubkeyTrie.remove(key: existingName, value: existingMetadataEvent.pubkey)
                    }
                    if let existingDisplayName = existingUserMetadata.displayName?.trimmedOrNilIfEmpty, existingDisplayName != newDisplayName {
                        pubkeyTrie.remove(key: existingDisplayName, value: existingMetadataEvent.pubkey)
                    }
                }
            } else {
                return
            }
        }

        self.metadataEvents[metadataEvent.pubkey] = metadataEvent

        if let userMetadata = metadataEvent.userMetadata {
            if let name = userMetadata.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
                _ = pubkeyTrie.insert(key: name, value: metadataEvent.pubkey, options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches, .includeNonPrefixedMatches])
            }
            if let displayName = userMetadata.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) {
                _ = pubkeyTrie.insert(key: displayName, value: metadataEvent.pubkey, options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches, .includeNonPrefixedMatches])
            }
        }

        if let publicKey = PublicKey(hex: metadataEvent.pubkey) {
            _ = pubkeyTrie.insert(key: publicKey.npub, value: metadataEvent.pubkey, options: [.includeNonPrefixedMatches])
        }
    }
    
    private func didReceiveLiveActivitiesEvent(_ liveActivitiesEvent: LiveActivitiesEvent) {
        guard let eventCoordinates = liveActivitiesEvent.replaceableEventCoordinates()?.tag.value else {
            return
        }

        let existingLiveActivity = self.liveActivitiesEvents[eventCoordinates]
        if let existingLiveActivity, existingLiveActivity.createdAt >= liveActivitiesEvent.createdAt {
            return
        }

        liveActivitiesEvents[eventCoordinates] = liveActivitiesEvent

        updateLiveActivitiesTrie(oldEvent: existingLiveActivity, newEvent: liveActivitiesEvent)
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
            let deletionEvent = try delete(events: deletableEvents, replaceableEvents: replaceableEvents, signedBy: keypair)
            relayWritePool.publishEvent(deletionEvent)
            _ = didReceive(nostrEvent: deletionEvent)
        } catch {
            print("Unable to delete NostrEvents. [\(events.map { "{ id=\($0.id), kind=\($0.kind)}" }.joined(separator: ", "))]")
        }
    }
    
    private func didReceiveDeletionEvent(_ deletionEvent: DeletionEvent) {
        deleteFromEventCoordinates(deletionEvent)
        deleteFromEventIds(deletionEvent)
    }

    func relay(_ relay: Relay, didReceive event: RelayEvent) {
        DispatchQueue.main.async {
            let nostrEvent = event.event

            // Verify the id and signature of the event.
            // If the verification throws an error, that means they are invalid and we should ignore the event.
            try? self.verifyEvent(nostrEvent)

            _ = self.didReceive(nostrEvent: nostrEvent, relay: relay)
        }
    }

    func didReceive(nostrEvent: NostrEvent, relay: Relay? = nil) -> PersistentNostrEvent? {
        switch nostrEvent {
        case let followListEvent as FollowListEvent:
            self.didReceiveFollowListEvent(followListEvent, shouldPullMissingEvents: true)
        case let metadataEvent as MetadataEvent:
            self.didReceiveMetadataEvent(metadataEvent)
        case let liveActivitiesEvent as LiveActivitiesEvent:
            self.didReceiveLiveActivitiesEvent(liveActivitiesEvent)
        case let deletionEvent as DeletionEvent:
            self.didReceiveDeletionEvent(deletionEvent)
        default:
            return nil
        }

        let persistentNostrEvent: PersistentNostrEvent
        if let existingEvent = self.persistentNostrEvent(nostrEvent.id) {
            if let relay, !existingEvent.relays.contains(where: { $0 == relay.url }) {
                existingEvent.relays.append(relay.url)
            }
            persistentNostrEvent = existingEvent
        } else {
            if let relay {
                persistentNostrEvent = PersistentNostrEvent(nostrEvent: nostrEvent, relays: [relay.url])
            } else {
                persistentNostrEvent = PersistentNostrEvent(nostrEvent: nostrEvent)
            }
            self.modelContext.insert(persistentNostrEvent)
            do {
                try self.modelContext.save()
            } catch {
                print("Failed to save PersistentNostrEvent. id=\(nostrEvent.id)")
            }
        }

        return persistentNostrEvent
    }

    func loadPersistentNostrEvents(_ persistentNostrEvents: [PersistentNostrEvent]) {
        for persistentNostrEvent in persistentNostrEvents {
            switch persistentNostrEvent.nostrEvent {
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

//    func relay(_ relay: Relay, didReceive response: RelayResponse) {
//        DispatchQueue.main.async {
//            switch response {
//            case let .eose(subscriptionId):
//                // Live new events are not strictly needed for this app for now.
//                // In the future, we could keep subscriptions open for updates.
//                try? relay.closeSubscription(with: subscriptionId)
//                self.updateRelaySubscriptionCounts(closedSubscriptionId: subscriptionId)
//            case let .closed(subscriptionId, _):
//                self.updateRelaySubscriptionCounts(closedSubscriptionId: subscriptionId)
//            case let .ok(eventId, success, message):
//                if success {
//                    if let persistentNostrEvent = self.persistentNostrEvent(eventId), !persistentNostrEvent.relays.contains(relay.url) {
//                        persistentNostrEvent.relays.append(relay.url)
//                    }
//                } else if message.prefix == .rateLimited {
//                    // TODO retry with exponential backoff.
//                }
//            default:
//                break
//            }
//        }
//    }

    func updateRelaySubscriptionCounts(closedSubscriptionId: String) {
        if let metadataSubscriptionCount = metadataSubscriptionCounts[closedSubscriptionId] {
            if metadataSubscriptionCount <= 1 {
                metadataSubscriptionCounts.removeValue(forKey: closedSubscriptionId)
            } else {
                metadataSubscriptionCounts[closedSubscriptionId] = metadataSubscriptionCount - 1
            }
        }

        if let bootstrapSubscriptionCount = bootstrapSubscriptionCounts[closedSubscriptionId] {
            if bootstrapSubscriptionCount <= 1 {
                bootstrapSubscriptionCounts.removeValue(forKey: closedSubscriptionId)
            } else {
                bootstrapSubscriptionCounts[closedSubscriptionId] = bootstrapSubscriptionCount - 1
            }
        }

        if let liveActivityEventSubscriptionCount = liveActivityEventSubscriptionCounts[closedSubscriptionId] {
            if liveActivityEventSubscriptionCount <= 1 {
                liveActivityEventSubscriptionCounts.removeValue(forKey: closedSubscriptionId)

                // Wait until we have fetched all the live activities before fetching metadata in bulk.
                pullMissingEventsFromPubkeysAndFollows(liveActivitiesEvents.values.map { $0.pubkey })
            } else {
                liveActivityEventSubscriptionCounts[closedSubscriptionId] = liveActivityEventSubscriptionCount - 1
            }
        }
    }
    
    func updateLiveActivitiesTrie(oldEvent: LiveActivitiesEvent? = nil, newEvent: LiveActivitiesEvent) {
        guard let eventCoordinates = newEvent.replaceableEventCoordinates()?.tag.value else {
            return
        }

        if let oldEvent, oldEvent.createdAt >= newEvent.createdAt {
            return
        }

        let newTitle = newEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty
        let newSummary = newEvent.firstValueForRawTagName("summary")?.trimmedOrNilIfEmpty

        if let oldEvent {
            liveActivitiesTrie.remove(key: oldEvent.id, value: eventCoordinates)
            if let oldTitle = oldEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty, oldTitle != newTitle {
                liveActivitiesTrie.remove(key: oldTitle, value: eventCoordinates)
            }
            if let oldSummary = oldEvent.firstValueForRawTagName("summary")?.trimmedOrNilIfEmpty, oldSummary != newSummary {
                liveActivitiesTrie.remove(key: oldSummary, value: eventCoordinates)
            }
        }

        _ = liveActivitiesTrie.insert(key: newEvent.id, value: eventCoordinates)
        _ = liveActivitiesTrie.insert(key: newEvent.pubkey, value: eventCoordinates)
        if let identifier = newEvent.firstValueForRawTagName("identifier") {
            _ = liveActivitiesTrie.insert(key: identifier, value: eventCoordinates)
        }
        if let newTitle {
            _ = liveActivitiesTrie.insert(key: newTitle, value: eventCoordinates, options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches, .includeNonPrefixedMatches])
        }
        if let newSummary {
            _ = liveActivitiesTrie.insert(key: newSummary, value: eventCoordinates, options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches, .includeNonPrefixedMatches])
        }
    }
    
    private func deleteFromEventCoordinates(_ deletionEvent: DeletionEvent) {
        let deletedEventCoordinates = deletionEvent.eventCoordinates.filter {
            $0.pubkey?.hex == deletionEvent.pubkey
        }

        for deletedEventCoordinate in deletedEventCoordinates {
            if let existingDeletedEventCoordinateDate = self.deletedEventCoordinates[deletedEventCoordinate.tag.value] {
                if existingDeletedEventCoordinateDate < deletionEvent.createdDate {
                    self.deletedEventCoordinates[deletedEventCoordinate.tag.value] = deletionEvent.createdDate
                } else {
                    continue
                }
            } else {
                self.deletedEventCoordinates[deletedEventCoordinate.tag.value] = deletionEvent.createdDate
            }

            switch deletedEventCoordinate.kind {
//            case .timeBasedCalendarEvent:
//                if let timeBasedCalendarEvent = timeBasedCalendarEvents[deletedEventCoordinate.tag.value], timeBasedCalendarEvent.createdAt <= deletionEvent.createdAt {
//                    timeBasedCalendarEvents.removeValue(forKey: deletedEventCoordinate.tag.value)
//                    calendarEventsToRsvps.removeValue(forKey: deletedEventCoordinate.tag.value)
//                }
//            case .calendarEventRSVP:
//                if let rsvp = rsvps[deletedEventCoordinate.tag.value], rsvp.createdAt <= deletionEvent.createdAt {
//                    rsvps.removeValue(forKey: deletedEventCoordinate.tag.value)
//                    if let calendarEventCoordinates = rsvp.calendarEventCoordinates?.tag.value {
//                        calendarEventsToRsvps[calendarEventCoordinates]?.removeAll(where: { $0 == rsvp })
//                    }
//                }
            default:
                continue
            }
        }
    }

    private func deleteFromEventIds(_ deletionEvent: DeletionEvent) {
        for deletedEventId in deletionEvent.deletedEventIds {
            if let persistentNostrEvent = persistentNostrEvent(deletedEventId) {
                let nostrEvent = persistentNostrEvent.nostrEvent

                guard nostrEvent.pubkey == deletionEvent.pubkey else {
                    continue
                }

                switch nostrEvent {
                case _ as FollowListEvent:
                    followListEvents.removeValue(forKey: nostrEvent.pubkey)
                case _ as MetadataEvent:
                    metadataEvents.removeValue(forKey: nostrEvent.pubkey)
//                case let timeBasedCalendarEvent as TimeBasedCalendarEvent:
//                    if let eventCoordinates = timeBasedCalendarEvent.replaceableEventCoordinates()?.tag.value, timeBasedCalendarEvents[eventCoordinates]?.id == timeBasedCalendarEvent.id {
//                        timeBasedCalendarEvents.removeValue(forKey: eventCoordinates)
//                        calendarEventsToRsvps.removeValue(forKey: eventCoordinates)
//                    }
//                case let calendarListEvent as CalendarListEvent:
//                    if let eventCoordinates = calendarListEvent.replaceableEventCoordinates()?.tag.value, calendarListEvents[eventCoordinates]?.id == calendarListEvent.id {
//                        calendarListEvents.removeValue(forKey: eventCoordinates)
//                    }
//                case let rsvp as CalendarEventRSVP:
//                    if let eventCoordinates = rsvp.replaceableEventCoordinates()?.tag.value, rsvps[eventCoordinates]?.id == rsvp.id {
//                        rsvps.removeValue(forKey: eventCoordinates)
//
//                        if let calendarEventCoordinates = rsvp.calendarEventCoordinates?.tag.value {
//                            calendarEventsToRsvps[calendarEventCoordinates]?.removeAll(where: { $0.id == rsvp.id })
//                        }
//                    }
//
//                    rsvps.removeValue(forKey: nostrEvent.pubkey)
                default:
                    continue
                }

                modelContext.delete(persistentNostrEvent)
                do {
                    try modelContext.save()
                } catch {
                    print("Unable to delete PersistentNostrEvent with id \(deletedEventId)")
                }
            }
        }
    }


}

enum HomeTabs {
    case events
    case calendars
}
