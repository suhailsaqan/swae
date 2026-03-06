//
//  MainTabBarProtocol.swift
//  swae
//
//  Protocol for tab bar controllers - supports both legacy and modern implementations
//

import UIKit

// MARK: - MainTab Enum (Shared)

enum MainTab: String, CaseIterable {
    case home, wallet, profile

    var tabImage: UIImage? {
        switch self {
        case .home:
            return UIImage(systemName: "house")
        case .wallet:
            return UIImage(systemName: "bolt.fill")
        case .profile:
            return UIImage(systemName: "person")
        }
    }

    var selectedTabImage: UIImage? {
        switch self {
        case .home:
            return UIImage(systemName: "house.fill")
        case .wallet:
            return UIImage(systemName: "bolt.fill")
        case .profile:
            return UIImage(systemName: "person.fill")
        }
    }

    var title: String {
        return rawValue.capitalized
    }
}

// MARK: - Protocol

protocol MainTabBarProtocol: UIViewController {
    var currentTab: MainTab { get }
    var vStack: UIView { get }
    
    func switchToTab(_ tab: MainTab, open vc: UIViewController?)
    func setCustomTabBarHidden(_ hidden: Bool, animated: Bool)
    func hideForMenu()
    func showButtons()
    func revealCamera()
}

// MARK: - Factory

enum MainTabBarFactory {
    static func create(appState: AppState, model: Model) -> UIViewController & MainTabBarProtocol {
        if #available(iOS 18.0, *) {
            return ModernTabBarController(appState: appState, model: model)
        } else {
            return LegacyTabBarController(appState: appState, model: model)
        }
    }
}

// MARK: - UIViewController Extension

extension UIViewController {
    var mainTabBarController: (UIViewController & MainTabBarProtocol)? {
        if let tabBar = parent as? (UIViewController & MainTabBarProtocol) {
            return tabBar
        }
        return parent?.mainTabBarController
    }
}
