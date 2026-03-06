//
//  GrainGradientShaders.metal
//  swae
//
//  Adapted from GrainGradient.metal for UIKit CAMetalLayer rendering
//

#include <metal_stdlib>
using namespace metal;

// Uniforms passed from CPU
struct GrainGradientUniforms {
    float time;
    int gridSize;
    int colorCount;
    float4 bounds; // x, y, width, height
    float grainStrength;
};

// Vertex output / Fragment input
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Hermite interpolation functions
float h00(float x) { return 2.0 * x * x * x - 3.0 * x * x + 1.0; }
float h10(float x) { return x * x * x - 2.0 * x * x + x; }
float h01(float x) { return 3.0 * x * x - 2.0 * x * x * x; }
float h11(float x) { return x * x * x - x * x; }

float hermite(float p0, float p1, float m0, float m1, float x) {
    return p0 * h00(x) + m0 * h10(x) + p1 * h01(x) + m1 * h11(x);
}

int getIndex(int x, int y, int2 gridSize, int lastIndex) {
    return clamp(y * gridSize.x + x, 0, lastIndex);
}

int4 getIndices(float2 gridCoords, int2 gridSize, int lastIndex) {
    int2 idStart = int2(gridCoords);
    int2 idEnd = int2(ceil(gridCoords));

    int4 id = int4(getIndex(idStart.x, idStart.y, gridSize, lastIndex),
                   getIndex(idEnd.x,   idStart.y, gridSize, lastIndex),
                   getIndex(idStart.x, idEnd.y, gridSize, lastIndex),
                   getIndex(idEnd.x,   idEnd.y, gridSize, lastIndex));
    return id;
}

float4 gridInterpolation(float2 coords, 
                         constant float4 *colors, 
                         float4 gridRange, 
                         int2 gridSize, 
                         int lastIndex, 
                         float time) {
    
    float a = sin(time * 1.0) * 0.5 + 0.5;
    float b = sin(time * 1.5) * 0.5 + 0.5;
    float c = sin(time * 2.0) * 0.5 + 0.5;
    float d = sin(time * 2.5) * 0.5 + 0.5;

    float y0 = mix(a, b, coords.x);
    float y1 = mix(c, d, coords.x);
    float x0 = mix(a, c, coords.y);
    float x1 = mix(b, d, coords.y);

    coords.x = hermite(0.0, 1.0, 2.0 * x0, 2.0 * x1, coords.x);
    coords.y = hermite(0.0, 1.0, 2.0 * y0, 2.0 * y1, coords.y);

    float2 gridCoords = coords * gridRange.zw;
    int4 id = getIndices(gridCoords, gridSize, lastIndex);

    float2 factors = smoothstep(float2(0.0), float2(1.0), fract(gridCoords));

    float4 result[2];
    result[0] = mix(colors[id.x], colors[id.y], factors.x);
    result[1] = mix(colors[id.z], colors[id.w], factors.x);

    return mix(result[0], result[1], factors.y);
}

// Vertex shader - generates a full-screen quad
vertex VertexOut grainGradientVertex(uint vertexID [[vertex_id]]) {
    // Full-screen quad vertices
    const float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0)
    };
    
    const float2 texCoords[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };
    
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// Fragment shader - renders the grain gradient
fragment float4 grainGradientFragment(VertexOut in [[stage_in]],
                                      constant GrainGradientUniforms &uniforms [[buffer(0)]],
                                      constant float4 *colors [[buffer(1)]]) {
    
    const int2 gridSize = int2(uniforms.gridSize);
    const int4 gridRange = int4(0, 0, gridSize.x - 1, gridSize.y - 1);
    const int gridLastIndex = uniforms.colorCount - 1;
    
    float2 coords = in.texCoord;
    float4 result = gridInterpolation(coords, colors, float4(gridRange), gridSize, gridLastIndex, uniforms.time * 0.20);
    
    // Add very subtle grain noise for texture (much reduced)
    float x = (coords.x + 4.0) * (coords.y + 4.0) * 10.0;
    float grainValue = fmod((fmod(x, 13.0) + 1.0) * (fmod(x, 123.0) + 1.0), 0.01) - 0.005;
    
    // Apply grain very subtly - barely noticeable, just adds slight texture
    float4 grain = float4(grainValue) * uniforms.grainStrength * 0.15; // Reduced to 15% of original
    
    result = result + grain;
    
    return result;
}
