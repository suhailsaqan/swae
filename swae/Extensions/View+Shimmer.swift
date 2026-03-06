//
//  View+Shimmer.swift
//  swae
//
//  Created by Suhail Saqan on 2/8/25.
//

import SwiftUI

extension View {
    func shimmer(_ isActive: Bool = true) -> some View {
        self.modifier(ShimmerModifier(isActive: isActive))
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isActive {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.clear,
                                        Color.white.opacity(0.3),
                                        Color.clear,
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .rotationEffect(.degrees(30))
                            .offset(x: phase)
                            .animation(
                                Animation.linear(duration: 1.5)
                                    .repeatForever(autoreverses: false),
                                value: phase
                            )
                    }
                }
            )
            .clipped()
            .onAppear {
                if isActive {
                    phase = 300
                }
            }
    }
}
