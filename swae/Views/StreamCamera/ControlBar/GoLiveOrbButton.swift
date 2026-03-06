//
//  GoLiveOrbButton.swift
//  swae
//
//  Liquid glass orb button for Go Live functionality
//

import MetalKit
import SwiftUI
import UIKit

// MARK: - Go Live State

enum GoLiveOrbState: Equatable {
    case idle
    case countdown(Int)  // 3, 2, 1
    case live
    case stopping
}

// MARK: - Go Live Orb View (UIKit)

class GoLiveOrbView: BubblyOrbView {
    
    private(set) var state: GoLiveOrbState = .idle
    
    // Animated config transition
    private var targetConfig: BubblyOrbConfig = .goLiveIdle
    private var configTransitionStart: CFTimeInterval?
    private var configTransitionDuration: CFTimeInterval = 0.25  // Faster transition to complete before next countdown tick
    private var previousConfig: BubblyOrbConfig = .goLiveIdle
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        config = .goLiveIdle
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        config = .goLiveIdle
    }
    
    // MARK: - State Management
    
    func transitionToState(_ newState: GoLiveOrbState, animated: Bool = true) {
        guard newState != state else { return }
        state = newState
        
        let newConfig: BubblyOrbConfig
        switch newState {
        case .idle:
            newConfig = .goLiveIdle
        case .countdown(let count):
            newConfig = countdownConfig(for: count)
        case .live:
            newConfig = .goLiveLive
        case .stopping:
            newConfig = .goLiveStopping
        }
        
        if animated {
            // IMPORTANT: Use current config (which may be mid-transition) as the starting point
            // This ensures smooth transitions even when interrupted
            previousConfig = config
            targetConfig = newConfig
            configTransitionStart = CACurrentMediaTime()
            
            // Longer transition for countdown→live (spinning arc needs to fade out smoothly)
            if newState == .live {
                configTransitionDuration = 0.5
            } else {
                configTransitionDuration = 0.25
            }
        } else {
            config = newConfig
            targetConfig = newConfig
            previousConfig = newConfig  // Also update previousConfig to avoid stale state
            configTransitionStart = nil
        }
    }
    
    private func countdownConfig(for count: Int) -> BubblyOrbConfig {
        var cfg = BubblyOrbConfig.goLiveCountdown
        // Increase intensity as countdown progresses
        let progress = Float(4 - count) / 3.0  // 0.33, 0.66, 1.0
        
        // FIXED: Use CONSTANT rimSpinSpeed so the arc doesn't reset position
        // Only the color changes between countdown steps, not the rotation speed
        cfg.rimSpinSpeed = 8.0  // Constant speed throughout countdown
        cfg.pulseRate = 1.5 + progress * 1.5
        cfg.animationSpeed = 1.5 + progress * 1.0
        cfg.glowIntensity = 0.2 + progress * 0.3
        
        // Smooth "heat" gradient: Green → Yellow → Orange → Red
        // Each step is adjacent on the color wheel for smooth transitions
        switch count {
        case 3:
            // Lime Green - "get ready" - cool but energetic
            cfg.liquidColor = SIMD3<Float>(0.5, 1.0, 0.2)
        case 2:
            // Golden Yellow - "warming up"
            cfg.liquidColor = SIMD3<Float>(1.0, 0.8, 0.1)
        case 1:
            // Hot Orange - "almost there" - close to red
            cfg.liquidColor = SIMD3<Float>(1.0, 0.4, 0.05)
        default:
            cfg.liquidColor = SIMD3<Float>(0.5, 1.0, 0.2)
        }
        
        return cfg
    }
    
    // MARK: - Config Animation
    
    func updateConfigTransition() {
        guard let startTime = configTransitionStart else { return }
        
        let elapsed = CACurrentMediaTime() - startTime
        let progress = min(Float(elapsed / configTransitionDuration), 1.0)
        
        // Ease out
        let easedProgress = 1.0 - pow(1.0 - progress, 3.0)
        
        config = interpolateConfig(from: previousConfig, to: targetConfig, t: easedProgress)
        
        if progress >= 1.0 {
            configTransitionStart = nil
            config = targetConfig
        }
    }
    
    private func interpolateConfig(from: BubblyOrbConfig, to: BubblyOrbConfig, t: Float) -> BubblyOrbConfig {
        return BubblyOrbConfig(
            liquidColor: mix(from.liquidColor, to.liquidColor, t: t),
            liquidIntensity: mix(from.liquidIntensity, to.liquidIntensity, t: t),
            animationSpeed: mix(from.animationSpeed, to.animationSpeed, t: t),
            glowIntensity: mix(from.glowIntensity, to.glowIntensity, t: t),
            pulseRate: mix(from.pulseRate, to.pulseRate, t: t),
            rimSpinSpeed: mix(from.rimSpinSpeed, to.rimSpinSpeed, t: t)
        )
    }
    
    private func mix(_ a: Float, _ b: Float, t: Float) -> Float {
        return a + (b - a) * t
    }
    
    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a + (b - a) * t
    }
}

// MARK: - Go Live Orb Button (UIKit Control)

class GoLiveOrbButtonView: UIControl {
    
    private let orbView: GoLiveOrbView
    private var countdownTimer: Timer?
    private var countdownValue: Int = 3
    
    // Demo mode for simulator testing
    #if DEBUG
    private var demoMode = false
    private var tapCount = 0
    private var lastTapTime: Date?
    
