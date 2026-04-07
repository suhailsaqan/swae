//
//  ModernTabBarController.swift
//  swae
//
//  Modern tab bar controller for iOS 18+ with liquid glass effect
//

import Combine
import Kingfisher
import SwiftUI
import UIKit

@available(iOS 18.0, *)
final class ModernTabBarController: UITabBarController, MainTabBarProtocol {
    weak var appState: AppState?
    weak var model: Model?
    
    private var cancellables = Set<AnyCancellable>()
    private var metadataUpdateTimer: Timer?
    private var pendingMetadataUpdate = false
    
    private let mainTabs: [MainTab] = [.wallet, .home, .profile]
    
    // Wrapper for backward compatibility with VideoListViewController
    // Return tabBar directly so transforms work
    var vStack: UIView {
        tabBar
    }
    
    var currentTab: MainTab {
        return mainTabs[safe: selectedIndex] ?? .home
    }
    
    // Lazy loaded view controllers
    lazy var home: VideoListViewController = {
        guard let appState = appState, let model = model else {
            fatalError("AppState and Model must be set before accessing home")
        }
        let orientationMonitor = OrientationMonitor()
        return VideoListViewController(appState: appState, orientationMonitor: orientationMonitor)
    }()
    
    lazy var wallet: UIHostingController<AnyView> = {
        guard let appState = appState else {
            fatalError("AppState must be set before accessing wallet")
        }
        let view = WalletTabView(onNavigateToProfile: { [weak self] in
            self?.switchToTab(.profile, open: nil)
        })
        .environmentObject(appState)
        return UIHostingController(rootView: AnyView(view))
    }()
    
    lazy var profile: ProfileViewController = {
        guard let appState = appState else {
            fatalError("AppState must be set before accessing profile")
        }
        return ProfileViewController(appState: appState)
    }()
    
    init(appState: AppState, model: Model) {
        self.appState = appState
        self.model = model
        super.init(nibName: nil, bundle: nil)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTabBarItems()
    }
    
    deinit {
        metadataUpdateTimer?.invalidate()
        metadataUpdateTimer = nil
    }
    
    // MARK: - MainTabBarProtocol
    
    func switchToTab(_ tab: MainTab, open vc: UIViewController? = nil) {
        guard let tabIndex = mainTabs.firstIndex(of: tab) else { return }
        
        // Check if already on this tab
        if selectedIndex == tabIndex {
            // Scroll to top - need to find scroll views in the navigation controller's root VC
            if let navController = viewControllers?[tabIndex] as? UINavigationController,
               let rootVC = navController.viewControllers.first,
               let scrollViews = rootVC.view.findAllSubviews() as? [UIScrollView] {
                scrollViews.forEach {
                    if $0.delegate?.scrollViewShouldScrollToTop?($0) ?? true {
                        $0.setContentOffset(.zero, animated: true)
                    }
                }
            }
            return
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Switch tab
        selectedIndex = tabIndex
    }
    
    func setCustomTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard tabBar.isHidden != hidden else { return }
        
        if !animated {
            tabBar.isHidden = hidden
            return
        }
        
        if hidden {
            // Fade out then hide
            UIView.animate(withDuration: 0.25, animations: {
                self.tabBar.alpha = 0
            }, completion: { _ in
                self.tabBar.isHidden = true
                self.tabBar.alpha = 1
            })
        } else {
            // Unhide then fade in
            tabBar.alpha = 0
            tabBar.isHidden = false
            UIView.animate(withDuration: 0.25) {
                self.tabBar.alpha = 1
            }
        }
    }
    
    func hideForMenu() {
        UIView.animate(withDuration: 0.3) {
            self.tabBar.alpha = 0
        }
    }
    
    func showButtons() {
        UIView.animate(withDuration: 0.3) {
            self.tabBar.alpha = 1
        }
    }
    
    func revealCamera() {
        // InstagramNavigationController is our parent - search up the responder chain
        if let instagramNav = findParentInstagramNavigationController() {
            instagramNav.revealCamera()
        }
    }
    
    private func findParentInstagramNavigationController() -> InstagramNavigationController? {
        // Search up the responder chain from this view controller
        var responder: UIResponder? = self
        while let current = responder {
            if let instagramNav = current as? InstagramNavigationController {
                return instagramNav
            }
            responder = current.next
        }
        return nil
    }
    
}

// MARK: - Private Setup

@available(iOS 18.0, *)
extension ModernTabBarController {
    private func setup() {
        // Wrap each view controller in UINavigationController for push navigation
        // This enables Instagram-style profile navigation (tap profile pic → push profile)
        let homeNav = UINavigationController(rootViewController: home)
        homeNav.setNavigationBarHidden(true, animated: false)
        homeNav.interactivePopGestureRecognizer?.isEnabled = true
        homeNav.interactivePopGestureRecognizer?.delegate = self
        
        let walletNav = UINavigationController(rootViewController: wallet)
        walletNav.setNavigationBarHidden(true, animated: false)
        
        let profileNav = UINavigationController(rootViewController: profile)
        profileNav.setNavigationBarHidden(true, animated: false)
        profileNav.interactivePopGestureRecognizer?.isEnabled = true
        profileNav.interactivePopGestureRecognizer?.delegate = self
        
        // Layout: [wallet, home, profile]
        viewControllers = [walletNav, homeNav, profileNav]
        
        // Default to home tab (center)
        selectedIndex = 1
        
        // Configure liquid glass appearance
        configureLiquidGlassAppearance()
        
        // Setup tab bar items
        setupTabBarItems()
        
        // Set delegate for tab selection
        delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observeMetadataChanges()
    }
    
