//
//  PhysicsParticleDemo.swift
//  swae
//
//  Demo view for physics-based particle system
//

import SwiftUI

struct PhysicsParticleDemo: View {
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var showInstructions = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            MetalParticleView(
                touchLocation: $touchLocation,
                isTouching: $isTouching
            )
            .ignoresSafeArea()
            
            // Instructions overlay
            if showInstructions {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        Text("Touch to disrupt particles")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("They'll spring back when you let go")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Button("Got it") {
                            withAnimation {
                                showInstructions = false
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.2))
                        )
                        .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.7))
                            .blur(radius: 20)
                    )
                    .padding(.bottom, 60)
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    PhysicsParticleDemo()
}
