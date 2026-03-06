//
//  GlobeShaders.metal
//  swae
//
//  Metal shaders for the globe zoom-out animation.
//  Multi-resolution tile stack with per-level alpha blending.
//

#include <metal_stdlib>
using namespace metal;

// Must match the Swift GlobeUniforms layout exactly.
struct GlobeUniforms {
    float4x4 mvp;
    float4x4 model;
    float3x3 normalMatrix;
    float3   cameraPos;
    float    padding1;
    float3   anchorWorldPos;
    float    patchBlend;       // used only for legacy/single-patch; per-level uses buffer(1)
    float    displacementScale;
    float    starAlpha;
    float    phoneAlpha;
    float    phoneScale;
    float    personAlpha;
    float    time;
    float    desaturationStrength;
    float    darkenFactor;
    float    nightLightsIntensity;
    float    ambientLightIntensity;
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct VertexOut {
    float4 position  [[position]];
    float3 worldPos;
    float3 worldNormal;
    float2 uv;
};

// MARK: - Globe Shaders

vertex VertexOut globe_vertex(
    VertexIn in [[stage_in]],
    constant GlobeUniforms &u [[buffer(1)]]
) {
    VertexOut out;
    float4 worldPos = u.model * float4(in.position, 1.0);
    out.position    = u.mvp * float4(in.position, 1.0);
    out.worldPos    = worldPos.xyz;
    out.worldNormal = u.normalMatrix * in.normal;
    out.uv          = in.uv;
    return out;
}

fragment float4 globe_fragment(
    VertexOut in [[stage_in]],
    constant GlobeUniforms &u [[buffer(0)]],
    texture2d<float> baseTexture  [[texture(0)]],
    texture2d<float> nightTexture [[texture(1)]],
    sampler s [[sampler(0)]]
) {
    float4 base  = baseTexture.sample(s, in.uv);
    float4 night = nightTexture.sample(s, in.uv);

    // Desaturate to grayscale
    float lum = dot(base.rgb, float3(0.299, 0.587, 0.114));
    float3 gray = float3(lum);
    float3 color = mix(base.rgb, gray, u.desaturationStrength);

    // Darken
    color *= u.darkenFactor;

    // City lights emission
    color += night.rgb * u.nightLightsIntensity;

    // Simple directional lighting
    float3 lightDir = normalize(float3(0.5, 0.8, 0.3));
    float NdotL = max(dot(normalize(in.worldNormal), lightDir), 0.0);
    color *= (u.ambientLightIntensity + (1.0 - u.ambientLightIntensity) * NdotL);

    return float4(color, 1.0);
}

// MARK: - Tile Pyramid Shaders

vertex VertexOut tile_vertex(
    VertexIn in [[stage_in]],
    constant GlobeUniforms &u [[buffer(1)]]
) {
    // No z-offset needed — tiles use depth-always state
    VertexOut out;
    float4 worldPos = u.model * float4(in.position, 1.0);
    out.position    = u.mvp * float4(in.position, 1.0);
    out.worldPos    = worldPos.xyz;
    out.worldNormal = u.normalMatrix * in.normal;
    out.uv          = in.uv;
    return out;
}

// Alpha-blended tile fragment with zoom-dependent desaturation and darkening.
// tileAlpha = overall alpha (zoom blend × layer fade).
// tileDesat = 0.0 (full color) to 1.0 (grayscale), driven by zoom level.
// tileDarken = 1.0 (full brightness) to 0.75 (darkened), driven by zoom level.
fragment float4 tile_fragment(
    VertexOut in [[stage_in]],
    constant GlobeUniforms &u [[buffer(0)]],
    constant float &tileAlpha [[buffer(1)]],
    constant float &tileDesat [[buffer(2)]],
    constant float &tileDarken [[buffer(3)]],
    texture2d<float> tileTex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float4 color = tileTex.sample(s, in.uv);
    float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, float3(lum), tileDesat);
    color.rgb *= tileDarken;
    return float4(color.rgb, tileAlpha);
}

// MARK: - Billboard Shaders (Person + Phone)

struct BillboardVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct BillboardOut {
    float4 position [[position]];
    float2 uv;
};

vertex BillboardOut billboard_vertex(
    BillboardVertexIn in [[stage_in]],
    constant GlobeUniforms &u [[buffer(1)]],
    constant float4 &billboardParams [[buffer(2)]]
) {
    // Transform anchor into rotated world space
    float3 rotatedAnchor = (u.model * float4(u.anchorWorldPos, 1.0)).xyz;
    float3 normal = normalize(rotatedAnchor);

    // Build tangent frame in rotated world space
    float3 worldUp = float3(0, 1, 0);
    if (abs(normal.y) > 0.99) worldUp = float3(1, 0, 0);
    float3 tangentX = normalize(cross(worldUp, normal));
    float3 tangentY = normalize(cross(normal, tangentX));

    // Position the quad on the rotated surface
    float3 center = rotatedAnchor + normal * billboardParams.z;
    float3 worldPos = center
        + tangentX * (in.position.x * billboardParams.x)
        + tangentY * (in.position.y * billboardParams.y);

    // For a pure rotation matrix, inverse = transpose
    float4x4 modelInv = transpose(u.model);
    float4x4 vp = u.mvp * modelInv;

    BillboardOut out;
    out.position = vp * float4(worldPos, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 person_fragment(
    BillboardOut in [[stage_in]],
    constant GlobeUniforms &u [[buffer(0)]],
    texture2d<float> tex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float4 color = tex.sample(s, in.uv);
    if (color.a < 0.01) discard_fragment();
    color.a *= u.personAlpha;
    color.rgb *= u.personAlpha;
    return color;
}

fragment float4 phone_fragment(
    BillboardOut in [[stage_in]],
    constant GlobeUniforms &u [[buffer(0)]],
    texture2d<float> tex [[texture(0)]],
    sampler s [[sampler(0)]]
) {
    float4 color = tex.sample(s, in.uv);
    color.a *= u.phoneAlpha;
    return color;
}
