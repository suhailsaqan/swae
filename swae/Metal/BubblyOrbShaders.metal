//
//  BubblyOrbShaders.metal
//  swae
//
//  Glass marble orb with liquid inside - enhanced realism
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms

struct BubblyOrbUniforms {
    float2 resolution;
    float time;
    float2 touchPoints[5];
    float touchStrengths[5];
    int activeTouchCount;
    float deformAmount;
    float wobbleDecay;
    float2 wobbleCenter;
    float birthProgress;  // 0 = just born, 1 = fully formed
    
    // Configuration for customizable appearance
    float3 liquidColor;      // RGB color of liquid (default: blue)
    float liquidIntensity;   // 0-1, amount of liquid visible
    float animationSpeed;    // Time multiplier for animations
    float glowIntensity;     // Outer glow strength (0 = none)
    float pulseRate;         // Pulsing frequency (0 = none)
    float rimSpinSpeed;      // 0 = no spin, >0 = spinning rainbow rim (for countdown)
};

// MARK: - Noise (prefixed to avoid conflicts)

static float orb_hash(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static float orb_noise3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(
        mix(mix(orb_hash(i + float3(0,0,0)), orb_hash(i + float3(1,0,0)), f.x),
            mix(orb_hash(i + float3(0,1,0)), orb_hash(i + float3(1,1,0)), f.x), f.y),
        mix(mix(orb_hash(i + float3(0,0,1)), orb_hash(i + float3(1,0,1)), f.x),
            mix(orb_hash(i + float3(0,1,1)), orb_hash(i + float3(1,1,1)), f.x), f.y),
        f.z
    );
}

