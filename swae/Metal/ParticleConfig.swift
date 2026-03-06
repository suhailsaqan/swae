//
//  ParticleConfig.swift
//  swae
//
//  Configuration presets for particle physics behavior
//

import Foundation

/// Configuration for particle physics behavior
struct ParticleConfig {
    var repulsionRadius: Float = 0.30  // Touch influence radius (0.2-0.4)
    var repulsionForce: Float = 2.0    // Push distance (0-10)
    var springStiffness: Float = 10.0  // Movement speed (5-20)
    var damping: Float = 2.0           // Falloff sharpness (1-4)
    var particleCount: Int = 15000     // Number of particles
    var particleSize: Float = 5.0      // Size of each particle
    
    static let `default` = ParticleConfig()
    
    static let onboarding = ParticleConfig(
        repulsionRadius: 0.75,
        repulsionForce: 4.0,
        springStiffness: 7.0,
        damping: 2.0,
        particleCount: 15000,
        particleSize: 5.0
    )
    
    /// Config for the rotating ring button (camera tab)
    static let ringButton = ParticleConfig(
        repulsionRadius: 0.35,    // Large radius to affect all particles when tapping center
        repulsionForce: 1.0,     // How far particles push out
        springStiffness: 5.0,   // Movement speed
        damping: 1.0,            // Falloff sharpness
        particleCount: 30000,    // More particles = smoother, less pixelated
        particleSize: 1.0        // Particle size
    )
    
    /// Config for the Go Live particle ring in toolbar
    static let goLiveRing = ParticleConfig(
        repulsionRadius: 0.4,
        repulsionForce: 2.5,
        springStiffness: 8.0,
        damping: 1.5,
        particleCount: 20000,
        particleSize: 1.2
    )
}
