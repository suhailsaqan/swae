//
//  ParticleRingButton.swift
//  swae
//
//  Particle ring button for camera tab
//

import SwiftUI
import UIKit

// Button that contains particle ring and forwards touches to particles
class CameraButtonWithParticles: UIButton {
    private let particleView: ParticleRingButtonView
    
    init(frame: CGRect = .zero, config: ParticleConfig = .ringButton) {
        particleView = ParticleRingButtonView(size: 150, config: config)
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        particleView = ParticleRingButtonView(size: 150, config: .ringButton)
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        
        particleView.translatesAutoresizingMaskIntoConstraints = false
        particleView.isUserInteractionEnabled = false
        particleView.clipsToBounds = false  // Allow particles to be visible outside bounds
        addSubview(particleView)
        
        NSLayoutConstraint.activate([
            particleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            particleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            particleView.widthAnchor.constraint(equalToConstant: 150),
            particleView.heightAnchor.constraint(equalToConstant: 150)
        ])
    }
    
    // Forward touches to particle view for disruption effect
    // Don't call super to avoid potential crashes
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Forward to particles for visual effect
        particleView.touchesBegan(touches, with: event)
        
        // Let the button handle the touch normally
        sendActions(for: .touchDown)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        particleView.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        particleView.touchesEnded(touches, with: event)
        
        // Check if touch is still inside button bounds
        if let touch = touches.first {
            let location = touch.location(in: self)
            if bounds.contains(location) {
                sendActions(for: .touchUpInside)
            } else {
                sendActions(for: .touchUpOutside)
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        particleView.touchesCancelled(touches, with: event)
        sendActions(for: .touchCancel)
    }
}

class ParticleRingButtonView: UIView {
    private var metalView: ParticleMetalView?
    private let size: CGFloat
    private var displayLink: CADisplayLink?
    private var rotationAngle: Float = 0
    private let rotationSpeed: Float = 1.0 // Radians per second
    private var config: ParticleConfig
    
    init(size: CGFloat = 40, config: ParticleConfig = .ringButton) {
        self.size = size
        self.config = config
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        setupParticles()
        startRotation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopRotation()
    }
    
    private func setupParticles() {
        backgroundColor = .clear
        clipsToBounds = false  // Allow particles to be visible outside bounds
        
        // Create metal view with config and startScattered = false for immediate ring formation
        let metalView = ParticleMetalView(frame: bounds, device: MTLCreateSystemDefaultDevice(), config: config, startScattered: false)
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.isUserInteractionEnabled = false // Don't block button taps
        metalView.clipsToBounds = false  // Allow particles to be visible outside bounds
        addSubview(metalView)
        self.metalView = metalView
        
        // Configure particles after a brief delay to ensure Metal is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.configureParticles()
        }
    }
    
    // Handle touches on the view to disrupt particles
    // No super calls to avoid crashes
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let metalView = metalView else { return }
        let location = touch.location(in: metalView)
        
        // Convert touch location to clip space [-1, 1]
        let x = (location.x / metalView.bounds.width) * 2.0 - 1.0
        let y = 1.0 - (location.y / metalView.bounds.height) * 2.0
        
        // Update touch in renderer
        metalView.renderer?.touchPoint = SIMD2<Float>(Float(x), Float(y))
        metalView.renderer?.isTouching = true
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let metalView = metalView else { return }
        let location = touch.location(in: metalView)
        
        // Convert touch location to clip space [-1, 1]
        let x = (location.x / metalView.bounds.width) * 2.0 - 1.0
        let y = 1.0 - (location.y / metalView.bounds.height) * 2.0
        
