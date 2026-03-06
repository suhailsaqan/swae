//
//  LiquidPoolView.swift
//  swae
//
//  Flowing liquid pool background for Control Panel
//  Touch-responsive with ripple effects and zap energy visualization
//

import MetalKit
import UIKit

// MARK: - Uniforms (must match Metal struct)

struct LiquidPoolUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    
    // Touch interaction
    var touchPoint: SIMD2<Float>
    var touchStrength: Float
    
    // Colors
    var baseColor: SIMD3<Float>
    var accentColor: SIMD3<Float>
    var accentStrength: Float
    
    // Energy state
    var energyLevel: Float
    var zapStormIntensity: Float
    
    // Ripple array (up to 4 active ripples)
    var ripplePoints: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    var rippleAges: (Float, Float, Float, Float)
    var activeRipples: Int32
}

// MARK: - Ripple State

private struct RippleState {
    var position: SIMD2<Float> = .zero
    var startTime: CFTimeInterval = 0
    var isActive: Bool = false
}

// MARK: - Pool Configuration

struct LiquidPoolConfig {
    var baseColor: SIMD3<Float>
    var energyLevel: Float
    
    // Preset configurations - subtle, refined colors
    static let normal = LiquidPoolConfig(
        baseColor: SIMD3<Float>(0.12, 0.14, 0.18),  // Dark charcoal with slight blue
        energyLevel: 0.0
    )
    
    static let active = LiquidPoolConfig(
        baseColor: SIMD3<Float>(0.14, 0.16, 0.22),  // Slightly lighter when streaming
        energyLevel: 0.2
    )
    
    static let stressed = LiquidPoolConfig(
        baseColor: SIMD3<Float>(0.18, 0.14, 0.16),  // Warm tint for stress
        energyLevel: 0.4
    )
    
    static let warning = LiquidPoolConfig(
        baseColor: SIMD3<Float>(0.22, 0.12, 0.12),  // Red tint for warning
        energyLevel: 0.6
    )
}

// MARK: - LiquidPoolView

class LiquidPoolView: MTKView {
    
    // MARK: - Properties
    
    private var commandQueue: MTLCommandQueue!
    private var renderPipeline: MTLRenderPipelineState!
    private var uniformsBuffer: MTLBuffer!
    
    private var startTime: CFTimeInterval = 0
    
    // Touch handling
    private var touchStrength: Float = 0
    private var touchPoint: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    private var touchVelocity: Float = 0
    
    // Ripples
    private var ripples: [RippleState] = Array(repeating: RippleState(), count: 4)
    private var nextRippleIndex: Int = 0
    
