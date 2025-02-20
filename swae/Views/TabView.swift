//
//  TabView.swift
//  swae
//
//  Created by Suhail Saqan on 9/30/24.
//

import SwiftUI

/// Extracted Tab Item View
struct TabItemView: View {
    let tab: ScreenTabs
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: tab.symbol)
                .font(.title3)
            Text(tab.description)
                .font(.caption2)
        }
        .foregroundColor(isSelected ? Color.primary : .gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
    }
}

enum ScreenTabs: String, CustomStringConvertible, Hashable, CaseIterable {
    case home
    case live
    case profile

    var description: String {
        return self.rawValue
    }
    
    var symbol: String {
        switch self {
        case .home:
            "house.fill"
        case .live:
            "video.fill"
        case .profile:
            "person.fill"
        }
    }
}

var tabBarHeight: CGFloat {
    return 44 + safeArea.bottom
}
