//
//  LiquidPoolShaders.metal
//  swae
//
//  Flowing liquid pool background for Control Panel
//  Features: Caustic patterns, touch ripples, zap energy effects
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms

struct LiquidPoolUniforms {
    float2 resolution;
    float time;
    
    // Touch interaction
    float2 touchPoint;      // Normalized touch position
    float touchStrength;    // 0-1, decays after release
    
    // Colors
    float3 baseColor;       // Primary liquid color
    float3 accentColor;     // Zap/energy tint color
    float accentStrength;   // 0-1, how much accent shows
    
    // Energy state
    float energyLevel;      // 0-1, affects movement speed
    float zapStormIntensity; // 0-1, storm mode intensity
    
    // Ripple array (up to 4 active ripples)
    float2 ripplePoints[4];
    float rippleAges[4];    // Time since ripple started
    int activeRipples;
};

// MARK: - Noise Functions

static float pool_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float pool_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = pool_hash(i);
    float b = pool_hash(i + float2(1.0, 0.0));
    float c = pool_hash(i + float2(0.0, 1.0));
    float d = pool_hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float pool_fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * pool_noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// MARK: - Caustic Pattern

static float caustic(float2 uv, float time) {
    // Layer multiple noise patterns for caustic effect
    float2 p1 = uv * 3.0 + float2(time * 0.1, time * 0.05);
    float2 p2 = uv * 4.0 - float2(time * 0.08, time * 0.12);
    float2 p3 = uv * 2.5 + float2(time * 0.06, -time * 0.04);
    
    float n1 = pool_fbm(p1, 3);
    float n2 = pool_fbm(p2, 3);
    float n3 = pool_fbm(p3, 2);
    
    // Combine for caustic pattern
    float caustic = n1 * n2 * 2.0;
    caustic += n3 * 0.3;
    
    // Sharpen the caustic lines
    caustic = pow(caustic, 1.5);
    
    return clamp(caustic, 0.0, 1.0);
}

// MARK: - Ripple Effect

static float ripple(float2 uv, float2 center, float age, float maxAge) {
    if (age <= 0.0 || age > maxAge) return 0.0;
    
    float dist = length(uv - center);
    float progress = age / maxAge;
    
    // Ripple expands outward
    float rippleRadius = progress * 0.8;
    float rippleWidth = 0.08 * (1.0 - progress * 0.5);
    
    // Ring shape
    float ring = smoothstep(rippleRadius - rippleWidth, rippleRadius, dist) *
                 smoothstep(rippleRadius + rippleWidth, rippleRadius, dist);
    
    // Fade out over time
    float fade = 1.0 - progress;
    fade = fade * fade;
    
    return ring * fade;
}

// MARK: - Electric Ripple (for zaps)

static float electricRipple(float2 uv, float2 center, float age, float time) {
    if (age <= 0.0 || age > 1.0) return 0.0;
    
    float dist = length(uv - center);
    float progress = age;
    
    // Ripple expands
    float rippleRadius = progress * 0.6;
    float rippleWidth = 0.05;
    
    // Jagged edge using noise
    float angle = atan2(uv.y - center.y, uv.x - center.x);
    float jagged = pool_noise(float2(angle * 5.0, time * 10.0)) * 0.03;
    
    float ring = smoothstep(rippleRadius - rippleWidth + jagged, rippleRadius, dist) *
                 smoothstep(rippleRadius + rippleWidth + jagged, rippleRadius, dist);
    
    // Crackling effect
    float crackle = pool_noise(float2(angle * 8.0 + time * 20.0, dist * 10.0));
    crackle = step(0.7, crackle);
    
    ring += crackle * 0.3 * (1.0 - progress);
    
    // Fade
    float fade = 1.0 - progress;
    
    return ring * fade;
}

// MARK: - Flow Distortion

static float2 flowDistort(float2 uv, float time, float energy) {
    float speed = 0.3 + energy * 0.5;
    
    float2 distort;
    distort.x = pool_fbm(uv * 2.0 + float2(time * speed, 0.0), 2) - 0.5;
    distort.y = pool_fbm(uv * 2.0 + float2(0.0, time * speed * 0.8), 2) - 0.5;
    
    return distort * 0.05 * (1.0 + energy * 0.5);
}

// MARK: - Lightning Bolt (for zap storm)

