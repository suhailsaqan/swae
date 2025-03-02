//
//  ProfileTabView.swift
//  swae
//
//  Created by Suhail Saqan on 2/26/25.
//

import SwiftUI

struct ProfileTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Top Tab Bar
            HStack {
                ProfileTabButton(title: "Live Streams", selectedTab: $selectedTab, tabIndex: 0)
                ProfileTabButton(title: "Shorts", selectedTab: $selectedTab, tabIndex: 1)
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Underline Indicator
            GeometryReader { geo in
                // Each button occupies half of the available width.
                let buttonWidth = geo.size.width / 2
                Capsule()
                    .fill(Color.purple)
                    .frame(width: 75, height: 2)
                    .offset(x: selectedTab == 0
                            ? (buttonWidth - 75) / 2
                            : buttonWidth + (buttonWidth - 75) / 2)
                    .animation(.easeInOut, value: selectedTab)
            }
            .frame(height: 2)
            
            // Swipeable TabView that fills the remaining space
            TabView(selection: $selectedTab) {
                LiveActivities()
                    .tag(0)
                Shorts()
                    .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Custom Tab Button
struct ProfileTabButton: View {
    var title: String
    @Binding var selectedTab: Int
    var tabIndex: Int

    var body: some View {
        Button(action: {
            withAnimation {
                selectedTab = tabIndex
            }
        }) {
            Text(title)
                .font(.headline)
                .foregroundColor(selectedTab == tabIndex ? .purple : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - First Tab Content
struct LiveActivities: View {
    var body: some View {
        Text("hey")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(0.2))
    }
}

// MARK: - Second Tab Content
struct Shorts: View {
    var body: some View {
        Text("yo")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green.opacity(0.2))
    }
}

// MARK: - Preview
struct ProfileTabView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTabView()
    }
}
