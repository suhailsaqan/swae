//
//  OnboardingViewWithParticles.swift
//  swae
//
//  Enhanced onboarding with physics-based particle background
//

import SwiftUI
import NostrSDK

struct OnboardingViewWithParticles: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentPage = 0
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
    
    var body: some View {
        ZStack {
            // Particle background - much larger area
            MetalParticleViewWithCoordinator(
                touchLocation: $touchLocation,
                isTouching: $isTouching,
                metalView: $metalView
            )
            .ignoresSafeArea()
            .onAppear {
                // Particles form a bolt/lightning shape
                metalView?.renderer?.transitionToPattern(.bolt)
            }
            
            // Dark overlay for readability
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Hero Section
                VStack(spacing: 24) {
                    Spacer()
                    
                    // App Name
                    Text("Swae")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Tagline
                    Text("Live streaming on Nostr")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("Touch to interact")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 4)
                    
                    Spacer()
                    
                    // Feature Cards
                    TabView(selection: $currentPage) {
                        ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                            FeatureCardGlass(feature: feature)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: 220)
                    
                    Spacer()
                }
                .padding(.top, 60)
                
                // Action Buttons
                VStack(spacing: 16) {
                    Button(action: {
                        showingCreateProfile = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Create Account")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        showingSignIn = true
                    }) {
                        HStack {
                            Spacer()
                            Text("Sign In")
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            Color.white.opacity(0.15)
                        )
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    Button(action: {
                        hasCompletedOnboarding = true
                    }) {
                        Text("Browse as Guest")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
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
}
