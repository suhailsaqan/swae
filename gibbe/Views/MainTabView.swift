//
//  MainTabView.swift
//  gibbe
//
//  Created by Suhail Saqan on 9/30/24.
//


import SwiftUI

enum ScreenTabs: String, CustomStringConvertible, Hashable {
    case home
    case live
    case profile
    
    var description: String {
        return self.rawValue
    }
}
    
struct TabButton: View {
    let screen_tab: ScreenTabs
    let img: String
    @Binding var selected: ScreenTabs
    
    let settings: AppSettings?
    let action: (ScreenTabs) -> ()
    
    var body: some View {
        ZStack(alignment: .center) {
            Tab
        }
    }
    
    var Tab: some View {
        Button(action: {
            action(screen_tab)
        }) {
            Image(systemName: selected != screen_tab ? img : "\(img).fill")
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 30.0)
        }
        .foregroundColor(.primary)
    }
}


struct TabBar: View {
    @Binding var selected: ScreenTabs
    
    let settings: AppSettings?
    let action: (ScreenTabs) -> ()
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                TabButton(screen_tab: .home, img: "house", selected: $selected, settings: settings, action: action).keyboardShortcut("1")
                TabButton(screen_tab: .live, img: "camera", selected: $selected, settings: settings, action: action).keyboardShortcut("2")
                TabButton(screen_tab: .profile, img: "person", selected: $selected, settings: settings, action: action).keyboardShortcut("3")
            }
        }
    }
}
