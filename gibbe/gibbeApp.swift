//
//  gibbeApp.swift
//  gibbe
//
//  Created by Suhail Saqan on 8/11/24.
//

import NostrSDK
import SwiftData
import SwiftUI

@main
struct gibbeApp: App {
    let container: ModelContainer

    @State private var appState: AppState

    init() {
        NostrEventValueTransformer.register()
        do {
            container = try ModelContainer(for: AppSettings.self, PersistentNostrEvent.self)
            appState = AppState(modelContext: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer for AppSettings and PersistentNostrEvent.")
        }

        loadAppSettings()
        updateActiveTab()
        loadNostrEvents()
        appState.updateRelayPool()
        appState.refresh()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: container.mainContext)
                .environmentObject(appState)
                .environmentObject(KeychainHelper.shared)
        }
        .modelContainer(container)
    }

    @MainActor
    private func updateActiveTab() {
        appState.activeTab = .events
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
                newAppSettings.activeProfile?.profileSettings?.relayPoolSettings?.relaySettingsList.append(RelaySettings(relayURLString: AppState.defaultRelayURLString))
            } catch {
                fatalError("Unable to save initial AppSettings.")
            }
        }
    }

    @MainActor
    private func loadNostrEvents() {
        let descriptor = FetchDescriptor<PersistentNostrEvent>()
        let persistentNostrEvents = (try? container.mainContext.fetch(descriptor)) ?? []
        appState.loadPersistentNostrEvents(persistentNostrEvents)

        appState.refreshFollowedPubkeys()
    }
}
