//
//  MainTabBarController.swift
//  swae
//
//  Legacy tab bar controller for iOS 17 and below
//

import Combine
import Kingfisher
import SwiftUI
import UIKit

final class LegacyTabBarController: UIViewController, MainTabBarProtocol {
    // Lazy loaded view controllers
    weak var appState: AppState?
    weak var model: Model?

    // Combine cancellables for observing metadata changes
    private var cancellables = Set<AnyCancellable>()

    // Debounce timer for metadata updates to prevent excessive UI updates
    private var metadataUpdateTimer: Timer?
    private var pendingMetadataUpdate = false

    // HOME TAB: Pure UIKit - no wrapper needed! ✅
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
    
    // Navigation controllers for push navigation support
    private lazy var navigationControllers: [MainTab: UINavigationController] = {
        var navControllers: [MainTab: UINavigationController] = [:]
        
        let homeNav = UINavigationController(rootViewController: home)
        homeNav.setNavigationBarHidden(true, animated: false)
        homeNav.interactivePopGestureRecognizer?.isEnabled = true
        homeNav.interactivePopGestureRecognizer?.delegate = self
        navControllers[.home] = homeNav
        
        let walletNav = UINavigationController(rootViewController: wallet)
        walletNav.setNavigationBarHidden(true, animated: false)
        navControllers[.wallet] = walletNav
        
        let profileNav = UINavigationController(rootViewController: profile)
        profileNav.setNavigationBarHidden(true, animated: false)
        profileNav.interactivePopGestureRecognizer?.isEnabled = true
        profileNav.interactivePopGestureRecognizer?.delegate = self
        navControllers[.profile] = profileNav
        
        return navControllers
    }()

    let vcParentView = UIView()
    
    // Create 3 buttons: home, wallet, profile
    lazy var buttons: [UIButton] = {
        var btns: [UIButton] = []
        for _ in 0..<3 {
            btns.append(UIButton())
        }
        return btns
    }()

    // Profile image view for the profile tab button
    private let profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = 14
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true  // Hidden by default, shown when we have a profile picture
        return imageView
    }()

    private let buttonStackParent = UIView()
    private(set) lazy var vStack: UIView = {
        let stack = UIStackView(arrangedSubviews: [
            navigationBorder, buttonStackParent, safeAreaSpacer,
        ])
        stack.axis = .vertical
        return stack
    }()
    private let safeAreaSpacer = UIView()
    private let navigationBorder = UIView().constrainToSize(height: 1)

    lazy var buttonStack = UIStackView(arrangedSubviews: buttons)

    var childSafeAreaInsets = UIEdgeInsets.zero {
        didSet {
            children.forEach { $0.additionalSafeAreaInsets = childSafeAreaInsets }
        }
    }

    private let tabs: [MainTab] = [.wallet, .home, .profile]
    
    var currentPageIndex = 1 {
        didSet {
            updateButtons()
        }
    }

    var currentTab: MainTab { tabs[safe: currentPageIndex] ?? .home }

    var showTabBarBorder: Bool {
        get { navigationBorder.alpha > 0.1 }
        set {
            navigationBorder.alpha = newValue ? 1 : 0
        }
    }

    init(appState: AppState, model: Model) {
        self.appState = appState
        self.model = model
        super.init(nibName: nil, bundle: nil)
        setup()
        // Don't observe metadata changes during init - wait until view appears
        // This prevents blocking the main thread during app launch
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Setup observation after view loads, but still defer heavy work
        observeMetadataChanges()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Update buttons once view appears to ensure UI is ready
        // This is a lightweight operation that won't block
        updateButtons()
    }

    deinit {
        // Clean up timer when view controller is deallocated
        metadataUpdateTimer?.invalidate()
        metadataUpdateTimer = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hideForMenu() {
        UIView.animate(withDuration: 0.3) {
            self.buttonStack.alpha = 0
            self.showTabBarBorder = false
        }
    }

    func showButtons() {
        UIView.animate(withDuration: 0.3) {
            self.buttonStack.alpha = 1
            self.showTabBarBorder = true
        }
    }

    func setCustomTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard vStack.isHidden != hidden else { return }
        
        if !animated {
            vStack.isHidden = hidden
            return
        }
        
        if hidden {
            UIView.animate(withDuration: 0.25, animations: {
                self.vStack.alpha = 0
            }, completion: { _ in
                self.vStack.isHidden = true
                self.vStack.alpha = 1
            })
        } else {
            vStack.alpha = 0
            vStack.isHidden = false
            UIView.animate(withDuration: 0.25) {
                self.vStack.alpha = 1
            }
        }
    }

    // Tab bar transforms are now handled directly by VideoListViewController
    // using the mainTabBarController extension

    func navForTab(_ tab: MainTab) -> UIViewController {
        return navigationControllers[tab] ?? home
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
    


    func switchToTab(_ tab: MainTab, open vc: UIViewController? = nil) {
        let targetVC = navForTab(tab)
        let currentVC = navForTab(currentTab)

        defer {
            if vc != nil {
                // Handle navigation within SwiftUI views if needed
                // This would need to be implemented based on your navigation needs
            }
        }

        if targetVC == currentVC { return }

        // Notify feed visibility based on target tab
        notify(.feed_visibility(tab == .home))

        targetVC.additionalSafeAreaInsets = childSafeAreaInsets
        targetVC.beginAppearanceTransition(true, animated: true)
        currentVC.beginAppearanceTransition(false, animated: true)

        targetVC.willMove(toParent: self)
        addChild(targetVC)
        vcParentView.addSubview(targetVC.view)
        targetVC.view.pinToSuperview()
        targetVC.didMove(toParent: self)

        currentPageIndex = tabs.firstIndex(of: tab) ?? 0

        targetVC.view.alpha = 0

        UIView.animate(withDuration: 5 / 30, delay: 0, options: [.curveEaseIn]) {
            currentVC.view.alpha = 0
            currentVC.view.transform = .init(translationX: 0, y: 40)
        } completion: { _ in
            currentVC.willMove(toParent: nil)
            currentVC.removeFromParent()
            currentVC.view.removeFromSuperview()
            currentVC.didMove(toParent: nil)

            currentVC.endAppearanceTransition()

            currentVC.view.alpha = 1
            currentVC.view.transform = .identity
        }

        UIView.animate(withDuration: 5 / 30, delay: 3 / 30, options: [.curveEaseOut]) {
            targetVC.view.alpha = 1
        } completion: { _ in
            targetVC.endAppearanceTransition()
        }
    }
}

