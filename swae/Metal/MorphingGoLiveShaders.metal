//
//  MorphingGoLiveShaders.metal
//  swae
//
//  Morphing Go Live orb - sphere to rounded rectangle transition
//  Based on BubblyOrbShaders with shape morphing capabilities
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms (MUST match Swift struct exactly)

struct MorphingGoLiveUniforms {
    // === Block 1: Resolution & Time (16 bytes) ===
    float2 resolution;        // 8 bytes (offset 0)
    float time;               // 4 bytes (offset 8)
    float _pad0;              // 4 bytes (offset 12) - explicit padding
    
    // === Block 2: Touch Points (40 bytes) ===
    float2 touchPoints[5];    // 40 bytes (offset 16)
    
    // === Block 3: Touch Strengths + Misc (32 bytes) ===
    float touchStrengths[5];  // 20 bytes (offset 56)
    int activeTouchCount;     // 4 bytes (offset 76)
    float deformAmount;       // 4 bytes (offset 80)
    float wobbleDecay;        // 4 bytes (offset 84)
    
    // === Block 4: Wobble + Birth + Morph (16 bytes) ===
    float2 wobbleCenter;      // 8 bytes (offset 88)
    float birthProgress;      // 4 bytes (offset 96)
    float morphProgress;      // 4 bytes (offset 100)
    
    // === Block 5: Morph Layout (32 bytes) ===
    float2 orbCenter;         // 8 bytes (offset 104)
    float2 modalCenter;       // 8 bytes (offset 112)
    float2 modalSize;         // 8 bytes (offset 120)
    float orbRadius;          // 4 bytes (offset 128)
    float modalCornerRadius;  // 4 bytes (offset 132)
    
    // === Block 6: Appearance (32 bytes) ===
    float4 liquidColor;       // 16 bytes (offset 136) - use float4 for alignment
    float liquidIntensity;    // 4 bytes (offset 152)
    float animationSpeed;     // 4 bytes (offset 156)
    float glowIntensity;      // 4 bytes (offset 160)
    float pulseRate;          // 4 bytes (offset 164)
    float rimSpinSpeed;       // 4 bytes (offset 168)
    float _pad1;              // 4 bytes (offset 172) - pad to 16-byte boundary
};
// Total: 176 bytes (aligned to 16)

// MARK: - Vertex Output

struct MorphingVertexOut {
    float4 position [[position]];
};

// MARK: - Noise Functions

static float morph_hash(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static float morph_noise3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(
        mix(mix(morph_hash(i + float3(0,0,0)), morph_hash(i + float3(1,0,0)), f.x),
            mix(morph_hash(i + float3(0,1,0)), morph_hash(i + float3(1,1,0)), f.x), f.y),
        mix(mix(morph_hash(i + float3(0,0,1)), morph_hash(i + float3(1,0,1)), f.x),
            mix(morph_hash(i + float3(0,1,1)), morph_hash(i + float3(1,1,1)), f.x), f.y),
        f.z
    );
}

