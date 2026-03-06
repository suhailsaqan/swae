//
//  ChaosLinesShaders.metal
//  swae
//
//  Electric glow shader for zap button
//

#include <metal_stdlib>
using namespace metal;

struct ChaosLinesUniforms {
    float time;
    float tapValue;
    float2 resolution;
    float2 tapLocation;  // Where the user tapped (0-1 range)
    float randomSeed;    // Random seed for variation
};

struct ChaosLinesVertexOut {
    float4 position [[position]];
    float2 uv;
};

// Vertex shader - generates full-screen quad
vertex ChaosLinesVertexOut chaosLinesVertex(uint vertexID [[vertex_id]],
                                   constant ChaosLinesUniforms &uniforms [[buffer(0)]]) {
    float2 positions[6] = {
        float2(-1, -1),
        float2( 1, -1),
        float2(-1,  1),
        float2(-1,  1),
        float2( 1, -1),
        float2( 1,  1)
    };
    
    ChaosLinesVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

// Simple hash for noise
float chaosHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise
float chaosNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = chaosHash(i);
    float b = chaosHash(i + float2(1.0, 0.0));
    float c = chaosHash(i + float2(0.0, 1.0));
    float d = chaosHash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fragment shader - electric cloud zap effect
fragment float4 chaosLinesFragment(ChaosLinesVertexOut in [[stage_in]],
                                    constant ChaosLinesUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.uv;
    float2 center = float2(0.5, 0.5);
    
    // Use tap location if tapping, otherwise center
    float2 strikeOrigin = mix(center, uniforms.tapLocation, uniforms.tapValue);
    float dist = length(uv - strikeOrigin);
    
    // Animated noise for cloud-like energy
    float n1 = chaosNoise(uv * 6.0 + uniforms.time * 0.4);
    float n2 = chaosNoise(uv * 10.0 - uniforms.time * 0.25);
    float n3 = chaosNoise(uv * 15.0 + uniforms.time * 0.6);
    float cloudNoise = (n1 * 0.5 + n2 * 0.3 + n3 * 0.2);
    
    // Gentle breathing pulse
    float pulse = sin(uniforms.time * 1.5) * 0.5 + 0.5;
    float basePulse = mix(0.5, 0.75, pulse);
    
    // Cloud-like radial gradient
    float cloudGlow = 1.0 - smoothstep(0.0, 0.8, dist);
    cloudGlow = pow(cloudGlow, 1.2);
    cloudGlow *= (0.7 + cloudNoise * 0.3); // Modulate with noise for cloud texture
    
    // Lightning strike effect on tap
    float lightning = 0.0;
    if (uniforms.tapValue > 0.01) {
        // Create branching lightning bolts from strike origin
        float angle = atan2(uv.y - strikeOrigin.y, uv.x - strikeOrigin.x);
        float boltNoise = chaosNoise(float2(angle * 8.0 + uniforms.randomSeed, dist * 20.0 + uniforms.time * 10.0));
        
        // Fewer branches (2-4)
        int numBranches = 2 + int(chaosHash(float2(uniforms.randomSeed, 0.0)) * 2.0);
        
        // Multiple lightning branches with random angles
        for (int i = 0; i < 4; i++) {
            if (i >= numBranches) break;
            
            // Random angle offset for each branch
            float randomOffset = chaosHash(float2(uniforms.randomSeed + float(i), float(i))) * 6.28318;
            float branchAngle = randomOffset + float(i) * (6.28318 / float(numBranches));
            
            float angleDiff = abs(angle - branchAngle);
            angleDiff = min(angleDiff, 6.28318 - angleDiff); // Wrap around
            
            // Thinner lightning bolts
            float boltWidth = 0.08 + boltNoise * 0.08;
            float bolt = smoothstep(boltWidth, 0.0, angleDiff);
            
            // Random length for each bolt
            float boltLength = 0.5 + chaosHash(float2(uniforms.randomSeed, float(i) + 10.0)) * 0.3;
            bolt *= smoothstep(0.0, 0.1, dist) * smoothstep(boltLength, 0.25, dist);
            
            lightning += bolt * 0.6; // Reduce individual bolt brightness
        }
        
        // Smaller, softer flash at strike origin
        float flash = smoothstep(0.25, 0.0, dist);
        lightning += flash * 0.8;
        
        // Animate lightning intensity with subtle flicker
        float zapDecay = 1.0 - uniforms.tapValue;
        zapDecay = 1.0 - (zapDecay * zapDecay); // Ease out
        
        // Subtle flicker
        float flicker = 0.85 + chaosNoise(float2(uniforms.time * 30.0, uniforms.randomSeed)) * 0.15;
        lightning *= zapDecay * 1.8 * flicker; // Reduced from 3.0 to 1.8
    }
    
    // Combine cloud glow and lightning
    float intensity = cloudGlow * basePulse + lightning;
    intensity = clamp(intensity, 0.0, 2.0);
    
    // Electric gradient colors
    float3 cloudColor = float3(1.0, 0.65, 0.15);  // Warm orange
    float3 glowColor = float3(1.0, 0.85, 0.35);   // Bright yellow
    float3 lightningColor = float3(1.0, 0.9, 0.5); // Bright yellow-orange (less white)
    
    // Mix colors based on intensity
    float3 finalColor = mix(cloudColor, glowColor, cloudGlow * pulse);
    
    // Add lightning color when zapping - more subtle blend
    if (lightning > 0.1) {
        finalColor = mix(finalColor, lightningColor, lightning * 0.5);
    }
    
    // Apply intensity
    finalColor *= intensity;
    
    // Subtle grain texture
    float grain = (cloudNoise - 0.5) * 0.04;
    finalColor += grain;
    
    // Soft edge fade
    float edgeFade = smoothstep(0.85, 0.4, dist);
    finalColor *= edgeFade;
    
    return float4(finalColor, intensity * 0.9);
}
