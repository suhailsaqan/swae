//
//  swaeApp.swift
//  swae
//
//  Created by Suhail Saqan on 8/11/24.
//

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
            withDuration: 0.4,
            delay: 0.1,
            options: [.curveEaseIn]
        ) {
            logoView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            logoView.alpha = 0
        } completion: { _ in
            UIView.animate(withDuration: 0.2) {
                launchOverlay.alpha = 0
            } completion: { _ in
                launchOverlay.removeFromSuperview()
            }
        }

        // Handle deep links
        AppCoordinator.shared.model.handleSettingsUrls(urls: connectionOptions.urlContexts)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppCoordinator.shared.model.externalMonitorDisconnected()
    }

    func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        AppCoordinator.shared.model.handleSettingsUrls(urls: urlContexts)
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
