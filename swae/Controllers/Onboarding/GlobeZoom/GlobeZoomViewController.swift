//
//  GlobeZoomViewController.swift
//  swae
//
//  Hosts the Metal globe zoom-out animation.
//  Tile pyramid: fetches real map tiles for seamless street → globe zoom.
//

import MetalKit
import UIKit

protocol GlobeZoomViewControllerDelegate: AnyObject {
    func globeZoomDidComplete()
    func globeZoomDidSkip()
}

final class GlobeZoomViewController: UIViewController {

    weak var delegate: GlobeZoomViewControllerDelegate?

    private var metalView: MTKView!
    private var renderer: GlobeRenderer!
    private var animationController: GlobeAnimationController!
    private var tileManager: GlobeTileManager?
    private var config = GlobeZoomConfig()

    private let skipButton = UIButton(type: .system)
    private var hasStartedAnimation = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        if UIAccessibility.isReduceMotionEnabled {
            delegate?.globeZoomDidComplete()
            return
        }

        setupMetalView()
        setupSkipButton()
        setupAnimationController()
        setupTileManager()
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Setup

    private func setupMetalView() {
        metalView = MTKView(frame: view.bounds)
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = config.preferredFPS
        view.addSubview(metalView)

        guard let r = GlobeRenderer(metalView: metalView, config: config) else {
            print("GlobeZoomViewController: Failed to create renderer")
            return
        }
        renderer = r

        metalView.isAccessibilityElement = true
        metalView.accessibilityLabel = "Animated globe zooming out from street level to Earth view"
        metalView.accessibilityTraits = .image
    }

    private func setupSkipButton() {
        skipButton.setTitle("Skip", for: .normal)
        skipButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        skipButton.setTitleColor(.white.withAlphaComponent(0.7), for: .normal)
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        view.addSubview(skipButton)

        skipButton.accessibilityLabel = "Skip animation"
        skipButton.accessibilityHint = "Skips the globe animation and goes to onboarding"

        NSLayoutConstraint.activate([
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func setupAnimationController() {
        animationController = GlobeAnimationController(config: config)

        animationController.onUpdate = { [weak self] state in
            self?.renderer?.currentState = state
        }

        animationController.onComplete = { [weak self] in
            self?.animationDidFinish()
        }
    }

    // MARK: - Tile Manager

    private func setupTileManager() {
        guard let device = renderer?.metalDevice else { return }

        let manager = GlobeTileManager(
            device: device,
            globeRadius: config.globeRadius,
            tileURLTemplate: config.tileURLTemplate,
            minZoom: config.tileMinZoom,
            maxZoom: config.tileMaxZoom
        )
        tileManager = manager
        renderer.tileManager = manager

        manager.resolveAndPrefetch(
            defaultLat: Double(config.defaultAnchorLat),
            defaultLon: Double(config.defaultAnchorLon),
            locationTimeout: config.locationTimeout,
            prefetchTimeout: config.tilePrefetchTimeout,
            altitudeStart: config.altitudeStart,
            fovStartDeg: config.fovStartDeg
        ) { [weak self] lat, lon, success in
            guard let self = self else { return }

            // Update config with resolved location
            self.config.resolveLocation(lat: Float(lat), lon: Float(lon))
            self.renderer.config = self.config

            if !manager.hasTiles {
                print("GlobeZoomViewController: No tiles loaded — globe-only fallback")
            }

            self.startAnimationIfReady()
        }
    }

    private func startAnimationIfReady() {
        guard !hasStartedAnimation else { return }
        hasStartedAnimation = true

        // Re-create animation controller with resolved config
        animationController = GlobeAnimationController(config: config)
        animationController.onUpdate = { [weak self] state in
            self?.renderer?.currentState = state
        }
        animationController.onComplete = { [weak self] in
            self?.animationDidFinish()
        }
        animationController.start()
    }

    // MARK: - Actions

    @objc private func skipTapped() {
        animationController?.cancel()
        delegate?.globeZoomDidSkip()
    }

    private func animationDidFinish() {
        delegate?.globeZoomDidComplete()
    }
}
