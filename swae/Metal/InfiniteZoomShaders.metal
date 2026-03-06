//
//  Shaders.metal
//  InfiniteZoomGallery
//
//  High-performance Metal shaders for the infinite zoom gallery effect.
//  Optimized for 60-120 FPS rendering with instanced drawing.
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

// =============================================================================
// MARK: - Shader I/O Structures
// =============================================================================

// Vertex shader output / Fragment shader input
// Interpolated across the triangle by the rasterizer
struct VertexOut {
    // Position in clip space (required, used by rasterizer)
    float4 position [[position]];
    
    // Texture coordinates for sampling
    float2 texCoord;
    
    // World-space position for fog calculation
    float3 worldPosition;
    
    // Distance from camera (pre-computed for fog efficiency)
    float depth;
    
    // Per-instance data passed through
    float opacity;
    float4 tintColor;
};

// =============================================================================
// MARK: - Vertex Shader
// =============================================================================
// Transforms vertices from model space to clip space using instanced rendering.
// Each instance represents one section in the gallery.
//
// Performance notes:
// - Single draw call renders all sections via instancing
// - Matrix multiplication done on GPU (faster than CPU for many instances)
// - Depth pre-computed here to avoid per-pixel calculation in fragment shader

vertex VertexOut vertexMain(
    // Vertex attributes from vertex buffer
    const device Vertex* vertices [[buffer(VertexInputIndexVertices)]],
    
    // Per-frame uniforms (camera matrices, fog params)
    constant Uniforms& uniforms [[buffer(VertexInputIndexUniforms)]],
    
    // Per-instance data (model matrices, tints)
    const device InstanceData* instances [[buffer(VertexInputIndexInstances)]],
    
    // Built-in vertex ID within the draw call
    uint vertexID [[vertex_id]],
    
    // Built-in instance ID for instanced rendering
    uint instanceID [[instance_id]]
) {
    // Fetch vertex data
    Vertex vert = vertices[vertexID];
    InstanceData instance = instances[instanceID];
    
    // Transform to world space
    // Model matrix includes the z-offset for this section
    float4 worldPos = instance.modelMatrix * float4(vert.position, 1.0);
    
    // Transform to clip space
    // viewProjectionMatrix = projection * view (pre-multiplied on CPU)
    float4 clipPos = uniforms.viewProjectionMatrix * worldPos;
    
    // Calculate depth for fog
    // Using distance from camera position for more accurate fog
    float depth = length(worldPos.xyz - uniforms.cameraPosition);
    
    // Build output
    VertexOut out;
    out.position = clipPos;
    out.texCoord = vert.texCoord;
    out.worldPosition = worldPos.xyz;
    out.depth = depth;
    out.opacity = instance.opacity;
    out.tintColor = instance.tintColor;
    
    return out;
}

// =============================================================================
// MARK: - Fragment Shader
// =============================================================================
// Samples texture, applies fog, and outputs final color.
//
// Performance notes:
// - Texture sampling with trilinear filtering (mipmaps)
// - Exponential fog is cheaper than linear (one exp vs. division)
// - Vignette computed from UV (no extra texture fetch)

fragment float4 fragmentMain(
    // Interpolated vertex output
    VertexOut in [[stage_in]],
    
    // Per-frame uniforms for fog parameters
    constant Uniforms& uniforms [[buffer(VertexInputIndexUniforms)]],
    
    // Section texture with sampler
    texture2d<float> colorTexture [[texture(TextureIndexColor)]],
    sampler textureSampler [[sampler(0)]]
) {
    // ==========================================================================
    // Texture Sampling
    // ==========================================================================
    // Sample with automatic mipmap selection based on screen-space derivatives
    float4 texColor = colorTexture.sample(textureSampler, in.texCoord);
    
    // Apply instance tint color (multiplicative blend)
    texColor *= in.tintColor;
    
    // ==========================================================================
    // Exponential Fog
    // ==========================================================================
    // Fog formula: finalColor = mix(fogColor, objectColor, exp(-density * distance))
    // This creates a natural atmospheric depth effect
    //
    // fogDensity controls how quickly fog accumulates:
    // - 0.0001: Very light fog, visible at extreme distances
    // - 0.0005: Medium fog, good for gallery effect
    // - 0.001:  Heavy fog, objects fade quickly
    
    float3 fogColor = float3(0.02, 0.02, 0.03); // Dark blue-gray fog
    float fogFactor = exp(-uniforms.fogDensity * in.depth);
    
    // Clamp fog factor to prevent complete fade-out of nearby objects
    fogFactor = clamp(fogFactor, 0.0, 1.0);
    
    // Mix object color with fog
    float3 foggedColor = mix(fogColor, texColor.rgb, fogFactor);
    
    // ==========================================================================
    // Vignette Effect
    // ==========================================================================
    // Darkens edges of each section for a more cinematic look
    // Computed from UV coordinates (0,0 at corner, 0.5,0.5 at center)
    
    float2 uvCentered = in.texCoord - 0.5;
    float vignette = 1.0 - dot(uvCentered, uvCentered) * 0.5;
    vignette = clamp(vignette, 0.0, 1.0);
    
    // Apply vignette
    foggedColor *= vignette;
    
    // ==========================================================================
    // Final Output
    // ==========================================================================
    // Apply instance opacity for fade effects
    float finalAlpha = texColor.a * in.opacity * fogFactor;
    
    return float4(foggedColor, finalAlpha);
}

// =============================================================================
// MARK: - Gaussian Blur Compute Shader (Optional)
// =============================================================================
// Two-pass separable Gaussian blur for soft focus effect.
// Can be used for depth-of-field or bloom effects.
//
// Performance notes:
// - Separable blur: O(2n) vs O(n²) for direct convolution
// - Uses shared memory for kernel weights (constant across invocations)
// - Threadgroup size optimized for typical GPU architectures

// Blur kernel weights for 9-tap Gaussian (sigma ≈ 2.0)
// Pre-computed: sum = 1.0 for energy conservation
constant float blurWeights[9] = {
    0.0162162162, 0.0540540541, 0.1216216216, 0.1945945946,
    0.2270270270,  // Center weight
    0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162
};

// Horizontal blur pass
kernel void blurHorizontal(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float4 result = float4(0.0);
    int width = inputTexture.get_width();
    
    // 9-tap horizontal blur
    for (int i = -4; i <= 4; i++) {
        int sampleX = clamp(int(gid.x) + i, 0, width - 1);
        float4 sample = inputTexture.read(uint2(sampleX, gid.y));
        result += sample * blurWeights[i + 4];
    }
    
    outputTexture.write(result, gid);
}

// Vertical blur pass
kernel void blurVertical(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float4 result = float4(0.0);
    int height = inputTexture.get_height();
    
    // 9-tap vertical blur
    for (int i = -4; i <= 4; i++) {
        int sampleY = clamp(int(gid.y) + i, 0, height - 1);
        float4 sample = inputTexture.read(uint2(gid.x, sampleY));
        result += sample * blurWeights[i + 4];
    }
    
    outputTexture.write(result, gid);
}
