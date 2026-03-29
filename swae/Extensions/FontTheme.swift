//
//  FontTheme.swift
//  swae
//
//  Global font theming for the app.
//  Change `appFontDesign` to switch the entire app's font feel.
//

import SwiftUI

// MARK: - App Font Configuration

/// The font design used across the app.
/// Switch to `.default`, `.serif`, `.monospaced`, or use a custom font name.
let appFontDesign: Font.Design = .rounded

/// A view modifier that applies the app's font design to all text in a view hierarchy.
struct AppFontModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fontDesign(appFontDesign)
    }
}

extension View {
    /// Apply the app-wide font design to this view and all its children.
    func appFont() -> some View {
        modifier(AppFontModifier())
    }
}
