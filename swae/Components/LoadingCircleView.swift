//
//  LoadingCircleView.swift
//  swae
//
//  Created by Suhail Saqan on 2/5/25.
//

import SwiftUI

struct LoadingCircleView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isAnimating = false
    
    var showBackground: Bool = true
    var backgroundColor: Color = Color.black.opacity(0.35)
    var strokeColor: Color? = nil
    
    var computedStrokeColor: Color {
        strokeColor ?? (colorScheme == .dark ? .purple : .purple)
    }
    
    var body: some View {
        Circle()
            .trim(from: 0.0, to: 0.7)
            .stroke(
                computedStrokeColor,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: 25, height: 25)
            .padding(10)
            .background {
                if showBackground {
                    Circle()
                        .fill(backgroundColor)
                }
            }
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(
                Animation.linear(duration: 1.2)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
