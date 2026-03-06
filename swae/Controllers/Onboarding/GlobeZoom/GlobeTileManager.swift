//
//  GlobeTileManager.swift
//  swae
//
//  Manages the tile pyramid for the globe zoom-out animation.
//  Handles GPS resolution, tile coordinate math, async fetching,
//  Metal texture upload, and per-frame draw lists.
//
//  V12: Prefetch ALL zoom levels before starting animation.
//  Increased grid padding at high zoom for full screen coverage.
//  Raw tile upload (shader handles desaturation).
//

import CoreLocation
import Metal
import UIKit

// MARK: - Types

/// Identifies a single map tile.
struct TileKey: Hashable {
    let x: Int
    let y: Int
    let zoom: Int
}

/// A loaded tile ready for rendering.
struct LoadedTile {
    let key: TileKey
    let texture: MTLTexture
    let mesh: TileMesh
}

/// What the renderer needs each frame.
struct TileDrawList {
    let baseTiles: [LoadedTile]      // floor(floatZoom) — full coverage
    let detailTiles: [LoadedTile]    // ceil(floatZoom) — fades in on top
    let blendFraction: Float         // 0 = all base, 1 = all detail
}

// MARK: - GlobeTileManager

final class GlobeTileManager: NSObject, CLLocationManagerDelegate {

    private let device: MTLDevice
    private let urlSession: URLSession
    private let globeRadius: Float
    private let tileURLTemplate: String
    private let maxZoom: Int
    private let minZoom: Int

    private var tileCache: [TileKey: LoadedTile] = [:]
    private var pendingFetches = Set<TileKey>()
    private(set) var anchorLat: Double = 0
    private(set) var anchorLon: Double = 0

    // GPS
    private var locationManager: CLLocationManager?
    private var locationTimer: Timer?
    private var resolveCompletion: ((Double, Double, Bool) -> Void)?
    private var hasResolved = false

    // MARK: - Init

    init(device: MTLDevice, globeRadius: Float,
         tileURLTemplate: String =
            "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
         minZoom: Int = 3, maxZoom: Int = 17) {
        self.device = device
        self.globeRadius = globeRadius
        self.tileURLTemplate = tileURLTemplate
        self.minZoom = minZoom
        self.maxZoom = maxZoom

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 12
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)