static float lightning(float2 uv, float time, float seed) {
    // Vertical lightning bolt with horizontal jitter
    float x = uv.x + seed;
    float jitter = pool_noise(float2(uv.y * 10.0 + time * 5.0, seed)) * 0.1;
    
    float bolt = smoothstep(0.02, 0.0, abs(x - 0.5 + jitter));
    
    // Branches
    float branch1 = pool_noise(float2(uv.y * 8.0, seed + 1.0));
    if (branch1 > 0.7) {
        float branchX = x + (uv.y - 0.5) * 0.3;
        bolt += smoothstep(0.015, 0.0, abs(branchX - 0.5 + jitter * 0.5)) * 0.5;
    }
    
    return bolt;
}

// MARK: - Main Fragment Shader

fragment float4 liquidPoolFragment(
    float4 position [[position]],
    constant LiquidPoolUniforms& u [[buffer(0)]]
) {
    float2 uv = position.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    
    // Aspect-corrected UV for circular effects
    float2 uvAspect = uv;
    uvAspect.x *= aspect;
    
    float time = u.time;
    
    // === SUBTLE GRADIENT BACKGROUND ===
    // Clean gradient from top-left to bottom-right
    float gradientAngle = 0.3;  // Slight diagonal
    float gradient = uv.x * gradientAngle + uv.y * (1.0 - gradientAngle);
    gradient = gradient * 0.15 + 0.85;  // Very subtle: 0.85 to 1.0
    
    float3 color = u.baseColor * gradient;
    
    // === VERY SUBTLE FLOW (like heat shimmer, not water) ===
    float2 flowOffset = float2(
        sin(uv.y * 3.0 + time * 0.2) * 0.003,
        cos(uv.x * 3.0 + time * 0.15) * 0.002
    );
    float2 flowUV = uv + flowOffset * (0.5 + u.energyLevel);
    
    // === SOFT HIGHLIGHT BANDS (like light through glass) ===
    float band1 = sin(flowUV.x * 4.0 + flowUV.y * 2.0 + time * 0.1) * 0.5 + 0.5;
    band1 = smoothstep(0.4, 0.6, band1) * 0.08;
    
    float band2 = sin(flowUV.x * 2.0 - flowUV.y * 3.0 + time * 0.08) * 0.5 + 0.5;
    band2 = smoothstep(0.45, 0.55, band2) * 0.05;
    
    color += float3(1.0, 1.0, 1.0) * (band1 + band2);
    
    // === TOUCH RIPPLES (only when touched) ===
    float rippleEffect = 0.0;
    
    if (u.touchStrength > 0.01) {
        float2 touchUV = u.touchPoint;
        touchUV.x *= aspect;
        
        float touchRipple = ripple(uvAspect, touchUV, (1.0 - u.touchStrength) * 0.8, 0.8);
        rippleEffect += touchRipple * u.touchStrength * 0.5;
    }
    
    // Active ripples array
    for (int i = 0; i < 4; i++) {
        if (i >= u.activeRipples) break;
        
        float2 rippleUV = u.ripplePoints[i];
        rippleUV.x *= aspect;
        
        float r = ripple(uvAspect, rippleUV, u.rippleAges[i], 1.2);
        rippleEffect += r * 0.4;
    }
    
    // Ripples add subtle brightness
    color += float3(0.1, 0.12, 0.15) * rippleEffect;
    
    // === ZAP ENERGY / ACCENT COLOR ===
    if (u.accentStrength > 0.01) {
        // Soft golden glow
        float glowMask = 1.0 - length(uv - float2(0.5, 0.5)) * 1.2;
        glowMask = clamp(glowMask, 0.0, 1.0);
        color = mix(color, u.accentColor * 0.8, u.accentStrength * glowMask * 0.4);
    }
    
    // === ZAP STORM MODE ===
    if (u.zapStormIntensity > 0.01) {
        float3 stormColor = float3(1.0, 0.85, 0.3);
        
        // Golden tint
        color = mix(color, stormColor * color * 1.2, u.zapStormIntensity * 0.3);
        
        // Occasional sparkles (much less frequent)
        float sparkle = pool_noise(uv * 15.0 + time * 3.0);
        sparkle = step(0.96, sparkle);
        color += stormColor * sparkle * u.zapStormIntensity * 0.6;
    }
    
    // === SOFT EDGE FADE ===
    float edgeFade = smoothstep(0.0, 0.1, uv.y) * smoothstep(1.0, 0.9, uv.y);
    edgeFade *= smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x);
    
    // === ALPHA ===
    float alpha = 0.92 * edgeFade;
    
    return float4(color, alpha);
}

// MARK: - Vertex Shader

struct LiquidPoolVertexOut {
    float4 position [[position]];
};

vertex LiquidPoolVertexOut liquidPoolVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };
    
    LiquidPoolVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}