// MARK: - Private Setup Methods

extension LegacyTabBarController {
    fileprivate func setup() {
        updateTheme()

        view.addSubview(vcParentView)
        vcParentView.backgroundColor = .systemBackground
        vcParentView.pinToSuperview()

        let nav = navForTab(currentTab)
        nav.willMove(toParent: self)
        addChild(nav)
        vcParentView.addSubview(nav.view)
        nav.view.pinToSuperview()
        nav.didMove(toParent: self)

        view.addSubview(vStack)
        vStack.pinToSuperview(edges: [.bottom, .left, .right])
        safeAreaSpacer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            .isActive = true

        let background = UIView()
        background.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        buttonStackParent.addSubview(background)
        background.pinToSuperview(edges: [.top, .left, .right])
        background.pinToSuperview(edges: .bottom, padding: -100)

        // Add subtle blur effect for modern glass morphism look
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackParent.insertSubview(blurView, at: 0)
        blurView.pinToSuperview(edges: [.top, .left, .right])
        blurView.pinToSuperview(edges: .bottom, padding: -100)

        buttonStackParent.addSubview(buttonStack)
        buttonStack.pinToSuperview(edges: [.left, .right, .top])
        buttonStack.pinToSuperview(edges: .bottom, padding: -12)
        buttonStack.constrainToSize(height: 64)  // Slightly taller for modern look
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8  // Add spacing between buttons

        // Modern border styling
        navigationBorder.backgroundColor = .separator.withAlphaComponent(0.3)

        updateButtons()
    }

