//
//  GlobeMath.swift
//  swae
//
//  Matrix math, coordinate conversions, and helper functions
//  for the globe zoom-out animation.
//

import simd

// MARK: - Matrix Builders

/// Right-handed perspective projection matrix.
func perspectiveMatrix(fovRadians: Float, aspect: Float, near: Float, far: Float) -> matrix_float4x4 {
    let y = 1.0 / tan(fovRadians * 0.5)
    let x = y / aspect
    let z = far / (near - far)
    return matrix_float4x4(columns: (
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, -1),
        SIMD4<Float>(0, 0, z * near, 0)
    ))
}

/// Right-handed look-at view matrix.
func lookAtMatrix(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let z = normalize(eye - target)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    let t = SIMD3<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye))
    return matrix_float4x4(columns: (
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(t.x, t.y, t.z, 1)
    ))
}

/// 4×4 rotation around the Y axis.
func rotationY(_ angle: Float) -> matrix_float4x4 {
    let c = cos(angle)
    let s = sin(angle)
    return matrix_float4x4(columns: (
        SIMD4<Float>( c, 0, s, 0),
        SIMD4<Float>( 0, 1, 0, 0),
        SIMD4<Float>(-s, 0, c, 0),
        SIMD4<Float>( 0, 0, 0, 1)
    ))
}

/// Extract the upper-left 3×3 from a 4×4 matrix (for normal matrix).
func upperLeft3x3(_ m: matrix_float4x4) -> matrix_float3x3 {
    return matrix_float3x3(columns: (
        SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
        SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
        SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
    ))
}

// MARK: - Coordinate Conversions

/// Convert latitude/longitude (degrees) to a Cartesian point on a sphere.
func latLonToCartesian(lat: Float, lon: Float, radius: Float) -> SIMD3<Float> {
    let latRad = lat * .pi / 180
    let lonRad = lon * .pi / 180
    return SIMD3<Float>(
        radius * cos(latRad) * cos(lonRad),
        radius * sin(latRad),
        radius * cos(latRad) * sin(lonRad)
    )
}

/// Compute a stable "up" vector for a camera looking down the surface normal.
/// Handles the pole degenerate case (|lat| > 85°).
func cameraUpVector(surfaceNormal: SIMD3<Float>, anchorLat: Float) -> SIMD3<Float> {
    let north: SIMD3<Float> = abs(anchorLat) > 85
        ? SIMD3<Float>(1, 0, 0)
        : SIMD3<Float>(0, 1, 0)
    let east = normalize(cross(north, surfaceNormal))
    return normalize(cross(surfaceNormal, east))
}

// MARK: - Interpolation Helpers

/// Hermite smoothstep: 0 at edge0, 1 at edge1, smooth in between.
func smoothstep(_ t: Float, edge0: Float, edge1: Float) -> Float {
    let x = max(0, min(1, (t - edge0) / (edge1 - edge0)))
    return x * x * (3 - 2 * x)
}
