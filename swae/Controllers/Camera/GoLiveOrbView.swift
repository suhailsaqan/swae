//
//  MorphingGoLiveOrbView.swift
//  swae
//
//  Metal-based Go Live orb that morphs into expanded modal
//  Uses MorphingGoLiveShaders.metal for sphere-to-rounded-rect morphing
//

import MetalKit
import UIKit

// MARK: - Uniforms (MUST match Metal struct exactly - 176 bytes)

struct MorphingGoLiveUniforms {
    // === Block 1: Resolution & Time (16 bytes) ===
    var resolution: SIMD2<Float>
    var time: Float
    var _pad0: Float
    
    // === Block 2: Touch Points (40 bytes) ===
    var touchPoints: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    
    // === Block 3: Touch Strengths + Misc (32 bytes) ===
    var touchStrengths: (Float, Float, Float, Float, Float)
    var activeTouchCount: Int32
    var deformAmount: Float
    var wobbleDecay: Float
    
    // === Block 4: Wobble + Birth + Morph (16 bytes) ===
    var wobbleCenter: SIMD2<Float>
    var birthProgress: Float
    var morphProgress: Float
    
    // === Block 5: Morph Layout (32 bytes) ===
    var orbCenter: SIMD2<Float>
    var modalCenter: SIMD2<Float>
    var modalSize: SIMD2<Float>
    var orbRadius: Float
    var modalCornerRadius: Float
    
    // === Block 6: Appearance (32 bytes) ===
    var liquidColor: SIMD4<Float>  // Use SIMD4 for alignment (w component unused)
    var liquidIntensity: Float
    var animationSpeed: Float
    var glowIntensity: Float
    var pulseRate: Float
    var rimSpinSpeed: Float
    var _pad1: Float
    
    init(
        resolution: SIMD2<Float>,
        time: Float,
        touchPoints: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>),
        touchStrengths: (Float, Float, Float, Float, Float),
        activeTouchCount: Int32,
        deformAmount: Float,
        wobbleDecay: Float,
        wobbleCenter: SIMD2<Float>,
        birthProgress: Float,
        morphProgress: Float,
        orbCenter: SIMD2<Float>,
        modalCenter: SIMD2<Float>,
        modalSize: SIMD2<Float>,
        orbRadius: Float,
        modalCornerRadius: Float,
        liquidColor: SIMD3<Float>,
        liquidIntensity: Float,
        animationSpeed: Float,
        glowIntensity: Float,
        pulseRate: Float,
        rimSpinSpeed: Float
    ) {
        self.resolution = resolution
        self.time = time
        self._pad0 = 0
        self.touchPoints = touchPoints
        self.touchStrengths = touchStrengths
        self.activeTouchCount = activeTouchCount
        self.deformAmount = deformAmount
        self.wobbleDecay = wobbleDecay
        self.wobbleCenter = wobbleCenter
        self.birthProgress = birthProgress
        self.morphProgress = morphProgress
        self.orbCenter = orbCenter
        self.modalCenter = modalCenter
        self.modalSize = modalSize
        self.orbRadius = orbRadius
        self.modalCornerRadius = modalCornerRadius
        self.liquidColor = SIMD4<Float>(liquidColor.x, liquidColor.y, liquidColor.z, 1.0)
        self.liquidIntensity = liquidIntensity
        self.animationSpeed = animationSpeed
        self.glowIntensity = glowIntensity
        self.pulseRate = pulseRate
        self.rimSpinSpeed = rimSpinSpeed
        self._pad1 = 0
    }
}

// MARK: - Morphing Go Live State

enum MorphingGoLiveState: Equatable {
    case idle           // Ready to stream
    case countdown(Int) // 3, 2, 1 countdown
    case live           // Currently streaming
    case stopping       // Transitioning back to idle
}

// MARK: - Touch State (private to avoid conflicts with BubblyOrbView.TouchState)

private struct MorphingOrbTouchState {
    var position: SIMD2<Float> = .zero
    var targetStrength: Float = 0
    var currentStrength: Float = 0
    var velocity: Float = 0
}

// MARK: - MorphingGoLiveOrbView

class MorphingGoLiveOrbView: MTKView, MTKViewDelegate, UIGestureRecognizerDelegate {
    
    // MARK: - State
    
    private(set) var goLiveState: MorphingGoLiveState = .idle
    private(set) var morphProgress: Float = 0.0
    private var targetMorphProgress: Float = 0.0
    private var morphVelocity: Float = 0.0
    
