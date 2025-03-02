//
//  AboutView.swift
//  swae
//
//  Created by Suhail Saqan on 2/24/25.
//


import SwiftUI

struct AboutView: View {
    let about: String
    let max_about_length: Int
    let text_alignment: NSTextAlignment
    @State var show_full_about: Bool = false
    @State private var about_string: AttributedString? = nil
    
    init(about: String, max_about_length: Int? = nil, text_alignment: NSTextAlignment? = nil) {
        self.about = about
        self.max_about_length = max_about_length ?? 280
        self.text_alignment = text_alignment ?? .natural
    }
    
    var body: some View {
        Group {
            if let about_string {
                let truncated_about = show_full_about ? about_string : about_string.truncateOrNil(maxLength: max_about_length)
                Text("\(truncated_about ?? about_string)")
                    .font(.subheadline)

                if truncated_about != nil {
                    if show_full_about {
                        Button(NSLocalizedString("Show less", comment: "Button to show less of a long profile description.")) {
                            show_full_about = false
                        }
                        .font(.footnote)
                    } else {
                        Button(NSLocalizedString("Show more", comment: "Button to show more of a long profile description.")) {
                            show_full_about = true
                        }
                        .font(.footnote)
                    }
                }
            } else {
                Text(verbatim: "")
                    .font(.subheadline)
            }
        }
        .onAppear {
            // add some filtering and formatting like npubs
            about_string = try? AttributedString(about)
        }
    }
}
