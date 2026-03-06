//
//  TileMeshBuilder.swift
//  swae
//
//  Builds small spherical quad meshes for individual map tiles.
//  Each mesh's vertices are placed at the tile's exact lat/lon bounds
//  on the globe surface. The texture maps 1:1 — no stretching possible.
//
//  V12: Uses Mercator-projected UV interpolation so that the mesh's UV
//  coordinates match the tile image's Mercator projection. Without this,
//  tiles show visible seams because linear latitude interpolation doesn't
//  match the non-linear Mercator pixel layout.
//  All math done in Double precision to eliminate Float rounding seams.
//

import Metal
import simd

/// Geographic bounds of a single map tile (degrees).
struct TileBounds {
    let lonW: Double
    let lonE: Double
    let latN: Double
    let latS: Double
}

/// A renderable tile mesh (vertex + index buffers).
struct TileMesh {
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
}

enum TileMeshBuilder {

    /// Convert latitude (degrees) to Mercator Y value.
    private static func mercatorY(_ latDeg: Double) -> Double {
        let latRad = latDeg * .pi / 180.0
        return log(tan(.pi / 4.0 + latRad / 2.0))
    }

    /// Convert Mercator Y value back to latitude (degrees).
    private static func inverseMercatorY(_ y: Double) -> Double {
        return (2.0 * atan(exp(y)) - .pi / 2.0) * 180.0 / .pi
    }

    /// Build a spherical quad mesh for a single map tile.
    /// Vertices are placed at Mercator-interpolated latitudes so that
    /// the UV mapping matches the tile image's Mercator projection exactly.
    static func build(
        device: MTLDevice,
        bounds: TileBounds,
        globeRadius: Float,
        subdivisions: Int
    ) -> TileMesh {
        let cols = subdivisions + 1
        let r = Double(globeRadius)
        var vertices: [GlobeVertex] = []
        vertices.reserveCapacity(cols * cols)
        var indices: [UInt32] = []
        indices.reserveCapacity(subdivisions * subdivisions * 6)

        // Mercator Y at tile north and south edges
        let mercN = mercatorY(bounds.latN)
        let mercS = mercatorY(bounds.latS)

        for row in 0...subdivisions {
            let v = Double(row) / Double(subdivisions)
            // Interpolate in Mercator Y space (matches tile image projection)
            let mercY = mercN + (mercS - mercN) * v
            let lat = inverseMercatorY(mercY)
            let latRad = lat * .pi / 180.0
            let cosLat = cos(latRad)
            let sinLat = sin(latRad)

            for col in 0...subdivisions {
                let u = Double(col) / Double(subdivisions)
                let lon = bounds.lonW + (bounds.lonE - bounds.lonW) * u
                let lonRad = lon * .pi / 180.0

                let px = cosLat * cos(lonRad) * r
                let py = sinLat * r
                let pz = cosLat * sin(lonRad) * r
                let pos = SIMD3<Float>(Float(px), Float(py), Float(pz))
                let normal = normalize(pos)

                // V flipped to match CGContext's bottom-left origin
                vertices.append(GlobeVertex(
                    position: pos,
                    normal: normal,
                    uv: SIMD2<Float>(Float(u), 1.0 - Float(v))
                ))
            }
        }

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

        let vb = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<GlobeVertex>.stride * vertices.count,
            options: .storageModeShared
        )!
        vb.label = "Tile Mesh"
        let ib = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt32>.stride * indices.count,
            options: .storageModeShared
        )!
        ib.label = "Tile Indices"

        return TileMesh(vertexBuffer: vb, indexBuffer: ib, indexCount: indices.count)
    }
}
