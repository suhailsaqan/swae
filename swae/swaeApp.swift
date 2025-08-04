//
//  swaeApp.swift
//  swae
//
//  Created by Suhail Saqan on 8/11/24.
//

import SwiftUI
import NostrSDK
import SwiftData

@main
struct swaeApp: App {
    let container: ModelContainer

    @State private var appState: AppState
    @StateObject private var orientationMonitor = OrientationMonitor()
    @StateObject var model: Model
    static var globalModel: Model?

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Register Nostr event transformer
        NostrEventValueTransformer.register()

        // Initialize SwiftData container and app state
        do {
            container = try ModelContainer(for: AppSettings.self, PersistentNostrEvent.self)
            appState = AppState(modelContext: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer for AppSettings and PersistentNostrEvent.")
        }

        // Load persisted data
        loadAppSettings()
        loadNostrEvents()
        appState.updateRelayPool()
        appState.refresh()

        // Initialize model and set global reference
        swaeApp.globalModel = Model()
        _model = StateObject(wrappedValue: swaeApp.globalModel!)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(modelContext: container.mainContext)
                .environmentObject(appState)
                .environmentObject(KeychainHelper.shared)
                .environmentObject(orientationMonitor)
                .environmentObject(model)
        }
        .modelContainer(container)
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
                newAppSettings.activeProfile?.profileSettings?.relayPoolSettings?.relaySettingsList.append(
                    RelaySettings(relayURLString: AppState.defaultRelayURLString)
                )
            } catch {
                fatalError("Unable to save initial AppSettings.")
            }
        }
    }

    @MainActor
    private func loadNostrEvents() {
        let descriptor = FetchDescriptor<PersistentNostrEvent>()
        let persistentNostrEvents = (try? container.mainContext.fetch(descriptor)) ?? []
        print("loaded nostr events: ", persistentNostrEvents.count)
        appState.loadPersistentNostrEvents(persistentNostrEvents)

        appState.refreshFollowedPubkeys()
    }
}

struct ExternalScreenContentView: View {
    @StateObject var model: Model

    init() {
        _model = StateObject(wrappedValue: swaeApp.globalModel!)
    }

    var body: some View {
        ExternalDisplayView()
            .ignoresSafeArea()
            .environmentObject(model)
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let model = swaeApp.globalModel else { return }
        model.handleSettingsUrls(urls: connectionOptions.urlContexts)
        if session.role == .windowExternalDisplayNonInteractive, let windowScene = scene as? UIWindowScene {
            model.externalMonitorConnected(windowScene: windowScene)
        }
    }

    func sceneDidDisconnect(_: UIScene) {
        guard let model = swaeApp.globalModel else { return }
        model.externalMonitorDisconnected()
    }

    func scene(_: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        swaeApp.globalModel?.handleSettingsUrls(urls: urlContexts)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .landscape {
        didSet {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windowScene.requestGeometryUpdate(
                        .iOS(interfaceOrientations: orientationLock)
                    )
                }
            }
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    func application(_: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options _: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }

    func application(_: UIApplication, willFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
