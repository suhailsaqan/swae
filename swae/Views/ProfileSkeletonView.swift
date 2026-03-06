//
//  ProfileSkeletonView.swift
//  swae
//
//  Created for profile skeleton loading states
//

import SwiftUI

/// Shimmer effect modifier for skeleton views
struct ShimmerEffect: ViewModifier {
    @State private var movingPhase: CGFloat = -1
    
    var gradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.3), location: 0.5),
                .init(color: .clear, location: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var animation: Animation {
        Animation
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false)
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    gradient
                        .frame(width: geometry.size.width)
                        .offset(x: movingPhase * geometry.size.width)
                }
            )
            .clipped()
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(animation) {
                        movingPhase = 2
                    }
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

/// Skeleton loading view for profile header
struct ProfileHeaderSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                // Profile picture skeleton
                Circle()
                    .fill(Color(UIColor.systemGray6))
                    .frame(width: 90, height: 90)
                    .padding(.top, -45)
                    .shimmer()
                
                Spacer()
                
                // Action button skeleton
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemGray6))
                    .frame(width: 80, height: 32)
                    .shimmer()
            }
            
            // Display name skeleton
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray6))
                .frame(width: 150, height: 20)
                .shimmer()
            
            // Username skeleton
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray6))
                .frame(width: 100, height: 16)
                .shimmer()
            
            // About section skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(UIColor.systemGray6))
                    .frame(height: 14)
                    .shimmer()
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(UIColor.systemGray6))
                    .frame(width: 200, height: 14)
                    .shimmer()
            }
            
            // Following count skeleton
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemGray6))
                .frame(width: 120, height: 16)
                .shimmer()
        }
        .padding(.horizontal)
    }
}

/// Skeleton loading view for stream cards in profile
struct ProfileStreamCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemGray6))
                .aspectRatio(16/9, contentMode: .fit)
                .shimmer()
            
            HStack(spacing: 8) {
                // Host image skeleton
                Circle()
                    .fill(Color(UIColor.systemGray6))
                    .frame(width: 32, height: 32)
                    .shimmer()
                
                VStack(alignment: .leading, spacing: 4) {
                    // Title skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(UIColor.systemGray6))
                        .frame(height: 14)
                        .shimmer()
                    
                    // Subtitle skeleton
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(UIColor.systemGray6))
                        .frame(width: 100, height: 12)
                        .shimmer()
                }
            }
        }
    }
}

/// Grid of skeleton stream cards
struct ProfileStreamsSkeleton: View {
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                ProfileStreamCardSkeleton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

/// Skeleton for banner image
struct ProfileBannerSkeleton: View {
    var body: some View {
        Rectangle()
            .fill(Color(UIColor.systemGray6))
            .frame(height: 150)
            .shimmer()
    }
}
