//
//  VoiceActivityParticleView.swift
//  swae
//
//  Particle view that responds to voice activity states
//  Matches the design from your screenshots
//

import SwiftUI

enum VoiceActivityState: String {
    case idle
    case listening
    case speaking
    case question
}

struct VoiceActivityParticleView: View {
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var currentState: VoiceActivityState = .idle
    @State private var stateChangeTimer: Timer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Particle system
            MetalParticleView(
                touchLocation: $touchLocation,
                isTouching: $isTouching
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
        // Get the metal view and update particle pattern
        // Note: You'll need to store a reference to the metal view to access the renderer
        
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
        
        // To actually apply this, you would:
        // metalView.renderer?.transitionToPattern(pattern)
        
        print("State changed to: \(state.rawValue)")
    }
}

struct StateButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.2))
                )
        }
    }
}

#Preview {
    VoiceActivityParticleView()
}
