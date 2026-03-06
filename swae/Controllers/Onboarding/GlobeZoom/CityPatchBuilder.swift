//
//  CityPatchBuilder.swift
//  swae
//
//  Builds a subdivided spherical cap mesh centered on a lat/lon anchor.
//  The patch sits on the globe surface and displays the satellite tile
//  texture, blending into the globe at its edges.
//

import Metal
import simd

struct CityPatchMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
}

enum CityPatchBuilder {

    /// Build a spherical cap mesh at the given lat/lon using separate angular radii
    /// for latitude and longitude. This allows rectangular patches that match the
    /// screen's aspect ratio (tall iPhone screens need more lat coverage than lon).
    static func build(
        device: MTLDevice,
        lat: Float,
        lon: Float,
        angularRadiusLon: Float,
        angularRadiusLat: Float,
        globeRadius: Float,
        subdivisions: Int
    ) -> CityPatchMesh {
        let latRad = lat * .pi / 180
        let lonRad = lon * .pi / 180

        var vertices: [GlobeVertex] = []
        vertices.reserveCapacity((subdivisions + 1) * (subdivisions + 1))

        var indices: [UInt32] = []
        indices.reserveCapacity(subdivisions * subdivisions * 6)

        for row in 0...subdivisions {
            let v = Float(row) / Float(subdivisions)
            let localV = (v - 0.5) * 2.0
            let dLat = localV * angularRadiusLat

            for col in 0...subdivisions {
                let u = Float(col) / Float(subdivisions)
                let localU = (u - 0.5) * 2.0
                let dLon = localU * angularRadiusLon / cos(latRad + dLat)

                let pLat = latRad + dLat
                let pLon = lonRad + dLon

                let pos = SIMD3<Float>(
                    cos(pLat) * cos(pLon),
                    sin(pLat),
                    cos(pLat) * sin(pLon)
                ) * globeRadius
                let normal = normalize(pos)

                vertices.append(GlobeVertex(
                    position: pos,
                    normal: normal,
                    uv: SIMD2<Float>(u, v)
                ))
            }
        }

        let cols = subdivisions + 1
        for row in 0..<subdivisions {
            for col in 0..<subdivisions {
                let tl = UInt32(row * cols + col)
                let tr = tl + 1
                let bl = UInt32((row + 1) * cols + col)
                let br = bl + 1
                indices.append(contentsOf: [tl, bl, tr])
                indices.append(contentsOf: [tr, bl, br])
            }
        }

        let vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<GlobeVertex>.stride * vertices.count,
            options: .storageModeShared
        )!
        vertexBuffer.label = "City Patch Vertices"

        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt32>.stride * indices.count,
            options: .storageModeShared
        )!
        indexBuffer.label = "City Patch Indices"

        return CityPatchMesh(
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            indexCount: indices.count
        )
    }

    /// Build a spherical cap mesh at the given lat/lon (legacy meters-based API).
    static func build(
        device: MTLDevice,
        lat: Float,
        lon: Float,
        radiusMeters: Float,
        globeRadius: Float,
        subdivisions: Int,
        heightmapData: [UInt8]? = nil,
        heightmapWidth: Int = 0,
        heightmapHeight: Int = 0,
        maxHeightMeters: Float = 300
    ) -> CityPatchMesh {
        let earthRadiusMeters: Float = 6_371_000
        let angularRadius = radiusMeters / earthRadiusMeters
        return build(
            device: device,
            lat: lat,
            lon: lon,
            angularRadiusLon: angularRadius,
            angularRadiusLat: angularRadius,
            globeRadius: globeRadius,
            subdivisions: subdivisions
        )
    }
}
