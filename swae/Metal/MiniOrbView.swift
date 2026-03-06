//
//  MiniOrbView.swift
//  swae
//
//  Smaller liquid orb for toggle buttons in Control Panel
//  Reuses BubblyOrbShaders with simplified configuration
//

import MetalKit
import UIKit

// MARK: - Mini Orb Configuration

struct MiniOrbConfig {
    var color: SIMD3<Float>
    var isOn: Bool
    var glowIntensity: Float
    
    // Preset colors for different toggle functions
    static func widget(isOn: Bool) -> MiniOrbConfig {
        MiniOrbConfig(
            color: isOn ? SIMD3<Float>(0.6, 0.3, 0.9) : SIMD3<Float>(0.3, 0.3, 0.35),
            isOn: isOn,
            glowIntensity: isOn ? 0.3 : 0.0
        )
    }
    
    static func lut(isOn: Bool) -> MiniOrbConfig {
        // Rainbow/prismatic when on
        MiniOrbConfig(
            color: isOn ? SIMD3<Float>(0.8, 0.4, 0.9) : SIMD3<Float>(0.3, 0.3, 0.35),
            isOn: isOn,
            glowIntensity: isOn ? 0.35 : 0.0
        )
    }
    
    static func mic(isOn: Bool) -> MiniOrbConfig {
        MiniOrbConfig(
            color: isOn ? SIMD3<Float>(0.2, 0.9, 0.4) : SIMD3<Float>(0.3, 0.3, 0.35),
            isOn: isOn,
            glowIntensity: isOn ? 0.3 : 0.0
        )
    }
    
    static func torch(isOn: Bool) -> MiniOrbConfig {
        MiniOrbConfig(
            color: isOn ? SIMD3<Float>(1.0, 0.8, 0.2) : SIMD3<Float>(0.3, 0.3, 0.35),
            isOn: isOn,
            glowIntensity: isOn ? 0.4 : 0.0
        )
    }
    
    static func mute(isOn: Bool) -> MiniOrbConfig {
        MiniOrbConfig(
            color: isOn ? SIMD3<Float>(0.95, 0.25, 0.25) : SIMD3<Float>(0.3, 0.3, 0.35),
            isOn: isOn,
            glowIntensity: isOn ? 0.3 : 0.0
        )
    }
    
    static func flip(isOn: Bool) -> MiniOrbConfig {
        // Flip doesn't have a persistent state, just flashes blue
        MiniOrbConfig(
            color: SIMD3<Float>(0.3, 0.6, 1.0),
            isOn: false,
            glowIntensity: 0.0
        )
    }
    
    static func scene(isOn: Bool) -> MiniOrbConfig {
        MiniOrbConfig(
            color: isOn ? SIMD3<Float>(0.2, 0.8, 0.8) : SIMD3<Float>(0.3, 0.3, 0.35),
            isOn: isOn,
            glowIntensity: isOn ? 0.25 : 0.0
        )
    }
    
    static func obs(isOn: Bool) -> MiniOrbConfig {
        MiniOrbConfig(
            color: isOn ? SIMD3<Float>(0.6, 0.3, 0.9) : SIMD3<Float>(0.3, 0.3, 0.35),
            isOn: isOn,
            glowIntensity: isOn ? 0.3 : 0.0
        )
    }
    
    // Generic off state
    static let off = MiniOrbConfig(
        color: SIMD3<Float>(0.3, 0.3, 0.35),
        isOn: false,
        glowIntensity: 0.0
    )
}

// MARK: - MiniOrbView

class MiniOrbView: MTKView {
    
    // MARK: - Properties
    
    private var commandQueue: MTLCommandQueue!
    private var renderPipeline: MTLRenderPipelineState!
    private var uniformsBuffer: MTLBuffer!
    
    private var startTime: CFTimeInterval = 0
    
    // Touch state
    private var touchStrength: Float = 0
    private var touchVelocity: Float = 0
    private var touchPoint: SIMD2<Float> = .zero
    
    // Wobble effect
    private var wobbleDecay: Float = 0
    private var wobbleCenter: SIMD2<Float> = .zero
    
    // Configuration
    var config: MiniOrbConfig = .off {
        didSet {
            targetConfig = config
        }
    }
    
    // Animated config transition
    private var targetConfig: MiniOrbConfig = .off
    private var currentColor: SIMD3<Float> = SIMD3<Float>(0.3, 0.3, 0.35)
    private var currentGlow: Float = 0
    
    // Physics
    private let springStiffness: Float = 100.0
    private let springDamping: Float = 10.0
    private let colorLerpSpeed: Float = 8.0
    