static float orb_fbm3D(float3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * orb_noise3D(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Smooth minimum for blob merging
static float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// MARK: - Sphere intersection

float2 sphereIntersect(float3 ro, float3 rd, float3 center, float radius) {
    float3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) return float2(-1.0);
    h = sqrt(h);
    return float2(-b - h, -b + h);
}

// MARK: - Liquid Orb Deformation (Shape Squish)

// Deformed sphere SDF - SHAPE deforms, orb stays in place
// Push on top = top flattens, sides bulge out (like a stress ball)
float deformedSphereSDF(float3 p, float radius, constant BubblyOrbUniforms& u) {
    
    // We'll modify the radius based on position, not transform the point
    float radiusMod = 0.0;
    
    // Process each touch - SQUISH physics (shape deformation)
    for (int i = 0; i < 5; i++) {
        float strength = u.touchStrengths[i];
        if (strength < 0.001) continue;
        
        // Touch position - where finger is pressing
        float2 touch2D = u.touchPoints[i];
        
        // Touch point on sphere surface (front-facing, z toward camera)
        float touchLen = length(touch2D);
        float tz = sqrt(max(0.2, 1.0 - touchLen * touchLen * 0.5));
        float3 touchPoint = normalize(float3(touch2D.x, touch2D.y, tz));
        
        // How aligned is this point with the touch direction?
        float3 pNorm = normalize(p);
        float alignment = dot(pNorm, touchPoint);  // 1 = at touch, -1 = opposite side
        
        // === LOCALIZED SQUISH - STRONGER ===
        // Only deform the side being touched, not the opposite side
        float squishAmount = strength * u.deformAmount * 0.25;  // Increased from 0.12
        
        // Flatten at touch point (positive alignment = near touch)
        // Use smoothstep to localize the effect
        float flattenZone = smoothstep(-0.3, 0.7, alignment);  // Wider zone
        float flatten = flattenZone * squishAmount;
        
        // Bulge on the sides (perpendicular to touch axis)
        // Maximum bulge at alignment = 0 (equator relative to touch)
        float bulgeZone = 1.0 - abs(alignment);  // Peak at sides
        bulgeZone = pow(bulgeZone, 0.6);  // Even softer falloff for wider bulge
        float bulge = bulgeZone * squishAmount * 0.7;  // Increased from 0.6
        
        // Apply: negative = push surface in, positive = push surface out
        radiusMod -= flatten * 0.25;  // Increased from 0.15
        radiusMod += bulge * 0.15;    // Increased from 0.08
    }
    
    // === WOBBLE - shape oscillates after release ===
    if (u.wobbleDecay > 0.01) {
        float2 wobbleDir2D = u.wobbleCenter;
        
        // Wobble axis
        float wLen = length(wobbleDir2D);
        float wz = sqrt(max(0.2, 1.0 - wLen * wLen * 0.5));
        float3 wobbleAxis = normalize(float3(wobbleDir2D.x, wobbleDir2D.y, wz));
        
        // How aligned is this point with wobble axis?
        float3 pNorm = normalize(p);
        float wobbleAlignment = dot(pNorm, wobbleAxis);
        
        // Oscillating deformation - STRONGER
        float wobblePhase = u.time * 12.0;
        float wobbleAmount = sin(wobblePhase) * u.wobbleDecay * 0.12;  // Increased from 0.05
        
        // Squish along wobble axis (flatten at poles, bulge at equator)
        float wobbleFlatten = abs(wobbleAlignment);  // Poles
        float wobbleBulge = 1.0 - abs(wobbleAlignment);  // Equator
        
        radiusMod += (-wobbleFlatten + wobbleBulge * 0.6) * wobbleAmount;  // Increased bulge
    }
    
    // === BIRTH WOBBLE - orb shape jiggles as it forms ===
    float bp = u.birthProgress;
    if (bp < 1.0 && bp > 0.0) {
        float3 pNorm = normalize(p);
        
        // Multi-frequency wobble that decays as birth completes
        float birthWobbleDecay = (1.0 - bp) * (1.0 - bp);  // Quadratic decay
        
        // Vertical squash/stretch
        float vertWobble = sin(bp * 25.0) * birthWobbleDecay * 0.06;
        float vertAlign = abs(pNorm.y);
        radiusMod += (vertAlign - 0.5) * vertWobble;
        
        // Horizontal wobble (perpendicular)
        float horizWobble = sin(bp * 20.0 + 1.5) * birthWobbleDecay * 0.04;
        float horizAlign = length(float2(pNorm.x, pNorm.z));
        radiusMod += (horizAlign - 0.5) * horizWobble;
    }
    
    return length(p) - (radius + radiusMod);
}

// Get deformation info for visual effects
float getDeformStrength(constant BubblyOrbUniforms& u) {
    float total = 0.0;
    for (int i = 0; i < 5; i++) {
        total += u.touchStrengths[i];
    }
    return total + u.wobbleDecay;
}

// MARK: - Marble-Style Multi-Color Liquid with Distinct Veins

// Returns liquid density at a point with marble-like color veins
static float getLiquidDensity(float3 p, float time, constant BubblyOrbUniforms& u, thread float3& outColor) {
    
    // === CALCULATE SLOSH OFFSET ===
    float3 sloshOffset = float3(0.0);
    
    for (int i = 0; i < 5; i++) {
        float strength = u.touchStrengths[i];
        if (strength < 0.001) continue;
        
        float2 touch2D = u.touchPoints[i];
        float touchLen = length(touch2D);
        float tz = sqrt(max(0.2, 1.0 - touchLen * touchLen * 0.5));
        float3 touchDir = normalize(float3(touch2D.x, touch2D.y, tz));
        
        sloshOffset -= touchDir * strength * 0.15;
    }
    
    // Wobble causes sloshing oscillation
    if (u.wobbleDecay > 0.01) {
        float2 wobbleDir2D = u.wobbleCenter;
        float wLen = length(wobbleDir2D);
        float wz = sqrt(max(0.2, 1.0 - wLen * wLen * 0.5));
        float3 wobbleDir = normalize(float3(wobbleDir2D.x, wobbleDir2D.y, wz));
        
        float sloshPhase = time * 8.0;
        float sloshAmount = sin(sloshPhase) * u.wobbleDecay * 0.12;
        sloshOffset += wobbleDir * sloshAmount;
    }
    
    float3 sloshP = p - sloshOffset;
    
    // === BIRTH ANIMATION ===
    float bp = u.birthProgress;
    if (bp < 1.0) {
        float scatter;
        if (bp < 0.4) {
            float t = bp / 0.4;
            scatter = (1.0 - t * t) * 0.25;
        } else if (bp < 0.7) {
            float t = (bp - 0.4) / 0.3;
            scatter = -sin(t * M_PI_F) * 0.08;
        } else {
            float t = (bp - 0.7) / 0.3;
            float damping = exp(-t * 3.0);
            scatter = sin(t * M_PI_F * 3.0) * damping * 0.05;
        }
        
        float3 pDir = normalize(p + float3(0.001));
        sloshP += pDir * scatter;
        
        float swirl = (1.0 - bp) * 0.15;
        float angle = bp * 8.0;
        sloshP.x += sin(angle + p.y * 3.0) * swirl;
        sloshP.z += cos(angle + p.y * 3.0) * swirl;
        
        float vertBounce = 0.0;
        if (bp < 0.5) {
            vertBounce = (1.0 - bp * 2.0) * 0.12;
        } else {
            float t = (bp - 0.5) * 2.0;
            vertBounce = sin(t * M_PI_F * 2.0) * exp(-t * 2.5) * 0.06;
        }
        sloshP.y -= vertBounce;
    }
    
    // FIXED: Use constant time multiplier for blob positions to avoid jumps during config transitions
    // animationSpeed should only affect visual intensity, not blob movement
    float animTime = time * 0.7;  // Constant speed for smooth transitions
    float breathe = sin(time * 0.8) * 0.02;
    
    // === SUBTLE INTERNAL SWIRL - rotates the whole liquid slowly ===
    float swirlAngle = time * 0.15;  // Very slow rotation
    float cosSwirl = cos(swirlAngle);
    float sinSwirl = sin(swirlAngle);
    float3 swirledP = float3(
        sloshP.x * cosSwirl - sloshP.z * sinSwirl,
        sloshP.y,
        sloshP.x * sinSwirl + sloshP.z * cosSwirl
    );
    sloshP = mix(sloshP, swirledP, 0.3);  // Partial swirl, not full rotation
    
    // === DYNAMIC COLOR PALETTE - Based on liquidColor uniform ===
    // This allows the orb to change colors for different states (idle, countdown, live)
    float3 baseColor = u.liquidColor;
    float colorPulse = sin(time * 0.5) * 0.08 + 1.0;  // 0.92 to 1.08
    
    // Generate harmonious color variations from the base color
    // Shift hue slightly for each blob to create variety while staying in the same family
    float3 color1 = baseColor * colorPulse;                                    // Base color
    float3 color2 = baseColor * float3(0.85, 1.1, 1.0) * (2.0 - colorPulse);  // Slight shift
    float3 color3 = baseColor * float3(1.1, 0.9, 1.05) * colorPulse;          // Another shift
    float3 color4 = baseColor * float3(0.9, 1.0, 1.15) * (2.0 - colorPulse);  // Blue-ish shift
    float3 color5 = mix(baseColor, float3(0.85, 0.88, 0.92), 0.35);           // Subtle lighter highlight
    
    // Clamp to valid range
    color1 = clamp(color1, float3(0.0), float3(1.2));
    color2 = clamp(color2, float3(0.0), float3(1.2));
    color3 = clamp(color3, float3(0.0), float3(1.2));
    color4 = clamp(color4, float3(0.0), float3(1.2));
    color5 = clamp(color5, float3(0.0), float3(1.2));
    
    // === BLOBS - closer together, more crowded ===
    
    // Micro-movement offsets - small organic shifts
    float micro1 = sin(time * 1.2) * 0.012;
    float micro2 = cos(time * 1.4) * 0.01;
    float micro3 = sin(time * 1.1 + 1.0) * 0.011;
    
    // Deep purple blob - central, larger
    float3 blob1Pos = float3(
        sin(animTime * 0.35) * 0.12 + micro1,
        cos(animTime * 0.28) * 0.1 + breathe + 0.02,
        sin(animTime * 0.22) * 0.08
    );
    
    // Violet blob - overlapping
    float3 blob2Pos = float3(
        cos(animTime * 0.32) * 0.14 - 0.04 + micro2,
        sin(animTime * 0.38) * 0.1 + breathe + micro1,
        cos(animTime * 0.25) * 0.1
    );
    
    // Magenta blob - close to center
    float3 blob3Pos = float3(
        sin(animTime * 0.4 + 2.0) * 0.1 + micro3,
        cos(animTime * 0.35 + 1.0) * 0.08 - 0.02 + breathe,
        sin(animTime * 0.28 + 1.5) * 0.1
    );
    
    // Royal blue blob - slightly offset
    float3 blob4Pos = float3(
        cos(animTime * 0.28 + 1.0) * 0.11 + sin(animTime * 0.45) * 0.03,
        sin(animTime * 0.32 + 0.5) * 0.09 + 0.04 + breathe,
        cos(animTime * 0.35 + 2.0) * 0.08 + micro2
    );
    
    // Lavender highlight blob - smaller accent
    float3 blob5Pos = float3(
        sin(animTime * 0.3 + 3.0) * 0.08 + micro1,
        cos(animTime * 0.34 + 2.5) * 0.07 + breathe,
        sin(animTime * 0.32 + 1.0) * 0.1 + micro3
    );
    
    // Noise for organic marble veins - animated but smooth
    float3 noisePos = sloshP * 4.0;
    noisePos += float3(time * 0.12, sin(time * 0.15) * 0.2, cos(time * 0.1) * 0.15);  // Slightly faster flow
    float noise = orb_fbm3D(noisePos);
    float veinNoise = orb_fbm3D(sloshP * 5.0 + float3(time * 0.08, time * 0.06, -time * 0.05));  // Flowing veins
    
    // Distance to each blob - larger blobs, more overlap
    float d1 = length(sloshP - blob1Pos) + noise * 0.04;
    float d2 = length(sloshP - blob2Pos) + noise * 0.035;
    float d3 = length(sloshP - blob3Pos) + noise * 0.04;
    float d4 = length(sloshP - blob4Pos) + noise * 0.035;
    float d5 = length(sloshP - blob5Pos) + veinNoise * 0.05;
    
    // Individual blob densities - LARGER blobs for more crowded look
    float density1 = smoothstep(0.38, 0.06, d1);
    float density2 = smoothstep(0.36, 0.05, d2);
    float density3 = smoothstep(0.34, 0.055, d3);
    float density4 = smoothstep(0.32, 0.05, d4);
    float density5 = smoothstep(0.28, 0.04, d5) * 0.5;
    
    // Total density
    float totalDensity = density1 + density2 + density3 + density4 + density5;
    totalDensity = clamp(totalDensity, 0.0, 1.0);
    
    // === COLOR MIXING - weighted by each blob's density ===
    float3 color = float3(0.0);
    float colorWeight = 0.0001;  // Prevent divide by zero
    
    // Each blob contributes its color based on its density at this point
    color += color1 * density1;
    colorWeight += density1;
    
    color += color2 * density2;
    colorWeight += density2;
    
    color += color3 * density3;
    colorWeight += density3;
    
    color += color4 * density4;
    colorWeight += density4;
    
    color += color5 * density5;
    colorWeight += density5;
    
    // Normalize color by total weight
    color /= colorWeight;
    
    // Add subtle shimmer at blob boundaries (tinted with base color)
    float boundary = abs(density1 - density2) + abs(density2 - density3) + abs(density3 - density4);
    boundary = smoothstep(0.0, 0.5, boundary);
    float shimmer = sin(time * 2.0 + length(sloshP) * 10.0) * 0.08 + 0.08;
    color += baseColor * shimmer * boundary * 0.25;
    
    // Inner glow - brighter in dense areas
    float glow = smoothstep(0.3, 0.8, totalDensity);
    color *= 1.0 + glow * 0.3;
    
    outColor = clamp(color, float3(0.0), float3(1.3));
    
    return totalDensity * u.liquidIntensity;
}

// MARK: - Main Fragment Shader

fragment float4 bubblyOrbFragment(
    float4 position [[position]],
    constant BubblyOrbUniforms& uniforms [[buffer(0)]]
) {
    float2 uv = position.xy / uniforms.resolution;
    uv = uv * 2.0 - 1.0;
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    uv.x *= aspect;
    
    // Camera
    float3 ro = float3(0.0, 0.0, 2.0);
    float3 rd = normalize(float3(uv, -1.5));
    
    // === BIRTH ANIMATION ===
    // Elastic ease-out with overshoot for scale pop
    float bp = uniforms.birthProgress;
    float elasticScale;
    if (bp < 1.0) {
        // Elastic overshoot: goes to ~1.15 then settles to 1.0
        float t = bp;
        float p = 0.4;  // Period
        float s = p / 4.0;  // Amplitude shift
        elasticScale = pow(2.0, -10.0 * t) * sin((t - s) * (2.0 * M_PI_F) / p) + 1.0;
        elasticScale = max(elasticScale, 0.0);  // Clamp negative
    } else {
        elasticScale = 1.0;
    }
    
    float sphereRadius = 0.55 * elasticScale;
    float3 sphereCenter = float3(0.0);
    
    // First do analytical intersection for bounding
    float2 tHit = sphereIntersect(ro, rd, sphereCenter, sphereRadius * 1.2);  // Slightly larger for deformation
    
    if (tHit.x < 0.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    
    // Raymarch the deformed sphere for accurate intersection
    float t = tHit.x;
    float tEnter = -1.0;
    float tExit = -1.0;
    float lastDist = 1000.0;
    
    for (int i = 0; i < 64; i++) {  // More steps for smoother intersection
        float3 p = ro + rd * t;
        float d = deformedSphereSDF(p, sphereRadius, uniforms);
        
        // Found entry point - use tighter threshold
        if (d < 0.0005 && tEnter < 0.0) {
            tEnter = t;
        }
        
        // Track when we exit
        if (tEnter > 0.0 && d > 0.0005 && lastDist < 0.0005) {
            tExit = t;
            break;
        }
        
        lastDist = d;
        // Smaller minimum step for smoother results
        t += max(abs(d) * 0.4, 0.003);
        
        if (t > tHit.y + 0.2) break;
    }
    
    // Fallback exit point
    if (tEnter > 0.0 && tExit < 0.0) {
        tExit = tHit.y;
    }
    
    if (tEnter < 0.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    
    // === IMPROVED ANTI-ALIASING for smooth rim ===
    float3 pEdge = ro + rd * tEnter;
    float edgeDist = abs(deformedSphereSDF(pEdge, sphereRadius, uniforms));
    
    // Calculate pixel size for resolution-aware AA
    float pixelSize = 2.0 / min(uniforms.resolution.x, uniforms.resolution.y);
    float aaWidth = pixelSize * 1.5;  // AA width based on pixel size
    
    // Smooth edge alpha with wider falloff
    float edgeAlpha = smoothstep(aaWidth, 0.0, edgeDist);
    
    // Additional rim softening based on view angle (grazing angles get softer)
    float3 approxNormal = normalize(pEdge - sphereCenter);
    float rimGraze = 1.0 - abs(dot(normalize(ro - pEdge), approxNormal));
    float rimSoftening = smoothstep(0.85, 0.98, rimGraze);
    edgeAlpha *= (1.0 - rimSoftening * 0.4);  // Soften at grazing angles
    
    float3 pEnter = ro + rd * tEnter;
    float3 pExit = ro + rd * tExit;
    
    // Calculate normals from deformed SDF gradient
    float eps = 0.002;
    float3 normalFront = normalize(float3(
        deformedSphereSDF(pEnter + float3(eps,0,0), sphereRadius, uniforms) - deformedSphereSDF(pEnter - float3(eps,0,0), sphereRadius, uniforms),
        deformedSphereSDF(pEnter + float3(0,eps,0), sphereRadius, uniforms) - deformedSphereSDF(pEnter - float3(0,eps,0), sphereRadius, uniforms),
        deformedSphereSDF(pEnter + float3(0,0,eps), sphereRadius, uniforms) - deformedSphereSDF(pEnter - float3(0,0,eps), sphereRadius, uniforms)
    ));
    float3 normalBack = normalize(pExit - sphereCenter);
    
    // Get deformation amount for visual feedback
    float deform = getDeformStrength(uniforms);
    
    // View direction
    float3 viewDir = normalize(ro - pEnter);
    
    // === LIGHTING SETUP ===
    float3 lightDir = normalize(float3(-0.5, 0.6, 0.8));
    float3 lightDir2 = normalize(float3(0.6, -0.3, 0.5));
    
    // === REFRACTION ===
    float ior = 1.45;
    float3 refractedRd = refract(rd, normalFront, 1.0 / ior);
    float edgeFactor = 1.0 - max(dot(viewDir, normalFront), 0.0);
    float3 sampleDir = mix(rd, refractedRd, edgeFactor * 0.7);
    
    // === VOLUMETRIC LIQUID WITH ABSORPTION ===
    float3 liquidColor = float3(0.0);
    float liquidDensity = 0.0;
    float absorption = 0.0;  // Beer's law absorption
    
    int steps = 48;  // Reduced steps, but with jittering for smooth results
    float stepSize = (tExit - tEnter) / float(steps);
    
    // Jitter offset to break up banding - based on screen position
    float jitter = fract(sin(dot(uv * 100.0, float2(12.9898, 78.233))) * 43758.5453);
    
    for (int i = 0; i < steps; i++) {
        // Add jitter to sample position to eliminate banding
        float jitteredOffset = (float(i) + jitter) / float(steps);
        float t = tEnter + (tExit - tEnter) * jitteredOffset;
        float3 samplePos = pEnter + sampleDir * (t - tEnter);
        
        // Keep inside sphere
        float distFromCenter = length(samplePos);
        if (distFromCenter > sphereRadius * 0.98) {
            samplePos = normalize(samplePos) * sphereRadius * 0.98;
        }
        
        // Sample liquid field (with slosh effect)
        float3 sampleColor;
        float density = getLiquidDensity(samplePos, uniforms.time, uniforms, sampleColor);
        
        // Beer's law - light absorption through liquid
        absorption += density * stepSize * 2.5;
        
        // Accumulate with depth-based darkening
        float depthDarken = exp(-absorption * 0.8);
        liquidDensity += density * stepSize * 3.5;
        liquidColor += sampleColor * density * stepSize * 3.0 * depthDarken;
    }
    
    liquidDensity = clamp(liquidDensity, 0.0, 1.0);
    liquidColor = liquidColor / max(liquidDensity * 0.8, 0.01);
    
    // Apply final absorption darkening
    float absorptionDarken = exp(-absorption * 0.3);
    liquidColor *= mix(1.0, absorptionDarken, liquidDensity);
    
    // === REFRACTION RIM EFFECT ===
    float rimLiquid = 0.0;
    float3 rimLiquidColor = float3(0.0);
    
    if (edgeFactor > 0.25) {
        float3 bentSamplePos = pEnter + refractedRd * sphereRadius * 0.65;
        float3 tempColor;
        rimLiquid = getLiquidDensity(bentSamplePos, uniforms.time, uniforms, tempColor);
        rimLiquid *= smoothstep(0.25, 0.7, edgeFactor);
        rimLiquidColor = tempColor;
    }
    
    // === ENHANCED GLASS SURFACE SHADING ===
    float fresnel = pow(1.0 - max(dot(viewDir, normalFront), 0.0), 4.0);  // Stronger fresnel
    
    // Sharp primary specular highlight (the bright white spot on glass)
    float3 halfVec = normalize(lightDir + viewDir);
    float specSharp = pow(max(dot(normalFront, halfVec), 0.0), 300.0) * 1.5;  // Very sharp
    float specMid = pow(max(dot(normalFront, halfVec), 0.0), 80.0) * 0.5;
    float specSoft = pow(max(dot(normalFront, halfVec), 0.0), 25.0) * 0.25;
    
    // Secondary specular (fill light)
    float3 halfVec2 = normalize(lightDir2 + viewDir);
    float spec2 = pow(max(dot(normalFront, halfVec2), 0.0), 120.0) * 0.3;
    
    // Third light for rim highlight
    float3 lightDir3 = normalize(float3(0.0, -0.8, 0.3));
    float3 halfVec3 = normalize(lightDir3 + viewDir);
    float spec3 = pow(max(dot(normalFront, halfVec3), 0.0), 60.0) * 0.15;
    
    // === BACK-FACE INTERNAL REFLECTION ===
    float3 backReflectDir = reflect(refractedRd, -normalBack);
    float3 backHalf = normalize(lightDir + normalize(-backReflectDir));
    float backSpec = pow(max(dot(-normalBack, backHalf), 0.0), 80.0) * 0.35;
    
    // Internal caustic - light focusing through the glass
    float internalCaustic = pow(max(dot(backReflectDir, lightDir), 0.0), 8.0) * 0.25;
    
    // === CHROMATIC ABERRATION at edges ===
    float3 chromaOffset = float3(0.0);
    if (edgeFactor > 0.4) {
        float chromaStrength = (edgeFactor - 0.4) * 0.2;
        chromaOffset = float3(-chromaStrength, 0.0, chromaStrength) * 0.6;
    }
    
    // Rim color - subtle, glass-like
    float rim = pow(fresnel, 1.5);
    float rimHue = uniforms.time * 0.2 + edgeFactor * 1.5;
    float3 rimColor = float3(
        0.6 + 0.3 * sin(rimHue),
        0.5 + 0.25 * sin(rimHue + 2.1),
        0.8 + 0.2 * sin(rimHue + 4.2)
    );
    
    // === COMBINE EVERYTHING - Enhanced for realism ===
    
    // Boost liquid color saturation for depth
    float3 saturatedLiquid = liquidColor;
    float lum = dot(saturatedLiquid, float3(0.299, 0.587, 0.114));
    saturatedLiquid = mix(float3(lum), saturatedLiquid, 1.4);  // 40% more saturated
    
    // Darken liquid based on depth for 3D feel
    float depthFactor = liquidDensity * 0.3;
    saturatedLiquid *= (1.0 - depthFactor * 0.4);
    
    // Glass tint - subtle blue-ish clear glass
    float3 glassTint = float3(0.85, 0.9, 1.0) * 0.08;
    
    // Start with liquid (boosted saturation)
    float3 color = saturatedLiquid * liquidDensity * 1.2;  // Brighter liquid
    
    // Add chromatic aberration tint at edges
    color += chromaOffset * edgeFactor * liquidDensity;
    
    // Refracted rim liquid - shows color wrapping around edges
    float3 saturatedRim = rimLiquidColor;
    float rimLum = dot(saturatedRim, float3(0.299, 0.587, 0.114));
    saturatedRim = mix(float3(rimLum), saturatedRim, 1.3);
    color += saturatedRim * rimLiquid * (1.0 - liquidDensity * 0.4) * 1.1;
    
    // Glass tint in clear areas
    float clearArea = (1.0 - liquidDensity) * (1.0 - rimLiquid);
    color += glassTint * clearArea;
    
    // Rim/edge color - subtle glass edge
    float3 edgeColor = mix(rimColor, rimLiquidColor, rimLiquid * 0.6);
    color += edgeColor * rim * 0.35;
    
    // === SPECULAR HIGHLIGHTS - Key for glass realism ===
    // Sharp white highlight (the "shine" spot)
    color += float3(1.0) * specSharp;
    // Medium highlight spread
    color += float3(0.98, 0.99, 1.0) * specMid;
    // Soft ambient highlight
    color += float3(0.9, 0.95, 1.0) * specSoft;
    // Secondary light
    color += float3(0.95, 0.97, 1.0) * spec2;
    // Rim light
    color += float3(0.85, 0.9, 1.0) * spec3;
    
    // Back-face reflection (internal highlight) - gives depth
    float3 backHighlight = float3(0.9, 0.95, 1.0) * backSpec;
    backHighlight += float3(0.8, 0.9, 1.0) * internalCaustic;
    color += backHighlight * (1.0 - liquidDensity * 0.25);
    
    // Subsurface scattering - colored light through liquid
    float sss = pow(max(dot(-lightDir, normalFront), 0.0), 2.5) * liquidDensity * 0.5;
    color += saturatedLiquid * sss * 0.5;
    
    // Edge definition - crisp glass edge
    float edge = smoothstep(0.75, 0.95, fresnel);
    color += rimColor * edge * 0.25;
    
    // Deformation feedback - REMOVED: was causing white/purple wash on touch
    // The squish physics and liquid sloshing already provide visual feedback
    
    // === ALPHA - More solid glass feel ===
    float glassAlpha = 0.25 + fresnel * 0.5;  // More visible glass
    float liquidAlpha = 0.96;
    float rimLiquidAlpha = 0.92;
    
    float alpha = mix(glassAlpha, liquidAlpha, liquidDensity);
    alpha = mix(alpha, rimLiquidAlpha, rimLiquid * (1.0 - liquidDensity * 0.4));
    // Specular highlights should be fully visible
    alpha = max(alpha, specSharp * 0.95 + specMid * 0.6 + backSpec * 0.5);
    
    // Apply edge anti-aliasing - smooth the rim
    alpha *= edgeAlpha;
    color *= edgeAlpha;
    
    // === PULSE EFFECT ===
    if (uniforms.pulseRate > 0.0) {
        float pulse = sin(uniforms.time * uniforms.pulseRate * 6.28318) * 0.5 + 0.5;
        float pulseBoost = 1.0 + pulse * 0.3;
        color *= pulseBoost;
        alpha = min(alpha * (1.0 + pulse * 0.1), 1.0);
    }
    
    // === GLOW EFFECT ===
    if (uniforms.glowIntensity > 0.0) {
        // Add soft glow based on liquid color
        float3 glowColor = uniforms.liquidColor;
        float glowAmount = uniforms.glowIntensity * (0.7 + 0.3 * liquidDensity);
        color += glowColor * glowAmount * 0.5;
        alpha = min(alpha + glowAmount * 0.2, 1.0);
    }
    
    // === SPINNING RIM EFFECT (for countdown) ===
    if (uniforms.rimSpinSpeed > 0.0) {
        // Use the 3D surface position to calculate angle around the sphere
        // pEnter is the point on the sphere surface
        float3 surfaceDir = normalize(pEnter - sphereCenter);
        
        // Calculate angle around the sphere (using X-Y plane, looking from front)
        float angle = atan2(surfaceDir.y, surfaceDir.x);  // -PI to PI
        
        // Spinning position - where the "head" of the arc is
        float spinAngle = uniforms.time * uniforms.rimSpinSpeed;
        
        // Calculate angular distance from the spinning head
        float angleDiff = angle - spinAngle;
        // Wrap to -PI to PI range
        while (angleDiff > M_PI_F) angleDiff -= 2.0 * M_PI_F;
        while (angleDiff < -M_PI_F) angleDiff += 2.0 * M_PI_F;
        
        // Arc covers half the circumference (PI radians) with a comet tail fade
        float arcLength = M_PI_F;  // Half circumference
        float arcIntensity = 0.0;
        
        // The arc trails BEHIND the spinning head
        // angleDiff = 0 is at the head, negative values trail behind
        if (angleDiff <= 0.0 && angleDiff >= -arcLength) {
            // We're in the arc - intensity fades from head (1.0) to tail (0.0)
            arcIntensity = 1.0 + angleDiff / arcLength;  // 1.0 at head, 0.0 at tail
            arcIntensity = pow(arcIntensity, 0.5);  // Softer falloff for visible tail
        }
        
        // The effect should be strongest at the EDGE of the sphere (rim)
        // edgeFactor is already calculated - it's high at grazing angles
        float rimStrength = pow(edgeFactor, 1.2);  // Boost edge visibility
        
        // Also add some effect to the whole visible surface, but weaker
        float surfaceStrength = 0.3;
        
        // Combine: strong on rim, weaker on surface
        float spatialMask = mix(surfaceStrength, 1.0, rimStrength);
        
        // Use a bright, saturated version of the liquid color
        float3 arcColor = uniforms.liquidColor * 2.0;  // Bright
        arcColor = clamp(arcColor, float3(0.0), float3(1.5));
        
        // Final intensity
        float spinIntensity = arcIntensity * spatialMask * 0.7;
        
        // Add spinning arc
        color += arcColor * spinIntensity;
        alpha = max(alpha, spinIntensity * 0.8);
    }
    
    return float4(color, alpha);
}

// MARK: - Vertex Shader

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut bubblyOrbVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}
