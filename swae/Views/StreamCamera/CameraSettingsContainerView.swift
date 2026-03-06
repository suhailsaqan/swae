//
//  CameraSettingsContainerView.swift
//  swae
//
//  Settings view for camera container - wraps UIKit ControlPanelViewController
//

import SwiftUI

struct CameraSettingsContainerView: View {
    @EnvironmentObject var model: Model
    
    var body: some View {
        ControlPanelViewControllerWrapper()
            .ignoresSafeArea()
    }
}

// MARK: - UIViewControllerRepresentable Wrapper

struct ControlPanelViewControllerWrapper: UIViewControllerRepresentable {
    @EnvironmentObject var model: Model
    
    func makeUIViewController(context: Context) -> ControlPanelViewController {
        let controller = ControlPanelViewController()
        controller.model = model
        return controller
    }
    
    func updateUIViewController(_ uiViewController: ControlPanelViewController, context: Context) {
        uiViewController.updateFromModel()
    }
}


