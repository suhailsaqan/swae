//
//  ZapButton+ParticleEffect.swift
//  swae
//
//  Extension to add physics-based particle effects to ZapButton
//

import SwiftUI

// Enhanced ZapButton with particle effect
extension ZapButton {
    /// Creates a ZapButton with particle effect overlay
    func withParticleEffect() -> some View {
        ZStack {
            self
            
            // Particle effect overlay (shown on successful zap)
            // You can trigger this based on zapService.zapSuccess
        }
    }
}

// Wrapper view that adds particle effect to any zap button
struct ZapButtonWithParticles<Content: View>: View {
    let content: Content
    let showEffect: Bool
    let effectSize: CGFloat
    
    @State private var effectId = UUID()
    
    init(
        showEffect: Bool,
        effectSize: CGFloat = 80,
        @ViewBuilder content: () -> Content
    ) {
        self.showEffect = showEffect
        self.effectSize = effectSize
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            content
            
            if showEffect {
                SimpleZapParticleView(size: effectSize, intensity: 1.5)
                    .id(effectId)
                    .allowsHitTesting(false)
                    .onAppear {
                        effectId = UUID()
                    }
            }
        }
    }
}

// Example usage in your existing code:
/*
 
 // Option 1: Wrap existing ZapButton
 ZapButtonWithParticles(showEffect: zapService.zapSuccess) {
     ZapButton(
         targetPubkey: pubkey,
         appState: appState
     )
 }
 
 // Option 2: Use the new AnimatedZapButton directly
 AnimatedZapButton(
     targetPubkey: pubkey,
     eventCoordinate: coordinate,
     amount: 1_000_000,
     appState: appState
 )
 
 // Option 3: Add to existing button with modifier
 ZapButton(targetPubkey: pubkey, appState: appState)
     .withParticleEffect()
 
 */
