//
//  AboutView.swift
//  swae
//
//  Created by Suhail Saqan on 2/24/25.
//

import SwiftUI

struct AboutView: View {
    let about: String
    let appState: AppState
    let max_about_length: Int
    let text_alignment: NSTextAlignment
    var onProfileTap: ((String) -> Void)?
    
    @State var show_full_about: Bool = false
    
    init(
        about: String,
        appState: AppState,
        max_about_length: Int? = nil,
        text_alignment: NSTextAlignment? = nil,
        onProfileTap: ((String) -> Void)? = nil
    ) {
        self.about = about
        self.appState = appState
        self.max_about_length = max_about_length ?? 280
        self.text_alignment = text_alignment ?? .natural
        self.onProfileTap = onProfileTap
    }
    
    var body: some View {
        Group {
            let displayText = show_full_about ? about : truncatedAbout
            
            TappableNostrText(
                content: displayText,
                appState: appState,
                onProfileTap: onProfileTap
            )
            .font(.subheadline)
            
            if about.count > max_about_length {
                Button(show_full_about
                    ? NSLocalizedString("Show less", comment: "Button to show less of a long profile description.")
                    : NSLocalizedString("Show more", comment: "Button to show more of a long profile description.")
                ) {
                    show_full_about.toggle()
                }
                .font(.footnote)
            }
        }
    }
    
    private var truncatedAbout: String {
        if about.count > max_about_length {
            // Find a good break point (space) near the max length
            let endIndex = about.index(about.startIndex, offsetBy: max_about_length, limitedBy: about.endIndex) ?? about.endIndex
            let substring = about[..<endIndex]
            
            // Try to break at a space
            if let lastSpace = substring.lastIndex(of: " ") {
                return String(about[..<lastSpace]) + "..."
            }
            return String(substring) + "..."
        }
        return about
    }
}
