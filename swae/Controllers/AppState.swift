//
//  AppState.swift
//  swae
//
//  Created by Suhail Saqan on 8/22/24.
//

import Foundation
import NostrSDK
import OrderedCollections
import Security
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
    static let defaultRelayURLStrings = [
        "wss://relay.damus.io",
        "wss://relay.snort.social",
        "wss://relay.primal.net",
        "wss://relay.coinos.io",
    ]

    let id = UUID()

    let privateKeySecureStorage = PrivateKeySecureStorage()

    let modelContext: ModelContext

    let nostrWalletConnectStorage = NostrWalletConnectKeyStorage()
    private var relayEventProcessor: RelayEventProcessor?

    @Published var relayReadPool: RelayPool = RelayPool(relays: [])
    @Published var relayWritePool: RelayPool = RelayPool(relays: [])

    @Published var followListEvents: [String: FollowListEvent] = [:]
    @Published var metadataEvents: [String: MetadataEvent] = [:]
    @Published var liveActivitiesEvents: [String: [LiveActivitiesEvent]] = [:]
    @Published var liveChatMessagesEvents: [String: [LiveChatMessageEvent]] = [:]
    @Published var zapReceiptEvents: [String: [LightningZapsReceiptEvent]] = [:]
    @Published var eventZapTotals: [String: Int64] = [:]
    
    // Raid events per stream coordinate (Kind 1312)
    @Published var raidEvents: [String: [LiveStreamRaidEvent]] = [:]

    // Clip events (Kind 1313)
    @Published var clipEvents: [LiveStreamClipEvent] = []
    
    // NIP-30 Custom Emoji: shortcode → imageURL, populated from kind 10030/30030 events
    var emojiPackCache: [String: URL] = [:]
    
    // NIP-30 Emoji pack service (loads and merges emoji packs)
    var emojiPackService: EmojiPackService?
    
    // Short events (Kind 22 + legacy 34236)
    @Published var shortEvents: [VideoEvent] = []

    // Zap collections for easy access
    @Published var zapRequests: [LightningZapRequestEvent] = []
    @Published var zapReceipts: [LightningZapsReceiptEvent] = []
    @Published var deletedEventIds = Set<String>()
    
    // O(1) duplicate detection Sets for chat messages and zaps (Fix #1)
    // These mirror the arrays above but provide O(1) lookup instead of O(n)
    private var chatMessageIdSets: [String: Set<String>] = [:]
    private var zapReceiptIdSets: [String: Set<String>] = [:]
    private var globalZapReceiptIds: Set<String> = []
    private var globalZapRequestIds: Set<String> = []
    
    // O(1) duplicate detection for raid events
    private var raidEventIdSets: [String: Set<String>] = [:]
    
    // O(1) duplicate detection for clips and shorts
    private var clipEventIds: Set<String> = []
    private var shortEventIds: Set<String> = []
    
    // Callback for zap plasma effect - called when a new zap is received for the current stream
    var onZapReceived: ((Int64) -> Void)?
    
    // Pending event OK callbacks — called when a relay confirms event acceptance (NIP-20)
    // Used by LiveChatController to confirm message delivery without waiting for echo-back.
    // Key: eventId, Value: callback(success)
    var pendingEventOKCallbacks: [String: (Bool) -> Void] = [:]
    @Published var deletedEventCoordinates = [String: Date]()

    @Published var followedPubkeys = Set<String>()

    @Published var eventsTrie = Trie<String>()
    @Published var liveActivitiesTrie = Trie<String>()
    @Published var pubkeyTrie = Trie<String>()

    @Published var playerConfig: PlayerConfig = .init()

    @Published var wallet: WalletModel?

    // Track active profile changes for UI updates
    @Published var activeProfileId: String?

    // Cached public key to avoid repeated database fetches
    private var cachedPublicKey: PublicKey?
    private var cachedPublicKeyHex: String?

    // Cached keypair to avoid repeated Keychain reads + Keypair construction
    private var cachedKeypair: Keypair?
    private var cachedKeypairPublicKeyHex: String?

    // Centralized dedupe/replace logic for all Nostr events
    let eventStore = NostrEventStore()

    // WebRTC collab call signaling service — set by Model when a call is active.
    // When nil, kind 4 events in the default branch are a no-op (see Safety Analysis Mod 3).
    var callSignalingService: CallSignalingService?

    // Always-on kind 4 subscription for receiving collab invites.
    // Started by Model.startCollabSignalingListener() after relay connection.
    private var collabSignalingSubscriptionId: String?
    private var _relayEventCounter: Int = 0
    private(set) var collabSignalingRelays: [Relay] = []
    var _pendingCollabFilter: Filter?
    private var collabPollingTimer: Timer?
    private var collabLastPollTimestamp: Int = Int(Date().timeIntervalSince1970)

    // Keep track of relay pool active subscriptions and the until filter so that we can limit the scope of how much we query from the relay pools.
    var metadataSubscriptionCounts = [String: Int]()
    var bootstrapSubscriptionCounts = [String: Int]()
    var liveActivityEventSubscriptionCounts = [String: Int]()
    var liveChatSubscriptionCounts: [String: String] = [:]
    var followListEventSubscriptionCounts: [String: String] = [:]
    var clipSubscriptionCounts = [String: Int]()
    var shortSubscriptionCounts = [String: Int]()
    var globalZapSubscriptionCounts = [String: Int]()
    var ownLiveEventSubscriptionIds: Set<String> = []
    var ownLiveEventSubscriptionPubkeys: [String: String] = [:]  // subscriptionId → pubkey
    
    // MARK: - Initial Sync State
    
    /// Whether the app is waiting for the first relay data before displaying content.
    /// While true, the UI shows skeleton loading state and suppresses section rebuilds.
    /// Set to false when: (a) EOSE received for liveActivities, or (b) fallback timer fires.
    @Published var isInitialSyncInProgress = false

    /// Feature flag: set to true to enable clips & shorts subscriptions and display.
    /// Flip this single flag to re-enable clips/shorts everywhere.
    static let clipsAndShortsEnabled = false
    
    /// Callback fired exactly once when initial sync completes.
    /// AppCoordinator sets this to cancel the fallback timer.
    var onInitialSyncComplete: (() -> Void)?
    
    /// Whether we've received EOSE for the liveActivities subscription during initial sync.
    private var hasReceivedLiveActivitiesEOSE = false
    
    // Track which event coordinates have completed initial load (received EOSE)
    @Published var liveChatLoadComplete: Set<String> = []
    
    // Track EOSE counts per coordinate - we have 2 subscriptions (messages + zaps)
    // Only mark as complete when ALL subscriptions have received EOSE
    private var liveChatExpectedEOSECount: [String: Int] = [:]
    private var liveChatReceivedEOSECount: [String: Int] = [:]

    // Background persistence actor for off-main-thread database operations
    private let backgroundPersistence: BackgroundPersistenceActor?
    
    // Batch processing for database operations
    private var pendingEvents = [NostrEvent]()
    private let batchSize = 50
    private var batchTimer: Timer?

    // Relay reconnection attempt tracking to prevent infinite error loops
    private var relayReconnectAttempts: [URL: Int] = [:]
    private let maxRelayReconnectAttempts = 5

    init(modelContext: ModelContext, backgroundPersistence: BackgroundPersistenceActor? = nil) {
        self.modelContext = modelContext
        self.backgroundPersistence = backgroundPersistence

        // Cache public key early to avoid repeated database fetches
        self.refreshCachedPublicKey()

        // Initialize wallet first
        if let publicKey = self.cachedPublicKey {
            self.wallet = WalletModel(publicKey: publicKey, appState: self)
        } else {
            print("set to nil")
            self.wallet = nil
        }

        // Initialize activeProfileId
        self.activeProfileId = self.cachedPublicKeyHex

        // Initialize relay event processor after init completes
        DispatchQueue.main.async {
            self.relayEventProcessor = RelayEventProcessor(appState: self)
        }
    }

    /// Refreshes the cached public key from the database
    /// This should be called when the active profile changes
    private func refreshCachedPublicKey() {
        let publicKeyHex = appSettings?.activeProfile?.publicKeyHex
        if let publicKeyHex = publicKeyHex, publicKeyHex != cachedPublicKeyHex {
            cachedPublicKeyHex = publicKeyHex
            cachedPublicKey = PublicKey(hex: publicKeyHex)
        } else if publicKeyHex == nil {
            cachedPublicKeyHex = nil
            cachedPublicKey = nil
        }
        // Invalidate keypair cache when public key changes
        cachedKeypair = nil
        cachedKeypairPublicKeyHex = nil
    }

    var publicKey: PublicKey? {
        // If cache is invalid or missing, refresh it
        let currentPublicKeyHex = appSettings?.activeProfile?.publicKeyHex
        if currentPublicKeyHex != cachedPublicKeyHex {
            refreshCachedPublicKey()
        }
        return cachedPublicKey
    }

    var keypair: Keypair? {
        guard let publicKey else {
            cachedKeypair = nil
            cachedKeypairPublicKeyHex = nil
            return nil
        }
        if publicKey.hex == cachedKeypairPublicKeyHex, let cached = cachedKeypair {
            return cached
        }
        let kp = privateKeySecureStorage.keypair(for: publicKey)
        cachedKeypair = kp
        cachedKeypairPublicKeyHex = publicKey.hex
        return kp
    }

    // MARK: - Cached Events
    
    /// Cache for flattened live activities events
    /// Invalidated when liveActivitiesEvents is modified
    private var _cachedAllEvents: [LiveActivitiesEvent]?
    
    /// Returns all live activities events as a flat array.
    /// Results are cached and invalidated when liveActivitiesEvents changes.
    func getAllEvents() -> [LiveActivitiesEvent] {
        if let cached = _cachedAllEvents {
            return cached
        }
        let events = liveActivitiesEvents.values.flatMap { $0 }
        _cachedAllEvents = events
        return events
    }
    
    /// Invalidates the cached events. Call this when liveActivitiesEvents is modified.
    private func invalidateEventsCache() {
        _cachedAllEvents = nil
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

    // MARK: - Initial Sync Completion Tracking

    /// Checks if the initial sync should complete based on an EOSE for a subscription.
    /// Called from the EOSE handler in relay(_:didReceive response:).
    func checkInitialSyncCompletion(forSubscriptionId subscriptionId: String) {
        guard isInitialSyncInProgress else { return }

        // We only care about the liveActivities subscription EOSE.
        // It populates the hero, "Live Now", "Following", and "Replays" sections.
        if liveActivityEventSubscriptionCounts[subscriptionId] != nil {
            hasReceivedLiveActivitiesEOSE = true
            
            // Delay 500ms to let in-flight events settle before transitioning.
            // Events arrive via 2 Task.detached hops; EOSE via 1 Task hop.
            // EOSE consistently wins the race. 500ms lets the event pipeline drain.
            // The delay is here (not in finishInitialSync) because the fallback timer
            // path also calls finishInitialSync and must NOT be delayed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.isInitialSyncInProgress else { return }
                self.finishInitialSync()
            }
        }
    }

    /// Completes the initial sync phase, transitioning from skeleton to content.
    func finishInitialSync() {
        guard isInitialSyncInProgress else { return }
        isInitialSyncInProgress = false
        hasReceivedLiveActivitiesEOSE = false
        print("📊 Initial relay sync complete")
        onInitialSyncComplete?()
        onInitialSyncComplete = nil
    }

    /// Returns live activities events for a specific profile.
    /// Filters by pubkey as author or as host participant.
    func profileEvents(_ publicKeyHex: String) -> [LiveActivitiesEvent] {
        return getAllEvents().filter { event in
            event.hostPubkeyHex == publicKeyHex
        }
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
            .filter { $0.write }
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
        
        // Initialize emoji pack service and load packs for current user
        if emojiPackService == nil {
            emojiPackService = EmojiPackService(appState: self)
        }
        if let userPubkey = keypair?.publicKey.hex {
            emojiPackService?.loadPacks(userPubkey: userPubkey, streamerPubkey: nil)
        }
    }

    /// Tears down existing relay connections and creates fresh ones.
    /// Must be called when the app returns to foreground after iOS suspension,
    /// because the underlying URLSessionWebSocketTasks become stale and cannot reconnect.
    func reconnectRelays() {
        // Clear own live event tracking — old subscription IDs are about to become invalid.
        // The caller (Model) is responsible for re-subscribing if still streaming.
        ownLiveEventSubscriptionIds.removeAll()
        ownLiveEventSubscriptionPubkeys.removeAll()

        let readSettings = relayPoolSettings?.relaySettingsList.filter { $0.read } ?? []
        let writeSettings = relayPoolSettings?.relaySettingsList.filter { $0.write } ?? []

        // Reset reconnect attempt tracking
        relayReconnectAttempts.removeAll()

        // Tear down old read relays and create fresh ones
        let oldReadRelays = relayReadPool.relays
        oldReadRelays.forEach { relayReadPool.remove(relay: $0) }

        relayReadPool.delegate = self
        for setting in readSettings {
            if let url = URL(string: setting.relayURLString),
               let relay = try? Relay(url: url) {
                relayReadPool.add(relay: relay)
            }
        }

        // Tear down old write relays and create fresh ones
        let oldWriteRelays = relayWritePool.relays
        oldWriteRelays.forEach { relayWritePool.remove(relay: $0) }

        relayWritePool.delegate = self
        for setting in writeSettings {
            if let url = URL(string: setting.relayURLString),
               let relay = try? Relay(url: url) {
                relayWritePool.add(relay: relay)
            }
        }

        print("Reconnected relay pools: \(relayReadPool.relays.count) read, \(relayWritePool.relays.count) write")

        // Re-subscribe and refresh after reconnection
        // refresh() handles republishing unpublished events via publishUnpublishedEventsAsync()
        refresh()
        if let currentUserPubkey = publicKey?.hex {
            pullMissingEventsFromPubkeysAndFollows([currentUserPubkey])
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
        guard let authorPubkey = publicKey?.hex else { return [] }
        let descriptor = FetchDescriptor<PersistentNostrEvent>(
            predicate: #Predicate { $0.relays == [] }
        )
        // Only republish events authored by the current user
        return ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.nostrEvent.pubkey == authorPubkey
        }
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
        // Delete all secrets associated with this profile
        if let publicKeyHex = profile.publicKeyHex,
            let publicKey = PublicKey(hex: publicKeyHex)
        {
            privateKeySecureStorage.delete(for: publicKey)
            nostrWalletConnectStorage.delete(for: publicKey)

            // Remove SharedWebCredential from iCloud Keychain
            // Passing nil as the password effectively deletes the credential
            SecAddSharedWebCredential("swae.live" as CFString, publicKey.npub as CFString, nil) { error in
                if let error {
                    print("⚠️ Failed to remove shared credential: \(error)")
                }
            }
        }

        // Handle active profile switching
        if let appSettings, appSettings.activeProfile == profile {
            // Try to find another profile to switch to
            if let newProfile = profiles.first(where: { $0 != profile }) {
                updateActiveProfile(newProfile)
            } else {
                // No other profiles exist, create a default guest profile
                let defaultProfile = Profile(publicKeyHex: nil)
                modelContext.insert(defaultProfile)
                do {
                    try modelContext.save()
                } catch {
                    print("Unable to save default profile after deletion")
                }
                updateActiveProfile(defaultProfile)
            }
            refreshFollowedPubkeys()
        }

        modelContext.delete(profile)
    }

    func updateActiveProfile(_ profile: Profile) {
        guard let appSettings, appSettings.activeProfile != profile else {
            return
        }

        appSettings.activeProfile = profile

        // Refresh cached public key when profile changes
        refreshCachedPublicKey()

        // Update the published activeProfileId to trigger UI updates
        activeProfileId = profile.publicKeyHex

        // Update wallet for the new profile
        if let publicKey = self.cachedPublicKey {
            self.wallet = WalletModel(publicKey: publicKey, appState: self)
        } else {
            self.wallet = nil
        }

        followedPubkeys.removeAll()

        if profile.publicKeyHex == nil {
            // empty for now
        } else if cachedPublicKey != nil {
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

            // Refresh cached public key when profile changes
            refreshCachedPublicKey()

            activeProfileId = profile.publicKeyHex

            // Update wallet for the profile
            if let publicKey = self.cachedPublicKey {
                self.wallet = WalletModel(publicKey: publicKey, appState: self)
            } else {
                self.wallet = nil
            }
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

            // Refresh cached public key when profile changes
            refreshCachedPublicKey()

            activeProfileId = profile.publicKeyHex

            // Update wallet for the profile
            if let publicKey = self.cachedPublicKey {
                self.wallet = WalletModel(publicKey: publicKey, appState: self)
            } else {
                self.wallet = nil
            }

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
        // Relay delegate may be called from any thread, ensure main thread for state updates
        Task { @MainActor in
            guard self.relayReadPool.relays.contains(relay) || self.relayWritePool.relays.contains(relay) || self.collabSignalingRelays.contains(where: { $0 === relay }) else {
                print(
                    "Relay \(relay.url.absoluteString) changed state to \(state) but it is not in the read or write relay pool. Doing nothing."
                )
                return
            }

            print("Relay \(relay.url.absoluteString) changed state to \(state)")
            switch state {
            case .connected:
                self.relayReconnectAttempts[relay.url] = 0
                self.refresh(relay: relay)
                // Re-subscribe kind 4 for collab signaling on this relay
                self.resubscribeCollabSignaling(relay: relay)
                // If this is a dedicated signaling relay that just connected, subscribe it
                if self.collabSignalingRelays.contains(where: { $0 === relay }),
                   let filter = self._pendingCollabFilter,
                   let subId = self.collabSignalingSubscriptionId {
                    do {
                        try relay.subscribe(with: filter, subscriptionId: subId)
                        print("🔔 [COLLAB] ✅ Subscribed signaling relay \(relay.url.absoluteString) for kind 4")
                    } catch {
                        print("🔔 [COLLAB] Failed to subscribe signaling relay: \(error)")
                    }
                }
            case .notConnected, .error:
                let attempts = self.relayReconnectAttempts[relay.url, default: 0]
                guard attempts < self.maxRelayReconnectAttempts else {
                    print("Relay \(relay.url.absoluteString) exceeded max reconnect attempts (\(self.maxRelayReconnectAttempts)), waiting for foreground reconnect")
                    return
                }
                self.relayReconnectAttempts[relay.url] = attempts + 1
                relay.connect()
            default:
                break
            }
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
                        EventKind.metadata.rawValue
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

    /// Start a dedicated kind 4 subscription for receiving collab call invites.
    /// Uses both the user's relay pool AND a dedicated signaling relay that supports kind 4.
    /// Many popular relays (damus, snort, coinos) block kind 4 events.
    func startCollabSignalingSubscription() {
        guard collabSignalingSubscriptionId == nil else {
            print("🔔 [COLLAB] Kind 4 subscription already active, subId=\(collabSignalingSubscriptionId ?? "nil")")
            return
        }
        guard let publicKey = self.publicKey else {
            print("🔔 [COLLAB] ⚠️ Cannot start kind 4 subscription — no public key!")
            return
        }

        print("🔔 [COLLAB] Starting kind 4 subscription for pubkey=\(publicKey.hex.prefix(8))...")
        print("🔔 [COLLAB] Connected relays: \(relayReadPool.relays.map { "\($0.url.absoluteString) (state: \($0.state))" })")

        guard let filter = Filter(
            kinds: [EventKind.legacyEncryptedDirectMessage.rawValue],
            pubkeys: [publicKey.hex],
            since: Int(Date().addingTimeInterval(-60).timeIntervalSince1970)
        ) else {
            print("🔔 [COLLAB] ⚠️ Failed to create kind 4 subscription filter")
            return
        }

        // Subscribe on the user's existing relay pool
        collabSignalingSubscriptionId = relayReadPool.subscribe(with: filter)
        print("🔔 [COLLAB] ✅ Kind 4 subscription on user relays, subId=\(collabSignalingSubscriptionId ?? "nil")")

        if let filterData = try? JSONEncoder().encode(filter),
           let filterJson = String(data: filterData, encoding: .utf8) {
            print("🔔 [COLLAB] Filter JSON: \(filterJson)")
        }

        // Also connect a dedicated signaling relay that supports kind 4.
        connectCollabSignalingRelay(filter: filter)

        // Start polling — many relays don't forward real-time kind 4 events after EOSE.
        // Re-subscribe every 5 seconds with an updated `since` to catch new events.
        startCollabSignalingPoll()
    }

    private func startCollabSignalingPoll() {
        collabPollingTimer?.invalidate()
        collabLastPollTimestamp = Int(Date().timeIntervalSince1970)
        collabPollingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.pollForSignalingEvents()
        }
    }

    /// Pause kind 4 polling during an active call (no need to poll for new invites).
    func pauseCollabSignalingPoll() {
        collabPollingTimer?.invalidate()
        collabPollingTimer = nil
    }

    /// Resume kind 4 polling after a call ends.
    func resumeCollabSignalingPoll() {
        guard collabPollingTimer == nil, collabSignalingSubscriptionId != nil else { return }
        startCollabSignalingPoll()
    }

    /// Change the poll interval for adaptive signaling speed.
    /// Fast (2-3s) during call setup, slow (15s) when idle.
    func setCollabSignalingPollInterval(_ interval: TimeInterval) {
        collabPollingTimer?.invalidate()
        collabPollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollForSignalingEvents()
        }
    }

    /// Trigger an immediate poll — don't wait for the next timer tick.
    /// Call after sending a signaling message to catch the response that may already be on the relay.
    func pollCollabSignalingNow() {
        pollForSignalingEvents()
    }

    private func pollForSignalingEvents() {
        guard let publicKey = self.publicKey else { return }
        guard let subId = collabSignalingSubscriptionId else { return }

        // Close old subscription and re-subscribe with updated since
        relayReadPool.closeSubscription(with: subId)
        for relay in collabSignalingRelays where relay.state == .connected {
            try? relay.closeSubscription(with: subId)
        }

        let since = collabLastPollTimestamp - 2  // 2 second overlap for safety
        guard let filter = Filter(
            kinds: [EventKind.legacyEncryptedDirectMessage.rawValue],
            pubkeys: [publicKey.hex],
            since: since
        ) else { return }

        let newSubId = relayReadPool.subscribe(with: filter, subscriptionId: subId)
        for relay in collabSignalingRelays where relay.state == .connected {
            try? relay.subscribe(with: filter, subscriptionId: subId)
        }
        collabLastPollTimestamp = Int(Date().timeIntervalSince1970)
        collabSignalingSubscriptionId = newSubId
    }

    /// Dedicated relay for kind 4 signaling. Kept separate from the user's relay pool.
    private static let signalingRelayURLs: [String] = [
        "wss://nos.lol",
        "wss://relay.nostr.band",
    ]

    private func connectCollabSignalingRelay(filter: Filter) {
        for urlString in Self.signalingRelayURLs {
            guard let url = URL(string: urlString) else { continue }
            // Skip if already in the user's pool
            if relayReadPool.relays.contains(where: { $0.url.absoluteString == urlString }) {
                print("🔔 [COLLAB] Signaling relay \(urlString) already in user pool, skipping")
                continue
            }
            do {
                let relay = try Relay(url: url)
                relay.delegate = self
                relay.connect()
                collabSignalingRelays.append(relay)
                print("🔔 [COLLAB] Connecting dedicated signaling relay: \(urlString)")

                // Subscribe once connected (observe state change)
                // The relay will call relayStateDidChange → .connected → resubscribeCollabSignaling
                // But we also need to subscribe after initial connect, so store the filter
                _pendingCollabFilter = filter
            } catch {
                print("🔔 [COLLAB] Failed to create signaling relay \(urlString): \(error)")
            }
        }
    }

    /// Pending filter to apply when signaling relays connect.

    /// Re-subscribe kind 4 on a specific relay after it reconnects.
    func resubscribeCollabSignaling(relay: Relay) {
        guard let subId = collabSignalingSubscriptionId else { return }
        guard let publicKey = self.publicKey else { return }
        guard let filter = Filter(
            kinds: [EventKind.legacyEncryptedDirectMessage.rawValue],
            pubkeys: [publicKey.hex],
            since: Int(Date().timeIntervalSince1970)
        ) else { return }
        do {
            try relay.subscribe(with: filter, subscriptionId: subId)
            print("🔔 [COLLAB] Re-subscribed kind 4 on reconnected relay: \(relay.url.absoluteString)")
        } catch {
            print("🔔 [COLLAB] Failed to re-subscribe kind 4 on \(relay.url.absoluteString): \(error)")
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

        // Use async version to avoid blocking main thread
        publishUnpublishedEventsAsync()

        // Clips subscription (kind 1313)
        if Self.clipsAndShortsEnabled, clipSubscriptionCounts.isEmpty {
            // No `since` — always fetch the most recent clips.
            // No `until` — keep subscription open for new clips arriving in real-time.
            if let clipsFilter = Filter(
                kinds: [EventKind.liveStreamClip.rawValue],
                limit: 50
            ) {
                print("📎 Subscribing to clips (kind 1313)")
                if let subId = try? subscribe(filter: clipsFilter, relay: relay) {
                    clipSubscriptionCounts[subId] = 1
                    print("📎 Clips subscription created: \(subId)")
                } else {
                    print("📎 Failed to create clips subscription")
                }
            } else {
                print("📎 Failed to create clips filter")
            }
        }

        // Shorts subscription (kind 22 + legacy 34236)
        if Self.clipsAndShortsEnabled, shortSubscriptionCounts.isEmpty {
            // No `since` — always fetch the most recent shorts.
            // No `until` — keep subscription open for new shorts arriving in real-time.
            if let shortsFilter = Filter(
                kinds: [22, 34236],
                limit: 50
            ) {
                print("🎬 Subscribing to shorts (kind 22+34236)")
                if let subId = try? subscribe(filter: shortsFilter, relay: relay) {
                    shortSubscriptionCounts[subId] = 1
                    print("🎬 Shorts subscription created: \(subId)")
                } else {
                    print("🎬 Failed to create shorts subscription")
                }
            } else {
                print("🎬 Failed to create shorts filter")
            }
        }

        // Global recent zaps for top streamers ranking (last 24h)
        if globalZapSubscriptionCounts.isEmpty {
            let recentZapsSince = Int(Date.now.addingTimeInterval(-24 * 3600).timeIntervalSince1970)
            if let recentZapsFilter = Filter(
                kinds: [EventKind.zapReceipt.rawValue],
                since: recentZapsSince,
                until: Int(until.timeIntervalSince1970),
                limit: 500
            ) {
                if let subId = try? subscribe(filter: recentZapsFilter, relay: relay) {
                    globalZapSubscriptionCounts[subId] = 1
                }
            }
        }
    }

    // MARK: - Pending Event Confirmation (NIP-20 OK Response)
    
    /// Registers a callback to be invoked when a relay confirms event acceptance.
    /// Only the first successful OK triggers the callback; failures are ignored
    /// (the timeout in LiveChatController is the fallback for rejected events).
    func registerPendingConfirmation(eventId: String, callback: @escaping (Bool) -> Void) {
        pendingEventOKCallbacks[eventId] = callback
    }

    private func publishUnpublishedEvents() {
        for persistentNostrEvent in unpublishedPersistentNostrEvents {
            relayWritePool.publishEvent(persistentNostrEvent.nostrEvent)
        }
    }

    private func didReceiveFollowListEvent(
        _ followListEvent: FollowListEvent, shouldPullMissingEvents: Bool = false
    ) {
        // Nostr replaceable event deduplication: only keep the latest per pubkey (tie-break by id)
        if let existingFollowList = self.followListEvents[followListEvent.pubkey] {
            if !NostrEventStore.shouldReplace(old: existingFollowList, with: followListEvent) {
                return
            }
        }
        cache(followListEvent, shouldPullMissingEvents: shouldPullMissingEvents)
    }

    private func cache(_ followListEvent: FollowListEvent, shouldPullMissingEvents: Bool) {
        self.followListEvents[followListEvent.pubkey] = followListEvent
        
        // Enforce memory limit - remove oldest entries when limit exceeded
        if self.followListEvents.count > CollectionLimits.maxFollowListEvents {
            // Find and remove the oldest entries (by createdAt timestamp)
            let sortedByAge = self.followListEvents.sorted { $0.value.createdAt < $1.value.createdAt }
            let toRemove = sortedByAge.prefix(self.followListEvents.count - CollectionLimits.maxFollowListEvents)
            for (pubkey, _) in toRemove {
                self.followListEvents.removeValue(forKey: pubkey)
            }
        }

        if shouldPullMissingEvents {
            pullMissingEventsFromPubkeysAndFollows(followListEvent.followedPubkeys)
        }

        if followListEvent.pubkey == publicKey?.hex {
            refreshFollowedPubkeys()
        }
    }

    private func didReceiveMetadataEvent(_ metadataEvent: MetadataEvent) {
        // NOTE: This method is called on the main thread from didReceive(nostrEvent:)
        
        // Capture new metadata values
        let newUserMetadata = metadataEvent.userMetadata
        let newName = newUserMetadata?.name?.trimmedOrNilIfEmpty
        let newDisplayName = newUserMetadata?.displayName?.trimmedOrNilIfEmpty

        // Check existing metadata for deduplication (already on main thread)
        let existingMetadataEvent = self.metadataEvents[metadataEvent.pubkey]
        
        if let existingMetadataEvent = existingMetadataEvent {
            // Nostr replaceable event deduplication: ignore older or equal by tie-break
            if !NostrEventStore.shouldReplace(old: existingMetadataEvent, with: metadataEvent) {
                return
            }
            
            // Remove old trie entries if names changed
            if let existingUserMetadata = existingMetadataEvent.userMetadata {
                if let existingName = existingUserMetadata.name?.trimmedOrNilIfEmpty,
                    existingName != newName
                {
                    pubkeyTrie.remove(key: existingName, value: existingMetadataEvent.pubkey)
                }
                if let existingDisplayName = existingUserMetadata.displayName?.trimmedOrNilIfEmpty,
                    existingDisplayName != newDisplayName
                {
                    pubkeyTrie.remove(key: existingDisplayName, value: existingMetadataEvent.pubkey)
                }
            }
        }

        // Update the metadata dictionary synchronously (we're already on main thread)
        self.metadataEvents[metadataEvent.pubkey] = metadataEvent
        
        // Enforce memory limit - remove oldest entries when limit exceeded
        if self.metadataEvents.count > CollectionLimits.maxMetadataEvents {
            let sortedByAge = self.metadataEvents.sorted { $0.value.createdAt < $1.value.createdAt }
            let toRemove = sortedByAge.prefix(self.metadataEvents.count - CollectionLimits.maxMetadataEvents)
            for (pubkey, _) in toRemove {
                self.metadataEvents.removeValue(forKey: pubkey)
            }
        }

        // Update trie with new entries
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

        // Update cached display metadata on the Profile model if this pubkey belongs to a local profile
        if let profile = profiles.first(where: { $0.publicKeyHex == metadataEvent.pubkey }),
           let userMetadata = metadataEvent.userMetadata {
            let newDisplayName = userMetadata.displayName ?? userMetadata.name
            let newUsername = userMetadata.name
            let newPictureURL = userMetadata.pictureURL?.absoluteString
            if profile.cachedDisplayName != newDisplayName
                || profile.cachedUsername != newUsername
                || profile.cachedProfilePictureURL != newPictureURL {
                profile.cachedDisplayName = newDisplayName
                profile.cachedUsername = newUsername
                profile.cachedProfilePictureURL = newPictureURL
                try? modelContext.save()
            }
        }
    }

    private func didReceiveLiveActivitiesEvent(_ liveActivitiesEvent: LiveActivitiesEvent) {
        // Accept events even if 'starts' tag is missing (older events). Only require valid coordinates.
        guard let eventCoordinates = liveActivitiesEvent.coordinateTag
        else {
            return
        }

        // If this coordinate has been deleted after this event's timestamp, ignore it.
        if let deletedAt = deletedEventCoordinates[eventCoordinates],
            liveActivitiesEvent.createdDate <= deletedAt
        {
            return
        }

        // Drop expired events if NIP-40 expiration present and passed.
        if let expirationStr = liveActivitiesEvent.firstValueForRawTagName("expiration"),
            let expiration = Int64(expirationStr),
            expiration <= Int64(Date().timeIntervalSince1970)
        {
            return
        }

        // Handle Nostr replaceable event deduplication
        if let existingEvents = liveActivitiesEvents[eventCoordinates] {
            // Find the most recent event for this coordinate
            if let mostRecentEvent = existingEvents.max(by: { $0.createdAt < $1.createdAt }) {
                // If incoming event is older or equal (tie-break by id), ignore it
                if !NostrEventStore.shouldReplace(old: mostRecentEvent, with: liveActivitiesEvent) {
                    return
                }
                // If incoming event is newer, we'll replace the old one
                updateLiveActivitiesTrie(oldEvent: mostRecentEvent, newEvent: liveActivitiesEvent)
            }
        } else {
            // No existing events, just update trie with new event
            updateLiveActivitiesTrie(newEvent: liveActivitiesEvent)
        }

        // Replace with the latest event (Nostr replaceable event semantics)
        self.replaceLiveActivity(liveActivitiesEvent, forEventCoordinate: eventCoordinates)
    }

    private func addLiveActivity(
        _ activity: LiveActivitiesEvent, toEventCoordinate coordinate: String
    ) {
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
            invalidateEventsCache()
        }
    }

    /// Replaces live activity events for a coordinate with the latest event (Nostr replaceable event semantics)
    private func replaceLiveActivity(
        _ latestActivity: LiveActivitiesEvent, forEventCoordinate coordinate: String
    ) {
        // For replaceable events in Nostr, we should only keep the latest version
        // This implements proper Nostr protocol deduplication
        liveActivitiesEvents[coordinate] = [latestActivity]
        invalidateEventsCache()
    }

    private func didReceiveZapReceiptEvent(_ zapReceipt: LightningZapsReceiptEvent) {
        guard let eventCoordinate = zapReceipt.eventCoordinate else { return }

        // NOTE: This method is called on the main thread from didReceive(nostrEvent:)
        
        // Initialize collections if needed
        if self.zapReceiptEvents[eventCoordinate] == nil {
            self.zapReceiptEvents[eventCoordinate] = []
            self.zapReceiptIdSets[eventCoordinate] = []
        }

        // Fix #1: O(1) duplicate check via Set
        guard !self.zapReceiptIdSets[eventCoordinate]!.contains(zapReceipt.id) else {
            return
        }
        
        // Track the ID
        self.zapReceiptIdSets[eventCoordinate]!.insert(zapReceipt.id)
        self.zapReceiptEvents[eventCoordinate]!.append(zapReceipt)

        // Fix #4: O(1) memory limit enforcement using removeFirst
        // Remove oldest zaps when over limit
        while self.zapReceiptEvents[eventCoordinate]!.count > CollectionLimits.maxZapReceiptsPerEvent {
            let removed = self.zapReceiptEvents[eventCoordinate]!.removeFirst()
            self.zapReceiptIdSets[eventCoordinate]?.remove(removed.id)
        }

        // Update the total amount - handle the optional properly
        if let amount = zapReceipt.description?.amount {
            self.eventZapTotals[eventCoordinate, default: 0] += Int64(amount)
            
            // Trigger zap plasma effect callback
            self.onZapReceived?(Int64(amount))
        }

        // Also add to the global zap receipts array with O(1) duplicate check
        guard !self.globalZapReceiptIds.contains(zapReceipt.id) else { return }
        
        self.globalZapReceiptIds.insert(zapReceipt.id)
        self.zapReceipts.append(zapReceipt)
        
        // Enforce global limit (keep newest) using removeFirst
        while self.zapReceipts.count > CollectionLimits.maxGlobalZapReceipts {
            let removed = self.zapReceipts.removeFirst()
            self.globalZapReceiptIds.remove(removed.id)
        }
    }

    private func didReceiveZapRequestEvent(_ zapRequest: LightningZapRequestEvent) {
        // NOTE: This method is called on the main thread from didReceive(nostrEvent:)
        
        // Fix #1: O(1) duplicate check via Set
        guard !self.globalZapRequestIds.contains(zapRequest.id) else { return }
        
        self.globalZapRequestIds.insert(zapRequest.id)
        self.zapRequests.append(zapRequest)
        
        // Fix #4: O(1) memory limit enforcement using removeFirst
        while self.zapRequests.count > CollectionLimits.maxGlobalZapRequests {
            let removed = self.zapRequests.removeFirst()
            self.globalZapRequestIds.remove(removed.id)
        }
    }

    private func didReceiveClipEvent(_ clip: LiveStreamClipEvent) {
        print("📎 Received clip event: \(clip.id), title: \(clip.clipTitle ?? "nil"), url: \(clip.clipURL?.absoluteString ?? "nil")")
        guard !clipEventIds.contains(clip.id) else { return }
        clipEventIds.insert(clip.id)
        clipEvents.append(clip)
        clipEvents.sort { $0.createdAt > $1.createdAt }
        while clipEvents.count > CollectionLimits.maxClipEvents {
            let removed = clipEvents.removeLast()
            clipEventIds.remove(removed.id)
        }
        print("📎 Total clips: \(clipEvents.count)")
    }

    private func didReceiveShortEvent(_ short: VideoEvent) {
        print("🎬 Received short event: \(short.id), title: \(short.videoTitle ?? "nil"), url: \(short.videoURL?.absoluteString ?? "nil")")
        guard !shortEventIds.contains(short.id) else { return }
        shortEventIds.insert(short.id)
        shortEvents.append(short)
        // Sort by published_at if available, otherwise createdAt
        shortEvents.sort { a, b in
            let aDate = a.publishedAt ?? a.createdDate
            let bDate = b.publishedAt ?? b.createdDate
            return aDate > bDate
        }
        while shortEvents.count > CollectionLimits.maxShortEvents {
            let removed = shortEvents.removeLast()
            shortEventIds.remove(removed.id)
        }
    }

    /// Handles legacy short events (kind 34236) by re-encoding with kind 21 and decoding as VideoEvent.
    private func didReceiveLegacyShortEvent(_ event: NostrEvent) {
        print("🎬 Received legacy short event (kind \(event.kind.rawValue)): \(event.id)")
        guard !shortEventIds.contains(event.id) else { return }
        do {
            var jsonData = try JSONEncoder().encode(event)
            // Patch the kind to 21 so VideoEvent's decoder accepts it
            if var json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                json["kind"] = 21
                jsonData = try JSONSerialization.data(withJSONObject: json)
            }
            let shortEvent = try JSONDecoder().decode(VideoEvent.self, from: jsonData)
            didReceiveShortEvent(shortEvent)
        } catch {
            print("🎬 Failed to re-decode legacy short event: \(error)")
        }
    }

    func subscribeToLiveChat(for event: LiveActivitiesEvent) {
        guard let eventCoordinate = event.coordinateTag,
            !liveChatSubscriptionCounts.values.contains(eventCoordinate)
        else { return }

        // Create SEPARATE filters for messages and zaps to ensure balanced loading
        // A single filter with limit would return mostly the most recent event type
        
        // Filter for chat messages AND raids (Kind 1311 and 1312)
        guard
            let messageFilter = Filter(
                kinds: [
                    EventKind.liveChatMessage.rawValue,
                    EventKind.liveStreamRaid.rawValue
                ],
                tags: ["a": [eventCoordinate]],
                limit: 2000
            )
        else {
            print("Failed to create live chat message filter")
            return
        }
        
        // Filter for zap receipts (and requests for completeness)
        guard
            let zapFilter = Filter(
                kinds: [
                    EventKind.zapRequest.rawValue,
                    EventKind.zapReceipt.rawValue,
                ],
                tags: ["a": [eventCoordinate]],
                limit: 2000
            )
        else {
            print("Failed to create live chat zap filter")
            return
        }

        // Initialize EOSE tracking - we expect 2 EOSEs (one for messages, one for zaps)
        liveChatExpectedEOSECount[eventCoordinate] = 2
        liveChatReceivedEOSECount[eventCoordinate] = 0
        
        // Subscribe to both filters
        let messageSubscriptionId = relayReadPool.subscribe(with: messageFilter)
        liveChatSubscriptionCounts[messageSubscriptionId] = eventCoordinate
        
        let zapSubscriptionId = relayReadPool.subscribe(with: zapFilter)
        liveChatSubscriptionCounts[zapSubscriptionId] = eventCoordinate

    }

    func unsubscribeFromLiveChat(for event: LiveActivitiesEvent) {
        guard let eventCoordinate = event.coordinateTag else { return }
        unsubscribeFromLiveChat(forCoordinate: eventCoordinate)
    }
    
    /// Unsubscribes from live chat by coordinate string.
    /// Used when the original event reference is no longer available (e.g., after event replacement).
    func unsubscribeFromLiveChat(forCoordinate eventCoordinate: String) {
        liveChatSubscriptionCounts
            .filter { $0.value == eventCoordinate }
            .keys
            .forEach { subscriptionId in
                relayReadPool.closeSubscription(with: subscriptionId)
                liveChatSubscriptionCounts.removeValue(forKey: subscriptionId)
                liveChatMessagesEvents.removeValue(forKey: eventCoordinate)
                zapReceiptEvents.removeValue(forKey: eventCoordinate)
                raidEvents.removeValue(forKey: eventCoordinate)
                // Fix #1: Also clear the ID Sets
                chatMessageIdSets.removeValue(forKey: eventCoordinate)
                zapReceiptIdSets.removeValue(forKey: eventCoordinate)
                raidEventIdSets.removeValue(forKey: eventCoordinate)
                // Clear load complete status and EOSE tracking
                liveChatLoadComplete.remove(eventCoordinate)
                liveChatExpectedEOSECount.removeValue(forKey: eventCoordinate)
                liveChatReceivedEOSECount.removeValue(forKey: eventCoordinate)
            }
    }

    // MARK: - Own Live Event Subscription (Zap Stream Core)

    /// Subscribes to the current user's own live activities events.
    /// Used when the user goes live via zap-stream-core — the server publishes
    /// the kind 30311 event, and we need a subscription to receive it.
    /// The subscription has no `until` so it stays open for new events.
    /// Safe to call multiple times — returns immediately if already subscribed for this pubkey.
    func subscribeToOwnLiveEvent(pubkey: String) {
        guard !ownLiveEventSubscriptionPubkeys.values.contains(pubkey) else {
            print("🔌 Own live event subscription already active for pubkey=\(String(pubkey.prefix(8)))...")
            return
        }

        // Filter by #p tag (not authors) because zap-stream-core signs the event
        // with the server's key, and the user's pubkey is in the "p" tag as host.
        guard let filter = Filter(
            kinds: [EventKind.liveActivities.rawValue],
            pubkeys: [pubkey]
        ) else {
            print("⚠️ Failed to create own live event filter")
            return
        }

        let subscriptionId = relayReadPool.subscribe(with: filter)
        ownLiveEventSubscriptionIds.insert(subscriptionId)
        ownLiveEventSubscriptionPubkeys[subscriptionId] = pubkey
        print("🔌 Subscribed to own live event for pubkey=\(String(pubkey.prefix(8)))... subId=\(subscriptionId)")
    }

    /// Unsubscribes from the user's own live event subscription.
    /// Called when the stream stops.
    func unsubscribeFromOwnLiveEvent() {
        for subscriptionId in ownLiveEventSubscriptionIds {
            relayReadPool.closeSubscription(with: subscriptionId)
        }
        if !ownLiveEventSubscriptionIds.isEmpty {
            print("🔌 Unsubscribed from own live event (\(ownLiveEventSubscriptionIds.count) subscriptions)")
        }
        ownLiveEventSubscriptionIds.removeAll()
        ownLiveEventSubscriptionPubkeys.removeAll()
    }

    func subscribeToProfile(for publicKeyHex: String) {
        guard !followListEventSubscriptionCounts.values.contains(publicKeyHex) else { return }

        // Create filter with proper tag structure
        guard
            let filter = Filter(
                authors: [publicKeyHex, appSettings?.activeProfile?.publicKeyHex].compactMap { $0 },
                kinds: [
                    EventKind.metadata.rawValue,
                    EventKind.followList.rawValue,
                ],
                since: 0
            )
        else {
            print("Unable to create profile filter.")
            return
        }

        let subscriptionId = relayReadPool.subscribe(with: filter)
        followListEventSubscriptionCounts[subscriptionId] = publicKeyHex
        print("Subscribed (metadata/follow) to profile \(publicKeyHex) with ID: \(subscriptionId)")

        // One-shot historical fetch with larger window to bypass relay defaults
        // Note: This subscription is intentionally NOT tracked in followListEventSubscriptionCounts
        // because it's a one-shot fetch that will be auto-closed on EOSE by the relay response handler.
        // This is the correct behavior for historical data fetches.
        let historyLimit = 2000
        if let historyP = Filter(
            kinds: [EventKind.liveActivities.rawValue],
            tags: ["p": [publicKeyHex]],
            since: 0,
            limit: historyLimit
        ) {
            _ = relayReadPool.subscribe(with: historyP)
            print("Subscribed (history live #p) for profile \(publicKeyHex)")
        }

        // Lightweight live stream for new updates from now
        let nowTs = Int(Date().timeIntervalSince1970)
        if let liveAuthor = Filter(
            kinds: [EventKind.liveActivities.rawValue],
            tags: ["p": [publicKeyHex]],
            since: nowTs + 1
        ) {
            let liveId = relayReadPool.subscribe(with: liveAuthor)
            followListEventSubscriptionCounts[liveId] = publicKeyHex
            print("Subscribed (live author) to profile \(publicKeyHex) with ID: \(liveId)")
        }
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
        guard let eventReference = message.liveEventReference else {
            print("🔍 AppState: No event reference found for message: \(message.id)")
            return
        }

        // Use the same coordinate format as LiveActivitiesEvent.replaceableEventCoordinates()
        let eventCoordinate =
            "\(eventReference.liveEventKind):\(eventReference.pubkey):\(eventReference.d)"
        
        // NOTE: This method is called on the main thread from didReceive(nostrEvent:)
        self.addChatMessage(message, toEventCoordinate: eventCoordinate)
    }
    
    private func didReceiveLiveStreamRaidEvent(_ raid: LiveStreamRaidEvent) {
        // A raid event has two "a" tags - one for source (root) and one for target (mention)
        // We need to add the raid to BOTH streams' raid collections so it shows up in both chats
        
        if let sourceCoordinate = raid.sourceStreamCoordinate {
            self.addRaidEvent(raid, toEventCoordinate: sourceCoordinate)
        }
        
        if let targetCoordinate = raid.targetStreamCoordinate {
            self.addRaidEvent(raid, toEventCoordinate: targetCoordinate)
        }
    }
    
    private func addRaidEvent(_ raid: LiveStreamRaidEvent, toEventCoordinate coordinate: String) {
        // Initialize collections if needed
        if self.raidEvents[coordinate] == nil {
            self.raidEvents[coordinate] = []
            self.raidEventIdSets[coordinate] = []
        }
        
        // O(1) duplicate check
        guard !self.raidEventIdSets[coordinate]!.contains(raid.id) else { return }
        
        // Track the ID
        self.raidEventIdSets[coordinate]!.insert(raid.id)
        
        var raids = self.raidEvents[coordinate]!
        raids.append(raid)
        
        // Keep only recent raids (last 50)
        while raids.count > 50 {
            let removed = raids.removeFirst()
            self.raidEventIdSets[coordinate]?.remove(removed.id)
        }
        
        self.raidEvents[coordinate] = raids
        
        let direction = raid.isOutgoingRaid(from: coordinate) ? "OUTGOING" : "INCOMING"
        print("🌊 Raid received (\(direction)) for \(coordinate) from \(raid.pubkey.prefix(8))...")
    }

    private func addChatMessage(
        _ message: LiveChatMessageEvent, toEventCoordinate coordinate: String
    ) {
        // Initialize collections if needed
        if self.liveChatMessagesEvents[coordinate] == nil {
            self.liveChatMessagesEvents[coordinate] = []
            self.chatMessageIdSets[coordinate] = []
        }

        // Fix #1: O(1) duplicate check via Set
        guard !self.chatMessageIdSets[coordinate]!.contains(message.id) else {
            return
        }
        
        // Track the ID
        self.chatMessageIdSets[coordinate]!.insert(message.id)

        // NIP-30: Learn emoji URLs from incoming chat messages
        // This populates the cache even when no kind 10030/30030 packs are loaded
        for emoji in message.customEmojis {
            if emojiPackCache[emoji.shortcode] == nil {
                emojiPackCache[emoji.shortcode] = emoji.imageURL
            }
        }

        var messages = self.liveChatMessagesEvents[coordinate]!
        messages.append(message)

        // Fix #4: O(1) memory limit enforcement using removeFirst
        // Messages arrive roughly in chronological order, so oldest are at front
        while messages.count > CollectionLimits.maxChatMessagesPerEvent {
            let removed = messages.removeFirst()
            self.chatMessageIdSets[coordinate]?.remove(removed.id)
        }

        self.liveChatMessagesEvents[coordinate] = messages
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
        // Log kind 4 at the relay level — earliest possible point
        if event.event.kind.rawValue == 4 {
            print("🔔 [COLLAB] ⚡ Kind 4 event received from relay — id=\(event.event.id.prefix(8)), from=\(event.event.pubkey.prefix(8)), relay=\(relay.url.absoluteString)")
        }

        // Log every 100th event to confirm relay is alive (avoid spam)
        _relayEventCounter += 1
        if _relayEventCounter % 100 == 1 {
            print("🔔 [COLLAB] Relay event #\(_relayEventCounter) — kind=\(event.event.kind.rawValue), relay=\(relay.url.absoluteString)")
        }

        // Offload heavy processing to a background task
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let nostrEvent = event.event

            // Perform verification on background thread
            do {
                try self.verifyEvent(nostrEvent)
            } catch {
                return
            }

            // Dispatch updates to published properties on the main thread
            await MainActor.run {
                _ = self.didReceive(nostrEvent: nostrEvent, relay: relay)
            }
        }
    }

    func didReceive(nostrEvent: NostrEvent, relay: Relay? = nil) -> PersistentNostrEvent? {

        // Log kind 4 events at the earliest point
        if nostrEvent.kind.rawValue == 4 {
            print("🔔 [COLLAB] Kind 4 event entered didReceive — id=\(nostrEvent.id.prefix(8)), from=\(nostrEvent.pubkey.prefix(8)), relay=\(relay?.url.absoluteString ?? "nil")")
        }

        // Ingest into centralized store first. Only proceed if accepted.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let accepted = await self.eventStore.ingest(nostrEvent)

            if nostrEvent.kind.rawValue == 4 {
                print("🔔 [COLLAB] Kind 4 event ingest result: accepted=\(accepted), id=\(nostrEvent.id.prefix(8))")
            }

            guard accepted else { return }

            await MainActor.run {
                // Log kind 4 type info before the switch
                if nostrEvent.kind.rawValue == 4 {
                    print("🔔 [COLLAB] Kind 4 entering switch — Swift type: \(type(of: nostrEvent)), id=\(nostrEvent.id.prefix(8))")
                }

                // Event-specific handling
                switch nostrEvent {
                case let followListEvent as FollowListEvent:
                    self.didReceiveFollowListEvent(
                        followListEvent,
                        shouldPullMissingEvents: nostrEvent.pubkey
                            == self.appSettings?.activeProfile?.publicKeyHex)
                case let metadataEvent as MetadataEvent:
                    self.didReceiveMetadataEvent(metadataEvent)
                case let liveActivitiesEvent as LiveActivitiesEvent:
                    self.didReceiveLiveActivitiesEvent(liveActivitiesEvent)
                case let liveChatMessageEvent as LiveChatMessageEvent:
                    self.didReceiveLiveChatMessage(liveChatMessageEvent)
                case let liveStreamRaidEvent as LiveStreamRaidEvent:
                    self.didReceiveLiveStreamRaidEvent(liveStreamRaidEvent)
                case let zapReceiptEvent as LightningZapsReceiptEvent:
                    self.didReceiveZapReceiptEvent(zapReceiptEvent)
                case let zapRequestEvent as LightningZapRequestEvent:
                    self.didReceiveZapRequestEvent(zapRequestEvent)
                case let clipEvent as LiveStreamClipEvent:
                    self.didReceiveClipEvent(clipEvent)
                case let videoEvent as VideoEvent:
                    // Kind 21 videos decoded by NostrSDK — treat as shorts if they arrive
                    self.didReceiveShortEvent(videoEvent)
                case let deletionEvent as DeletionEvent:
                    self.didReceiveDeletionEvent(deletionEvent)
                case let emojiListEvent as EmojiListEvent:
                    self.emojiPackService?.didReceiveEmojiList(emojiListEvent)
                case let emojiSetEvent as EmojiSetEvent:
                    self.emojiPackService?.didReceiveEmojiSet(emojiSetEvent)
                default:
                    // Try to manually create a LiveChatMessageEvent if it's kind 1311
                    if nostrEvent.kind == .liveChatMessage {
                        do {
                            let jsonData = try JSONEncoder().encode(nostrEvent)
                            let liveChatEvent = try JSONDecoder().decode(
                                LiveChatMessageEvent.self, from: jsonData)
                            self.didReceiveLiveChatMessage(liveChatEvent)
                        } catch {
                            // Failed to manually create LiveChatMessageEvent
                        }
                    }
                    // Try to manually create a LiveStreamRaidEvent if it's kind 1312
                    else if nostrEvent.kind == .liveStreamRaid {
                        do {
                            let jsonData = try JSONEncoder().encode(nostrEvent)
                            let raidEvent = try JSONDecoder().decode(
                                LiveStreamRaidEvent.self, from: jsonData)
                            self.didReceiveLiveStreamRaidEvent(raidEvent)
                        } catch {
                            // Failed to manually create LiveStreamRaidEvent
                        }
                    }
                    // Handle shorts (kind 22) and legacy shorts (kind 34236) — same tag structure as videos
                    else if nostrEvent.kind.rawValue == 22 || nostrEvent.kind.rawValue == 34236 {
                        self.didReceiveLegacyShortEvent(nostrEvent)
                    }
                    // Debug: log if a clip/short kind arrived but wasn't decoded as the expected type
                    else if nostrEvent.kind.rawValue == 1313 {
                        print("⚠️ Kind 1313 event arrived as plain NostrEvent (not LiveStreamClipEvent): \(nostrEvent.id)")
                    }
                    // WebRTC collab signaling (kind 4 / legacyEncryptedDirectMessage)
                    // When callSignalingService is nil (no active call), this is a no-op.
                    else if nostrEvent.kind == .legacyEncryptedDirectMessage {
                        print("🔔 [COLLAB] Kind 4 event arrived in AppState.didReceive — id=\(nostrEvent.id.prefix(8)), from=\(nostrEvent.pubkey.prefix(8)), callSignalingService=\(self.callSignalingService != nil ? "SET" : "NIL")")
                        if let svc = self.callSignalingService {
                            svc.didReceiveEncryptedDM(nostrEvent)
                        } else {
                            print("🔔 [COLLAB] ⚠️ callSignalingService is nil — invite will be dropped!")
                        }
                    }
                    break
                }

                // Persistence: enqueue event for batch processing
                // Deduplication is handled by SwiftData's unique constraint on eventId
                // This avoids blocking main thread with database fetches
                self.enqueueEvent(nostrEvent)
            }
        }

        // The pipeline is asynchronous; return nil immediately.
        return nil
    }

    /// Enqueues an incoming event for batch processing.
    /// NOTE: This method is called on the main thread from didReceive(nostrEvent:)
    private func enqueueEvent(_ event: NostrEvent) {
        self.pendingEvents.append(event)
        // If we have reached the batch size, process immediately.
        if self.pendingEvents.count >= self.batchSize {
            self.processPendingEvents()
            self.batchTimer?.invalidate()
            self.batchTimer = nil
        } else if self.batchTimer == nil {
            // Otherwise, set up a timer to process after a short delay (e.g., 1 second).
            self.batchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) {
                [weak self] _ in
                self?.processPendingEvents()
                self?.batchTimer = nil
            }
        }
    }

    func loadPersistentNostrEvents(_ persistentNostrEvents: [PersistentNostrEvent]) {
        for persistentNostrEvent in persistentNostrEvents {
            // Extract NostrEvent immediately to avoid SwiftData threading issues
            // PersistentNostrEvent should only be accessed on the thread where its context lives
            let nostrEvent = persistentNostrEvent.nostrEvent
            
            // Ingest into centralized store to initialize replaceable/parameterized indexes
            Task.detached { [weak self] in
                _ = await self?.eventStore.ingest(nostrEvent)
            }
            
            switch nostrEvent {
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

    /// Asynchronous version that processes events in batches
    /// This prevents blocking the main thread during app launch by yielding between batches
    @MainActor
    func loadPersistentNostrEventsAsync(_ persistentNostrEvents: [PersistentNostrEvent]) async {
        guard !persistentNostrEvents.isEmpty else { return }
        
        // IMPORTANT: Extract all NostrEvent objects immediately while on main thread
        // PersistentNostrEvent is a SwiftData model and can only be safely accessed
        // on the thread where its ModelContext lives (main thread for mainContext)
        let nostrEvents: [NostrEvent] = persistentNostrEvents.compactMap { $0.nostrEvent }

        // Process events in small batches, yielding to main thread between batches
        // This keeps the UI responsive while loading data
        let batchSize = 10  // Small batches to keep UI responsive

        for batch in nostrEvents.chunked(into: batchSize) {
            // Process batch on current actor (main thread) but quickly
            for nostrEvent in batch {
                // Ingest into centralized store asynchronously (doesn't block)
                Task.detached { [weak self] in
                    _ = await self?.eventStore.ingest(nostrEvent)
                }

                // Process event type-specific logic
                switch nostrEvent {
                case let liveActivitiesEvent as LiveActivitiesEvent:
                    // For live activities, do expensive coordinate extraction off main thread
                    await processLiveActivityEventAsync(liveActivitiesEvent)
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

            // Yield to main thread after each batch to keep UI responsive
            // This allows the UI to update and remain interactive
            await Task.yield()
        }

        // After all events are processed
        if let publicKey = self.publicKey,
            let followListEvent = self.followListEvents[publicKey.hex]
        {
            self.pullMissingEventsFromPubkeysAndFollows(followListEvent.followedPubkeys)
        }
    }

    /// Processes a live activity event asynchronously to avoid blocking main thread
    /// Expensive operations like PublicKey.init are done off main thread
    @MainActor
    private func processLiveActivityEventAsync(_ event: LiveActivitiesEvent) async {
        // Extract coordinates — now lightweight, no PublicKey construction needed
        let eventCoordinates = event.coordinateTag

        // If no coordinates, skip processing
        guard let eventCoordinates = eventCoordinates else { return }

        // Check if deleted (access deletedEventCoordinates on main thread)
        if let deletedAt = self.deletedEventCoordinates[eventCoordinates],
            event.createdDate <= deletedAt
        {
            return
        }

        // Check expiration (lightweight operation, can do on main thread)
        if let expirationStr = event.firstValueForRawTagName("expiration"),
            let expiration = Int64(expirationStr),
            expiration <= Int64(Date().timeIntervalSince1970)
        {
            return
        }

        // Now do the lightweight processing on main thread
        // Handle Nostr replaceable event deduplication
        var oldEvent: LiveActivitiesEvent? = nil
        if let existingEvents = self.liveActivitiesEvents[eventCoordinates] {
            if let mostRecentEvent = existingEvents.max(by: { $0.createdAt < $1.createdAt }) {
                if !NostrEventStore.shouldReplace(old: mostRecentEvent, with: event) {
                    return
                }
                oldEvent = mostRecentEvent
            }
        }

        // Replace with the latest event (lightweight dictionary operation)
        self.replaceLiveActivity(event, forEventCoordinate: eventCoordinates)

        // Update trie on background thread (pass coordinates to avoid re-computation)
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.updateLiveActivitiesTrieAsync(
                oldEvent: oldEvent,
                newEvent: event,
                eventCoordinates: eventCoordinates
            )
        }
    }

    /// Async version of updateLiveActivitiesTrie that processes on background thread
    /// Takes eventCoordinates as parameter to avoid expensive re-computation
    private func updateLiveActivitiesTrieAsync(
        oldEvent: LiveActivitiesEvent?,
        newEvent: LiveActivitiesEvent,
        eventCoordinates: String
    ) async {
        // Process on background thread
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // Extract values (lightweight operations)
            let newTitle = newEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty
            let newSummary = newEvent.firstValueForRawTagName("summary")?.trimmedOrNilIfEmpty

            // Prepare removals
            var removals = [(key: String, value: String)]()
            if let oldEvent = oldEvent {
                if let oldTitle = oldEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty,
                    oldTitle != newTitle
                {
                    removals.append((key: oldTitle, value: eventCoordinates))
                }
                if let oldSummary = oldEvent.firstValueForRawTagName("summary")?
                    .trimmedOrNilIfEmpty,
                    oldSummary != newSummary
                {
                    removals.append((key: oldSummary, value: eventCoordinates))
                }
            }

            // Prepare insertions
            var insertions = [(key: String, options: TrieInsertionOptions?)]()
            insertions.append((key: newEvent.id, options: nil))
            insertions.append((key: newEvent.pubkey, options: nil))
            if let identifier = newEvent.firstValueForRawTagName("identifier") {
                insertions.append((key: identifier, options: nil))
            }
            if let newTitle = newTitle {
                insertions.append(
                    (
                        key: newTitle,
                        options: [
                            .includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches,
                        ]
                    ))
            }
            if let newSummary = newSummary {
                insertions.append(
                    (
                        key: newSummary,
                        options: [
                            .includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches,
                        ]
                    ))
            }

            // Update trie on main thread (trie operations need to be on main thread)
            await MainActor.run {
                for removal in removals {
                    self.liveActivitiesTrie.remove(key: removal.key, value: removal.value)
                }
                for insertion in insertions {
                    if let options = insertion.options {
                        _ = self.liveActivitiesTrie.insert(
                            key: insertion.key, value: eventCoordinates, options: options)
                    } else {
                        _ = self.liveActivitiesTrie.insert(
                            key: insertion.key, value: eventCoordinates)
                    }
                }
            }
        }.value
    }

    func relay(_ relay: Relay, didReceive response: RelayResponse) {
        // Relay delegate may be called from any thread, ensure main thread for UI updates
        Task { @MainActor in
            switch response {
            case .eose(let subscriptionId):
                // Log EOSE for collab subscription
                if subscriptionId == self.collabSignalingSubscriptionId {
                    print("🔔 [COLLAB] EOSE received for kind 4 subscription — relay acknowledged it")
                }

                // Track initial sync completion
                self.checkInitialSyncCompletion(forSubscriptionId: subscriptionId)
                
                if let eventCoordinate = self.liveChatSubscriptionCounts[subscriptionId] {
                    // Increment received EOSE count for this coordinate
                    let receivedCount = (self.liveChatReceivedEOSECount[eventCoordinate] ?? 0) + 1
                    self.liveChatReceivedEOSECount[eventCoordinate] = receivedCount
                    let expectedCount = self.liveChatExpectedEOSECount[eventCoordinate] ?? 1
                    
                    print("Live chat EOSE received for: \(eventCoordinate) (\(receivedCount)/\(expectedCount))")
                    
                    // Only mark as complete when ALL subscriptions have received EOSE
                    if receivedCount >= expectedCount {
                        self.liveChatLoadComplete.insert(eventCoordinate)
                        print("Live chat fully loaded for: \(eventCoordinate)")
                    }
                    // Maintain live chat subscription for real-time updates
                } else if self.followListEventSubscriptionCounts.keys.contains(subscriptionId) {
                    // Maintain follow list subscription for real-time updates
                    print("Maintaining subscription: \(subscriptionId)")
                } else if self.ownLiveEventSubscriptionIds.contains(subscriptionId) {
                    // Own live event subscription — keep open (waiting for server to publish)
                    print("🔌 Own live event EOSE received, keeping subscription open")
                } else {
                    try? relay.closeSubscription(with: subscriptionId)
                    self.updateRelaySubscriptionCounts(closedSubscriptionId: subscriptionId)
                }

            case .closed(let subscriptionId, _):
                self.liveChatSubscriptionCounts.removeValue(forKey: subscriptionId)
                self.followListEventSubscriptionCounts.removeValue(forKey: subscriptionId)
                self.ownLiveEventSubscriptionIds.remove(subscriptionId)
                self.ownLiveEventSubscriptionPubkeys.removeValue(forKey: subscriptionId)
                self.updateRelaySubscriptionCounts(closedSubscriptionId: subscriptionId)
            case .ok(let eventId, let success, let message):
                if success {
                    // Update relay list in background to avoid blocking main thread
                    if let backgroundPersistence = self.backgroundPersistence {
                        Task.detached(priority: .utility) {
                            do {
                                _ = try await backgroundPersistence.addRelayToEvent(
                                    eventId: eventId,
                                    relayURL: relay.url
                                )
                            } catch {
                                // Silently ignore - relay tracking is not critical
                            }
                        }
                    }
                    
                    // Notify pending message confirmation — first successful OK wins
                    if let callback = self.pendingEventOKCallbacks.removeValue(forKey: eventId) {
                        callback(true)
                    }
                } else if message.prefix == .rateLimited {
                    // Don't call failure callback — another relay may accept.
                    // Timeout in LiveChatController is the fallback.
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
        if let liveActivityEventSubscriptionCount = liveActivityEventSubscriptionCounts[
            closedSubscriptionId]
        {
            if liveActivityEventSubscriptionCount <= 1 {
                liveActivityEventSubscriptionCounts.removeValue(forKey: closedSubscriptionId)

                // Use cached events for efficiency
                let allLiveActivities = getAllEvents()

                // Fetch metadata for all unique pubkeys in live activities
                let uniquePubkeys = Set(allLiveActivities.map { $0.pubkey })
                pullMissingEventsFromPubkeysAndFollows(Array(uniquePubkeys))

                // Fetch metadata for hosts of live activities
                let hostPubkeys = allLiveActivities.map { $0.hostPubkeyHex }
                pullMissingEventsFromPubkeysAndFollows(hostPubkeys)
            } else {
                liveActivityEventSubscriptionCounts[closedSubscriptionId] =
                    liveActivityEventSubscriptionCount - 1
            }
        }

        // Handle clip subscription counts
        if let clipSubscriptionCount = clipSubscriptionCounts[closedSubscriptionId] {
            if clipSubscriptionCount <= 1 {
                clipSubscriptionCounts.removeValue(forKey: closedSubscriptionId)
            } else {
                clipSubscriptionCounts[closedSubscriptionId] = clipSubscriptionCount - 1
            }
        }

        // Handle short subscription counts
        if let shortSubscriptionCount = shortSubscriptionCounts[closedSubscriptionId] {
            if shortSubscriptionCount <= 1 {
                shortSubscriptionCounts.removeValue(forKey: closedSubscriptionId)
            } else {
                shortSubscriptionCounts[closedSubscriptionId] = shortSubscriptionCount - 1
            }
        }

        // Handle global zap subscription counts
        if let globalZapSubscriptionCount = globalZapSubscriptionCounts[closedSubscriptionId] {
            if globalZapSubscriptionCount <= 1 {
                globalZapSubscriptionCounts.removeValue(forKey: closedSubscriptionId)
            } else {
                globalZapSubscriptionCounts[closedSubscriptionId] = globalZapSubscriptionCount - 1
            }
        }

        // Handle own live event subscription cleanup (server-side close)
        if ownLiveEventSubscriptionIds.contains(closedSubscriptionId) {
            ownLiveEventSubscriptionIds.remove(closedSubscriptionId)
            ownLiveEventSubscriptionPubkeys.removeValue(forKey: closedSubscriptionId)
        }
    }

    func updateLiveActivitiesTrie(
        oldEvent: LiveActivitiesEvent? = nil, newEvent: LiveActivitiesEvent
    ) {
        // First, get the event coordinate. If missing, nothing to do.
        guard let eventCoordinates = newEvent.coordinateTag else {
            return
        }

        // Ignore new events that are older or equal by tie-break rule.
        if let oldEvent,
            !NostrEventStore.shouldReplace(old: oldEvent, with: newEvent)
        {
            return
        }

        // Offload key extraction and decision-making to a background task.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // Extract new values.
            let newTitle = newEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty
            let newSummary = newEvent.firstValueForRawTagName("summary")?.trimmedOrNilIfEmpty

            // Prepare removals based on differences from the old event.
            var removals = [(key: String, value: String)]()
            if let oldEvent = oldEvent {
                if let oldTitle = oldEvent.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty,
                    oldTitle != newTitle
                {
                    removals.append((key: oldTitle, value: eventCoordinates))
                }
                if let oldSummary = oldEvent.firstValueForRawTagName("summary")?
                    .trimmedOrNilIfEmpty,
                    oldSummary != newSummary
                {
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
                insertions.append(
                    (
                        key: newTitle,
                        options: [
                            .includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches,
                        ]
                    ))
            }
            if let newSummary = newSummary {
                insertions.append(
                    (
                        key: newSummary,
                        options: [
                            .includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches,
                        ]
                    ))
            }

            // Update trie on main thread.
            await MainActor.run {
                // Remove outdated entries.
                for removal in removals {
                    self.liveActivitiesTrie.remove(key: removal.key, value: removal.value)
                }

                // Insert new entries.
                for insertion in insertions {
                    if let options = insertion.options {
                        _ = self.liveActivitiesTrie.insert(
                            key: insertion.key, value: eventCoordinates, options: options)
                    } else {
                        _ = self.liveActivitiesTrie.insert(
                            key: insertion.key, value: eventCoordinates)
                    }
                }
            }
        }
    }

    private func deleteFromEventCoordinates(_ deletionEvent: DeletionEvent) {
        let deletedEventCoordinates = deletionEvent.eventCoordinates.filter {
            $0.pubkeyHex == deletionEvent.pubkey
        }

        for deletedEventCoordinate in deletedEventCoordinates {
            // Update the deletion timestamp for the event coordinate
            if let existingDeletedEventCoordinateDate = self.deletedEventCoordinates[
                deletedEventCoordinate.tag.value]
            {
                if existingDeletedEventCoordinateDate < deletionEvent.createdDate {
                    self.deletedEventCoordinates[deletedEventCoordinate.tag.value] =
                        deletionEvent.createdDate
                } else {
                    continue
                }
            } else {
                self.deletedEventCoordinates[deletedEventCoordinate.tag.value] =
                    deletionEvent.createdDate
            }

            // Handle deletion based on event kind
            switch deletedEventCoordinate.kind {
            case .liveActivities:
                if let liveActivitiesArray = liveActivitiesEvents[deletedEventCoordinate.tag.value]
                {
                    // Find the most recent event in the array
                    if let mostRecentEvent = liveActivitiesArray.max(by: {
                        $0.createdAt < $1.createdAt
                    }),
                        mostRecentEvent.createdAt <= deletionEvent.createdAt
                    {
                        // Remove the entire array of events for this coordinate
                        liveActivitiesEvents.removeValue(forKey: deletedEventCoordinate.tag.value)
                        invalidateEventsCache()
                    }
                }
            default:
                continue
            }
        }
        
        // Enforce memory limit - remove oldest deletion records when limit exceeded
        if self.deletedEventCoordinates.count > CollectionLimits.maxDeletedEventCoordinates {
            // Sort by deletion date (oldest first) and remove oldest entries
            let sortedByAge = self.deletedEventCoordinates.sorted { $0.value < $1.value }
            let toRemove = sortedByAge.prefix(self.deletedEventCoordinates.count - CollectionLimits.maxDeletedEventCoordinates)
            for (coordinate, _) in toRemove {
                self.deletedEventCoordinates.removeValue(forKey: coordinate)
            }
        }
    }

    private func deleteFromEventIds(_ deletionEvent: DeletionEvent) {
        var eventIdsToDelete: [String] = []
        
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
                    if let eventCoordinates = liveActivitiesEvent.coordinateTag
                    {
                        // Filter out the event with the matching ID from the array
                        liveActivitiesEvents[eventCoordinates]?.removeAll {
                            $0.id == liveActivitiesEvent.id
                        }

                        // If the array is now empty, remove the coordinate entry entirely
                        if liveActivitiesEvents[eventCoordinates]?.isEmpty == true {
                            liveActivitiesEvents.removeValue(forKey: eventCoordinates)
                        }
                        
                        invalidateEventsCache()
                    }

                default:
                    continue
                }

                // Collect event ID for batch deletion
                eventIdsToDelete.append(deletedEventId)
            }
        }
        
        // Batch delete using background actor if available
        if !eventIdsToDelete.isEmpty {
            if let backgroundPersistence = backgroundPersistence {
                Task {
                    do {
                        let deletedCount = try await backgroundPersistence.deleteEvents(withIds: eventIdsToDelete)
                        print("Background persistence: deleted \(deletedCount) events")
                    } catch {
                        print("Background persistence delete error: \(error)")
                    }
                }
            } else {
                // Fallback to main context deletion (batch save at end)
                for eventId in eventIdsToDelete {
                    if let persistentEvent = persistentNostrEvent(eventId) {
                        modelContext.delete(persistentEvent)
                    }
                }
                do {
                    try modelContext.save()
                } catch {
                    print("Unable to delete PersistentNostrEvents: \(error)")
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
            let followListEvent = try followList(
                withPubkeys: pubkeys,
                signedBy: keypair
            )
            // Publish the event.
            relayWritePool.publishEvent(followListEvent)

            // Cache locally so activeFollowList is immediately up to date.
            // This prevents race conditions when rapid follow/unfollow actions
            // read from activeFollowList before the relay echoes the event back.
            followListEvents[followListEvent.pubkey] = followListEvent
            if followListEvent.pubkey == publicKey?.hex {
                refreshFollowedPubkeys()
            }

            return true
        } catch {
            print("Unable to save event: \(error)")
        }
        return false
    }

    private func updateCollectionsWithNostrEvents(_ events: [NostrEvent]) {
        for nostrEvent in events {
            switch nostrEvent {
            case let followListEvent as FollowListEvent:
                // Update follow list events using the pubkey as key.
                self.followListEvents[followListEvent.pubkey] = followListEvent
            case let metadataEvent as MetadataEvent:
                // Update metadata events keyed by pubkey.
                self.metadataEvents[metadataEvent.pubkey] = metadataEvent
            case let liveActivitiesEvent as LiveActivitiesEvent:
                // Use event coordinates as the key (if available).
                if let eventCoordinates = liveActivitiesEvent.coordinateTag
                {
                    if let existing = self.liveActivitiesEvents[eventCoordinates]?.first {
                        if NostrEventStore.shouldReplace(old: existing, with: liveActivitiesEvent) {
                            self.replaceLiveActivity(
                                liveActivitiesEvent, forEventCoordinate: eventCoordinates)
                        }
                    } else {
                        self.replaceLiveActivity(
                            liveActivitiesEvent, forEventCoordinate: eventCoordinates)
                    }
                }
            default:
                break
            }
        }
    }

    /// Processes the pending events in batches.
    /// Uses BackgroundPersistenceActor for off-main-thread database operations.
    /// UI collection updates still happen on main thread.
    private func processPendingEvents() {
        // Guard against an empty pendingEvents array.
        guard !pendingEvents.isEmpty else { return }

        // Take a batch of events up to the batch size.
        let batch = Array(pendingEvents.prefix(batchSize))
        pendingEvents.removeFirst(min(batchSize, pendingEvents.count))

        // Update UI collections immediately on main thread (we're already on main)
        // This ensures UI is responsive even before persistence completes
        self.updateCollectionsWithNostrEvents(batch)

        // Use background persistence actor if available (preferred path)
        if let backgroundPersistence = backgroundPersistence {
            // Use Task.detached to ensure we're truly off the main thread
            Task.detached(priority: .utility) {
                do {
                    // Insert events on background thread via actor
                    let insertedIds = try await backgroundPersistence.insertEvents(batch)
                    
                    if !insertedIds.isEmpty {
                        print("Background persistence: inserted \(insertedIds.count) events")
                    }
                } catch {
                    print("Background persistence error: \(error)")
                    // Events are already in memory collections, just not persisted
                }
            }
        } else {
            // Fallback to legacy main-thread persistence (for previews or if actor not available)
            // Create and insert persistent events on main thread since modelContext is main-thread bound
            for event in batch {
                let persistentEvent = PersistentNostrEvent(nostrEvent: event)
                modelContext.insert(persistentEvent)
            }
            
            // Save synchronously (this is the fallback path, so blocking is acceptable)
            do {
                try modelContext.save()
            } catch {
                print("Error saving batch of events: \(error)")
            }
        }
    }
    
    // MARK: - Direct Processing Methods (for startup loading)
    // These methods process events synchronously without Task overhead.
    // Use only during initial load when we're on main thread and want to avoid
    // creating thousands of Task.detached calls.
    
    /// Processes a live activity event directly without async overhead
    /// Called during startup loading to avoid Task creation overhead.
    @MainActor
    func processLiveActivityDirect(_ event: LiveActivitiesEvent) {
        guard let eventCoordinates = event.coordinateTag else {
            return
        }
        
        // Check if deleted
        if let deletedAt = deletedEventCoordinates[eventCoordinates],
           event.createdDate <= deletedAt {
            return
        }
        
        // Check expiration
        if let expirationStr = event.firstValueForRawTagName("expiration"),
           let expiration = Int64(expirationStr),
           expiration <= Int64(Date().timeIntervalSince1970) {
            return
        }
        
        // Deduplication check
        if let existingEvents = liveActivitiesEvents[eventCoordinates],
           let mostRecentEvent = existingEvents.max(by: { $0.createdAt < $1.createdAt }) {
            if !NostrEventStore.shouldReplace(old: mostRecentEvent, with: event) {
                return
            }
        }
        
        // Store event
        liveActivitiesEvents[eventCoordinates] = [event]
        invalidateEventsCache()
        
        // Update trie incrementally (not deferred)
        updateLiveActivitiesTrieDirectly(event, eventCoordinates: eventCoordinates)
    }
    
    /// Processes a follow list event directly without async overhead
    @MainActor
    func processFollowListDirect(_ event: FollowListEvent) {
        if let existing = followListEvents[event.pubkey] {
            if !NostrEventStore.shouldReplace(old: existing, with: event) {
                return
            }
        }
        
        followListEvents[event.pubkey] = event
        
        // Enforce limits
        if followListEvents.count > CollectionLimits.maxFollowListEvents {
            let sortedByAge = followListEvents.sorted { $0.value.createdAt < $1.value.createdAt }
            let toRemove = sortedByAge.prefix(followListEvents.count - CollectionLimits.maxFollowListEvents)
            for (pubkey, _) in toRemove {
                followListEvents.removeValue(forKey: pubkey)
            }
        }
    }
    
    /// Processes a metadata event directly without async overhead
    @MainActor
    func processMetadataDirect(_ event: MetadataEvent) {
        if let existing = metadataEvents[event.pubkey] {
            if !NostrEventStore.shouldReplace(old: existing, with: event) {
                return
            }
        }
        
        metadataEvents[event.pubkey] = event
        
        // Enforce limits
        if metadataEvents.count > CollectionLimits.maxMetadataEvents {
            let sortedByAge = metadataEvents.sorted { $0.value.createdAt < $1.value.createdAt }
            let toRemove = sortedByAge.prefix(metadataEvents.count - CollectionLimits.maxMetadataEvents)
            for (pubkey, _) in toRemove {
                metadataEvents.removeValue(forKey: pubkey)
            }
        }
        
        // Update pubkey trie incrementally
        if let userMetadata = event.userMetadata {
            if let name = userMetadata.name?.trimmedOrNilIfEmpty {
                _ = pubkeyTrie.insert(
                    key: name,
                    value: event.pubkey,
                    options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]
                )
            }
            if let displayName = userMetadata.displayName?.trimmedOrNilIfEmpty {
                _ = pubkeyTrie.insert(
                    key: displayName,
                    value: event.pubkey,
                    options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]
                )
            }
        }

        // Update cached display metadata on the Profile model if this pubkey belongs to a local profile
        if let profile = profiles.first(where: { $0.publicKeyHex == event.pubkey }),
           let userMetadata = event.userMetadata {
            let newDisplayName = userMetadata.displayName ?? userMetadata.name
            let newUsername = userMetadata.name
            let newPictureURL = userMetadata.pictureURL?.absoluteString
            if profile.cachedDisplayName != newDisplayName
                || profile.cachedUsername != newUsername
                || profile.cachedProfilePictureURL != newPictureURL {
                profile.cachedDisplayName = newDisplayName
                profile.cachedUsername = newUsername
                profile.cachedProfilePictureURL = newPictureURL
                try? modelContext.save()
            }
        }
    }
    
    /// Processes a deletion event directly without async overhead
    @MainActor
    func processDeletionDirect(_ event: DeletionEvent) {
        // Process coordinate deletions
        for coordinate in event.eventCoordinates {
            guard coordinate.pubkeyHex == event.pubkey else { continue }
            
            if let existingDate = deletedEventCoordinates[coordinate.tag.value] {
                if existingDate >= event.createdDate {
                    continue
                }
            }
            
            deletedEventCoordinates[coordinate.tag.value] = event.createdDate
            
            if coordinate.kind == .liveActivities {
                liveActivitiesEvents.removeValue(forKey: coordinate.tag.value)
                invalidateEventsCache()
            }
        }
        
        // Enforce limits
        if deletedEventCoordinates.count > CollectionLimits.maxDeletedEventCoordinates {
            let sortedByAge = deletedEventCoordinates.sorted { $0.value < $1.value }
            let toRemove = sortedByAge.prefix(deletedEventCoordinates.count - CollectionLimits.maxDeletedEventCoordinates)
            for (coord, _) in toRemove {
                deletedEventCoordinates.removeValue(forKey: coord)
            }
        }
    }
    
    /// Processes a clip event directly without async overhead.
    /// Called during cache fallback loading.
    @MainActor
    func processClipEventDirect(_ clip: LiveStreamClipEvent) {
        guard !clipEventIds.contains(clip.id) else { return }
        clipEventIds.insert(clip.id)
        clipEvents.append(clip)
        clipEvents.sort { $0.createdAt > $1.createdAt }
        while clipEvents.count > CollectionLimits.maxClipEvents {
            let removed = clipEvents.removeLast()
            clipEventIds.remove(removed.id)
        }
    }

    /// Processes a short/video event directly without async overhead.
    /// Called during cache fallback loading.
    @MainActor
    func processShortEventDirect(_ short: VideoEvent) {
        guard !shortEventIds.contains(short.id) else { return }
        shortEventIds.insert(short.id)
        shortEvents.append(short)
        shortEvents.sort { a, b in
            let aDate = a.publishedAt ?? a.createdDate
            let bDate = b.publishedAt ?? b.createdDate
            return aDate > bDate
        }
        while shortEvents.count > CollectionLimits.maxShortEvents {
            let removed = shortEvents.removeLast()
            shortEventIds.remove(removed.id)
        }
    }

    /// Handles legacy short events (kind 22/34236) during cache loading.
    @MainActor
    func processLegacyShortEventDirect(_ event: NostrEvent) {
        guard !shortEventIds.contains(event.id) else { return }
        do {
            var jsonData = try JSONEncoder().encode(event)
            if var json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                json["kind"] = 21
                jsonData = try JSONSerialization.data(withJSONObject: json)
            }
            let shortEvent = try JSONDecoder().decode(VideoEvent.self, from: jsonData)
            processShortEventDirect(shortEvent)
        } catch {
            print("🎬 Failed to re-decode legacy short during cache load: \(error)")
        }
    }

    /// Updates live activities trie synchronously (for startup loading)
    /// This is called during initial load to update tries incrementally.
    @MainActor
    private func updateLiveActivitiesTrieDirectly(_ event: LiveActivitiesEvent, eventCoordinates: String) {
        _ = liveActivitiesTrie.insert(key: event.id, value: eventCoordinates)
        _ = liveActivitiesTrie.insert(key: event.pubkey, value: eventCoordinates)
        
        if let identifier = event.firstValueForRawTagName("identifier") {
            _ = liveActivitiesTrie.insert(key: identifier, value: eventCoordinates)
        }
        if let title = event.firstValueForRawTagName("title")?.trimmedOrNilIfEmpty {
            _ = liveActivitiesTrie.insert(
                key: title,
                value: eventCoordinates,
                options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]
            )
        }
        if let summary = event.firstValueForRawTagName("summary")?.trimmedOrNilIfEmpty {
            _ = liveActivitiesTrie.insert(
                key: summary,
                value: eventCoordinates,
                options: [.includeCaseInsensitiveMatches, .includeDiacriticsInsensitiveMatches]
            )
        }
    }
    
    // MARK: - Async Database Access
    
    /// Publishes unpublished events asynchronously (non-blocking replacement for publishUnpublishedEvents)
    /// This fetches unpublished event IDs on background thread, then publishes them.
    /// Only republishes events authored by the current user to avoid flooding relays
    /// with received events that were never meant to be republished.
    func publishUnpublishedEventsAsync() {
        guard let authorPubkey = publicKey?.hex else { return }
        
        guard let backgroundPersistence = backgroundPersistence else {
            // Fallback to synchronous version if no background actor
            for persistentNostrEvent in unpublishedPersistentNostrEvents {
                relayWritePool.publishEvent(persistentNostrEvent.nostrEvent)
            }
            return
        }
        
        Task { @MainActor in
            do {
                let eventIds = try await backgroundPersistence.fetchUnpublishedEventIds()
                for eventId in eventIds {
                    // Fetch on main thread for transformer safety
                    if let persistent = persistentNostrEvent(eventId),
                       persistent.nostrEvent.pubkey == authorPubkey {
                        relayWritePool.publishEvent(persistent.nostrEvent)
                    }
                }
            } catch {
                print("Failed to fetch unpublished events: \(error)")
            }
        }
    }
    
    // MARK: - NIP-30 Custom Emoji Resolution
    
    /// Resolves a shortcode to an image URL from loaded emoji packs.
    /// Returns nil if the shortcode is not found in any loaded pack.
    func resolveEmojiURL(shortcode: String) -> URL? {
        return emojiPackCache[shortcode]
    }
}

struct CollectionLimits {
    static let maxChatMessagesPerEvent = 2000
    static let maxZapReceiptsPerEvent = 2000
    static let maxLiveActivitiesEvents = 1000
    
    // Global collection limits (should be >= per-stream limits)
    static let maxGlobalZapReceipts = 2000
    static let maxGlobalZapRequests = 2000
    static let maxMetadataEvents = 5000
    static let maxFollowListEvents = 1000
    static let maxDeletedEventIds = 1000
    static let maxDeletedEventCoordinates = 1000
    static let maxClipEvents = 200
    static let maxShortEvents = 200
}

// MARK: - Array Extension for Chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
