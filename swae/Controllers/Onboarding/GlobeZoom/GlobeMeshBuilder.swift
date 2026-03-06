//
//  GlobeMeshBuilder.swift
//  swae
//
//  Generates a procedural UV sphere mesh for the globe.
//

import Metal
import simd

struct GlobeMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
    let vertexDescriptor: MTLVertexDescriptor
}

struct GlobeVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
}

enum GlobeMeshBuilder {

    /// Build a UV sphere centered at origin.
    /// - Parameters:
    ///   - device: Metal device
    ///   - radius: Sphere radius (0.5 for our globe)
    ///   - latSegments: Number of latitude rings
    ///   - lonSegments: Number of longitude slices
    static func build(
        device: MTLDevice,
        radius: Float,
        latSegments: Int,
        lonSegments: Int
    ) -> GlobeMesh {
        var vertices: [GlobeVertex] = []
        vertices.reserveCapacity((latSegments + 1) * (lonSegments + 1))

        var indices: [UInt32] = []
        indices.reserveCapacity(latSegments * lonSegments * 6)

        // Generate vertices
        for lat in 0...latSegments {
            let theta = Float(lat) * .pi / Float(latSegments) // 0 (north pole) → π (south pole)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for lon in 0...lonSegments {
                let phi = Float(lon) * 2.0 * .pi / Float(lonSegments) // 0 → 2π
                let sinPhi = sin(phi)
                let cosPhi = cos(phi)

                let x = cosPhi * sinTheta
                let y = cosTheta
                let z = sinPhi * sinTheta

                let position = SIMD3<Float>(x, y, z) * radius
                let normal = SIMD3<Float>(x, y, z) // unit sphere normal
                let u = Float(lon) / Float(lonSegments)
                let v = Float(lat) / Float(latSegments)

                vertices.append(GlobeVertex(position: position, normal: normal, uv: SIMD2<Float>(u, v)))
            }
        }

        // Generate indices (two triangles per quad)
        for lat in 0..<latSegments {
            for lon in 0..<lonSegments {
                let topLeft = UInt32(lat * (lonSegments + 1) + lon)
                let topRight = topLeft + 1
                let bottomLeft = UInt32((lat + 1) * (lonSegments + 1) + lon)
                let bottomRight = bottomLeft + 1

                indices.append(contentsOf: [topLeft, bottomLeft, topRight])
                indices.append(contentsOf: [topRight, bottomLeft, bottomRight])
            }
        }

        let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<GlobeVertex>.stride * vertices.count,
            options: .storageModeShared
        )!
        vertexBuffer.label = "Globe Vertices"

        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt32>.stride * indices.count,
            options: .storageModeShared
        )!
        indexBuffer.label = "Globe Indices"

        // Vertex descriptor matching GlobeVertex layout and VertexIn in the shader
        let descriptor = MTLVertexDescriptor()
        let stride = MemoryLayout<GlobeVertex>.stride

        // position: float3 at offset 0
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0

        // normal: float3 at offset 12
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0

        // uv: float2 at offset 24
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        descriptor.attributes[2].bufferIndex = 0

        descriptor.layouts[0].stride = stride
        descriptor.layouts[0].stepFunction = .perVertex

        return GlobeMesh(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            vertexDescriptor: descriptor
        )
    }
}