    private lazy var demoBadge: UILabel = {
        let label = UILabel()
        label.text = "DEMO"
        label.font = .systemFont(ofSize: 8, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .systemOrange
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    #endif
    
    // Callbacks
    var onStreamAction: (() -> Void)?
    var onStopStream: (() -> Void)?
    var isStreamConfigured: (() -> Bool)?
    var openSetup: (() -> Void)?
    
    // Display link for config animation
    private var displayLink: CADisplayLink?
    
    // MARK: - Init
    
    override init(frame: CGRect) {
        orbView = GoLiveOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        orbView = GoLiveOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        clipsToBounds = false
        
        orbView.translatesAutoresizingMaskIntoConstraints = false
        orbView.isUserInteractionEnabled = false
        orbView.clipsToBounds = false
        addSubview(orbView)
        
        NSLayoutConstraint.activate([
            orbView.centerXAnchor.constraint(equalTo: centerXAnchor),
            orbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            orbView.widthAnchor.constraint(equalToConstant: 120),
            orbView.heightAnchor.constraint(equalToConstant: 120)
        ])
        
        #if DEBUG
        addSubview(demoBadge)
        NSLayoutConstraint.activate([
            demoBadge.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            demoBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            demoBadge.widthAnchor.constraint(equalToConstant: 32),
            demoBadge.heightAnchor.constraint(equalToConstant: 14)
        ])
        #endif
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        
        // Long press for settings (or demo state cycling)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.5
        addGestureRecognizer(longPress)
        
        // Start display link for config animation
        startDisplayLink()
        
        // Trigger birth animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.orbView.triggerBirthAnimation()
        }
    }
    
    deinit {
        stopDisplayLink()
        countdownTimer?.invalidate()
    }
    
    // MARK: - Display Link
    
    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func updateFrame() {
        orbView.updateConfigTransition()
    }
    
    // MARK: - External State Sync
    
    func setLiveState(_ live: Bool) {
        #if DEBUG
        if demoMode { return }  // Don't sync in demo mode
        #endif
        
        if live && orbView.state != .live {
            orbView.transitionToState(.live)
        } else if !live && orbView.state == .live {
            orbView.transitionToState(.stopping)
            // After animation, go to idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if self?.orbView.state == .stopping {
                    self?.orbView.transitionToState(.idle)
                }
            }
        }
    }
    
    // MARK: - Tap Handling
    
    @objc private func handleTap() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        #if DEBUG
        // Check for triple tap to toggle demo mode
        checkTripleTap()
        
        if demoMode {
            handleDemoTap()
            return
        }
        #endif
        
        switch orbView.state {
        case .idle:
            if isStreamConfigured?() == true {
                startCountdown()
            } else {
                openSetup?()
            }
            
        case .countdown:
            cancelCountdown()
            
        case .live:
            onStopStream?()
            
        case .stopping:
            break
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        
        #if DEBUG
        if demoMode {
            cycleDemoState()
            return
        }
        #endif
        
        // Normal long press behavior - could open settings
        // For now, just provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    // MARK: - Countdown
    
    private func startCountdown() {
        countdownValue = 3
        orbView.transitionToState(.countdown(3))
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.advanceCountdown()
        }
    }
    
    private func advanceCountdown() {
        countdownValue -= 1
        
        if countdownValue > 0 {
            orbView.transitionToState(.countdown(countdownValue))
        } else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            
            #if DEBUG
            if demoMode {
                orbView.transitionToState(.live)
                return
            }
            #endif
            
            orbView.transitionToState(.live)
            onStreamAction?()
        }
    }
    
    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        orbView.transitionToState(.idle)
        
        // Haptic feedback for cancel
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    // MARK: - Touch Forwarding
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesCancelled(touches, with: event)
    }
    
    // MARK: - Demo Mode (DEBUG only)
    
    #if DEBUG
    private func checkTripleTap() {
        let now = Date()
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) < 0.4 {
            tapCount += 1
        } else {
            tapCount = 1
        }
        lastTapTime = now
        
        if tapCount >= 3 {
            tapCount = 0
            toggleDemoMode()
        }
    }
    
    private func toggleDemoMode() {
        demoMode.toggle()
        demoBadge.isHidden = !demoMode
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(demoMode ? .success : .warning)
        
        if demoMode {
            // Reset to idle when entering demo mode
            orbView.transitionToState(.idle)
        }
    }
    
    private func handleDemoTap() {
        switch orbView.state {
        case .idle:
            startCountdown()
        case .countdown:
            cancelCountdown()
        case .live:
            orbView.transitionToState(.stopping)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.orbView.transitionToState(.idle)
            }
        case .stopping:
            break
        }
    }
    
    private func cycleDemoState() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        switch orbView.state {
        case .idle:
            orbView.transitionToState(.countdown(3))
        case .countdown(3):
            orbView.transitionToState(.countdown(2))
        case .countdown(2):
            orbView.transitionToState(.countdown(1))
        case .countdown(1):
            orbView.transitionToState(.live)
        case .countdown:
            orbView.transitionToState(.live)
        case .live:
            orbView.transitionToState(.stopping)
        case .stopping:
            orbView.transitionToState(.idle)
        }
    }
    #endif
}

// MARK: - SwiftUI Wrapper

struct GoLiveOrb: UIViewRepresentable {
    @EnvironmentObject var model: Model
    
    func makeUIView(context: Context) -> GoLiveOrbButtonView {
        let view = GoLiveOrbButtonView(frame: .zero)
        
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
    
    func updateUIView(_ uiView: GoLiveOrbButtonView, context: Context) {
        uiView.setLiveState(model.isLive)
    }
}

// MARK: - Preview

#if DEBUG
struct GoLiveOrb_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GoLiveOrb()
                .frame(width: 100, height: 100)
                .environmentObject(Model())
        }
    }
}
#endif
