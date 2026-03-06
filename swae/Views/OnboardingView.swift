//
//  OnboardingView.swift
//  swae
//
//  Created by Suhail Saqan on 4/12/25.
//

import SwiftUI
import Kingfisher
import NostrSDK

struct OnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    // Pre-computed color components for performance
    var colorSIMD: SIMD4<Float> {
        let components = color.components
        return SIMD4<Float>(
            Float(components.red),
            Float(components.green),
            Float(components.blue),
            1.0
        )
    }
}

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentFeatureIndex = 0
    @State private var showingCreateProfile = false
    @State private var showingSignIn = false
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var metalView: ParticleMetalView?
    
    let features = [
        OnboardingFeature(
            icon: "play.circle.fill",
            title: "Watch Live Streams",
            description: "Discover and watch live content from creators worldwide on a decentralized platform",
            color: .purple
        ),
        OnboardingFeature(
            icon: "video.fill",
            title: "Go Live Instantly",
            description: "Stream to your audience with built-in tools and real-time engagement",
            color: .blue
        ),
        OnboardingFeature(
            icon: "bolt.fill",
            title: "Support with Zaps",
            description: "Send instant Bitcoin tips to creators you love using Lightning Network",
            color: .orange
        ),
        OnboardingFeature(
            icon: "lock.shield.fill",
            title: "Own Your Identity",
            description: "Your account, your keys, your data. Built on Nostr for true ownership",
            color: .green
        )
    ]
    
    var currentFeature: OnboardingFeature {
        features[currentFeatureIndex]
    }
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)
                
                Text("Swae")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Live streaming on Nostr")
                    .font(.title3)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    .padding(.top, 8)
                
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    currentFeature.color.opacity(0.2),
                                    currentFeature.color.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .blur(radius: 20)
                        .animation(.easeInOut(duration: 0.8), value: currentFeatureIndex)
                    
                    MetalParticleViewWithCoordinator(
                        touchLocation: $touchLocation,
                        isTouching: $isTouching,
                        metalView: $metalView,
                        config: .onboarding
                    )
                    .frame(width: 250, height: 250)
                    .onChange(of: metalView) { newValue in
                        guard let renderer = newValue?.renderer else { return }
                        DispatchQueue.global(qos: .userInitiated).async {
                            let firstFeature = features[0]
                            let colorComponents = firstFeature.color.components
                            let initialColor = SIMD4<Float>(
                                Float(colorComponents.red),
                                Float(colorComponents.green),
                                Float(colorComponents.blue),
                                1.0
                            )
                            DispatchQueue.main.async {
                                renderer.setParticleColor(initialColor)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    self.updateParticleShape()
                                }
                            }
                        }
                    }
                    .onChange(of: currentFeatureIndex) { _ in
                        // Defer particle update to next run loop to avoid blocking animation
                        DispatchQueue.main.async {
                            self.updateParticleShape()
                        }
                    }
                }
                .frame(height: 240)
                .padding(.vertical, 20)
                
                VStack(spacing: 32) {
                    VStack(spacing: 16) {
                        Text(currentFeature.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .multilineTextAlignment(.center)
                            .id("title-\(currentFeatureIndex)")
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                        
                        Text(currentFeature.description)
                            .font(.body)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 40)
                            .id("desc-\(currentFeatureIndex)")
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    .frame(height: 120)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<features.count, id: \.self) { index in
                            Button(action: {
                                navigateToFeature(index)
                            }) {
                                Capsule()
                                    .fill(index == currentFeatureIndex ? currentFeature.color : (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)))
                                    .frame(width: index == currentFeatureIndex ? 32 : 8, height: 8)
                                    .animation(.spring(response: 0.3), value: currentFeatureIndex)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Button(action: nextFeature) {
                        HStack(spacing: 12) {
                            Text(currentFeatureIndex < features.count - 1 ? "Next" : "Get Started")
                                .font(.headline)
                            
                            Image(systemName: currentFeatureIndex < features.count - 1 ? "arrow.right" : "checkmark")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [currentFeature.color, currentFeature.color.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: currentFeature.color.opacity(0.5), radius: 20, y: 10)
                        )
                    }
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.3), value: currentFeatureIndex)
                }
                .padding(.bottom, 40)
                
                VStack(spacing: 16) {
                    Button(action: {
                        showingSignIn = true
                    }) {
                        Text("Already have an account? Sign In")
                            .font(.subheadline)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                    }
                    
                    Button(action: {
                        hasCompletedOnboarding = true
                    }) {
                        Text("Browse as Guest")
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.4))
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    let horizontalAmount = value.translation.width
                    let verticalAmount = value.translation.height
                    
                    if abs(horizontalAmount) > abs(verticalAmount) {
                        if horizontalAmount < 0 && currentFeatureIndex < features.count - 1 {
                            nextFeature()
                        }
                    }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isTouching {
                        let impact = UIImpactFeedbackGenerator(style: .soft)
                        impact.impactOccurred(intensity: 0.7)
                    }
                    touchLocation = value.location
                    isTouching = true
                }
                .onEnded { _ in
                    isTouching = false
                }
        )
        .sheet(isPresented: $showingCreateProfile) {
            NavigationStack {
                CreateProfileView(appState: appState)
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
                .environmentObject(appState)
        }
    }
    
    private func nextFeature() {
        // Trigger haptic asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }
        
        if currentFeatureIndex < features.count - 1 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentFeatureIndex += 1
            }
        } else {
            showingCreateProfile = true
        }
    }
    
    private func navigateToFeature(_ index: Int) {
        guard index != currentFeatureIndex else { return }
        
        // Trigger haptic asynchronously to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentFeatureIndex = index
        }
    }
    
    private func updateParticleShape() {
        guard let renderer = metalView?.renderer else { return }
        
        let feature = features[currentFeatureIndex]
        let newColor = feature.colorSIMD
        let icon = feature.icon
        
        // Execute Metal updates on main thread (Metal requires this)
        renderer.setParticleColor(newColor)
        renderer.transitionToSFSymbol(icon, size: 200)
    }
}

extension Color {
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        #if canImport(UIKit)
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        NSColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        
        return (r, g, b, a)
    }
}

struct FeatureCardGlass: View {
    let feature: OnboardingFeature
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(feature.color.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(feature.color.opacity(0.5), lineWidth: 2)
                    )
                
                Image(systemName: feature.icon)
                    .font(.system(size: 36))
                    .foregroundColor(feature.color)
            }
            
            VStack(spacing: 8) {
                Text(feature.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(feature.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 32)
    }
}
