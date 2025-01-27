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
    
    var description: String {
        return self.rawValue
    }
}
    
struct TabButton: View {
    let screen_tab: ScreenTabs
    let img: String
    @Binding var selected: ScreenTabs
//    @ObservedObject var nstatus: NotificationStatusModel
    
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
//            let bits = timeline_to_notification_bits(timeline, ev: nil)
//            nstatus.new_events = NewEventsBits(rawValue: nstatus.new_events.rawValue & ~bits.rawValue)
        }) {
            Image(systemName: selected != screen_tab ? img : "\(img).fill")
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 30.0)
        }
        .foregroundColor(.primary)
    }
}


struct TabBar: View {
//    var nstatus: NotificationStatusModel
    @Binding var selected: ScreenTabs
    
    let settings: AppSettings?
    let action: (ScreenTabs) -> ()
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                TabButton(screen_tab: .home, img: "house", selected: $selected, settings: settings, action: action).keyboardShortcut("1")
                TabButton(screen_tab: .live, img: "camera", selected: $selected, settings: settings, action: action).keyboardShortcut("2")
            }
        }
    }
}
