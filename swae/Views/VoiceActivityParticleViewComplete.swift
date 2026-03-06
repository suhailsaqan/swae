//
//  VoiceActivityParticleViewComplete.swift
//  swae
//
//  Complete working example with pattern transitions
//

import SwiftUI
import MetalKit

struct VoiceActivityParticleViewComplete: View {
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var currentState: VoiceActivityState = .idle
    @State private var metalView: ParticleMetalView?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Particle system with coordinator
            MetalParticleViewWithCoordinator(
                touchLocation: $touchLocation,
                isTouching: $isTouching,
                metalView: $metalView
            )
            .ignoresSafeArea()
            
            // State buttons at bottom
            VStack {
                Spacer()
                
                HStack(spacing: 20) {
                    StateButton(title: "idle", isSelected: currentState == .idle) {
                        currentState = .idle
                    }
                    
                    StateButton(title: "listening", isSelected: currentState == .listening) {
                        currentState = .listening
                    }
                    
                    StateButton(title: "speaking", isSelected: currentState == .speaking) {
                        currentState = .speaking
                    }
                    
                    StateButton(title: "question", isSelected: currentState == .question) {
                        currentState = .question
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            
            // Back button
            VStack {
                HStack {
                    Button(action: {
                        // Navigate back
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                    .padding(.leading, 20)
                    .padding(.top, 60)
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: currentState) { newState in
            updateParticlesForState(newState)
        }
    }
    
    func updateParticlesForState(_ state: VoiceActivityState) {
        guard let renderer = metalView?.renderer else { return }
        
        let pattern: ParticlePattern
        switch state {
        case .idle:
            pattern = .idle
        case .listening:
            pattern = .listening
        case .speaking:
            pattern = .speaking
        case .question:
            pattern = .question
        }
        
        renderer.transitionToPattern(pattern)
    }
}

// ParticleConfig and MetalParticleViewWithCoordinator are now in swae/Metal/

#Preview {
    VoiceActivityParticleViewComplete()
}
