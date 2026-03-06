//
//  GlobeZoomConfig.swift
//  swae
//
//  Configuration for the Co-Star style globe zoom-out animation.
//  Every tunable knob lives here — no magic numbers in other files.
//

import CoreGraphics
import Foundation

struct GlobeZoomConfig {
    // ── Timing ──
    var totalDuration: CFTimeInterval = 7.5
    var uiTransitionDuration: CFTimeInterval = 1.5

    // ── Camera ──
    var altitudeStart: Float = 0.0002
    var altitudeEnd: Float = 4.0
    var fovStartDeg: Float = 55
    var fovEndDeg: Float = 45
    var cameraTargetBlendStart: Float = 0.55
    var cameraTargetBlendEnd: Float = 0.80

    // ── Anchor (defaults — used when GPS unavailable) ──
    var defaultAnchorLat: Float = 40.7580
    var defaultAnchorLon: Float = -73.9855

    // ── Anchor (resolved at runtime) ──
    var resolvedAnchorLat: Float = 40.7580
    var resolvedAnchorLon: Float = -73.9855

    // ── Location ──
    var locationTimeout: TimeInterval = 3.0

    // ── Globe ──
    var globeRadius: Float = 0.5
    var globeLatSegments: Int = 64
    var globeLonSegments: Int = 128
    var globeRotationSpeed: Float = 0.15

    // ── Tile Pyramid ──
    var tileURLTemplate: String = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
    var tileMinZoom: Int = 3
    var tileMaxZoom: Int = 17
    var tilePrefetchTimeout: TimeInterval = 30.0

    // ── Tile-to-Globe Transition ──
    var tileLayerFadeStartZoom: Float = 4.0
    var tileLayerFadeEndZoom: Float = 3.0

    // ── Person ──
    var personModelHeight: Float = 0.0012
    var personFadeStart: Float = 0.02
    var personFadeEnd: Float = 0.08

    // ── Phone ──
    var phoneFadeStart: Float = 0.01
    var phoneFadeEnd: Float = 0.05
    var phoneSnapshotMaxDim: Int = 1024

    // ── Stars ──
    var starCount: Int = 2000
    var starsAppearStart: Float = 0.55
    var starsAppearEnd: Float = 0.75

    // ── Visual ──
    var desaturationStrength: Float = 0.85
    var darkenFactor: Float = 0.75
    var nightLightsIntensity: Float = 0.25
    var ambientLightIntensity: Float = 0.25

    // ── Performance ──
    var preferredFPS: Int = 120
    var minimumFPS: Int = 60

    // ── LOD ──
    var reducedGlobeSegments: Int = 48
    var reducedStarCount: Int = 800

    // ── Convenience ──
    mutating func resolveLocation(lat: Float, lon: Float) {
        resolvedAnchorLat = lat
        resolvedAnchorLon = lon
    }

    mutating func resolveToDefault() {
        resolvedAnchorLat = defaultAnchorLat
        resolvedAnchorLon = defaultAnchorLon
    }
}
