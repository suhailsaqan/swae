//
//  ZapPlasmaShaders.metal
//  swae
//
//  GPU shaders for the Zap Plasma Conduit Effect
//  Visualizes incoming Bitcoin Lightning payments during live streams
//

#include <metal_stdlib>
using namespace metal;

// Uniforms passed from CPU
struct ZapPlasmaUniforms {
    float time;
    float intensity;
    float progress;
    float2 resolution;
    float2 faceCenter;      // Normalized 0-1
    float2 tendrilOrigins[4];
    int tendrilCount;
};

// Vertex output for full-screen quad
struct ZapPlasmaVertexOut {
    float4 position [[position]];
    float2 uv;
};

// Hash function for noise
float zapHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise function
float zapNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = zapHash(i);
    float b = zapHash(i + float2(1.0, 0.0));
    float c = zapHash(i + float2(0.0, 1.0));
    float d = zapHash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Curl noise for organic plasma movement
float2 curlNoise(float2 p, float time) {
    float epsilon = 0.001;
    
    float n = zapHash(p);
    float n1 = zapHash(p + float2(epsilon, 0));
    float n2 = zapHash(p + float2(0, epsilon));
    
    float dx = (n1 - n) / epsilon;
    float dy = (n2 - n) / epsilon;
    
    // Add time-based animation for flowing effect
    dx += sin(time * 2.0 + p.y * 5.0) * 0.5;
    dy += cos(time * 2.0 + p.x * 5.0) * 0.5;
    
    return float2(-dy, dx) * 0.1;
}