    // MARK: - Init
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.device = MTLCreateSystemDefaultDevice()
        setup()
    }
    
    private func setup() {
        guard let device = self.device else {
            print("MiniOrbView: No Metal device")
            return
        }
        
        // View configuration
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        isPaused = false
        enableSetNeedsDisplay = false
        isOpaque = false
        backgroundColor = .clear
        layer.isOpaque = false
        
        // Command queue
        commandQueue = device.makeCommandQueue()
        
        // Load shaders (reuse BubblyOrb shaders)
        guard let library = device.makeDefaultLibrary(),
              let vertexFunc = library.makeFunction(name: "bubblyOrbVertex"),
              let fragmentFunc = library.makeFunction(name: "bubblyOrbFragment") else {
            print("MiniOrbView: Failed to load shaders")
            return
        }
        
        // Render pipeline
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
            print("MiniOrbView: Pipeline error: \(error)")
            return
        }
        
        // Uniforms buffer (reuse BubblyOrbUniforms)
        uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<BubblyOrbUniforms>.stride,
            options: .storageModeShared
        )
        
        startTime = CACurrentMediaTime()
        delegate = self
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let pos = normalizedTouchPosition(touch)
        touchPoint = pos
        touchStrength = 1.0
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchPoint = normalizedTouchPosition(touch)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Trigger wobble
        wobbleDecay = touchStrength * 0.8
        wobbleCenter = touchPoint
        touchStrength = 0
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
    
    // MARK: - Animation
    
    /// Trigger a "flash" animation (for momentary actions like Flip)
    func flash() {
        touchStrength = 0.6
        wobbleDecay = 0.5
        wobbleCenter = .zero
    }
    
    /// Animate the orb "igniting" when turned on
    func animateOn() {
        wobbleDecay = 0.4
        wobbleCenter = .zero
    }
    
    /// Animate the orb "draining" when turned off
    func animateOff() {
        wobbleDecay = 0.3
        wobbleCenter = SIMD2<Float>(0, -0.5)
    }
    
    // MARK: - Physics Update
    
    private func updatePhysics(deltaTime: Float) {
        let dt = min(deltaTime, 0.033)
        
        // Spring physics for touch
        let displacement = 0 - touchStrength
        let springForce = displacement * springStiffness
        let dampingForce = touchVelocity * springDamping
        
        touchVelocity += (springForce - dampingForce) * dt
        touchStrength += touchVelocity * dt
        touchStrength = max(0, touchStrength)
        
        // Decay wobble
        wobbleDecay *= (1.0 - dt * 4.0)
        if wobbleDecay < 0.01 {
            wobbleDecay = 0
        }
        
        // Lerp color and glow
        currentColor = currentColor + (targetConfig.color - currentColor) * dt * colorLerpSpeed
        currentGlow = currentGlow + (targetConfig.glowIntensity - currentGlow) * dt * colorLerpSpeed
    }
}

// MARK: - MTKViewDelegate

extension MiniOrbView: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = Float(1.0 / 60.0)
        
        updatePhysics(deltaTime: deltaTime)
        
        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Animation speed based on on/off state
        let animSpeed: Float = config.isOn ? 0.8 : 0.3
        let pulseRate: Float = config.isOn ? 0.15 : 0.0
        let intensity: Float = config.isOn ? 0.85 : 0.5
        
        // Update uniforms (using BubblyOrbUniforms structure)
        var uniforms = BubblyOrbUniforms(
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(currentTime - startTime),
            touchPoints: (touchPoint, .zero, .zero, .zero, .zero),
            touchStrengths: (touchStrength, 0, 0, 0, 0),
            activeTouchCount: touchStrength > 0.01 ? 1 : 0,
            deformAmount: 1.2,  // Slightly less deform for small orbs
            wobbleDecay: wobbleDecay,
            wobbleCenter: wobbleCenter,
            birthProgress: 1.0,  // Always fully formed
            liquidColor: currentColor,
            liquidIntensity: intensity,
            animationSpeed: animSpeed,
            glowIntensity: currentGlow,
            pulseRate: pulseRate,
            rimSpinSpeed: 0.0
        )
        
        uniformsBuffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<BubblyOrbUniforms>.stride)
        
        // Render
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }
        
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - SwiftUI Wrapper

import SwiftUI

struct MiniOrbSwiftUIView: UIViewRepresentable {
    var config: MiniOrbConfig
    
    func makeUIView(context: Context) -> MiniOrbView {
        let view = MiniOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.config = config
        return view
    }
    
    func updateUIView(_ uiView: MiniOrbView, context: Context) {
        let wasOn = uiView.config.isOn
        uiView.config = config
        
        // Trigger animation on state change
        if config.isOn && !wasOn {
            uiView.animateOn()
        } else if !config.isOn && wasOn {
            uiView.animateOff()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MiniOrbView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            VStack {
                MiniOrbSwiftUIView(config: .mic(isOn: true))
                    .frame(width: 50, height: 50)
                Text("Mic ON")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            VStack {
                MiniOrbSwiftUIView(config: .mic(isOn: false))
                    .frame(width: 50, height: 50)
                Text("Mic OFF")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            VStack {
                MiniOrbSwiftUIView(config: .torch(isOn: true))
                    .frame(width: 50, height: 50)
                Text("Torch")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            
            VStack {
                MiniOrbSwiftUIView(config: .mute(isOn: true))
                    .frame(width: 50, height: 50)
                Text("Mute")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
