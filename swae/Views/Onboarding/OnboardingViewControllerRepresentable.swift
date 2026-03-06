//
//  OnboardingViewControllerRepresentable.swift
//  swae
//
//  SwiftUI wrapper for UIKit onboarding flow.
//  Starts with the globe zoom-out animation, then transitions
//  to the feature carousel onboarding.
//

import SwiftUI

struct OnboardingViewControllerRepresentable: UIViewControllerRepresentable {
    @EnvironmentObject var appState: AppState
    @Binding var hasCompletedOnboarding: Bool

    func makeUIViewController(context: Context) -> UINavigationController {
        // Globe zoom animation commented out — go straight to feature carousel
        // let globeVC = GlobeZoomViewController()
        // globeVC.delegate = context.coordinator

        let onboardingVC = OnboardingViewController(appState: appState)
        onboardingVC.delegate = context.coordinator

        let navController = UINavigationController(rootViewController: onboardingVC)
        navController.setNavigationBarHidden(true, animated: false)
        navController.modalPresentationStyle = .fullScreen

        context.coordinator.navController = navController

        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, /* GlobeZoomViewControllerDelegate, */ OnboardingViewControllerDelegate {
        var parent: OnboardingViewControllerRepresentable
        weak var navController: UINavigationController?

        init(_ parent: OnboardingViewControllerRepresentable) {
            self.parent = parent
        }

        // MARK: - GlobeZoomViewControllerDelegate (commented out — globe disabled)

        // func globeZoomDidComplete() {
        //     pushOnboarding()
        // }

        // func globeZoomDidSkip() {
        //     pushOnboarding()
        // }

        // private func pushOnboarding() {
        //     guard let nav = navController else { return }
        //     let onboardingVC = OnboardingViewController(appState: parent.appState)
        //     onboardingVC.delegate = self
        //     nav.setViewControllers([onboardingVC], animated: true)
        // }

        // MARK: - OnboardingViewControllerDelegate

        func onboardingDidComplete() {
            parent.hasCompletedOnboarding = true
        }

        func onboardingDidSkip() {
            parent.hasCompletedOnboarding = true
        }
    }
}
