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
        detectCurrentOrientation()  // Initialize with correct value
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(detectOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    /// Detects current device orientation using `UIWindowScene`
    private func detectCurrentOrientation() {
        guard !manualOverride else {
            print("🔒 OrientationMonitor: Manual override active, skipping auto-detection")
            return
        }
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            DispatchQueue.main.async {
                let newIsLandscape = scene.interfaceOrientation.isLandscape
                print(
                    "🔄 OrientationMonitor: Detected orientation change: \(scene.interfaceOrientation.rawValue), isLandscape: \(newIsLandscape)"
                )
                self.isLandscape = newIsLandscape
            }
        }
    }

    @objc private func detectOrientation() {
        detectCurrentOrientation()
    }

    /// Manually set the orientation and prevent automatic updates
    func setOrientation(to orientation: UIInterfaceOrientationMask) {
        print("🎯 OrientationMonitor: Setting orientation to \(orientation)")
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("❌ OrientationMonitor: No window scene found")
            return
        }

        manualOverride = true  // Prevent system from overriding
        let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: orientation)

        windowScene.requestGeometryUpdate(geometryPreferences) { error in
            if error != nil {
                print(
                    "❌ OrientationMonitor: Failed to update geometry: \(error.localizedDescription)"
                )
            } else {
                print("✅ OrientationMonitor: Geometry update successful")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let newIsLandscape =
                orientation.contains(.landscapeLeft) || orientation.contains(.landscapeRight)
            self.isLandscape = newIsLandscape
            self.manualOverride = false
        }
    }
}