    // Spring physics for morph
    private let springStiffness: Float = 280.0
    private let springDamping: Float = 22.0
    
    // MARK: - Metal Properties
    
    private var commandQueue: MTLCommandQueue!
    private var renderPipeline: MTLRenderPipelineState!
    private var uniformsBuffer: MTLBuffer!
    
    private var startTime: CFTimeInterval = 0
    private var lastUpdateTime: CFTimeInterval = 0
    private var birthStartTime: CFTimeInterval?
    
    // MARK: - Touch State
    
    private var touchStates: [MorphingOrbTouchState] = Array(repeating: MorphingOrbTouchState(), count: 5)
    private var activeTouches: [UITouch: Int] = [:]
    private let touchSpringStiffness: Float = 80.0
    private let touchSpringDamping: Float = 8.0
    
    // Wobble effect
    private var wobbleDecay: Float = 0
    private var wobbleCenter: SIMD2<Float> = .zero
    
    // MARK: - Layout (morph positions)
    // Note: In shader UV coords, y = -1 is TOP, y = +1 is BOTTOM
    // So orbCenter.y should be positive (near +0.85) for bottom of screen
    private var orbCenter: SIMD2<Float> = SIMD2<Float>(0.0, 0.85)
    private var modalCenter: SIMD2<Float> = SIMD2<Float>(0.0, 0.0)
    private var modalSize: SIMD2<Float> = SIMD2<Float>(0.8, 0.5)
    private var orbRadius: Float = 0.12
    private var modalCornerRadius: Float = 0.04
    
    // MARK: - Appearance
    
    private var liquidColor: SIMD3<Float> = SIMD3<Float>(0.7, 0.25, 0.3)
    private var targetLiquidColor: SIMD3<Float> = SIMD3<Float>(0.7, 0.25, 0.3)
    private var glowIntensity: Float = 0.05
    private var pulseRate: Float = 0.1
    private var rimSpinSpeed: Float = 0.0

    
    // MARK: - Gestures
    
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    private var panStartY: CGFloat = 0
    private var panStartMorphProgress: Float = 0
    private let maxDragDistance: CGFloat = 200
    private let expandThreshold: Float = 0.4
    
    // MARK: - Callbacks
    
    var onTap: (() -> Void)?
    var onSwipeUp: (() -> Void)?
    var onMorphProgress: ((Float) -> Void)?
    var isStreamConfigured: (() -> Bool)?
    var openSetup: (() -> Void)?
    var onStreamAction: (() -> Void)?
    var onStopStream: (() -> Void)?
    
    // Countdown
    private var countdownTimer: Timer?
    private var countdownValue: Int = 3
    
