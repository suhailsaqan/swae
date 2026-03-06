//
//  ParticleTypes.swift
//  swae
//
//  Shared types between Swift and Metal for particle system
//

import simd

struct Particle {
    var position: SIMD2<Float>      // Current position in clip space [-1, 1]
    var velocity: SIMD2<Float>      // Current velocity
    var target: SIMD2<Float>        // Target position (from mask)
    var color: SIMD4<Float>         // RGBA color
    var life: Float                 // Life/phase value [0, 1]
    var size: Float                 // Particle size
    
    init() {
        position = SIMD2<Float>(0, 0)
        velocity = SIMD2<Float>(0, 0)
        target = SIMD2<Float>(0, 0)
        color = SIMD4<Float>(1, 1, 1, 1)
        life = 0
        size = 5.0  // Smaller default for sand-like effect
    }
}

struct ParticleUniforms {
    var deltaTime: Float
    var touchPoint: SIMD2<Float>    // Touch position in clip space
    var isTouching: Float           // 0 or 1
    var repulsionRadius: Float      // Radius of touch repulsion
    var repulsionForce: Float       // Strength of repulsion
    var springStiffness: Float      // How strongly particles return to target
    var damping: Float              // Velocity damping
    var time: Float                 // Total elapsed time
}
