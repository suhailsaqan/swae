//
//  swaeApp.swift
//  swae
//
//  Created by Suhail Saqan on 8/11/24.
//

import Combine
import NostrSDK
import SwiftData
import SwiftUI

@main
class SwaeAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Block all network requests
        // URLProtocol.registerClass(NetworkBlocker.self)
        
        // Seed the Coinos API key into the Keychain on first launch
        CoinosSecrets.bootstrapIfNeeded()
        
        // Initialize app coordinator on main thread
        // This will be called before scene setup, ensuring coordinator is ready
        return true
    }
    
    /// Sets UIKit appearance proxies to use the rounded system font design,
    /// matching the SwiftUI `.fontDesign(.rounded)` applied in ContentView.
    private func applyGlobalUIKitFontAppearance() {
        let roundedDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        let roundedFont = UIFont(descriptor: roundedDescriptor, size: 0)
        
        // Navigation bar titles
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont(descriptor: roundedDescriptor.withSymbolicTraits(.traitBold) ?? roundedDescriptor, size: 34)
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont(descriptor: roundedDescriptor.withSymbolicTraits(.traitBold) ?? roundedDescriptor, size: 17)
        ]
        
        // Tab bar items
        let tabBarAppearance = UITabBarItem.appearance()
        tabBarAppearance.setTitleTextAttributes([.font: UIFont(descriptor: roundedDescriptor, size: 10)], for: .normal)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

