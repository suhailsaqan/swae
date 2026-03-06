//
//  ShaderTypes.h
//  swae
//
//  Shared types between Metal shaders and Swift code for InfiniteZoomShaders.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// MARK: - Buffer Indices

typedef enum VertexInputIndex {
    VertexInputIndexVertices = 0,
    VertexInputIndexUniforms = 1,
    VertexInputIndexInstances = 2
} VertexInputIndex;

typedef enum TextureIndex {
    TextureIndexColor = 0
} TextureIndex;

// MARK: - Vertex Data

typedef struct {
    simd_float3 position;
    simd_float2 texCoord;
} Vertex;

// MARK: - Per-Frame Uniforms

typedef struct {
    simd_float4x4 viewProjectionMatrix;
    simd_float3 cameraPosition;
    float fogDensity;
} Uniforms;

// MARK: - Per-Instance Data

typedef struct {
    simd_float4x4 modelMatrix;
    float opacity;
    simd_float4 tintColor;
} InstanceData;

#endif /* ShaderTypes_h */
