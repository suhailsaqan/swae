//
//  ParticleRenderShaders.metal
//  swae
//
//  Vertex and fragment shaders for rendering particles
//

#include "ParticleShared.h"

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

vertex VertexOut computeParticleVertex(
    constant Particle* particles [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    Particle p = particles[vertexID];
    
    VertexOut out;
    out.position = float4(p.position.x, p.position.y, 0.0, 1.0);
    out.pointSize = p.size;
    out.color = p.color;
    
    return out;
}

fragment float4 computeParticleFragment(
    VertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    // Create circular particles with soft edges
    float2 center = pointCoord - 0.5;
    float dist = length(center);
    
    // Smooth circle with soft falloff
    float alpha = smoothstep(0.5, 0.2, dist);
    
    // Add glow by brightening the existing color (not adding white)
    // This preserves saturation better on light backgrounds
    float glow = smoothstep(0.5, 0.0, dist) * 0.3;
    
    float4 color = in.color;
    // Brighten by scaling toward white while preserving hue
    color.rgb = mix(color.rgb, min(color.rgb * 1.3, float3(1.0)), glow);
    color.a *= alpha;
    
    return color;
}