static float morph_fbm3D(float3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * morph_noise3D(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Smooth minimum for blob merging
static float morph_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// MARK: - Rounded Box SDF

// 3D rounded box signed distance function
static float roundedBoxSDF(float3 p, float3 size, float radius) {
    float3 q = abs(p) - size + radius;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - radius;
}

// MARK: - Morphed Shape SDF

// Signed distance function that morphs between sphere and rounded rectangle
static float morphedShapeSDF(float3 p, constant MorphingGoLiveUniforms& u) {
    float progress = u.morphProgress;
    
    // Interpolate center position
    float2 center2D = mix(u.orbCenter, u.modalCenter, progress);
    float3 center = float3(center2D, 0.0);
    
    // Interpolate size
    // Orb: size = (orbRadius, orbRadius, orbRadius)
    // Modal: size = (modalSize.x, modalSize.y, 0.08)
    float3 orbSize = float3(u.orbRadius);
    float3 modalSizeVec = float3(u.modalSize.x, u.modalSize.y, 0.08);
    float3 size = mix(orbSize, modalSizeVec, progress);
    
    // Interpolate corner radius
    // Orb: cornerRadius = orbRadius (makes it a sphere)
    // Modal: cornerRadius = modalCornerRadius
    float cornerRadius = mix(u.orbRadius, u.modalCornerRadius, progress);
    
    // Transform point to local space
    float3 localP = p - center;
    
    // Add stretch during mid-transition for liquid feel
    float stretchPhase = sin(progress * M_PI_F);  // Peaks at progress=0.5
    float stretchY = 1.0 + stretchPhase * 0.3;    // Up to 30% vertical stretch
    localP.y /= stretchY;
    
    // === TOUCH DEFORMATION ===
    float radiusMod = 0.0;
    
    for (int i = 0; i < 5; i++) {
        float strength = u.touchStrengths[i];
        if (strength < 0.001) continue;
        
        float2 touch2D = u.touchPoints[i];
        float touchLen = length(touch2D);
        float tz = sqrt(max(0.2, 1.0 - touchLen * touchLen * 0.5));
        float3 touchPoint = normalize(float3(touch2D.x, touch2D.y, tz));
        
        float3 pNorm = normalize(localP);
        float alignment = dot(pNorm, touchPoint);
        
        float squishAmount = strength * u.deformAmount * 0.25;
        float flattenZone = smoothstep(-0.3, 0.7, alignment);
        float flatten = flattenZone * squishAmount;
        
        float bulgeZone = 1.0 - abs(alignment);
        bulgeZone = pow(bulgeZone, 0.6);
        float bulge = bulgeZone * squishAmount * 0.7;
        
        radiusMod -= flatten * 0.25;
        radiusMod += bulge * 0.15;
    }
    
    // === WOBBLE ===
    if (u.wobbleDecay > 0.01) {
        float2 wobbleDir2D = u.wobbleCenter;
        float wLen = length(wobbleDir2D);
        float wz = sqrt(max(0.2, 1.0 - wLen * wLen * 0.5));
        float3 wobbleAxis = normalize(float3(wobbleDir2D.x, wobbleDir2D.y, wz));
        
        float3 pNorm = normalize(localP);
        float wobbleAlignment = dot(pNorm, wobbleAxis);
        
        float wobblePhase = u.time * 12.0;
        float wobbleAmount = sin(wobblePhase) * u.wobbleDecay * 0.12;
        
        float wobbleFlatten = abs(wobbleAlignment);
        float wobbleBulge = 1.0 - abs(wobbleAlignment);
        
        radiusMod += (-wobbleFlatten + wobbleBulge * 0.6) * wobbleAmount;
    }
    
    // === BIRTH WOBBLE ===
    float bp = u.birthProgress;
    if (bp < 1.0 && bp > 0.0) {
        float3 pNorm = normalize(localP);
        float birthWobbleDecay = (1.0 - bp) * (1.0 - bp);
        
        float vertWobble = sin(bp * 25.0) * birthWobbleDecay * 0.06;
        float vertAlign = abs(pNorm.y);
        radiusMod += (vertAlign - 0.5) * vertWobble;
        
        float horizWobble = sin(bp * 20.0 + 1.5) * birthWobbleDecay * 0.04;
        float horizAlign = length(float2(pNorm.x, pNorm.z));
        radiusMod += (horizAlign - 0.5) * horizWobble;
    }
    
    // Apply radius modification to size
    float3 modifiedSize = size + radiusMod;
    
    // Rounded box SDF
    return roundedBoxSDF(localP, modifiedSize, cornerRadius);
}

// Get deformation strength for visual feedback
static float getMorphDeformStrength(constant MorphingGoLiveUniforms& u) {
    float total = 0.0;
    for (int i = 0; i < 5; i++) {
        total += u.touchStrengths[i];
    }
    return total + u.wobbleDecay;
}


// MARK: - Liquid Density with Color

static float getMorphLiquidDensity(float3 p, float time, constant MorphingGoLiveUniforms& u, thread float3& outColor) {
    
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
    
    // === MORPH SLOSH - liquid sloshes during morph transition ===
    float morphSlosh = sin(u.morphProgress * M_PI_F) * 0.15;
    sloshOffset.y += morphSlosh * (1.0 - u.morphProgress);
    
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
    
    float animTime = time * 0.7;
    float breathe = sin(time * 0.8) * 0.02;
    
    // Subtle internal swirl
    float swirlAngle = time * 0.15;
    float cosSwirl = cos(swirlAngle);
    float sinSwirl = sin(swirlAngle);
    float3 swirledP = float3(
        sloshP.x * cosSwirl - sloshP.z * sinSwirl,
        sloshP.y,
        sloshP.x * sinSwirl + sloshP.z * cosSwirl
    );
    sloshP = mix(sloshP, swirledP, 0.3);
    
    // === DYNAMIC COLOR PALETTE ===
    float3 baseColor = u.liquidColor.rgb;
    float colorPulse = sin(time * 0.5) * 0.08 + 1.0;
    
    float3 color1 = baseColor * colorPulse;
    float3 color2 = baseColor * float3(0.85, 1.1, 1.0) * (2.0 - colorPulse);
    float3 color3 = baseColor * float3(1.1, 0.9, 1.05) * colorPulse;
    float3 color4 = baseColor * float3(0.9, 1.0, 1.15) * (2.0 - colorPulse);
    float3 color5 = mix(baseColor, float3(0.85, 0.88, 0.92), 0.35);
    
    color1 = clamp(color1, float3(0.0), float3(1.2));
    color2 = clamp(color2, float3(0.0), float3(1.2));
    color3 = clamp(color3, float3(0.0), float3(1.2));
    color4 = clamp(color4, float3(0.0), float3(1.2));
    color5 = clamp(color5, float3(0.0), float3(1.2));
    
    // Micro-movement offsets
    float micro1 = sin(time * 1.2) * 0.012;
    float micro2 = cos(time * 1.4) * 0.01;
    float micro3 = sin(time * 1.1 + 1.0) * 0.011;
    
    // === BLOB POSITIONS - spread based on morph progress ===
    float spread = mix(1.0, 2.5, u.morphProgress);  // Blobs spread out in modal
    
    float3 blob1Pos = float3(
        sin(animTime * 0.35) * 0.12 * spread + micro1,
        cos(animTime * 0.28) * 0.1 + breathe + 0.02,
        sin(animTime * 0.22) * 0.08
    );
    
    float3 blob2Pos = float3(
        cos(animTime * 0.32) * 0.14 * spread - 0.04 + micro2,
        sin(animTime * 0.38) * 0.1 + breathe + micro1,
        cos(animTime * 0.25) * 0.1
    );
    
    float3 blob3Pos = float3(
        sin(animTime * 0.4 + 2.0) * 0.1 * spread + micro3,
        cos(animTime * 0.35 + 1.0) * 0.08 - 0.02 + breathe,
        sin(animTime * 0.28 + 1.5) * 0.1
    );
    
    float3 blob4Pos = float3(
        cos(animTime * 0.28 + 1.0) * 0.11 * spread + sin(animTime * 0.45) * 0.03,
        sin(animTime * 0.32 + 0.5) * 0.09 + 0.04 + breathe,
        cos(animTime * 0.35 + 2.0) * 0.08 + micro2
    );
    
    float3 blob5Pos = float3(
        sin(animTime * 0.3 + 3.0) * 0.08 * spread + micro1,
        cos(animTime * 0.34 + 2.5) * 0.07 + breathe,
        sin(animTime * 0.32 + 1.0) * 0.1 + micro3
    );
    
    // Noise for organic marble veins
    float3 noisePos = sloshP * 4.0;
    noisePos += float3(time * 0.12, sin(time * 0.15) * 0.2, cos(time * 0.1) * 0.15);
    float noise = morph_fbm3D(noisePos);
    float veinNoise = morph_fbm3D(sloshP * 5.0 + float3(time * 0.08, time * 0.06, -time * 0.05));
    
    // Distance to each blob
    float d1 = length(sloshP - blob1Pos) + noise * 0.04;
    float d2 = length(sloshP - blob2Pos) + noise * 0.035;
    float d3 = length(sloshP - blob3Pos) + noise * 0.04;
    float d4 = length(sloshP - blob4Pos) + noise * 0.035;
    float d5 = length(sloshP - blob5Pos) + veinNoise * 0.05;
    
    // Individual blob densities
    float density1 = smoothstep(0.38, 0.06, d1);
    float density2 = smoothstep(0.36, 0.05, d2);
    float density3 = smoothstep(0.34, 0.055, d3);
    float density4 = smoothstep(0.32, 0.05, d4);
    float density5 = smoothstep(0.28, 0.04, d5) * 0.5;
    
    float totalDensity = density1 + density2 + density3 + density4 + density5;
    totalDensity = clamp(totalDensity, 0.0, 1.0);
    
    // Color mixing
    float3 color = float3(0.0);
    float colorWeight = 0.0001;
    
    color += color1 * density1; colorWeight += density1;
    color += color2 * density2; colorWeight += density2;
    color += color3 * density3; colorWeight += density3;
    color += color4 * density4; colorWeight += density4;
    color += color5 * density5; colorWeight += density5;
    
    color /= colorWeight;
    
    // Shimmer at blob boundaries
    float boundary = abs(density1 - density2) + abs(density2 - density3) + abs(density3 - density4);
    boundary = smoothstep(0.0, 0.5, boundary);
    float shimmer = sin(time * 2.0 + length(sloshP) * 10.0) * 0.08 + 0.08;
    color += baseColor * shimmer * boundary * 0.25;
    
    // Inner glow
    float glow = smoothstep(0.3, 0.8, totalDensity);
    color *= 1.0 + glow * 0.3;
    
    outColor = clamp(color, float3(0.0), float3(1.3));
    
    return totalDensity * u.liquidIntensity;
}


// MARK: - Fragment Shader

fragment float4 morphingGoLiveFragment(
    float4 position [[position]],
    constant MorphingGoLiveUniforms& uniforms [[buffer(0)]]
) {
    float2 uv = position.xy / uniforms.resolution;
    uv = uv * 2.0 - 1.0;
    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    uv.x *= aspect;
    
    // Camera
    float3 ro = float3(0.0, 0.0, 2.0);
    float3 rd = normalize(float3(uv, -1.5));
    
    // Birth animation - elastic ease-out
    float bp = uniforms.birthProgress;
    float elasticScale;
    if (bp < 1.0) {
        float t = bp;
        float p = 0.4;
        float s = p / 4.0;
        elasticScale = pow(2.0, -10.0 * t) * sin((t - s) * (2.0 * M_PI_F) / p) + 1.0;
        elasticScale = max(elasticScale, 0.0);
    } else {
        elasticScale = 1.0;
    }
    
    // Ray march the morphed shape
    float t = 0.0;
    float3 pMarch;
    float tEnter = -1.0;
    float tExit = -1.0;
    float lastDist = 1000.0;
    
    // Adjust march distance based on morph progress (modal is larger)
    float maxDist = mix(3.0, 5.0, uniforms.morphProgress);
    
    for (int i = 0; i < 64; i++) {
        pMarch = ro + rd * t;
        float d = morphedShapeSDF(pMarch, uniforms);
        
        if (d < 0.0005 && tEnter < 0.0) {
            tEnter = t;
        }
        
        if (tEnter > 0.0 && d > 0.0005 && lastDist < 0.0005) {
            tExit = t;
            break;
        }
        
        lastDist = d;
        t += max(abs(d) * 0.4, 0.003);
        
        if (t > maxDist) break;
    }
    
    if (tEnter < 0.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    
    // Fallback exit point
    if (tExit < 0.0) {
        tExit = tEnter + mix(1.1, 0.3, uniforms.morphProgress);
    }
    
    float3 pEnter = ro + rd * tEnter;
    float3 pExit = ro + rd * tExit;
    
    // Calculate normal from SDF gradient
    float eps = 0.002;
    float3 normalFront = normalize(float3(
        morphedShapeSDF(pEnter + float3(eps,0,0), uniforms) - morphedShapeSDF(pEnter - float3(eps,0,0), uniforms),
        morphedShapeSDF(pEnter + float3(0,eps,0), uniforms) - morphedShapeSDF(pEnter - float3(0,eps,0), uniforms),
        morphedShapeSDF(pEnter + float3(0,0,eps), uniforms) - morphedShapeSDF(pEnter - float3(0,0,eps), uniforms)
    ));
    
    // Interpolated center for normal calculation
    float2 center2D = mix(uniforms.orbCenter, uniforms.modalCenter, uniforms.morphProgress);
    float3 sphereCenter = float3(center2D, 0.0);
    float3 normalBack = normalize(pExit - sphereCenter);
    
    // Anti-aliasing
    float edgeDist = abs(morphedShapeSDF(pEnter, uniforms));
    float pixelSize = 2.0 / min(uniforms.resolution.x, uniforms.resolution.y);
    float aaWidth = pixelSize * 1.5;
    float edgeAlpha = smoothstep(aaWidth, 0.0, edgeDist);
    
    // View direction
    float3 viewDir = normalize(ro - pEnter);
    float edgeFactor = 1.0 - max(dot(viewDir, normalFront), 0.0);
    
    // Rim softening
    float rimGraze = 1.0 - abs(dot(normalize(ro - pEnter), normalFront));
    float rimSoftening = smoothstep(0.85, 0.98, rimGraze);
    edgeAlpha *= (1.0 - rimSoftening * 0.4);
    
    // Lighting
    float3 lightDir = normalize(float3(-0.5, 0.6, 0.8));
    float3 lightDir2 = normalize(float3(0.6, -0.3, 0.5));
    
    // Refraction
    float ior = 1.45;
    float3 refractedRd = refract(rd, normalFront, 1.0 / ior);
    float3 sampleDir = mix(rd, refractedRd, edgeFactor * 0.7);
    
    // Volumetric liquid sampling
    float3 liquidColor = float3(0.0);
    float liquidDensity = 0.0;
    float absorption = 0.0;
    
    int steps = 48;
    float stepSize = (tExit - tEnter) / float(steps);
    float jitter = fract(sin(dot(uv * 100.0, float2(12.9898, 78.233))) * 43758.5453);
    
    for (int i = 0; i < steps; i++) {
        float jitteredOffset = (float(i) + jitter) / float(steps);
        float sampleT = tEnter + (tExit - tEnter) * jitteredOffset;
        float3 samplePos = pEnter + sampleDir * (sampleT - tEnter);
        
        float3 sampleColor;
        float density = getMorphLiquidDensity(samplePos, uniforms.time, uniforms, sampleColor);
        
        absorption += density * stepSize * 2.5;
        float depthDarken = exp(-absorption * 0.8);
        liquidDensity += density * stepSize * 3.5;
        liquidColor += sampleColor * density * stepSize * 3.0 * depthDarken;
    }
    
    liquidDensity = clamp(liquidDensity, 0.0, 1.0);
    liquidColor = liquidColor / max(liquidDensity * 0.8, 0.01);
    
    float absorptionDarken = exp(-absorption * 0.3);
    liquidColor *= mix(1.0, absorptionDarken, liquidDensity);
    
    // Rim liquid refraction
    float rimLiquid = 0.0;
    float3 rimLiquidColor = float3(0.0);
    
    if (edgeFactor > 0.25) {
        float3 bentSamplePos = pEnter + refractedRd * 0.4;
        float3 tempColor;
        rimLiquid = getMorphLiquidDensity(bentSamplePos, uniforms.time, uniforms, tempColor);
        rimLiquid *= smoothstep(0.25, 0.7, edgeFactor);
        rimLiquidColor = tempColor;
    }
    
    // Fresnel
    float fresnel = pow(1.0 - max(dot(viewDir, normalFront), 0.0), 4.0);
    
    // Specular highlights
    float3 halfVec = normalize(lightDir + viewDir);
    float specSharp = pow(max(dot(normalFront, halfVec), 0.0), 300.0) * 1.5;
    float specMid = pow(max(dot(normalFront, halfVec), 0.0), 80.0) * 0.5;
    float specSoft = pow(max(dot(normalFront, halfVec), 0.0), 25.0) * 0.25;
    
    float3 halfVec2 = normalize(lightDir2 + viewDir);
    float spec2 = pow(max(dot(normalFront, halfVec2), 0.0), 120.0) * 0.3;
    
    float3 lightDir3 = normalize(float3(0.0, -0.8, 0.3));
    float3 halfVec3 = normalize(lightDir3 + viewDir);
    float spec3 = pow(max(dot(normalFront, halfVec3), 0.0), 60.0) * 0.15;
    
    // Back-face internal reflection
    float3 backReflectDir = reflect(refractedRd, -normalBack);
    float3 backHalf = normalize(lightDir + normalize(-backReflectDir));
    float backSpec = pow(max(dot(-normalBack, backHalf), 0.0), 80.0) * 0.35;
    float internalCaustic = pow(max(dot(backReflectDir, lightDir), 0.0), 8.0) * 0.25;
    
    // Chromatic aberration at edges
    float3 chromaOffset = float3(0.0);
    if (edgeFactor > 0.4) {
        float chromaStrength = (edgeFactor - 0.4) * 0.2;
        chromaOffset = float3(-chromaStrength, 0.0, chromaStrength) * 0.6;
    }
    
    // Rim color
    float rim = pow(fresnel, 1.5);
    float rimHue = uniforms.time * 0.2 + edgeFactor * 1.5;
    float3 rimColor = float3(
        0.6 + 0.3 * sin(rimHue),
        0.5 + 0.25 * sin(rimHue + 2.1),
        0.8 + 0.2 * sin(rimHue + 4.2)
    );
    
    // === COMBINE ===
    float3 saturatedLiquid = liquidColor;
    float lum = dot(saturatedLiquid, float3(0.299, 0.587, 0.114));
    saturatedLiquid = mix(float3(lum), saturatedLiquid, 1.4);
    
    float depthFactor = liquidDensity * 0.3;
    saturatedLiquid *= (1.0 - depthFactor * 0.4);
    
    float3 glassTint = float3(0.85, 0.9, 1.0) * 0.08;
    
    float3 color = saturatedLiquid * liquidDensity * 1.2;
    color += chromaOffset * edgeFactor * liquidDensity;
    
    float3 saturatedRim = rimLiquidColor;
    float rimLum = dot(saturatedRim, float3(0.299, 0.587, 0.114));
    saturatedRim = mix(float3(rimLum), saturatedRim, 1.3);
    color += saturatedRim * rimLiquid * (1.0 - liquidDensity * 0.4) * 1.1;
    
    float clearArea = (1.0 - liquidDensity) * (1.0 - rimLiquid);
    color += glassTint * clearArea;
    
    float3 edgeColor = mix(rimColor, rimLiquidColor, rimLiquid * 0.6);
    color += edgeColor * rim * 0.35;
    
    // Specular
    color += float3(1.0) * specSharp;
    color += float3(0.98, 0.99, 1.0) * specMid;
    color += float3(0.9, 0.95, 1.0) * specSoft;
    color += float3(0.95, 0.97, 1.0) * spec2;
    color += float3(0.85, 0.9, 1.0) * spec3;
    
    float3 backHighlight = float3(0.9, 0.95, 1.0) * backSpec;
    backHighlight += float3(0.8, 0.9, 1.0) * internalCaustic;
    color += backHighlight * (1.0 - liquidDensity * 0.25);
    
    // Subsurface scattering
    float sss = pow(max(dot(-lightDir, normalFront), 0.0), 2.5) * liquidDensity * 0.5;
    color += saturatedLiquid * sss * 0.5;
    
    // Edge definition
    float edge = smoothstep(0.75, 0.95, fresnel);
    color += rimColor * edge * 0.25;
    
    // Alpha
    float glassAlpha = 0.25 + fresnel * 0.5;
    float liquidAlpha = 0.96;
    float rimLiquidAlpha = 0.92;
    
    float alpha = mix(glassAlpha, liquidAlpha, liquidDensity);
    alpha = mix(alpha, rimLiquidAlpha, rimLiquid * (1.0 - liquidDensity * 0.4));
    alpha = max(alpha, specSharp * 0.95 + specMid * 0.6 + backSpec * 0.5);
    
    alpha *= edgeAlpha;
    color *= edgeAlpha;
    
    // Pulse effect
    if (uniforms.pulseRate > 0.0) {
        float pulse = sin(uniforms.time * uniforms.pulseRate * 6.28318) * 0.5 + 0.5;
        float pulseBoost = 1.0 + pulse * 0.3;
        color *= pulseBoost;
        alpha = min(alpha * (1.0 + pulse * 0.1), 1.0);
    }
    
    // Glow effect
    if (uniforms.glowIntensity > 0.0) {
        float3 glowColor = uniforms.liquidColor.rgb;
        float glowAmount = uniforms.glowIntensity * (0.7 + 0.3 * liquidDensity);
        color += glowColor * glowAmount * 0.5;
        alpha = min(alpha + glowAmount * 0.2, 1.0);
    }
    
    // Spinning rim effect (countdown)
    if (uniforms.rimSpinSpeed > 0.0) {
        float3 surfaceDir = normalize(pEnter - sphereCenter);
        float angle = atan2(surfaceDir.y, surfaceDir.x);
        float spinAngle = uniforms.time * uniforms.rimSpinSpeed;
        
        float angleDiff = angle - spinAngle;
        while (angleDiff > M_PI_F) angleDiff -= 2.0 * M_PI_F;
        while (angleDiff < -M_PI_F) angleDiff += 2.0 * M_PI_F;
        
        float arcLength = M_PI_F;
        float arcIntensity = 0.0;
        
        if (angleDiff <= 0.0 && angleDiff >= -arcLength) {
            arcIntensity = 1.0 + angleDiff / arcLength;
            arcIntensity = pow(arcIntensity, 0.5);
        }
        
        float rimStrength = pow(edgeFactor, 1.2);
        float surfaceStrength = 0.3;
        float spatialMask = mix(surfaceStrength, 1.0, rimStrength);
        
        float3 arcColor = uniforms.liquidColor.rgb * 2.0;
        arcColor = clamp(arcColor, float3(0.0), float3(1.5));
        
        float spinIntensity = arcIntensity * spatialMask * 0.7;
        
        color += arcColor * spinIntensity;
        alpha = max(alpha, spinIntensity * 0.8);
    }
    
    return float4(color, alpha);
}

// MARK: - Vertex Shader

vertex MorphingVertexOut morphingGoLiveVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };
    
    MorphingVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}