    fileprivate func updateButtons() {
        for (index, button) in buttons.enumerated() {
            let tab = tabs[index]
            
            // Modern styling - icons only, no text
            let isSelected = index == currentPageIndex

            // Special handling for profile tab - show profile picture if available
            if tab == .profile {
                updateProfileButton(button: button, isSelected: isSelected)
            } else {
                // Use SF Symbols with appropriate size for modern look
                let config = UIImage.SymbolConfiguration(
                    pointSize: 20, weight: .bold, scale: .medium)
                let image = isSelected ? tab.selectedTabImage : tab.tabImage
                button.setImage(image?.withConfiguration(config), for: .normal)

                // Modern color scheme with accent color for selected state
                if isSelected {
                    button.tintColor = .accentPurple  // App accent color

                    // Add subtle scale animation for selection
                    UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                        button.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                    }
                } else {
                    button.tintColor = .tertiaryLabel  // Subtle unselected state
                    button.transform = .identity
                }
            }

            // Remove any title
            button.setTitle(nil, for: .normal)
            button.titleEdgeInsets = .zero
            button.imageEdgeInsets = .zero

            // Add subtle haptic feedback on tap
            button.removeTarget(nil, action: nil, for: .allEvents)
            button.addAction(
                .init(handler: { [weak self] _ in
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    self?.menuButtonPressedForTab(tab)
                }), for: .touchUpInside)
        }
    }

    fileprivate func menuButtonPressedForTab(_ tab: MainTab) {
        guard currentTab == tab else {
            switchToTab(tab, open: nil)
            return
        }

        // Handle scroll to top for current tab
        if let scrollViews = navForTab(tab).view.findAllSubviews() as? [UIScrollView] {
            scrollViews.forEach {
                if $0.delegate?.scrollViewShouldScrollToTop?($0) ?? true {
                    $0.setContentOffset(.zero, animated: true)
                }
            }
        }
    }

    fileprivate func updateTheme() {
        view.backgroundColor = .systemBackground
        navigationBorder.backgroundColor = .separator
        updateButtons()
    }

    fileprivate func observeMetadataChanges() {
        // Observe changes to metadataEvents to update profile picture when it loads
        appState?.$metadataEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metadataEvents in
                guard let self = self,
                    let appState = self.appState,
                    let publicKey = appState.publicKey
                else { return }

                // Check if the current user's metadata was updated
                if metadataEvents[publicKey.hex] != nil {
                    // Debounce updates to prevent excessive UI refreshes
                    self.scheduleMetadataUpdate()
                }
            }
            .store(in: &cancellables)
        
        // Observe active profile changes to update tab bar when user switches profiles
        appState?.$activeProfileId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleMetadataUpdate()
            }
            .store(in: &cancellables)
    }

    /// Schedules a debounced metadata update to prevent blocking the main thread
    private func scheduleMetadataUpdate() {
        pendingMetadataUpdate = true

        // Cancel any existing timer
        metadataUpdateTimer?.invalidate()

        // Schedule update after a short delay (debounce)
        // This prevents rapid-fire updates from blocking the UI
        // Timer.scheduledTimer automatically adds to current run loop
        metadataUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) {
            [weak self] _ in
            guard let self = self, self.pendingMetadataUpdate else { return }
            self.pendingMetadataUpdate = false

            // Perform update on next run loop to avoid blocking current operations
            DispatchQueue.main.async {
                self.updateButtons()
            }
        }
    }

    fileprivate func updateProfileButton(button: UIButton, isSelected: Bool) {
        // Access cached publicKey (now fast, no database fetch)
        // Access metadataEvents dictionary (fast dictionary lookup)
        if let appState = appState,
            let publicKey = appState.publicKey,
            let metadata = appState.metadataEvents[publicKey.hex],
            let pictureURL = metadata.userMetadata?.pictureURL
        {
            // We have a profile picture - show the image view
            if profileImageView.superview == nil {
                button.addSubview(profileImageView)
                NSLayoutConstraint.activate([
                    profileImageView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    profileImageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    profileImageView.widthAnchor.constraint(equalToConstant: 28),
                    profileImageView.heightAnchor.constraint(equalToConstant: 28),
                ])
            }

            // Load the profile picture using Kingfisher (asynchronous, won't block)
            profileImageView.kf.setImage(
                with: pictureURL,
                options: [
                    .transition(.fade(0.2)),
                    .cacheOriginalImage,
                ]
            )

            profileImageView.isHidden = false
            button.setImage(nil, for: .normal)  // Hide the default icon

            // Add border for selected state
            if isSelected {
                profileImageView.layer.borderWidth = 2
                profileImageView.layer.borderColor = UIColor.accentPurple.cgColor

                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    button.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                }
            } else {
                profileImageView.layer.borderWidth = 0
                button.transform = .identity
            }
        } else {
            // No profile picture - use default person icon
            profileImageView.isHidden = true

            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold, scale: .medium)
            let image =
                isSelected ? UIImage(systemName: "person.fill") : UIImage(systemName: "person")
            button.setImage(image?.withConfiguration(config), for: .normal)

            if isSelected {
                button.tintColor = .accentPurple
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                    button.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                }
            } else {
                button.tintColor = .tertiaryLabel
                button.transform = .identity
            }
        }
    }

}

// MARK: - UIGestureRecognizerDelegate

extension LegacyTabBarController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow interactive pop gesture only when there's something to pop
        if let navController = navForTab(currentTab) as? UINavigationController {
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
