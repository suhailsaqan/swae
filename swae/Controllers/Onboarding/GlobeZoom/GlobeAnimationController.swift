//
//  GlobeAnimationController.swift
//  swae
//
//  CADisplayLink-driven animation controller for the globe zoom-out.
//  Computes all time-driven values: camera altitude, float zoom level,
//  tile layer alpha, visibility fades, easing curves.
//
//  V11: Geometric zoom formula — computes the correct zoom level based on
//  what the camera actually sees, so tiles fill the screen at every altitude.
//

import QuartzCore
import simd

final class GlobeAnimationController {

    let config: GlobeZoomConfig

    var onUpdate: ((AnimationState) -> Void)?
    var onComplete: (() -> Void)?

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    // MARK: - Animation State

    struct AnimationState {
        let altitude: Float
        let fovRadians: Float
        let cameraTargetBlend: Float

        /// Continuous zoom level (e.g. 8.6 = between zoom 8 and 9)
        let floatZoom: Float
        /// Alpha of the entire tile layer (1.0 = visible, 0.0 = only globe)
        let tileLayerAlpha: Float

        /// Tile desaturation: 0.0 = full color, 1.0 = grayscale
        let tileDesaturation: Float
        /// Tile darken factor: 1.0 = full brightness, 0.75 = darkened
        let tileDarkenFactor: Float

        let phoneAlpha: Float
        let personAlpha: Float
        let starAlpha: Float
        let globeRotationY: Float

        let rawProgress: Float
        let easedProgress: Float
    }

    // MARK: - Init

    init(config: GlobeZoomConfig) {
        self.config = config
    }

    deinit { cancel() }

    // MARK: - Control

    func start() {
        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(config.minimumFPS),
            maximum: Float(config.preferredFPS),
            preferred: Float(config.preferredFPS)
        )
        displayLink?.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - Tick

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = link.timestamp - startTime
        let raw = Float(min(elapsed / config.totalDuration, 1.0))
        let eased = threePhaseEasing(raw)

        // ── Altitude (logarithmic) ──
        let logStart = log(config.altitudeStart)
        let logEnd = log(config.altitudeEnd)
        let altitude = exp(logStart + (logEnd - logStart) * eased)

        // ── FOV ──
        let fovDeg = config.fovStartDeg + (config.fovEndDeg - config.fovStartDeg) * eased
        let fov = fovDeg * .pi / 180.0

        // ── Camera target blend ──
        let targetBlend = smoothstep(raw, edge0: config.cameraTargetBlendStart, edge1: config.cameraTargetBlendEnd)

        // ── Float zoom level (geometric — matches camera's actual field of view) ──
        // How many meters of Earth surface does the camera see vertically?
        let screenHeight = 2.0 * altitude * tan(fov / 2.0)
        let earthCircumference: Float = .pi * config.globeRadius * 2.0
        let metersPerGlobeUnit: Float = 40_075_000.0 / earthCircumference
        let screenHeightMeters = screenHeight * metersPerGlobeUnit
        // We want ~5 tiles to fill the screen vertically
        let tilesOnScreen: Float = 5.0
        let tileSize = screenHeightMeters / tilesOnScreen
        let rawZoom = log2(40_075_000.0 / tileSize)
        let floatZoom = max(Float(config.tileMinZoom),
                           min(Float(config.tileMaxZoom), rawZoom))

        // ── Tile layer alpha (fade out at globe level) ──
        let tileLayerAlpha: Float
        if floatZoom > config.tileLayerFadeStartZoom {
            tileLayerAlpha = 1.0
        } else if floatZoom < config.tileLayerFadeEndZoom {
            tileLayerAlpha = 0.0
        } else {
            tileLayerAlpha = (floatZoom - config.tileLayerFadeEndZoom) /
                (config.tileLayerFadeStartZoom - config.tileLayerFadeEndZoom)
        }

        // ── Tile visual treatment (bright at close zoom, dark/desaturated at far zoom) ──
        // Thresholds: zoom 12+ = full color, zoom 5- = fully desaturated
        let tileDesaturation: Float
        let tileDarkenFactor: Float
        if floatZoom > 12.0 {
            tileDesaturation = 0.0
            tileDarkenFactor = 1.0
        } else if floatZoom > 5.0 {
            let blend = (floatZoom - 5.0) / 7.0  // 1.0 at zoom 12, 0.0 at zoom 5
            tileDesaturation = (1.0 - blend) * 0.85
            tileDarkenFactor = 1.0 - (1.0 - blend) * 0.25
        } else {
            tileDesaturation = 0.85
            tileDarkenFactor = 0.75
        }

        // ── Phone alpha ──
        let phoneAlpha = 1.0 - smoothstep(raw, edge0: config.phoneFadeStart, edge1: config.phoneFadeEnd)

        // ── Person alpha ──
        let personAlpha = 1.0 - smoothstep(raw, edge0: config.personFadeStart, edge1: config.personFadeEnd)

        // ── Stars ──
        let starAlpha = smoothstep(raw, edge0: config.starsAppearStart, edge1: config.starsAppearEnd)

        // ── Globe rotation ──
        let rotationProgress = max(0, (raw - 0.30)) / 0.70
        let rotation = rotationProgress * rotationProgress * config.globeRotationSpeed

        let state = AnimationState(
            altitude: altitude,
            fovRadians: fov,
            cameraTargetBlend: targetBlend,
            floatZoom: floatZoom,
            tileLayerAlpha: tileLayerAlpha,
            tileDesaturation: tileDesaturation,
            tileDarkenFactor: tileDarkenFactor,
            phoneAlpha: phoneAlpha,
            personAlpha: personAlpha,
            starAlpha: starAlpha,
            globeRotationY: rotation,
            rawProgress: raw,
            easedProgress: eased
        )

        onUpdate?(state)

        if raw >= 1.0 {
            cancel()
            onComplete?()
        }
    }

    // MARK: - Easing

    private func threePhaseEasing(_ t: Float) -> Float {
        if t < 0.20 {
            let n = t / 0.20
            return 0.06 * (n * n)
        } else if t < 0.75 {
            let n = (t - 0.20) / 0.55
            return 0.06 + 0.82 * n
        } else {
            let n = (t - 0.75) / 0.25
            return 0.88 + 0.12 * (1.0 - (1.0 - n) * (1.0 - n))
        }
    }
}