        super.init()
    }

    // MARK: - GPS + Prefetch

    func resolveAndPrefetch(
        defaultLat: Double, defaultLon: Double,
        locationTimeout: TimeInterval,
        prefetchTimeout: TimeInterval,
        altitudeStart: Float,
        fovStartDeg: Float,
        completion: @escaping (Double, Double, Bool) -> Void
    ) {
        resolveCompletion = { [weak self] lat, lon, _ in
            guard let self = self else { completion(defaultLat, defaultLon, false); return }
            self.prefetchTiles(lat: lat, lon: lon, timeout: prefetchTimeout,
                               altitudeStart: altitudeStart, fovStartDeg: fovStartDeg,
                               completion: completion)
        }

        let mgr = CLLocationManager()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager = mgr

        let status = mgr.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            startLocationRequest(timeout: locationTimeout, defaultLat: defaultLat, defaultLon: defaultLon)
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
            startLocationTimer(timeout: locationTimeout, defaultLat: defaultLat, defaultLon: defaultLon)
        default:
            finishResolve(lat: defaultLat, lon: defaultLon)
        }
    }

    private func startLocationRequest(timeout: TimeInterval, defaultLat: Double, defaultLon: Double) {
        startLocationTimer(timeout: timeout, defaultLat: defaultLat, defaultLon: defaultLon)
        locationManager?.requestLocation()
    }

    private func startLocationTimer(timeout: TimeInterval, defaultLat: Double, defaultLon: Double) {
        locationTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.locationManager?.stopUpdatingLocation()
            self?.finishResolve(lat: defaultLat, lon: defaultLon)
        }
    }

    private func finishResolve(lat: Double, lon: Double) {
        guard !hasResolved else { return }
        hasResolved = true
        locationTimer?.invalidate()
        anchorLat = lat
        anchorLon = lon
        resolveCompletion?(lat, lon, true)
        resolveCompletion = nil
    }

    // CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        finishResolve(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            locationTimer?.fire()
        default: break
        }
    }

    // MARK: - Prefetch

    private func prefetchTiles(lat: Double, lon: Double, timeout: TimeInterval,
                               altitudeStart: Float, fovStartDeg: Float,
                               completion: @escaping (Double, Double, Bool) -> Void) {
        anchorLat = lat
        anchorLon = lon

        // Compute the zoom level the animation starts at using the geometric formula
        let fovRad = fovStartDeg * .pi / 180.0
        let screenH = 2.0 * altitudeStart * tan(fovRad / 2.0)
        let metersPerUnit: Float = 40_075_000.0 / (.pi * globeRadius * 2.0)
        let tileSize = screenH * metersPerUnit / 5.0
        let startZoom = min(maxZoom, max(minZoom, Int(ceil(log2(40_075_000.0 / tileSize)))))

        // Block on ALL zoom levels from startZoom down to minZoom.
        // User accepts startup time cost for a flawless animation.
        var keys: [TileKey] = []
        for zoom in stride(from: startZoom, through: minZoom, by: -1) {
            keys.append(contentsOf: visibleTiles(zoom: zoom))
        }

        let group = DispatchGroup()
        for key in keys {
            group.enter()
            fetchTile(key: key) { _ in group.leave() }
        }

        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global(qos: .userInitiated).async {
            let result = group.wait(timeout: deadline)
            DispatchQueue.main.async {
                completion(lat, lon, result == .success)
            }
        }
    }

    // MARK: - Tile Coordinate Math

    func tileXY(lat: Double, lon: Double, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))
        let x = Int((lon + 180.0) / 360.0 * n)
        let latRad = lat * .pi / 180.0
        let y = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)
        let maxTile = Int(n) - 1
        return (min(max(x, 0), maxTile), min(max(y, 0), maxTile))
    }

    func tileBounds(x: Int, y: Int, zoom: Int) -> TileBounds {
        let n = pow(2.0, Double(zoom))
        return TileBounds(
            lonW: Double(x) / n * 360.0 - 180.0,
            lonE: Double(x + 1) / n * 360.0 - 180.0,
            latN: atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n))) * 180.0 / .pi,
            latS: atan(sinh(.pi * (1.0 - 2.0 * Double(y + 1) / n))) * 180.0 / .pi
        )
    }

    /// Grid padding varies by zoom level.
    /// High zoom = small tiles, need more padding to fill screen.
    /// Low zoom = large tiles, less padding needed.
    private func gridPadding(forZoom zoom: Int) -> Int {
        switch zoom {
        case 15...17: return 5   // 11×11 = 121 tiles
        case 12...14: return 4   // 9×9 = 81 tiles
        case 9...11:  return 3   // 7×7 = 49 tiles
        default:      return 3   // 7×7 = 49 tiles
        }
    }

    func visibleTiles(zoom: Int) -> [TileKey] {
        let padding = gridPadding(forZoom: zoom)
        let (cx, cy) = tileXY(lat: anchorLat, lon: anchorLon, zoom: zoom)
        let n = Int(pow(2.0, Double(zoom)))
        var seen = Set<TileKey>()
        var keys: [TileKey] = []
        for dy in -padding...padding {
            for dx in -padding...padding {
                let tx = ((cx + dx) % n + n) % n
                let ty = cy + dy
                guard ty >= 0, ty < n else { continue }
                let key = TileKey(x: tx, y: ty, zoom: zoom)
                if seen.insert(key).inserted { keys.append(key) }
            }
        }
        return keys
    }

    // MARK: - Tile Fetching

    private func fetchTile(key: TileKey, completion: @escaping (LoadedTile?) -> Void) {
        if let cached = tileCache[key] { completion(cached); return }
        guard !pendingFetches.contains(key) else { completion(nil); return }
        pendingFetches.insert(key)

        let urlString = tileURLTemplate
            .replacingOccurrences(of: "{z}", with: "\(key.zoom)")
            .replacingOccurrences(of: "{x}", with: "\(key.x)")
            .replacingOccurrences(of: "{y}", with: "\(key.y)")
        guard let url = URL(string: urlString) else {
            pendingFetches.remove(key)
            completion(nil)
            return
        }

        urlSession.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else {
                DispatchQueue.main.async {
                    self?.pendingFetches.remove(key)
                    completion(nil)
                }
                return
            }
            DispatchQueue.main.async {
                self.pendingFetches.remove(key)
                guard let texture = self.uploadToTexture(cgImage,
                    label: "tile_\(key.zoom)_\(key.x)_\(key.y)") else {
                    completion(nil); return
                }
                let bounds = self.tileBounds(x: key.x, y: key.y, zoom: key.zoom)
                let mesh = TileMeshBuilder.build(
                    device: self.device, bounds: bounds,
                    globeRadius: self.globeRadius,
                    subdivisions: self.meshSubdivisions(forZoom: key.zoom))
                let loaded = LoadedTile(key: key, texture: texture, mesh: mesh)
                self.tileCache[key] = loaded
                completion(loaded)
            }
        }.resume()
    }

    private func meshSubdivisions(forZoom zoom: Int) -> Int {
        switch zoom {
        case 15...17: return 4
        case 11...14: return 8
        case 7...10:  return 16
        default:      return 24
        }
    }

    // MARK: - Per-Frame Draw List

    func drawList(floatZoom: Float) -> TileDrawList {
        let zoom = max(minZoom, min(maxZoom, Int(round(floatZoom))))
        let tiles = visibleTiles(zoom: zoom).compactMap { tileCache[$0] }
        return TileDrawList(baseTiles: tiles, detailTiles: [], blendFraction: 0)
    }

    // MARK: - Memory

    func evictDistantZoomLevels(currentZoom: Int, keepRange: Int = 3) {
        let remove = tileCache.keys.filter { abs($0.zoom - currentZoom) > keepRange }
        for key in remove { tileCache.removeValue(forKey: key) }
    }

    var hasTiles: Bool { !tileCache.isEmpty }

    // MARK: - Texture Upload

    private func uploadToTexture(_ cgImage: CGImage, label: String) -> MTLTexture? {
        let w = cgImage.width, h = cgImage.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.label = label
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                    withBytes: data, bytesPerRow: w * 4)
        return tex
    }
}