    // MARK: - Initialization
    
    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.device = MTLCreateSystemDefaultDevice()
        setup()
    }
    
    private func setup() {
        guard let device = self.device else { return }
        
        // View config
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isPaused = false
        enableSetNeedsDisplay = false
        isOpaque = false
        backgroundColor = .clear
        layer.isOpaque = false
        isMultipleTouchEnabled = true
        
        // Metal setup
        commandQueue = device.makeCommandQueue()
        
        // Use the new morphing shaders
        guard let library = device.makeDefaultLibrary(),
              let vertexFunc = library.makeFunction(name: "morphingGoLiveVertex"),
              let fragmentFunc = library.makeFunction(name: "morphingGoLiveFragment") else {
            print("MorphingGoLiveOrbView: Failed to load morphing shaders")
            return
        }
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("MorphingGoLiveOrbView: Pipeline error: \(error)")
            return
        }
        
        // Allocate buffer for MorphingGoLiveUniforms (176 bytes)
        uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<MorphingGoLiveUniforms>.stride,
            options: .storageModeShared
        )
        
        #if DEBUG
        verifyUniformsAlignment()
        #endif
        
        startTime = CACurrentMediaTime()
        lastUpdateTime = startTime
        birthStartTime = nil
        
        setupGestures()
        delegate = self
    }
    
    #if DEBUG
    private func verifyUniformsAlignment() {
        let size = MemoryLayout<MorphingGoLiveUniforms>.size
        let stride = MemoryLayout<MorphingGoLiveUniforms>.stride
        let alignment = MemoryLayout<MorphingGoLiveUniforms>.alignment
        print("MorphingGoLiveUniforms - size: \(size), stride: \(stride), alignment: \(alignment)")
        // Expected: size=176, stride=176, alignment=16
//        assert(stride == 176, "MorphingGoLiveUniforms stride mismatch! Expected 176, got \(stride)")
    }
    #endif
    
    deinit {
        countdownTimer?.invalidate()
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout is now controlled by updateLayoutForScreen() called from container
    }
    
    /// Update layout positions based on screen dimensions
    /// Called by MorphingOrbContainerView when layout changes
    func updateLayoutForScreen(
        screenSize: CGSize,
        controlBarHeight: CGFloat,
        orbDiameter: CGFloat,
        modalSize: CGSize
    ) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        
        // Orb position: center of control bar area (at BOTTOM of screen)
        // In Metal shader UV coords after transform: y = -1 is TOP, y = +1 is BOTTOM
        // So for orb at bottom, we need POSITIVE y value
        let orbYFromBottom = controlBarHeight / 2  // 60pt from bottom edge
        let orbYFromTop = screenSize.height - orbYFromBottom  // Distance from top
        // Convert to normalized coords: (orbYFromTop / height) * 2 - 1
        // For bottom of screen (orbYFromTop ≈ height), this gives ≈ +1
        let orbYNormalized = (orbYFromTop / screenSize.height) * 2.0 - 1.0
        orbCenter = SIMD2<Float>(0.0, Float(orbYNormalized))
        
        // Orb radius in normalized coords (relative to height)
        let orbRadiusPoints = orbDiameter / 2
        orbRadius = Float(orbRadiusPoints / screenSize.height) * 2.0
        
        // Modal size in normalized coords
        // The shader transforms UV: uv.x *= aspect (where aspect = width/height)
        // This means the coordinate space is stretched horizontally
        // So we need to express modal size in that stretched space
        // 
        // For width: modalSize.width points → normalized = (width / height) * 2.0
        //            (we use height as reference since that's what the shader uses)
        // For height: modalSize.height points → normalized = (height / screenHeight) * 2.0
        let modalWidthNorm = Float(modalSize.width / screenSize.height) * 2.0
        let modalHeightNorm = Float(modalSize.height / screenSize.height) * 2.0
        self.modalSize = SIMD2<Float>(modalWidthNorm, modalHeightNorm)
        
        // Modal position: bottom of screen
        // The modal bottom edge should be at y = +1.0 (very bottom of screen)
        // So modal center Y = 1.0 - (modalHeight / 2)
        let modalCenterY: Float = 1.0 - (modalHeightNorm / 2.0)
        modalCenter = SIMD2<Float>(0.0, modalCenterY)
        
        // Modal corner radius (proportional to modal size)
        modalCornerRadius = modalHeightNorm * 0.08
    }
    
    /// Legacy method for backward compatibility
    private func updateLayoutPositions() {
        // Use default values if updateLayoutForScreen hasn't been called
        let screenSize = bounds.size
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        
        updateLayoutForScreen(
            screenSize: screenSize,
            controlBarHeight: 120,
            orbDiameter: 70,
            modalSize: CGSize(width: 300, height: 280)
        )
    }
    
    // MARK: - Birth Animation
    
    func triggerBirthAnimation() {
        birthStartTime = CACurrentMediaTime()
    }
    
    // MARK: - Gestures
    
    private var isDragging: Bool = false  // Track if user is actively dragging
    
    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.require(toFail: panGesture)
        addGestureRecognizer(tapGesture)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .began:
            isDragging = true
            panStartY = 0
            panStartMorphProgress = targetMorphProgress  // Use target, not current
            
        case .changed:
            guard isDragging else { return }
            // Drag up (negative translation.y) increases morphProgress
            let dragProgress = Float(-translation.y / maxDragDistance)
            let newProgress = clampFloat(panStartMorphProgress + dragProgress, min: 0, max: 1)
            // During drag, set both to keep them in sync
            morphProgress = newProgress
            targetMorphProgress = newProgress
            morphVelocity = 0  // Reset velocity during drag
            onMorphProgress?(morphProgress)
            
        case .ended:
            guard isDragging else { return }
            isDragging = false
            finalizeGesture(velocity: velocity)
            
        case .cancelled, .failed:
            // CRITICAL: Always finalize on cancel/fail to prevent stuck state
            isDragging = false
            finalizeGesture(velocity: velocity)
            
        default:
            break
        }
    }
    
    /// Finalize the gesture by deciding whether to expand or collapse
    private func finalizeGesture(velocity: CGPoint) {
        let velocityThreshold: CGFloat = 500
        
        // Determine whether to expand or collapse based on:
        // 1. Fast swipe up (velocity.y < -500) → always expand
        // 2. Fast swipe down (velocity.y > 500) → always collapse
        // 3. Released past threshold (morphProgress > 0.4) → expand
        // 4. Released before threshold → collapse
        
        let shouldExpand: Bool
        if velocity.y < -velocityThreshold {
            // Fast swipe up → expand
            shouldExpand = true
        } else if velocity.y > velocityThreshold {
            // Fast swipe down → collapse
            shouldExpand = false
        } else {
            // No fast swipe → use position threshold
            shouldExpand = morphProgress > expandThreshold
        }
        
        if shouldExpand {
            onSwipeUp?()  // Container will call expand()
        } else {
            collapse()
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onTap?()
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        for touch in touches {
            if let freeIndex = (0..<5).first(where: { touchStates[$0].targetStrength == 0 && !activeTouches.values.contains($0) }) {
                activeTouches[touch] = freeIndex
                let pos = normalizedTouchPosition(touch)
                touchStates[freeIndex].position = pos
                touchStates[freeIndex].targetStrength = 1.0
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        for touch in touches {
            if let index = activeTouches[touch] {
                touchStates[index].position = normalizedTouchPosition(touch)
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        for touch in touches {
            if let index = activeTouches[touch] {
                touchStates[index].targetStrength = 0
                wobbleDecay = min(touchStates[index].currentStrength * 1.2 + 0.3, 0.9)
                wobbleCenter = touchStates[index].position
                activeTouches.removeValue(forKey: touch)
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    private func normalizedTouchPosition(_ touch: UITouch) -> SIMD2<Float> {
        let loc = touch.location(in: self)
        let x = Float(loc.x / bounds.width) * 2.0 - 1.0
        let y = 1.0 - Float(loc.y / bounds.height) * 2.0
        let aspect = Float(bounds.width / bounds.height)
        return SIMD2<Float>(x * aspect, y)
    }

    
    // MARK: - Physics Update
    
    private func updatePhysics(deltaTime: Float) {
        let dt = min(deltaTime, 0.033)
        
        // Touch spring physics
        for i in 0..<5 {
            let displacement = touchStates[i].targetStrength - touchStates[i].currentStrength
            let springForce = displacement * touchSpringStiffness
            let dampingForce = touchStates[i].velocity * touchSpringDamping
            
            touchStates[i].velocity += (springForce - dampingForce) * dt
            touchStates[i].currentStrength += touchStates[i].velocity * dt
            touchStates[i].currentStrength = max(0, min(1, touchStates[i].currentStrength))
        }
        
        // Wobble decay
        wobbleDecay *= (1.0 - dt * 3.0)
        if wobbleDecay < 0.01 { wobbleDecay = 0 }
        
        // SAFETY: If not dragging, ensure targetMorphProgress is either 0 or 1
        // This prevents getting stuck in intermediate states
        if !isDragging {
            if targetMorphProgress > 0 && targetMorphProgress < 1 {
                // Snap to nearest endpoint
                targetMorphProgress = targetMorphProgress > 0.5 ? 1.0 : 0.0
            }
        }
        
        // Morph spring physics (only animate when not dragging)
        if !isDragging {
            let morphDisplacement = targetMorphProgress - morphProgress
            let morphSpringForce = morphDisplacement * springStiffness
            let morphDampingForce = morphVelocity * springDamping
            
            morphVelocity += (morphSpringForce - morphDampingForce) * dt
            morphProgress += morphVelocity * dt
            
            // Clamp to valid range
            morphProgress = clampFloat(morphProgress, min: 0, max: 1)
            
            // Settle when close enough
            if abs(morphDisplacement) < 0.001 && abs(morphVelocity) < 0.01 {
                morphProgress = targetMorphProgress
                morphVelocity = 0
            }
        }
        
        // Smooth color transition
        liquidColor = liquidColor + (targetLiquidColor - liquidColor) * dt * 8.0
    }
    
    // MARK: - Public API
    
    func expand() {
        targetMorphProgress = 1.0
    }
    
    func collapse() {
        targetMorphProgress = 0.0
    }
    
    var isExpanded: Bool {
        return targetMorphProgress > 0.5
    }
    
    // MARK: - Go Live State
    
    func setLiveState(_ live: Bool) {
        if live && goLiveState != .live {
            goLiveState = .live
            targetLiquidColor = SIMD3<Float>(1.0, 0.15, 0.15)
            glowIntensity = 0.35
            pulseRate = 0.3
            rimSpinSpeed = 0.0
        } else if !live && goLiveState == .live {
            goLiveState = .stopping
            targetLiquidColor = SIMD3<Float>(0.5, 0.3, 0.3)
            glowIntensity = 0.05
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.goLiveState = .idle
                self?.targetLiquidColor = SIMD3<Float>(0.7, 0.25, 0.3)
            }
        }
    }
    
    // MARK: - Countdown
    
    func startCountdown() {
        countdownValue = 3
        goLiveState = .countdown(3)
        updateCountdownAppearance(3)
        
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.advanceCountdown()
        }
    }
    
    private func advanceCountdown() {
        countdownValue -= 1
        
        if countdownValue > 0 {
            goLiveState = .countdown(countdownValue)
            updateCountdownAppearance(countdownValue)
        } else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            goLiveState = .live
            targetLiquidColor = SIMD3<Float>(1.0, 0.15, 0.15)
            glowIntensity = 0.35
            rimSpinSpeed = 0.0
            onStreamAction?()
        }
    }
    
    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        goLiveState = .idle
        targetLiquidColor = SIMD3<Float>(0.7, 0.25, 0.3)
        glowIntensity = 0.05
        rimSpinSpeed = 0.0
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    private func updateCountdownAppearance(_ count: Int) {
        rimSpinSpeed = 8.0
        
        switch count {
        case 3: targetLiquidColor = SIMD3<Float>(0.5, 1.0, 0.2)
        case 2: targetLiquidColor = SIMD3<Float>(1.0, 0.8, 0.1)
        case 1: targetLiquidColor = SIMD3<Float>(1.0, 0.4, 0.05)
        default: break
        }
        
        glowIntensity = 0.2 + Float(4 - count) * 0.1
        pulseRate = 1.5 + Float(4 - count) * 0.5
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Don't allow simultaneous recognition - orb gestures are exclusive
        return false
    }
    
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Don't require other gestures to fail - we want to compete
        return false
    }
    
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // CRITICAL: Other gestures (navigation, scroll views, etc.) should require
        // our gestures to fail first. This gives the orb priority when touched.
        // This prevents CameraContainerViewController's vertical pan from stealing our drag.
        return true
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGesture {
            let velocity = panGesture.velocity(in: self)
            return abs(velocity.y) > abs(velocity.x)
        }
        return true
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = Float(currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        
        updatePhysics(deltaTime: deltaTime)
        
        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Birth animation progress
        let birthDuration: Float = 0.8
        let birthProgress: Float
        if let birthStart = birthStartTime {
            birthProgress = min(Float(currentTime - birthStart) / birthDuration, 1.0)
        } else {
            birthProgress = 0.0
        }
        
        // Create uniforms with all morph data
        var uniforms = MorphingGoLiveUniforms(
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(currentTime - startTime),
            touchPoints: (
                touchStates[0].position,
                touchStates[1].position,
                touchStates[2].position,
                touchStates[3].position,
                touchStates[4].position
            ),
            touchStrengths: (
                touchStates[0].currentStrength,
                touchStates[1].currentStrength,
                touchStates[2].currentStrength,
                touchStates[3].currentStrength,
                touchStates[4].currentStrength
            ),
            activeTouchCount: Int32(activeTouches.count + (wobbleDecay > 0.01 ? 1 : 0)),
            deformAmount: 1.5,
            wobbleDecay: wobbleDecay,
            wobbleCenter: wobbleCenter,
            birthProgress: birthProgress,
            morphProgress: morphProgress,
            orbCenter: orbCenter,
            modalCenter: modalCenter,
            modalSize: modalSize,
            orbRadius: orbRadius,
            modalCornerRadius: modalCornerRadius,
            liquidColor: liquidColor,
            liquidIntensity: 0.85,
            animationSpeed: 0.8,
            glowIntensity: glowIntensity,
            pulseRate: pulseRate,
            rimSpinSpeed: rimSpinSpeed
        )
        
        uniformsBuffer.contents().copyMemory(
            from: &uniforms,
            byteCount: MemoryLayout<MorphingGoLiveUniforms>.stride
        )
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }
        
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Helper
    
    private func clampFloat(_ value: Float, min minVal: Float, max maxVal: Float) -> Float {
        return Swift.min(Swift.max(value, minVal), maxVal)
    }
}
