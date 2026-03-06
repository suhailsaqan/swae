//
//  MainTabBarRepresentable.swift
//  swae
//
//  SwiftUI wrapper for tab bar controller (supports both legacy and modern)
//

import SwiftUI
import UIKit

struct MainTabBarRepresentable: UIViewControllerRepresentable {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var model: Model

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = MainTabBarFactory.create(appState: appState, model: model)
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update if needed
    }
}

// MARK: - SwiftUI View Modifier

extension View {
    func mainTabBar() -> some View {
        MainTabBarRepresentable()
    }
}