struct ExternalScreenContentView: View {
    var body: some View {
        ExternalDisplayView(externalDisplay: AppCoordinator.shared.model.externalDisplay)
            .ignoresSafeArea()
            .environmentObject(AppCoordinator.shared.model)
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Initialize app coordinator (this should be on main thread already)
        do {
            try AppCoordinator.shared.initialize()
        } catch {
            fatalError("Failed to initialize AppCoordinator: \(error)")
        }

        // Handle external display
        if session.role == .windowExternalDisplayNonInteractive {
            AppCoordinator.shared.model.externalMonitorConnected(windowScene: windowScene)
            return
        }

        // Main window setup
        let window = UIWindow(windowScene: windowScene)

        // Set RootViewController as window root
        let rootVC = RootViewController.instance

        // Create SwiftUI content view with all environment objects
        let contentView = AppCoordinator.shared.createContentView()
        let hostingController = UIHostingController(rootView: contentView)

        // Set hosting controller as child of RootViewController
        rootVC.setChild(hostingController)

        // Setup app state observer for live player presentation
        rootVC.setupAppStateObserver(appState: AppCoordinator.shared.appState)

        // Set window root and make visible
        window.rootViewController = rootVC
        self.window = window
        window.makeKeyAndVisible()

        // Bridge animation: overlay that matches the launch screen, then fades out
        let launchOverlay = UIView(frame: window.bounds)
        launchOverlay.backgroundColor = UIColor(red: 0.008, green: 0.008, blue: 0.035, alpha: 1.0) // #020209

        let logoView = UIImageView(image: UIImage(named: "SwaeLogo"))
        logoView.contentMode = .scaleAspectFit
        logoView.frame = CGRect(x: 0, y: 0, width: 300, height: 75)
        logoView.center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
        launchOverlay.addSubview(logoView)

        window.addSubview(launchOverlay)

        // Phase 1: hold briefly so the overlay feels seamless with the launch screen
        UIView.animate(
            withDuration: 0.25,
            delay: 0.05,
            options: [.curveEaseIn]
        ) {
            logoView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            logoView.alpha = 0
        } completion: { _ in
            UIView.animate(withDuration: 0.15) {
                launchOverlay.alpha = 0
            } completion: { _ in
                launchOverlay.removeFromSuperview()
            }
        }

        // Handle deep links — check for Meta Wearables callback first
        for context in connectionOptions.urlContexts {
            if let components = URLComponents(url: context.url, resolvingAgainstBaseURL: false),
               components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
            {
                Task {
                    await AppCoordinator.shared.model.metaGlassesManager?.handleUrl(context.url)
                }
                return
            }
        }
        // Handle deep links to watch streams on cold launch: swae://watch/<pubkey>:<dTag>
        for context in connectionOptions.urlContexts {
            let url = context.url
            if url.scheme == "swae" && url.host == "watch" || url.path.hasPrefix("/watch/") {
                let streamId = url.host == "watch"
                    ? String(url.path.dropFirst())
                    : String(url.path.dropFirst("/watch/".count))
                if !streamId.isEmpty {
                    // Delay to let the app finish initializing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.handleWatchDeepLink(streamId: streamId)
                    }
                    return
                }
            }
        }
        AppCoordinator.shared.model.handleSettingsUrls(urls: connectionOptions.urlContexts)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppCoordinator.shared.model.externalMonitorDisconnected()
    }

    func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        // Check for Meta Wearables SDK callback first
        for context in urlContexts {
            if let components = URLComponents(url: context.url, resolvingAgainstBaseURL: false),
               components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
            {
                Task {
                    await AppCoordinator.shared.model.metaGlassesManager?.handleUrl(context.url)
                }
                return
            }
        }
        // Handle deep links to watch streams: swae://watch/<pubkey>:<dTag>
        for context in urlContexts {
            let url = context.url
            if url.scheme == "swae" && url.host == "watch" || url.path.hasPrefix("/watch/") {
                let streamId = url.host == "watch"
                    ? String(url.path.dropFirst()) // swae://watch/<id> → host="watch", path="/<id>"
                    : String(url.path.dropFirst("/watch/".count)) // swae:///watch/<id>
                if !streamId.isEmpty {
                    handleWatchDeepLink(streamId: streamId)
                    return
                }
            }
        }
        AppCoordinator.shared.model.handleSettingsUrls(urls: urlContexts)
    }

    /// Handle swae://watch/<pubkey>:<dTag> deep links by finding the stream event
    /// in AppState's cache (populated by the relay pool) and opening the video player.
    private func handleWatchDeepLink(streamId: String) {
        guard let colonIdx = streamId.firstIndex(of: ":") else {
            print("⚠️ Deep link: invalid streamId format (no colon): \(streamId)")
            return
        }
        let pubkey = String(streamId[streamId.startIndex..<colonIdx])
        let dTag = String(streamId[streamId.index(after: colonIdx)...])

        guard !pubkey.isEmpty, !dTag.isEmpty else {
            print("⚠️ Deep link: empty pubkey or dTag")
            return
        }

        print("🔗 Deep link: opening stream pubkey=\(pubkey.prefix(8))... dTag=\(dTag)")

        let appState = AppCoordinator.shared.appState!

        // Try to find the event in the existing cache (relay pool already fetches these)
        if let event = findLiveEvent(pubkey: pubkey, dTag: dTag, appState: appState) {
            print("🔗 Deep link: found cached event, opening player")
            appState.playerConfig.selectedLiveActivitiesEvent = event
            appState.playerConfig.showMiniPlayer = true
            return
        }

        // Not in cache yet — the relay pool is likely still syncing.
        // Observe liveActivitiesEvents until the event appears or we time out.
        print("🔗 Deep link: event not in cache, waiting for relay sync...")
        var cancellable: AnyCancellable?
        var timedOut = false

        cancellable = appState.$liveActivitiesEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] _ in
                guard let appState, !timedOut else { return }
                if let event = self.findLiveEvent(pubkey: pubkey, dTag: dTag, appState: appState) {
                    print("🔗 Deep link: event arrived from relay, opening player")
                    cancellable?.cancel()
                    appState.playerConfig.selectedLiveActivitiesEvent = event
                    appState.playerConfig.showMiniPlayer = true
                }
            }

        // Timeout after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            timedOut = true
            cancellable?.cancel()
            print("⚠️ Deep link: timed out waiting for event from relays")
        }
    }

    /// Look up a LiveActivitiesEvent by pubkey and dTag from AppState's cache.
    private func findLiveEvent(pubkey: String, dTag: String, appState: AppState) -> LiveActivitiesEvent? {
        // The liveActivitiesEvents dict is keyed by pubkey
        if let events = appState.liveActivitiesEvents[pubkey] {
            return events.first { $0.identifier == dTag }
        }
        // Also check all events in case the key structure is different
        return appState.getAllEvents().first { $0.pubkey == pubkey && $0.identifier == dTag }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait {
        didSet {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windowScene
                        .requestGeometryUpdate(
                            .iOS(interfaceOrientations: orientationLock)
                        )
                }
            }
            // For some reason new way of doing this does not work in all
            // cases. See repo log.
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }

    func application(
        _: UIApplication,
        willFinishLaunchingWithOptions _: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication
            .LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(
        _: UIApplication,
        supportedInterfaceOrientationsFor _: UIWindow?
    )
        -> UIInterfaceOrientationMask
    {
        return AppDelegate.orientationLock
    }
}