        // Update touch in renderer
        metalView.renderer?.touchPoint = SIMD2<Float>(Float(x), Float(y))
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        metalView?.renderer?.isTouching = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        metalView?.renderer?.isTouching = false
    }
    
    private func startRotation() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateRotation))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopRotation() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func updateRotation() {
        guard let displayLink = displayLink else { return }
        
        // Update rotation angle
        let deltaTime = Float(displayLink.targetTimestamp - displayLink.timestamp)
        rotationAngle += rotationSpeed * deltaTime
        
        // Keep angle in 0-2π range
        if rotationAngle > Float.pi * 2 {
            rotationAngle -= Float.pi * 2
        }
        
        // Update particle targets with rotation
        updateParticleTargets()
    }
    
    private func configureParticles() {
        guard let renderer = metalView?.renderer else { return }
        
        // Create a ring
        // Scale factor for the 150x150 canvas
        let scale: Float = 0.333
        let innerRadius: Float = 0.35 * scale  // Inner edge of ring
        let outerRadius: Float = 0.85 * scale  // Outer edge of ring (much thicker)
        
        let pattern = ParticlePattern.ring(innerRadius: innerRadius, outerRadius: outerRadius)
        renderer.transitionToPattern(pattern)
        
        // Set rainbow colors for each particle
        setRainbowColors()
        
        // Apply config values
        setParticleSize(config.particleSize)
        renderer.repulsionRadius = config.repulsionRadius
        renderer.repulsionForce = config.repulsionForce
        renderer.springStiffness = config.springStiffness
        renderer.damping = config.damping
    }
    
    private func setRainbowColors() {
        guard let renderer = metalView?.renderer else { return }
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        // Adjust saturation and brightness based on color scheme
        // Light mode needs more saturated, darker colors to stand out against white background
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        let saturation: CGFloat = isDarkMode ? 0.85 : 1.0
        let brightness: CGFloat = isDarkMode ? 0.95 : 0.8
        
        // Create a rainbow gradient around the ring
        for i in 0..<renderer.particleCount {
            let t = Float(i) / Float(renderer.particleCount)
            
            // HSB to RGB conversion for rainbow effect
            let hue = t * 360.0 // 0-360 degrees
            let color = UIColor(hue: CGFloat(hue / 360.0), saturation: saturation, brightness: brightness, alpha: 1.0)
            
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            particles[i].color = SIMD4<Float>(
                Float(red),
                Float(green),
                Float(blue),
                Float(alpha)
            )
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Update colors when switching between light/dark mode
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setRainbowColors()
        }
    }
    
    private func setParticleSize(_ size: Float) {
        guard let renderer = metalView?.renderer else { return }
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        for i in 0..<renderer.particleCount {
            particles[i].size = size
        }
    }
    
    private func updateParticleTargets() {
        guard let renderer = metalView?.renderer else { return }
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        // Scale factor for the 150x150 canvas
        let scale: Float = 0.333
        let innerRadius: Float = 0.35 * scale
        let outerRadius: Float = 0.85 * scale
        
        // Update each particle's target position with rotation
        for i in 0..<renderer.particleCount {
            let t = Float(i) / Float(renderer.particleCount)
            let angle = t * .pi * 2 + rotationAngle // Add rotation offset
            let r = Float.random(in: innerRadius...outerRadius)
            
            particles[i].target = SIMD2<Float>(cos(angle) * r, sin(angle) * r)
        }
    }
    
    func updateColor(_ color: UIColor) {
        guard let renderer = metalView?.renderer else { return }
        
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let particleColor = SIMD4<Float>(
            Float(red),
            Float(green),
            Float(blue),
            Float(alpha)
        )
        
        renderer.setParticleColor(particleColor)
    }
}

// SwiftUI wrapper
struct ParticleRingButton: UIViewRepresentable {
    let size: CGFloat
    let color: UIColor
    let config: ParticleConfig
    
    init(size: CGFloat = 40, color: UIColor = .tertiaryLabel, config: ParticleConfig = .ringButton) {
        self.size = size
        self.color = color
        self.config = config
    }
    
    func makeUIView(context: Context) -> ParticleRingButtonView {
        let view = ParticleRingButtonView(size: size, config: config)
        view.updateColor(color)
        return view
    }
    
    func updateUIView(_ uiView: ParticleRingButtonView, context: Context) {
        uiView.updateColor(color)
    }
}
