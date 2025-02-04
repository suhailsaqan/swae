//
//  SwiftUI+LocalizedStringResource.swift
//  swae
//
//  Created by Suhail Saqan on 1/6/24.
//

import SwiftUI

extension Button where Label == Text {

    /// Creates a button that generates its label from a localized string resource.
    ///
    /// This initializer creates a ``Text`` view on your behalf.
    ///
    /// - Parameters:
    ///   - title: The string resource for the button's localized title, that describes
    ///     the purpose of the button's `action`.
    ///   - action: The action to perform when the user triggers the button.
    init(_ title: LocalizedStringResource, action: @escaping () -> Void) {
        self.init(String(localized: title), action: action)
    }
}

extension Label where Title == Text, Icon == Image {

    /// Creates a label with a system icon image and a title generated from a
    /// localized string resource.
    ///
    /// - Parameters:
    ///    - title: A title generated from a localized string resource.
    ///    - systemImage: The name of the image resource to lookup.
    init(_ title: LocalizedStringResource, systemImage name: String) {
        self.init(String(localized: title), systemImage: name)
    }
}

extension Link where Label == Text {

    /// Creates a control, consisting of a URL and a localized title string resource, used to
    /// navigate to a URL.
    ///
    /// Use ``Link`` to create a control that your app uses to navigate to a
    /// URL that you provide. The example below creates a link to
    /// `example.com` and uses `.localizable.visitExampleCo` as the localized title string resource to
    /// generate a link-styled view in your app:
    ///
    ///     Link(.localizable.visitExampleCo,
    ///           destination: URL(string: "https://www.example.com/")!)
    ///
    /// - Parameters:
    ///     - title: The localized title string resource that describes the
    ///       purpose of this link.
    ///     - destination: The URL for the link.
    init(_ title: LocalizedStringResource, destination: URL) {
        self.init(String(localized: title), destination: destination)
    }
}

extension Picker where Label == Text {

    /// Creates a picker that generates its label from a localized string resource.
    ///
    /// - Parameters:
    ///     - title: A localized string resource that describes the purpose of selecting an option.
    ///     - selection: A binding to a property that determines the
    ///       currently-selected option.
    ///     - content: A view that contains the set of options.
    ///
    /// This initializer creates a ``Text`` view on your behalf.
    init(
        _ title: LocalizedStringResource, selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(String(localized: title), selection: selection, content: content)
    }
}

//extension SecureField where Label == Text {
//
//    /// Creates a secure field with a prompt generated from a `Text`.
//    ///
//    /// Use the ``View/onSubmit(of:_:)`` modifier to invoke an action
//    /// whenever someone submits this secure field --- for example, by
//    /// pressing the Return key.
//    ///
//    /// - Parameters:
//    ///   - title: A localized string resource for the title. The title
//    ///     describes the purpose of the field.
//    ///   - text: A binding to the text that the field displays and edits.
//    init(_ title: LocalizedStringResource, text: Binding<String>) {
//        self.init(String(localized: title), text: text)
//    }
//}

extension TextField where Label == Text {

    /// Creates a text field with a text label generated from a localized title
    /// string resource.
    ///
    /// - Parameters:
    ///   - localized: The string resource for the localized title of the text field,
    ///     describing its purpose.
    ///   - text: The text to display and edit.
    init(localized: LocalizedStringResource, text: Binding<String>) {
        self.init(String(localized: localized), text: text)
    }
}

extension Toggle where Label == Text {

    /// Creates a toggle that generates its label from a localized string key.
    ///
    /// This initializer creates a ``Text`` view on your behalf, and treats the
    /// localized key similar to ``Text/init(_:tableName:bundle:comment:)``. See
    /// `Text` for more information about localizing strings.
    ///
    /// To initialize a toggle with a string variable, use
    /// ``Toggle/init(_:isOn:)-2qurm`` instead.
    ///
    /// - Parameters:
    ///   - localized: The string resource for the toggle's localized title, that describes
    ///     the purpose of the toggle.
    ///   - isOn: A binding to a property that indicates whether the toggle is
    ///    on or off.
    init(_ localized: LocalizedStringResource, isOn: Binding<Bool>) {
        self.init(String(localized: localized), isOn: isOn)
    }
}

extension View {

    /// Configures the view's title for purposes of navigation,
    /// using a localized string resource.
    ///
    /// A view's navigation title is used to visually display
    /// the current navigation state of an interface.
    /// On iOS and watchOS, when a view is navigated to inside
    /// of a navigation view, that view's title is displayed
    /// in the navigation bar. On iPadOS, the primary destination's
    /// navigation title is reflected as the window's title in the
    /// App Switcher. Similarly on macOS, the primary destination's title
    /// is used as the window title in the titlebar, Windows menu
    /// and Mission Control.
    ///
    /// Refer to the <doc:Configure-Your-Apps-Navigation-Titles> article
    /// for more information on navigation title modifiers.
    ///
    /// - Parameter title: The localized string resource to display.
    func navigationTitle(_ title: LocalizedStringResource) -> some View {
        navigationTitle(String(localized: title))
    }

    func confirmationDialog<A>(
        _ title: LocalizedStringResource, isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> A
    ) -> some View where A: View {
        confirmationDialog(
            String(localized: title), isPresented: isPresented, titleVisibility: titleVisibility,
            actions: actions)
    }
}
