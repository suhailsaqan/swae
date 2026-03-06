//
//  LocationTileProvider.swift
//  swae
//
//  Resolves the user's GPS location and fetches multi-resolution satellite
//  tiles via MKMapSnapshotter. Falls back to bundled Manhattan assets
//  when location is unavailable.
//
//  Always calls completion exactly once, on the main thread.
//

import CoreLocation
import MapKit
import Metal
import UIKit

/// A single resolved tile at a specific zoom level.
struct ResolvedTileLevel {
    let level: Int
    let coverageMeters: Double
    let image: CGImage
}

final class LocationTileProvider: NSObject {

    struct Result {
        let latitude: Float
        let longitude: Float
        let tiles: [ResolvedTileLevel]   // may be fewer than 5 if some failed
        let isDynamic: Bool
    }

    private let device: MTLDevice
    private let config: GlobeZoomConfig
    private let locationManager = CLLocationManager()
    private var completion: ((Result) -> Void)?

    private var locationTimer: Timer?
    private var globalTimer: Timer?
    private var hasCompleted = false

    init(device: MTLDevice, config: GlobeZoomConfig) {
        self.device = device
        self.config = config
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Start the resolve process. Completion called exactly once on main thread.
    func resolve(completion: @escaping (Result) -> Void) {
        self.completion = completion

        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            startLocationTimer()
        case .denied, .restricted:
            finishWithFallback()
        @unknown default:
            finishWithFallback()
        }
    }

    private func requestLocation() {
        startLocationTimer()
        locationManager.requestLocation()
    }

    // MARK: - Multi-Resolution Tile Fetch

    // Legacy fallback tile levels (kept for compilation — not used in V10 tile pyramid)
    private struct LegacyTileLevel {
        let coverageMeters: Double
        let angularRadiusLat: Float
        let angularRadiusLon: Float
        let textureSize: CGSize
        let subdivisions: Int
    }
    private static let legacyLevels: [LegacyTileLevel] = [
        LegacyTileLevel(coverageMeters: 200,   angularRadiusLat: 0.003, angularRadiusLon: 0.004, textureSize: CGSize(width: 512, height: 512), subdivisions: 16),
        LegacyTileLevel(coverageMeters: 1000,  angularRadiusLat: 0.012, angularRadiusLon: 0.016, textureSize: CGSize(width: 512, height: 512), subdivisions: 16),
        LegacyTileLevel(coverageMeters: 5000,  angularRadiusLat: 0.05,  angularRadiusLon: 0.07,  textureSize: CGSize(width: 512, height: 512), subdivisions: 24),
        LegacyTileLevel(coverageMeters: 30000, angularRadiusLat: 0.20,  angularRadiusLon: 0.28,  textureSize: CGSize(width: 512, height: 512), subdivisions: 32),
        LegacyTileLevel(coverageMeters: 200000,angularRadiusLat: 0.80,  angularRadiusLon: 1.10,  textureSize: CGSize(width: 512, height: 512), subdivisions: 48),
    ]
    private static let legacyTileTimeout: TimeInterval = 12.0

    private func fetchAllTiles(at coordinate: CLLocationCoordinate2D) {
        let levels = Self.legacyLevels
        let group = DispatchGroup()
        var results = [Int: CGImage]()
        let lock = NSLock()

        startGlobalTimer()

        for (i, level) in levels.enumerated() {
            group.enter()

            let latLonRatio = Double(level.angularRadiusLat / level.angularRadiusLon)
            let lonMeters = level.coverageMeters
            let latMeters = level.coverageMeters * latLonRatio

            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: latMeters,
                longitudinalMeters: lonMeters
            )

            let options = MKMapSnapshotter.Options()
            options.region = region
            options.size = level.textureSize
            options.mapType = .satellite

            let snapshotter = MKMapSnapshotter(options: options)
            snapshotter.start { snapshot, error in
                defer { group.leave() }
                guard let snapshot = snapshot else { return }

                let processed = self.desaturate(image: snapshot.image)
                lock.lock()
                results[i] = processed
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self, !self.hasCompleted else { return }
            self.globalTimer?.invalidate()

            var tiles: [ResolvedTileLevel] = []
            for (i, level) in levels.enumerated() {
                if let img = results[i] {
                    tiles.append(ResolvedTileLevel(
                        level: i,
                        coverageMeters: level.coverageMeters,
                        image: img
                    ))
                }
            }

            if tiles.isEmpty {
                self.finishWithFallback()
            } else {
                self.finishWithDynamic(
                    lat: Float(coordinate.latitude),
                    lon: Float(coordinate.longitude),
                    tiles: tiles
                )
            }
        }
    }

    // MARK: - CPU Desaturation

    private func desaturate(image: UIImage) -> CGImage {
        guard let cgImage = image.cgImage else { return image.cgImage! }
        let width = cgImage.width
        let height = cgImage.height

        let graySpace = CGColorSpaceCreateDeviceGray()
        guard let grayCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: graySpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return cgImage
        }
        grayCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let rgbaSpace = CGColorSpaceCreateDeviceRGB()
        guard let rgbaCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: rgbaSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let grayImage = grayCtx.makeImage() else {
            return cgImage
        }
        rgbaCtx.draw(grayImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Darken pixels to match dark globe aesthetic
        if let data = rgbaCtx.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
            let darken: Float = 0.7
            for i in stride(from: 0, to: width * height * 4, by: 4) {
                pixels[i + 0] = UInt8(Float(pixels[i + 0]) * darken)
                pixels[i + 1] = UInt8(Float(pixels[i + 1]) * darken)
                pixels[i + 2] = UInt8(Float(pixels[i + 2]) * darken)
            }
        }

        return rgbaCtx.makeImage() ?? cgImage
    }

    // MARK: - Timers

    private func startLocationTimer() {
        locationTimer = Timer.scheduledTimer(
            withTimeInterval: config.locationTimeout, repeats: false
        ) { [weak self] _ in
            self?.locationManager.stopUpdatingLocation()
            self?.finishWithFallback()
        }
    }

    private func startGlobalTimer() {
        globalTimer = Timer.scheduledTimer(
            withTimeInterval: Self.legacyTileTimeout, repeats: false
        ) { [weak self] _ in
            self?.finishWithFallback()
        }
    }

    // MARK: - Completion

    private func finishWithDynamic(lat: Float, lon: Float, tiles: [ResolvedTileLevel]) {
        guard !hasCompleted else { return }
        hasCompleted = true
        locationTimer?.invalidate()
        globalTimer?.invalidate()
        completion?(Result(latitude: lat, longitude: lon, tiles: tiles, isDynamic: true))
    }

    private func finishWithFallback() {
        guard !hasCompleted else { return }
        hasCompleted = true
        locationTimer?.invalidate()
        globalTimer?.invalidate()
        completion?(Result(
            latitude: config.defaultAnchorLat,
            longitude: config.defaultAnchorLon,
            tiles: [],
            isDynamic: false
        ))
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTileProvider: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasCompleted, let location = locations.last else { return }
        locationTimer?.invalidate()
        fetchAllTiles(at: location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishWithFallback()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocation()
        case .denied, .restricted:
            finishWithFallback()
        case .notDetermined:
            break
        @unknown default:
            finishWithFallback()
        }
    }
}
