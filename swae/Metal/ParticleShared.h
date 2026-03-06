//
//  ParticleShared.h
//  swae
//
//  Shared definitions between compute and render shaders
//

#ifndef ParticleShared_h
#define ParticleShared_h

#include <metal_stdlib>
using namespace metal;

struct Particle {
    float2 position;
    float2 velocity;
    float2 target;
    float4 color;
    float life;
    float size;
};

struct ParticleUniforms {
    float deltaTime;
    float2 touchPoint;
    float isTouching;
    float repulsionRadius;
    float repulsionForce;
    float springStiffness;
    float damping;
    float time;
};

#endif /* ParticleShared_h */
