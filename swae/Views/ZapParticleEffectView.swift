//
//  ZapParticleEffectView.swift
//  swae
//
//  Physics-based particle effect for Zap interactions
//

import SwiftUI
import MetalKit

struct ZapParticleEffectView: View {
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var metalView: ParticleMetalView?
    @State private var isAnimating = false
    
    let size: CGFloat
    let autoPlay: Bool
    let intensity: Float
    
    init(
        size: CGFloat = 200,
        autoPlay: Bool = true,
        intensity: Float = 1.0
    ) {
        self.size = size
        self.autoPlay = autoPlay
        self.intensity = intensity
    }
    
    var body: some View {
        ZStack {
            // Physics particle system
            MetalParticleViewWithCoordinator(
                touchLocation: $touchLocation,
                isTouching: $isTouching,
                metalView: $metalView
            )
            .frame(width: size * 1.5, height: size * 1.5)
            
            // Bolt icon overlay
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, Color(red: 1.0, green: 0.6, blue: 0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(isAnimating ? 0.3 : 1.0)
        }
        .frame(width: size, height: size)
        .onAppear {
            if autoPlay {
                startAnimation()
            }
        }
        .onTapGesture {
            restartAnimation()
        }
    }
    
    func startAnimation() {
        guard let renderer = metalView?.renderer else { return }
        
        // Start with particles at center
        renderer.transitionToPattern(.circle(radius: 0.1, thickness: 0.02))
        
        isAnimating = true
        
        // Explode outward
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            renderer.transitionToPattern(.ring(innerRadius: 0.6, outerRadius: 0.8))
        }
        
        // Reset after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isAnimating = false
            renderer.transitionToPattern(.circle(radius: 0.4, thickness: 0.05))
        }
    }
    
    func restartAnimation() {
        isAnimating = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            startAnimation()
        }
    }
}

// Interactive version - particles repel from touch, spring back when released
struct SimpleZapParticleView: View {
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var metalView: ParticleMetalView?
    
    let size: CGFloat
    let intensity: Float
    let loop: Bool
    
    init(size: CGFloat = 200, intensity: Float = 1.0, loop: Bool = false) {
        self.size = size
        self.intensity = intensity
        self.loop = loop
    }
    
    var body: some View {
        ZStack {
            // Physics particle system
            MetalParticleViewWithCoordinator(
                touchLocation: $touchLocation,
                isTouching: $isTouching,
                metalView: $metalView
            )
            .frame(width: size * 1.5, height: size * 1.5)
            
            // Bolt icon overlay
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.7, blue: 0.1),
                            Color(red: 1.0, green: 0.5, blue: 0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(isTouching ? 0.5 : 1.0)
        }
        .frame(width: size, height: size)
        .onAppear {
            // Start with bolt shape
            metalView?.renderer?.transitionToPattern(.circle(radius: 0.4, thickness: 0.05))
        }
    }
}

// Animated zap button with particle effect on tap
struct AnimatedZapButton: View {
    let targetPubkey: String
    let eventCoordinate: String?
    let amount: Int64
    let content: String?
    
    @StateObject private var zapService: ZapService
    @State private var showParticleEffect = false
    @State private var particleEffectId = UUID()
    
    init(
        targetPubkey: String,
        eventCoordinate: String? = nil,
        amount: Int64 = 1_000_000,
        content: String? = nil,
        appState: AppState
    ) {
        self.targetPubkey = targetPubkey
        self.eventCoordinate = eventCoordinate
        self.amount = amount
        self.content = content
        self._zapService = StateObject(wrappedValue: ZapService(appState: appState))
    }
    
    var body: some View {
        ZStack {
            // Particle effect overlay
            if showParticleEffect {
                SimpleZapParticleView(size: 60, intensity: 1.5)
                    .id(particleEffectId)
                    .allowsHitTesting(false)
            }
            
            // Original button
            Button(action: {
                triggerZap()
            }) {
                HStack(spacing: 6) {
                    if zapService.isProcessingZap {
                        ProgressView()
                            .scaleEffect(0.7)
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    
                    Text("\(amount / 1000)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .disabled(zapService.isProcessingZap)
        }
        .onChange(of: zapService.zapSuccess) { success in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    zapService.reset()
                }
            }
        }
    }
    
    private func triggerZap() {
        // Show particle effect
        showParticleEffect = true
        particleEffectId = UUID()
        
        // Send the zap
        Task {
            await zapService.sendZap(
                amount: amount,
                targetPubkey: targetPubkey,
                eventCoordinate: eventCoordinate,
                content: content ?? "Zap! ⚡"
            )
        }
        
        // Hide particle effect after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showParticleEffect = false
        }
    }
}

#Preview("Simple Particle") {
    VStack(spacing: 40) {
        Text("Tap to interact")
            .font(.caption)
            .foregroundColor(.secondary)
        
        SimpleZapParticleView(size: 150, intensity: 1.0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}

#Preview("Animated Effect") {
    ZapParticleEffectView(
        size: 200,
        autoPlay: true,
        intensity: 1.2
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