    // Zap effects
    private var accentStrength: Float = 0
    private var accentColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.85, 0.3)  // Golden
    private var zapStormIntensity: Float = 0
    private var zapStormDecayStart: CFTimeInterval?
    
    // Configuration
    var config: LiquidPoolConfig = .normal
    
    // Physics
    private let touchDecayRate: Float = 3.0
    private let accentDecayRate: Float = 2.0
    private let stormDecayRate: Float = 0.5
    
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
            print("LiquidPoolView: No Metal device")
            return
        }
        
        // View configuration
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        isPaused = false
        enableSetNeedsDisplay = false
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        layer.isOpaque = false
        
        // Command queue
        commandQueue = device.makeCommandQueue()
        
        // Load shaders
        guard let library = device.makeDefaultLibrary(),
              let vertexFunc = library.makeFunction(name: "liquidPoolVertex"),
              let fragmentFunc = library.makeFunction(name: "liquidPoolFragment") else {
            print("LiquidPoolView: Failed to load shaders")
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
            print("LiquidPoolView: Pipeline error: \(error)")
            return
        }
        
        // Uniforms buffer
        uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<LiquidPoolUniforms>.stride,
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
        
        // Add ripple
        addRipple(at: pos)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchPoint = normalizedTouchPosition(touch)
        touchStrength = min(touchStrength + 0.1, 1.0)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Touch strength will decay naturally
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    
    private func normalizedTouchPosition(_ touch: UITouch) -> SIMD2<Float> {
        let loc = touch.location(in: self)
        let x = Float(loc.x / bounds.width)
        let y = 1.0 - Float(loc.y / bounds.height)  // Flip Y
        return SIMD2<Float>(x, y)
    }
    
    // MARK: - Ripple Management
    
    private func addRipple(at position: SIMD2<Float>) {
        ripples[nextRippleIndex] = RippleState(
            position: position,
            startTime: CACurrentMediaTime(),
            isActive: true
        )
        nextRippleIndex = (nextRippleIndex + 1) % 4
    }
    
    /// Add a ripple at a specific point (for external triggers)
    func triggerRipple(at normalizedPoint: SIMD2<Float>) {
        addRipple(at: normalizedPoint)
    }
    
    // MARK: - Zap Effects
    
    /// Trigger a zap effect at a point with given intensity
    func triggerZap(at normalizedPoint: SIMD2<Float>, intensity: Float) {
        // Set accent for golden flash
        accentStrength = min(intensity, 1.0)
        accentColor = SIMD3<Float>(1.0, 0.85, 0.3)  // Golden
        
        // Add ripple at zap point
        addRipple(at: normalizedPoint)
        
        // Check for zap storm (multiple zaps in quick succession)
        // This is tracked externally and set via enterZapStorm()
    }
    
    /// Enter zap storm mode (called when multiple zaps arrive quickly)
    func enterZapStorm() {
        zapStormIntensity = 1.0
        zapStormDecayStart = nil  // Don't decay while storm is active
    }
    
    /// Exit zap storm mode (called after zaps stop)
    func exitZapStorm() {
        zapStormDecayStart = CACurrentMediaTime()
    }
    
    // MARK: - Configuration
    
    /// Update the pool's base color and energy level
    func setStreamState(_ config: LiquidPoolConfig, animated: Bool = true) {
        if animated {
            // Animate to new config (handled in draw loop)
            self.config = config
        } else {
            self.config = config
        }
    }
    
    // MARK: - Physics Update
    
    private func updatePhysics(deltaTime: Float) {
        // Decay touch strength
        if touchStrength > 0 {
            touchStrength -= deltaTime * touchDecayRate
            touchStrength = max(0, touchStrength)
        }
        
        // Decay accent strength
        if accentStrength > 0 {
            accentStrength -= deltaTime * accentDecayRate
            accentStrength = max(0, accentStrength)
        }
        
        // Decay zap storm
        if let decayStart = zapStormDecayStart {
            let elapsed = Float(CACurrentMediaTime() - decayStart)
            zapStormIntensity = max(0, 1.0 - elapsed * stormDecayRate)
            if zapStormIntensity <= 0 {
                zapStormDecayStart = nil
            }
        }
        
        // Update ripple ages (handled in uniforms)
    }
}

// MARK: - MTKViewDelegate

extension LiquidPoolView: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = Float(currentTime - startTime)
        
        // Use a small fixed delta for physics (not cumulative time)
        updatePhysics(deltaTime: 1.0 / 60.0)
        
        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Calculate ripple ages
        var rippleAges: (Float, Float, Float, Float) = (0, 0, 0, 0)
        var ripplePoints: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = (
            .zero, .zero, .zero, .zero
        )
        var activeCount: Int32 = 0
        
        for i in 0..<4 {
            if ripples[i].isActive {
                let age = Float(currentTime - ripples[i].startTime)
                if age > 1.5 {
                    ripples[i].isActive = false
                } else {
                    switch i {
                    case 0:
                        rippleAges.0 = age
                        ripplePoints.0 = ripples[i].position
                    case 1:
                        rippleAges.1 = age
                        ripplePoints.1 = ripples[i].position
                    case 2:
                        rippleAges.2 = age
                        ripplePoints.2 = ripples[i].position
                    case 3:
                        rippleAges.3 = age
                        ripplePoints.3 = ripples[i].position
                    default:
                        break
                    }
                    activeCount += 1
                }
            }
        }
        
        // Update uniforms
        var uniforms = LiquidPoolUniforms(
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(currentTime - startTime),
            touchPoint: touchPoint,
            touchStrength: touchStrength,
            baseColor: config.baseColor,
            accentColor: accentColor,
            accentStrength: accentStrength,
            energyLevel: config.energyLevel,
            zapStormIntensity: zapStormIntensity,
            ripplePoints: ripplePoints,
            rippleAges: rippleAges,
            activeRipples: activeCount
        )
        
        uniformsBuffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<LiquidPoolUniforms>.stride)
        
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

struct LiquidPoolSwiftUIView: UIViewRepresentable {
    var config: LiquidPoolConfig = .normal
    
    func makeUIView(context: Context) -> LiquidPoolView {
        let view = LiquidPoolView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.config = config
        return view
    }
    
    func updateUIView(_ uiView: LiquidPoolView, context: Context) {
        uiView.setStreamState(config, animated: true)
    }
}

// MARK: - Preview

#if DEBUG
struct LiquidPoolView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            LiquidPoolSwiftUIView(config: .normal)
                .frame(height: 300)
                .cornerRadius(20)
                .padding()
        }
    }
}
#endif