// Fractal Brownian Motion for complex noise patterns
float fbm(float2 p, float time) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 4; i++) {
        value += amplitude * zapNoise(p * frequency + time * 0.1);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Vertex shader - generates full-screen quad
vertex ZapPlasmaVertexOut zapPlasmaVertex(uint vertexID [[vertex_id]]) {
    float2 positions[6] = {
        float2(-1, -1),
        float2( 1, -1),
        float2(-1,  1),
        float2(-1,  1),
        float2( 1, -1),
        float2( 1,  1)
    };
    
    ZapPlasmaVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

// Fragment shader for plasma overlay effect
fragment float4 zapPlasmaFragment(
    ZapPlasmaVertexOut in [[stage_in]],
    constant ZapPlasmaUniforms& uniforms [[buffer(0)]],
    texture2d<float, access::sample> videoTexture [[texture(0)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    float2 uv = in.uv;
    float4 videoColor = videoTexture.sample(textureSampler, uv);
    
    // Early exit if no intensity
    if (uniforms.intensity < 0.01) {
        return videoColor;
    }
    
    float2 faceCenter = uniforms.faceCenter;
    float plasma = 0.0;
    
    // Generate plasma tendrils from each origin toward face
    for (int i = 0; i < uniforms.tendrilCount && i < 4; i++) {
        float2 origin = uniforms.tendrilOrigins[i];
        float2 toFace = normalize(faceCenter - origin);
        
        // Calculate tendril path with curl noise displacement
        float pathProgress = uniforms.progress;
        float2 currentPos = origin + toFace * pathProgress * 2.0; // *2 because clip space is -1 to 1
        
        // Add organic movement with curl noise
        float2 curl = curlNoise(uv * 8.0 + uniforms.time * 0.5, uniforms.time);
        float2 tendrilPos = currentPos + curl * (1.0 - pathProgress);
        
        // Convert tendril position to UV space for distance calculation
        float2 tendrilUV = tendrilPos * 0.5 + 0.5;
        
        // Distance from pixel to tendril path
        float dist = length(uv - tendrilUV);
        
        // Tendril thickness varies along path with noise
        float thickness = 0.03 + zapNoise(uv * 10.0 + uniforms.time) * 0.02;
        thickness *= (1.0 - pathProgress * 0.5); // Thinner as it reaches face
        
        float tendril = smoothstep(thickness, 0.0, dist);
        
        // Energy packets traveling along tendril
        float packetPhase = (length(uv - (origin * 0.5 + 0.5)) - uniforms.time * 2.0) * 20.0;
        float packet = max(0.0, sin(packetPhase)) * tendril;
        
        // Add branching effect
        float branch = zapNoise(uv * 20.0 + float2(i) + uniforms.time * 0.3);
        float branchTendril = smoothstep(thickness * 0.5, 0.0, dist + branch * 0.02) * 0.3;
        
        plasma += tendril * 0.7 + packet * 0.4 + branchTendril;
    }
    
    // Clamp and apply intensity
    plasma = clamp(plasma, 0.0, 1.0) * uniforms.intensity;
    
    // Fade out based on progress (dissipation)
    float fadeOut = 1.0 - smoothstep(0.7, 1.0, uniforms.progress);
    plasma *= fadeOut;
    
    // Lightning color gradient based on intensity
    // Low intensity: warm orange, High intensity: white-hot
    float3 coolColor = float3(1.0, 0.6, 0.1);   // Orange
    float3 warmColor = float3(1.0, 0.8, 0.3);   // Yellow-orange
    float3 hotColor = float3(1.0, 0.95, 0.85);  // White-hot
    
    float3 plasmaColor;
    if (uniforms.intensity < 0.5) {
        plasmaColor = mix(coolColor, warmColor, uniforms.intensity * 2.0);
    } else {
        plasmaColor = mix(warmColor, hotColor, (uniforms.intensity - 0.5) * 2.0);
    }
    
    // Apply chromatic aberration in plasma wake
    float aberration = plasma * 0.008 * uniforms.intensity;
    float2 redOffset = float2(aberration, 0.0);
    float2 blueOffset = float2(-aberration, 0.0);
    
    float r = videoTexture.sample(textureSampler, uv + redOffset).r;
    float g = videoColor.g;
    float b = videoTexture.sample(textureSampler, uv + blueOffset).b;
    
    float3 aberratedColor = float3(r, g, b);
    
    // Blend plasma with video
    float3 finalColor = mix(aberratedColor, plasmaColor, plasma * 0.6);
    
    // Add bloom/glow effect
    finalColor += plasmaColor * plasma * 0.5;
    
    // Add subtle screen-wide glow toward face center
    float distToFace = length(uv - faceCenter);
    float faceGlow = (1.0 - smoothstep(0.0, 0.5, distToFace)) * uniforms.intensity * fadeOut * 0.15;
    finalColor += plasmaColor * faceGlow;
    
    return float4(finalColor, 1.0);
}

// Compute kernel for plasma field generation (alternative GPU approach)
kernel void computeZapPlasma(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant ZapPlasmaUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uint(uniforms.resolution.x) || gid.y >= uint(uniforms.resolution.y)) {
        return;
    }
    
    float2 uv = float2(gid) / uniforms.resolution;
    float4 color = inTexture.read(gid);
    
    // Early exit if no intensity
    if (uniforms.intensity < 0.01) {
        outTexture.write(color, gid);
        return;
    }
    
    float2 faceCenter = uniforms.faceCenter;
    float plasma = 0.0;
    
    // Generate plasma tendrils
    for (int i = 0; i < uniforms.tendrilCount && i < 4; i++) {
        float2 origin = uniforms.tendrilOrigins[i];
        float2 toFace = normalize(faceCenter - origin);
        
        float pathProgress = uniforms.progress;
        float2 currentPos = origin + toFace * pathProgress * 2.0;
        
        float2 curl = curlNoise(uv * 8.0 + uniforms.time * 0.5, uniforms.time);
        float2 tendrilPos = currentPos + curl * (1.0 - pathProgress);
        float2 tendrilUV = tendrilPos * 0.5 + 0.5;
        
        float dist = length(uv - tendrilUV);
        float thickness = 0.03 + zapNoise(uv * 10.0 + uniforms.time) * 0.02;
        thickness *= (1.0 - pathProgress * 0.5);
        
        float tendril = smoothstep(thickness, 0.0, dist);
        float packetPhase = (length(uv - (origin * 0.5 + 0.5)) - uniforms.time * 2.0) * 20.0;
        float packet = max(0.0, sin(packetPhase)) * tendril;
        
        plasma += tendril * 0.7 + packet * 0.4;
    }
    
    plasma = clamp(plasma, 0.0, 1.0) * uniforms.intensity;
    float fadeOut = 1.0 - smoothstep(0.7, 1.0, uniforms.progress);
    plasma *= fadeOut;
    
    // Color calculation
    float3 coolColor = float3(1.0, 0.6, 0.1);
    float3 hotColor = float3(1.0, 0.95, 0.85);
    float3 plasmaColor = mix(coolColor, hotColor, uniforms.intensity);
    
    // Chromatic aberration
    float aberration = plasma * 0.008 * uniforms.intensity;
    uint2 redGid = uint2(clamp(float(gid.x) + aberration * uniforms.resolution.x, 0.0, uniforms.resolution.x - 1.0), gid.y);
    uint2 blueGid = uint2(clamp(float(gid.x) - aberration * uniforms.resolution.x, 0.0, uniforms.resolution.x - 1.0), gid.y);
    
    float r = inTexture.read(redGid).r;
    float g = color.g;
    float b = inTexture.read(blueGid).b;
    
    float3 aberratedColor = float3(r, g, b);
    float3 finalColor = mix(aberratedColor, plasmaColor, plasma * 0.6);
    finalColor += plasmaColor * plasma * 0.5;
    
    outTexture.write(float4(finalColor, 1.0), gid);
}
