//
//  ParticlePatternGallery.swift
//  swae
//
//  Gallery view showing all available particle patterns
//

import SwiftUI

struct ParticlePatternGallery: View {
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var metalView: ParticleMetalView?
    @State private var currentPatternIndex = 0
    
    let patterns: [(name: String, pattern: ParticlePattern)] = [
        ("Bolt", .bolt),
        ("Circle", .circle(radius: 0.6, thickness: 0.05)),
        ("Ring", .ring(innerRadius: 0.4, outerRadius: 0.6)),
        ("Spiral", .spiral(rotations: 4, radius: 0.7)),
        ("Wave", .wave(amplitude: 0.4, frequency: 3)),
        ("Heart", .heart),
        ("Star", .star(points: 5, innerRadius: 0.3, outerRadius: 0.6)),
        ("Grid", .grid(rows: 10, cols: 10, spacing: 0.15)),
        ("Random", .random(bounds: 0.8)),
        ("Idle", .idle),
        ("Listening", .listening),
        ("Speaking", .speaking),
        ("Question", .question)
    ]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Particle system
            MetalParticleViewWithCoordinator(
                touchLocation: $touchLocation,
                isTouching: $isTouching,
                metalView: $metalView
            )
            .ignoresSafeArea()
            
            VStack {
                // Title
                VStack(spacing: 8) {
                    Text("Particle Patterns")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text(patterns[currentPatternIndex].name)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Touch to interact")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Navigation
                HStack(spacing: 40) {
                    Button(action: previousPattern) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    .disabled(currentPatternIndex == 0)
                    .opacity(currentPatternIndex == 0 ? 0.3 : 1.0)
                    
                    Text("\(currentPatternIndex + 1) / \(patterns.count)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 80)
                    
                    Button(action: nextPattern) {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    .disabled(currentPatternIndex == patterns.count - 1)
                    .opacity(currentPatternIndex == patterns.count - 1 ? 0.3 : 1.0)
                }
                .padding(.bottom, 60)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Load first pattern
            if let renderer = metalView?.renderer {
                renderer.transitionToPattern(patterns[0].pattern)
            }
        }
    }
    
    func nextPattern() {
        guard currentPatternIndex < patterns.count - 1 else { return }
        currentPatternIndex += 1
        updatePattern()
    }
    
    func previousPattern() {
        guard currentPatternIndex > 0 else { return }
        currentPatternIndex -= 1
        updatePattern()
    }
    
    func updatePattern() {
        guard let renderer = metalView?.renderer else { return }
        renderer.transitionToPattern(patterns[currentPatternIndex].pattern)
    }
}

#Preview {
    ParticlePatternGallery()
}
