import SwiftUI
import UIKit

// MARK: - Particle Ring Toolbar (Go Live Only)
struct ParticleRingToolbar: View {
    @EnvironmentObject var model: Model
    @State private var zapTriggered = false
    
    var body: some View {
        HStack {
            // Zap Plasma Test Button (left side) - always visible for testing
            Button(action: {
                testZapPlasmaEffect()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: zapTriggered ? "bolt.circle.fill" : "bolt.fill")
                        .font(.system(size: 24))
                        .foregroundColor(zapTriggered ? .yellow : .orange)
                        .scaleEffect(zapTriggered ? 1.3 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: zapTriggered)
                    Text("Test Zap")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60, height: 60)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.8))
                .cornerRadius(12)
            }
            
            Spacer()
            
            // TODO: Temporarily using GoLiveOrb instead of GoLiveParticleRing for testing
            GoLiveOrb()
                .frame(width: 100, height: 100)
            
            Spacer()
            
            // Placeholder for symmetry
            Spacer()
                .frame(width: 60)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .safeAreaPadding(.bottom)
    }
    
    private func testZapPlasmaEffect() {
        // Simulate a 10K sat zap (10,000,000 millisats)
        model.triggerZapPlasmaEffect(amount: 10_000_000)
        
        // Visual feedback animation
        zapTriggered = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            zapTriggered = false
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Show toast feedback
        if model.isLive {
            model.makeToast(title: "⚡ Zap Triggered!", subTitle: "10K sats plasma effect")
        } else {
            model.makeToast(title: "⚡ Zap Triggered!", subTitle: "Go live to see the effect on stream")
        }
    }
}

// MARK: - State Machine for Go Live Button
enum GoLiveState {
    case idle           // Ring, white/gray, not rotating
    case countdown3     // Number "3" shape
    case countdown2     // Number "2" shape
    case countdown1     // Number "1" shape
    case live           // Ring, rainbow, rotating
    case stopping       // Transition back to idle
}

// MARK: - Go Live Particle Ring (SwiftUI Wrapper)
struct GoLiveParticleRing: UIViewRepresentable {
    @EnvironmentObject var model: Model
    
    func makeUIView(context: Context) -> GoLiveParticleRingView {
        let view = GoLiveParticleRingView(size: 100)
        view.onStreamAction = { [weak model] in
            model?.startStream()
        }
        view.onStopStream = { [weak model] in
            _ = model?.stopStream()
        }
        view.isStreamConfigured = { [weak model] in
            model?.isStreamConfigured() ?? false
        }
        view.openSetup = { [weak model] in
            model?.resetWizard()
            model?.createStreamWizard.isPresentingSetup = true
        }
        return view
    }
    
    func updateUIView(_ uiView: GoLiveParticleRingView, context: Context) {
        uiView.setLiveState(model.isLive)
    }
}

// MARK: - Go Live Particle Ring View (UIKit)
class GoLiveParticleRingView: UIView {
    private var metalView: ParticleMetalView?
    private let size: CGFloat
    private var displayLink: CADisplayLink?
    private var rotationAngle: Float = 0
    private var state: GoLiveState = .idle
    private let config: ParticleConfig
    
    // Countdown timing
    private var countdownTimer: Timer?
    private var stateStartTime: CFTimeInterval = 0
    private let countdownStepDuration: TimeInterval = 1.0
    
    // Color transition
    private var colorTransitionProgress: Float = 0
    private let colorTransitionSpeed: Float = 2.0
    
    // Callbacks
    var onStreamAction: (() -> Void)?
    var onStopStream: (() -> Void)?
    var isStreamConfigured: (() -> Bool)?
    var openSetup: (() -> Void)?
    
    init(size: CGFloat = 100) {
        self.size = size
        self.config = .goLiveRing
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        setupView()
        setupParticles()
        startDisplayLink()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopDisplayLink()
        countdownTimer?.invalidate()
    }
    
    private func setupView() {
        backgroundColor = .clear
        clipsToBounds = false
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }
    
