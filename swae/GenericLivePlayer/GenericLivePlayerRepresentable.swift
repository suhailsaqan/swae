//
//  GenericLivePlayerRepresentable.swift
//  swae
//
//  SwiftUI wrapper for the UIKit live player
//

import NostrSDK
import SwiftUI

struct GenericLivePlayerRepresentable: UIViewControllerRepresentable {
    let liveStream: LiveStream
    let liveActivitiesEvent: LiveActivitiesEvent
    let appState: AppState?

    func makeUIViewController(context: Context) -> UIViewController {
        // Return a simple view controller that will present the live player
        let containerVC = UIViewController()
        containerVC.view.backgroundColor = .clear

        // Present the live player immediately using modal presentation
        DispatchQueue.main.async {
            self.presentLivePlayer(
                liveStream: liveStream,
                liveActivitiesEvent: liveActivitiesEvent,
                appState: appState
            )
        }

        return containerVC
    }

    private func presentLivePlayer(
        liveStream: LiveStream,
        liveActivitiesEvent: LiveActivitiesEvent,
        appState: AppState?
    ) {
        let controller = GenericLivePlayerController(
            liveStream: liveStream,
            liveActivitiesEvent: liveActivitiesEvent,
            appState: appState
        )

        controller.onDismiss = {
            // Clean up chat subscription when player is FULLY dismissed
            appState?.unsubscribeFromLiveChat(for: liveActivitiesEvent)
            
            // Reset player config
            appState?.playerConfig.setHiddenState()
            appState?.playerConfig.selectedLiveActivitiesEvent = nil
        }

        RootViewController.instance.present(controller, animated: true)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - SwiftUI View for presenting the player

struct GenericLivePlayerView: View {
    let liveStream: LiveStream
    let liveActivitiesEvent: LiveActivitiesEvent
    let appState: AppState?

    var body: some View {
        GenericLivePlayerRepresentable(
            liveStream: liveStream,
            liveActivitiesEvent: liveActivitiesEvent,
            appState: appState
        )
        .ignoresSafeArea()
    }
}

// MARK: - Helper View Modifier

extension View {
    func genericLivePlayer(
        liveStream: LiveStream?,
        liveActivitiesEvent: LiveActivitiesEvent?,
        appState: AppState?
    ) -> some View {
        self.overlay {
            if let liveStream = liveStream, let liveActivitiesEvent = liveActivitiesEvent {
                GenericLivePlayerView(
                    liveStream: liveStream,
                    liveActivitiesEvent: liveActivitiesEvent,
                    appState: appState
                )
            }
        }
    }
}
