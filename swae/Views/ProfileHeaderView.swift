//
//  ProfileHeaderView.swift
//  swae
//
//  Created by Assistant on 9/7/25.
//

import SwiftUI

struct ProfileHeaderTabs: View {
    @Binding var selectedIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton(title: "Live Streams", index: 0)
                tabButton(title: "Shorts", index: 1)
            }
            .padding(.horizontal)
            .padding(.top)

            GeometryReader { geo in
                let buttonWidth = geo.size.width / 2
                let indicatorWidth: CGFloat = 75

                Capsule()
                    .fill(Color.purple)
                    .frame(width: indicatorWidth, height: 2)
                    .offset(
                        x: selectedIndex == 0
                            ? (buttonWidth - indicatorWidth) / 2
                            : buttonWidth + (buttonWidth - indicatorWidth) / 2
                    )
                    .animation(.easeInOut(duration: 0.25), value: selectedIndex)
            }
            .frame(height: 2)
            .padding(.horizontal)
        }
        .background(.background)
    }

    private func tabButton(title: String, index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) { selectedIndex = index }
        }) {
            Text(title)
                .font(.headline)
                .fontWeight(selectedIndex == index ? .semibold : .medium)
                .foregroundColor(selectedIndex == index ? .purple : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
