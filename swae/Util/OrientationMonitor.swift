//
//  OrientationMonitor.swift
//  swae
//
//  Created by Suhail Saqan on 2/4/25.
//

import SwiftUI

class OrientationMonitor: ObservableObject {
    @Published var isLandscape: Bool = false
    private var manualOverride: Bool = false  // Track if manual rotation is active

    init() {
        detectCurrentOrientation() // Initialize with correct value
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(detectOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    /// Detects current device orientation using `UIWindowScene`
    private func detectCurrentOrientation() {
        guard !manualOverride else { return } // Prevent auto-updates when manually set
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            DispatchQueue.main.async {
                self.isLandscape = scene.interfaceOrientation.isLandscape
            }
        }
    }

    @objc private func detectOrientation() {
        detectCurrentOrientation()
    }

    /// Manually set the orientation and prevent automatic updates
    func setOrientation(to orientation: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        manualOverride = true  // Prevent system from overriding
        let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientation)

        windowScene.requestGeometryUpdate(geometryPreferences) { error in
            print("Failed to update geometry: \(error.localizedDescription)")
//            if let error = error {
//                print("Failed to update geometry: \(error.localizedDescription)")
//            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() /* + 1*/) {  // Allow time for update
            self.isLandscape = orientation == .landscape
            self.manualOverride = false  // Re-enable auto-detection
        }
    }
}