    private func configureLiquidGlassAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // iOS 18+ liquid glass effect
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        
        // Subtle shadow for depth
        appearance.shadowColor = .black.withAlphaComponent(0.1)
        appearance.shadowImage = nil
        
        // Configure item appearance
        let itemAppearance = UITabBarItemAppearance()
        
        // Normal state
        itemAppearance.normal.iconColor = .tertiaryLabel
        itemAppearance.normal.titleTextAttributes = [:]
        
        // Selected state with accent color
        itemAppearance.selected.iconColor = .accentPurple
        itemAppearance.selected.titleTextAttributes = [:]
        
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance
        
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        
        // Modern styling
        tabBar.tintColor = .accentPurple
        tabBar.unselectedItemTintColor = .tertiaryLabel
    }
    
    private func setupTabBarItems() {
        guard let viewControllers = viewControllers else { return }
        
        for (index, vc) in viewControllers.enumerated() {
            let tab = mainTabs[index]
            
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold, scale: .medium)
            
            let item = UITabBarItem(
                title: nil,
                image: tab.tabImage?.withConfiguration(config),
                selectedImage: tab.selectedTabImage?.withConfiguration(config)
            )
            
            // Consistent insets for all tabs
            item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            
            vc.tabBarItem = item
        }
        
        updateTabBarItems()
    }
    
    private func updateTabBarItems() {
        guard let viewControllers = viewControllers else { return }
        
        // Update profile tab with profile picture if available
        let profileTabIndex = mainTabs.firstIndex(of: .profile) ?? 2
        
        if profileTabIndex < viewControllers.count {
            updateProfileTabBarItem(at: profileTabIndex)
        }
    }
    
    private func updateProfileTabBarItem(at index: Int) {
        guard let appState = appState,
              let publicKey = appState.publicKey,
              let metadata = appState.metadataEvents[publicKey.hex],
              let pictureURL = metadata.userMetadata?.pictureURL,
              let viewControllers = viewControllers,
              index < viewControllers.count else {
            return
        }
        
        // Download and create circular profile image with proper alignment
        KingfisherManager.shared.retrieveImage(with: pictureURL) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let imageResult):
                // Create images with alignment rect to match SF Symbols
                let profileImage = self.createCircularImageWithAlignment(from: imageResult.image, size: 28)
                let selectedProfileImage = self.createCircularImageWithAlignment(from: imageResult.image, size: 28, withBorder: true)
                
                DispatchQueue.main.async {
                    let item = viewControllers[index].tabBarItem
                    item?.image = profileImage?.withRenderingMode(.alwaysOriginal)
                    item?.selectedImage = selectedProfileImage?.withRenderingMode(.alwaysOriginal)
                }
                
            case .failure:
                // Keep default icon on failure
                break
            }
        }
    }
    
    private func createCircularImageWithAlignment(from image: UIImage, size: CGFloat, withBorder: Bool = false) -> UIImage? {
        // Create image with proper alignment rect to match SF Symbols
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let circularImage = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            
            // Clip to circle
            UIBezierPath(ovalIn: rect).addClip()
            
            // Draw image
            image.draw(in: rect)
            
            // Add border if selected
            if withBorder {
                context.cgContext.setStrokeColor(UIColor.accentPurple.cgColor)
                context.cgContext.setLineWidth(2)
                context.cgContext.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
            }
        }
        
        // Set alignment rect insets to center the image properly
        // This matches how SF Symbols are aligned in tab bars
        return circularImage.withAlignmentRectInsets(UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
    }
    
    private func observeMetadataChanges() {
        // Only react when the CURRENT USER's metadata changes, not every metadata event.
        // Extract just the current user's picture URL and only fire when it actually changes.
        appState?.$metadataEvents
            .compactMap { [weak self] events -> URL? in
                guard let pubkey = self?.appState?.publicKey?.hex,
                      let metadata = events[pubkey] else { return nil }
                return metadata.userMetadata?.pictureURL
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTabBarItems()
            }
            .store(in: &cancellables)
        
        // Observe active profile changes to update tab bar when user switches profiles
        appState?.$activeProfileId
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleMetadataUpdate()
            }
            .store(in: &cancellables)
    }
    
    private func scheduleMetadataUpdate() {
        pendingMetadataUpdate = true
        metadataUpdateTimer?.invalidate()
        
        metadataUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            guard let self = self, self.pendingMetadataUpdate else { return }
            self.pendingMetadataUpdate = false
            
            DispatchQueue.main.async {
                self.updateTabBarItems()
            }
        }
    }
}

// MARK: - UITabBarControllerDelegate

@available(iOS 18.0, *)
extension ModernTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Notify feed visibility based on selected tab
        let isFeedVisible = currentTab == .home
        notify(.feed_visibility(isFeedVisible))
    }
}

// MARK: - UIGestureRecognizerDelegate

@available(iOS 18.0, *)
extension ModernTabBarController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow interactive pop gesture only when there's something to pop
        if let navController = selectedViewController as? UINavigationController {
            return navController.viewControllers.count > 1
        }
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't allow simultaneous recognition with InstagramNavigationController's pan gesture
        // when we have a pushed view controller
        return false
    }
}