    private func setupParticles() {
        let metalView = ParticleMetalView(
            frame: bounds,
            device: MTLCreateSystemDefaultDevice(),
            config: config,
            startScattered: false
        )
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.isUserInteractionEnabled = false
        metalView.clipsToBounds = false
        addSubview(metalView)
        self.metalView = metalView
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.transitionToRing()
            self?.setIdleColor()
        }
    }
    
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // MARK: - Frame Update
    
    @objc private func updateFrame() {
        guard let displayLink = displayLink else { return }
        let deltaTime = Float(displayLink.targetTimestamp - displayLink.timestamp)
        
        switch state {
        case .idle:
            break
            
        case .countdown3, .countdown2, .countdown1:
            updateCountdownColor(deltaTime: deltaTime)
            
        case .live:
            rotationAngle += 1.5 * deltaTime
            if rotationAngle > Float.pi * 2 {
                rotationAngle -= Float.pi * 2
            }
            updateRingTargetsWithRotation()
            updateRainbowColors()
            
        case .stopping:
            colorTransitionProgress -= colorTransitionSpeed * deltaTime
            if colorTransitionProgress <= 0 {
                colorTransitionProgress = 0
                state = .idle
                setIdleColor()
            } else {
                updateTransitionColor()
            }
        }
    }
    
    // MARK: - State Transitions
    
    func setLiveState(_ live: Bool) {
        if live && state != .live && state != .countdown3 && state != .countdown2 && state != .countdown1 {
            state = .live
            colorTransitionProgress = 1.0
            transitionToRing()
        } else if !live && state == .live {
            state = .stopping
            transitionToRing()
        }
    }
    
    @objc private func handleTap() {
        triggerBurstEffect()
        
        switch state {
        case .idle:
            if isStreamConfigured?() == true {
                startCountdown()
            } else {
                openSetup?()
            }
            
        case .countdown3, .countdown2, .countdown1:
            cancelCountdown()
            
        case .live:
            onStopStream?()
            
        case .stopping:
            break
        }
    }
    
    // MARK: - Countdown Logic
    
    private func startCountdown() {
        state = .countdown3
        stateStartTime = CACurrentMediaTime()
        colorTransitionProgress = 0
        
        transitionToNumber(3)
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: countdownStepDuration, repeats: true) { [weak self] _ in
            self?.advanceCountdown()
        }
    }
    
    private func advanceCountdown() {
        switch state {
        case .countdown3:
            state = .countdown2
            transitionToNumber(2)
            colorTransitionProgress = 0
            
        case .countdown2:
            state = .countdown1
            transitionToNumber(1)
            colorTransitionProgress = 0
            
        case .countdown1:
            countdownTimer?.invalidate()
            countdownTimer = nil
            state = .live
            colorTransitionProgress = 1.0
            transitionToRing()
            onStreamAction?()
            
        default:
            break
        }
    }
    
    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        state = .idle
        transitionToRing()
        setIdleColor()
    }
    
    // MARK: - Particle Patterns
    
    private func transitionToRing() {
        guard let renderer = metalView?.renderer else { return }
        
        let scale: Float = 0.35
        let innerRadius: Float = 0.65 * scale
        let outerRadius: Float = 0.95 * scale
        
        let pattern = ParticlePattern.ring(innerRadius: innerRadius, outerRadius: outerRadius)
        renderer.transitionToPattern(pattern)
    }
    
    private func transitionToNumber(_ number: Int) {
        guard let renderer = metalView?.renderer else { return }
        
        let symbolName = "\(number).circle.fill"
        let pattern = ParticlePattern.sfSymbol(name: symbolName, size: 140)
        renderer.transitionToPattern(pattern)
    }
    
    private func updateRingTargetsWithRotation() {
        guard let renderer = metalView?.renderer else { return }
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        let scale: Float = 0.35
        let innerRadius: Float = 0.65 * scale
        let outerRadius: Float = 0.95 * scale
        
        for i in 0..<renderer.particleCount {
            let t = Float(i) / Float(renderer.particleCount)
            let angle = t * .pi * 2 + rotationAngle
            let r = Float.random(in: innerRadius...outerRadius)
            particles[i].target = SIMD2<Float>(cos(angle) * r, sin(angle) * r)
        }
    }
    
    // MARK: - Color Updates
    
    private func setIdleColor() {
        guard let renderer = metalView?.renderer else { return }
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        for i in 0..<renderer.particleCount {
            let t = Float(i) / Float(renderer.particleCount)
            let brightness: Float = 0.5 + 0.3 * sin(t * .pi * 4)
            particles[i].color = SIMD4<Float>(brightness, brightness, brightness, 1.0)
        }
    }
    
    private func updateCountdownColor(deltaTime: Float) {
        guard let renderer = metalView?.renderer else { return }
        
        colorTransitionProgress += deltaTime * 2.0
        let pulse = (sin(colorTransitionProgress * .pi * 2) + 1.0) / 2.0
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        let baseColor: SIMD3<Float>
        switch state {
        case .countdown3:
            baseColor = SIMD3<Float>(1.0, 0.3, 0.2)
        case .countdown2:
            baseColor = SIMD3<Float>(1.0, 0.5, 0.1)
        case .countdown1:
            baseColor = SIMD3<Float>(1.0, 0.8, 0.0)
        default:
            baseColor = SIMD3<Float>(1.0, 1.0, 1.0)
        }
        
        let brightness: Float = 0.7 + 0.3 * pulse
        
        for i in 0..<renderer.particleCount {
            particles[i].color = SIMD4<Float>(
                baseColor.x * brightness,
                baseColor.y * brightness,
                baseColor.z * brightness,
                1.0
            )
        }
    }
    
    private func updateRainbowColors() {
        guard let renderer = metalView?.renderer else { return }
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        let saturation: CGFloat = isDarkMode ? 0.85 : 1.0
        let brightness: CGFloat = isDarkMode ? 0.95 : 0.85
        
        for i in 0..<renderer.particleCount {
            let t = Float(i) / Float(renderer.particleCount)
            let hueOffset = rotationAngle / (Float.pi * 2)
            let hue = fmod(t + hueOffset, 1.0) * 360.0
            
            let color = UIColor(hue: CGFloat(hue / 360.0), saturation: saturation, brightness: brightness, alpha: 1.0)
            
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            particles[i].color = SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
        }
    }
    
    private func updateTransitionColor() {
        guard let renderer = metalView?.renderer else { return }
        
        let particles = renderer.particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: renderer.particleCount
        )
        
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        let saturation: CGFloat = isDarkMode ? 0.85 : 1.0
        let brightness: CGFloat = isDarkMode ? 0.95 : 0.85
        
        for i in 0..<renderer.particleCount {
            let t = Float(i) / Float(renderer.particleCount)
            let hueOffset = rotationAngle / (Float.pi * 2)
            let hue = fmod(t + hueOffset, 1.0) * 360.0
            
            let rainbowColor = UIColor(hue: CGFloat(hue / 360.0), saturation: saturation, brightness: brightness, alpha: 1.0)
            
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            rainbowColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            
            let grayValue: Float = 0.5 + 0.3 * sin(t * .pi * 4)
            
            let finalR = Float(red) * colorTransitionProgress + grayValue * (1 - colorTransitionProgress)
            let finalG = Float(green) * colorTransitionProgress + grayValue * (1 - colorTransitionProgress)
            let finalB = Float(blue) * colorTransitionProgress + grayValue * (1 - colorTransitionProgress)
            
            particles[i].color = SIMD4<Float>(finalR, finalG, finalB, 1.0)
        }
    }
    
    // MARK: - Touch Effects
    
    private func triggerBurstEffect() {
        guard let renderer = metalView?.renderer else { return }
        
        renderer.touchPoint = SIMD2<Float>(0, 0)
        renderer.isTouching = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            renderer.isTouching = false
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let metalView = metalView else { return }
        let location = touch.location(in: metalView)
        
        let x = (location.x / metalView.bounds.width) * 2.0 - 1.0
        let y = 1.0 - (location.y / metalView.bounds.height) * 2.0
        
        metalView.renderer?.touchPoint = SIMD2<Float>(Float(x), Float(y))
        metalView.renderer?.isTouching = true
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let metalView = metalView else { return }
        let location = touch.location(in: metalView)
        
        let x = (location.x / metalView.bounds.width) * 2.0 - 1.0
        let y = 1.0 - (location.y / metalView.bounds.height) * 2.0
        
        metalView.renderer?.touchPoint = SIMD2<Float>(Float(x), Float(y))
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        metalView?.renderer?.isTouching = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        metalView?.renderer?.isTouching = false
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            ParticleRingToolbar()
                .environmentObject(Model())
        }
    }
}
