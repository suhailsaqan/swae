//
//  ParticleCompute.metal
//  swae
//
//  Compute shader for physics-based particle simulation
//

#include "ParticleShared.h"

// Simple hash function for randomness
float hash(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

kernel void computeUpdateParticles(
    device Particle* particles [[buffer(0)]],
    constant ParticleUniforms& uniforms [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    Particle p = particles[id];
    
    // Calculate repulsion from touch point
    float2 toTouch = p.position - uniforms.touchPoint;
    float distToTouch = length(toTouch);
    
    // Determine the effective target position
    float2 effectiveTarget = p.target;
    
    // lerpSpeed controls how fast particles move (higher = faster)
    // springStiffness is repurposed as base lerp speed (0.05-0.20 range works well)
    float lerpSpeed = uniforms.springStiffness * 0.01;
    
    if (uniforms.isTouching > 0.5 && distToTouch < uniforms.repulsionRadius) {
        // Calculate where particle should move to (pushed away from finger)
        float t = distToTouch / uniforms.repulsionRadius;
        
        // damping controls falloff curve (higher = sharper edge, lower = softer)
        float pushStrength = pow(1.0 - t, uniforms.damping);
        float2 direction = normalize(toTouch + 0.001); // Avoid division by zero
        
        // repulsionForce controls how far particles push out (multiplier on radius)
        float pushDistance = uniforms.repulsionRadius * (1.0 + uniforms.repulsionForce * 0.05);
        float2 pushTarget = uniforms.touchPoint + direction * pushDistance;
        
        // Blend between original target and push target based on proximity to finger
        effectiveTarget = mix(p.target, pushTarget, pushStrength);
        
        // Slightly faster lerp when being pushed for responsive feel
        lerpSpeed *= 1.5;
    }
    
    // Add subtle noise for organic movement
    float noiseX = hash(float2(id, uniforms.time * 0.1)) * 2.0 - 1.0;
    float noiseY = hash(float2(id + 1000, uniforms.time * 0.1)) * 2.0 - 1.0;
    float2 noiseOffset = float2(noiseX, noiseY) * 0.001;
    
    // Smooth interpolation toward effective target (same feel for push and return)
    p.position = mix(p.position, effectiveTarget, lerpSpeed) + noiseOffset;
    
    // Calculate distance to original target for snapping
    float distToTarget = length(p.target - p.position);
    
    // Snap to target when very close and not touching
    if (distToTarget < 0.001 && uniforms.isTouching < 0.5) {
        p.position = p.target;
    }
    
    // Clear velocity (using interpolation, not physics)
    p.velocity = float2(0.0);
    
    // Update life/animation phase
    p.life = fract(p.life + uniforms.deltaTime * 0.1);
    
    // Keep the particle's color and size unchanged
    // Size is set during initialization, no animation override
    
    particles[id] = p;
}
