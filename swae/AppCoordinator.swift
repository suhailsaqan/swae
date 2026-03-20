//
//  AppCoordinator.swift
//  swae
//
//  Manages app-wide state and coordination between UIKit and SwiftUI
//

import Combine
import Foundation
import MWDATCore
import NostrSDK
import SwiftData
import SwiftUI

final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    // SwiftData container
    private(set) var container: ModelContainer!
    
    // Background persistence actor for off-main-thread database operations
    private(set) var backgroundPersistenceActor: BackgroundPersistenceActor!

    // App state
    private(set) var appState: AppState!

    // Global model
    private(set) var model: Model!

    // Orientation monitor
    private(set) var orientationMonitor: OrientationMonitor!

    // Initialization flag
    private var isInitialized = false
    
    // MARK: - Loading State
    
    /// Indicates whether initial event loading is in progress
    @Published private(set) var isLoadingInitialEvents = true
    
    /// Number of events loaded so far during initial load
    @Published private(set) var loadedEventCount = 0
    
    /// Total number of events to load (for progress indication)
    @Published private(set) var totalEventCount = 0
    
    /// Flag to track if initial load has completed (prevents relay connection during load)
    private var initialLoadComplete = false

    // MARK: - Relay-First Loading
    
    private var fallbackTimer: Timer?
    
    /// How long to wait for relay data before falling back to cache.
    private let fallbackTimeout: TimeInterval = 5.0

    private init() {}

    @MainActor
    func initialize() throws {
        guard !isInitialized else { return }
        isInitialized = true
        
        // Initialize Meta Wearables SDK (must be before Model creation)
        do {
            try Wearables.configure()
        } catch {
            print("⚠️ Meta Wearables SDK failed to configure: \(error)")
        }
        
        // Register Nostr transformer
        NostrEventValueTransformer.register()

        // Create SwiftData container
        container = try ModelContainer(for: AppSettings.self, PersistentNostrEvent.self)
        
        // Create background persistence actor for off-main-thread database operations
        backgroundPersistenceActor = BackgroundPersistenceActor(modelContainer: container)

        // Create app state with both main context (for reads) and background actor (for writes)
        appState = AppState(modelContext: container.mainContext, backgroundPersistence: backgroundPersistenceActor)

        // Create global model
        model = Model()

        // Create orientation monitor
        orientationMonitor = OrientationMonitor()

        // Load initial app settings (must be synchronous for app to work)
        loadAppSettings()

        // Set app state reference on model
        model.appState = appState
        
        // Initialize Meta Glasses integration
        model.setupMetaGlasses()
        
        // Set up zap plasma effect callback
        appState.onZapReceived = { [weak model] amount in
            model?.triggerZapPlasmaEffect(amount: amount)
        }

        // 1. Preload follow lists from cache (fast, synchronous).
        //    Needed so refreshFollowedPubkeys() works and the bootstrap filter has authors.
        preloadFollowListsFromCache()
        
        // 2. Mark initial sync in progress BEFORE connecting relays.
        //    This tells the UI to show skeletons and suppress rebuilds.
        appState.isInitialSyncInProgress = true
        isLoadingInitialEvents = true
        
        // 3. Connect to relays immediately.
        //    Each relay that connects will call refresh(relay:) via relayStateDidChange.
        appState.updateRelayPool()
        appState.refreshFollowedPubkeys()
        
        // 4. Start fallback timer.
        startFallbackTimer()
        
        // 5. Set completion callback — cancels fallback timer when relay data arrives.
        appState.onInitialSyncComplete = { [weak self] in
            self?.onRelayDataReady()
        }
        
        // 6. Run one-time migration to backfill kind/createdAt columns on existing events.
        //    This runs on the background actor so it doesn't block startup.
        if !UserDefaults.standard.bool(forKey: "persistentEventKindMigrated") {
            Task.detached(priority: .utility) { [weak self] in
                guard let actor = self?.backgroundPersistenceActor else { return }
                do {
                    let count = try await actor.backfillKindAndCreatedAt()
                    print("📊 Migrated \(count) events with kind/createdAt columns")
                    UserDefaults.standard.set(true, forKey: "persistentEventKindMigrated")
                } catch {
                    print("❌ Kind column migration failed: \(error)")
                    // Not fatal — app still works, just uses the slow preload path next launch
                }
            }
        }
    }

    @MainActor
    private func loadAppSettings() {
        var descriptor = FetchDescriptor<AppSettings>()
        descriptor.fetchLimit = 1

        let existingAppSettings = (try? container.mainContext.fetch(descriptor))?.first
        if existingAppSettings == nil {
            let newAppSettings = AppSettings()
            container.mainContext.insert(newAppSettings)
            do {
                try container.mainContext.save()
            } catch {
                fatalError("Unable to save initial AppSettings.")
            }
        }
    }

    // MARK: - Relay-First Loading

    private func startFallbackTimer() {
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: fallbackTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.onFallbackTimerFired()
            }
        }
    }

    /// Called when relay EOSE arrives for liveActivities — we have fresh data.
    @MainActor
    private func onRelayDataReady() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        
        isLoadingInitialEvents = false
        initialLoadComplete = true
        
        print("📊 Relay-first load complete — displaying fresh data")
        
        // If relay returned no live activities, load from cache as supplement.
        // getAllEvents() only returns LiveActivitiesEvent — clips/shorts are separate.
        if appState.getAllEvents().isEmpty {
            print("📊 No live activities from relay — supplementing with cache")
            loadCachedEvents()
        }
        
        // Trigger a full refresh across all connected relays to ensure
        // any subscriptions that didn't fire per-relay get created.
        // After Fix 3 cleans up clip/short/zap counts, this re-subscribes them.
        appState.refresh()
        
        if let currentUserPubkey = appState.publicKey?.hex {
            appState.pullMissingEventsFromPubkeysAndFollows([currentUserPubkey])
        }

        // Start the always-on collab invite listener now that relays are connected
        print("🔔 [COLLAB] AppCoordinator calling startCollabSignalingListener()")
        model.startCollabSignalingListener()
    }

    /// Called when fallback timer fires — relays were too slow, load from cache.
    @MainActor
    private func onFallbackTimerFired() {
        guard appState.isInitialSyncInProgress else { return }
        
        print("📊 Fallback timer fired — loading from cache")
        
        // Stop waiting for relays (but don't disconnect — they'll continue in background)
        appState.finishInitialSync()
        
        // Load cached events
        loadCachedEvents()
    }

    /// Loads persisted events from SwiftData into AppState.
    /// Handles ALL event types including clips and shorts.
    /// Uses a single bulk fetch on the background actor to avoid O(N²) offset pagination,
    /// then processes in batches on the main thread with yields for UI responsiveness.
    @MainActor
    private func loadCachedEvents() {
        Task { @MainActor in
            do {
                // Single bulk fetch + deserialize on background thread
                // This fixes the O(N²) offset scan and the thread-safety violation
                // where PersistentNostrEvent objects were accessed across actor boundaries
                let allEvents = try await backgroundPersistenceActor.fetchAllEventsDeserialized()
                
                guard !allEvents.isEmpty else {
                    isLoadingInitialEvents = false
                    initialLoadComplete = true
                    return
                }
                
                // Process in batches on main thread with yields for UI responsiveness
                let batchSize = 50
                for batch in allEvents.chunked(into: batchSize) {
                    processLoadedEvents(batch)
                    await Task.yield()
                }
                
                isLoadingInitialEvents = false
                initialLoadComplete = true
                
                if let currentUserPubkey = appState.publicKey?.hex {
                    appState.pullMissingEventsFromPubkeysAndFollows([currentUserPubkey])
                }
            } catch {
                print("❌ Cache loading failed: \(error)")
                isLoadingInitialEvents = false
                initialLoadComplete = true
            }
        }
    }

    /// Loads follow lists and metadata from cache.
    /// Phase 1 (instant): restores cached followed pubkeys from UserDefaults so the
    /// "Following" section works immediately.
    /// Phase 2 (deferred): full SwiftData fetch runs in a yielded Task so it doesn't
    /// block the first frame. The 108ms fetch is deferred to after UI renders.
    @MainActor
    private func preloadFollowListsFromCache() {
        // Phase 1: Instant restore of followed pubkeys from UserDefaults cache
        if let cached = UserDefaults.standard.array(forKey: "cachedFollowedPubkeys") as? [String],
           !cached.isEmpty {
            appState.followedPubkeys = Set(cached)
        }

        // Phase 2: Deferred SwiftData fetch — yields to run loop so initialize() completes
        // and the UI can render before the 108ms fetch runs.
        Task { @MainActor in
            do {
                let migrated = UserDefaults.standard.bool(forKey: "persistentEventKindMigrated")

                let persisted: [PersistentNostrEvent]
                if migrated {
                    // Fast path: only fetch the 3 kinds we need
                    let descriptor = FetchDescriptor<PersistentNostrEvent>(
                        predicate: #Predicate { $0.kind == 0 || $0.kind == 3 || $0.kind == 5 }
                    )
                    persisted = try container.mainContext.fetch(descriptor)
                } else {
                    // First launch after update: fall back to full table
                    let descriptor = FetchDescriptor<PersistentNostrEvent>()
                    persisted = try container.mainContext.fetch(descriptor)
                }

                for persistent in persisted {
                    let event = persistent.nostrEvent
                    switch event {
                    case let followListEvent as FollowListEvent:
                        appState.processFollowListDirect(followListEvent)
                    case let metadataEvent as MetadataEvent:
                        appState.processMetadataDirect(metadataEvent)
                    case let deletionEvent as DeletionEvent:
                        appState.processDeletionDirect(deletionEvent)
                    default:
                        break
                    }
                }

                // Refresh with full data now available
                appState.refreshFollowedPubkeys()

                // Update cache for next launch
                UserDefaults.standard.set(
                    Array(appState.followedPubkeys), forKey: "cachedFollowedPubkeys"
                )
            } catch {
                print("❌ Failed to preload follow lists: \(error)")
            }
        }
    }

    /// Processes loaded events into AppState, handling ALL event types including clips and shorts.
    @MainActor
    private func processLoadedEvents(_ events: [NostrEvent]) {
        // Batch ingest into event store — single task for all events in this batch
        Task.detached { [weak self] in
            guard let eventStore = await self?.appState.eventStore else { return }
            for event in events {
                _ = await eventStore.ingest(event)
            }
        }
        
        // Process event types on main thread (already @MainActor)
        for event in events {
            switch event {
            case let liveActivitiesEvent as LiveActivitiesEvent:
                appState.processLiveActivityDirect(liveActivitiesEvent)
            case let followListEvent as FollowListEvent:
                appState.processFollowListDirect(followListEvent)
            case let metadataEvent as MetadataEvent:
                appState.processMetadataDirect(metadataEvent)
            case let deletionEvent as DeletionEvent:
                appState.processDeletionDirect(deletionEvent)
            case let clipEvent as LiveStreamClipEvent:
                appState.processClipEventDirect(clipEvent)
            case let videoEvent as VideoEvent:
                appState.processShortEventDirect(videoEvent)
            default:
                if event.kind.rawValue == 22 || event.kind.rawValue == 34236 {
                    appState.processLegacyShortEventDirect(event)
                }
                break
            }
        }
    }

    @MainActor
    func createContentView() -> some View {
        ContentView(modelContext: container.mainContext)
            .environmentObject(self)
            .environmentObject(appState)
            .environmentObject(KeychainHelper.shared)
            .environmentObject(orientationMonitor)
            .environmentObject(model)
            .modelContainer(container)
    }
}
