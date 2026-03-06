//
//  BubblyOrbView.swift
//  swae
//
//  Touch-responsive bubbly orb using Metal raymarching
//

import MetalKit
import UIKit

// MARK: - Uniforms (must match Metal struct)

struct BubblyOrbUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var touchPoints: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    var touchStrengths: (Float, Float, Float, Float, Float)
    var activeTouchCount: Int32
    var deformAmount: Float
    var wobbleDecay: Float
    var wobbleCenter: SIMD2<Float>
    var birthProgress: Float  // 0 = just born, 1 = fully formed
    
    // Configuration for customizable appearance
    var liquidColor: SIMD3<Float>
    var liquidIntensity: Float
    var animationSpeed: Float
    var glowIntensity: Float
    var pulseRate: Float
    var rimSpinSpeed: Float   // 0 = no spin, >0 = spinning rim (for countdown)
}

// MARK: - Orb Configuration

struct BubblyOrbConfig {
    var liquidColor: SIMD3<Float>
    var liquidIntensity: Float
    var animationSpeed: Float
    var glowIntensity: Float
    var pulseRate: Float
    var rimSpinSpeed: Float = 0.0  // 0 = no spin, >0 = spinning rim (for countdown)
    
    // Default config - now Siri-style
    static let `default` = BubblyOrbConfig.siri
    
    // Classic blue orb
    static let classicBlue = BubblyOrbConfig(
        liquidColor: SIMD3<Float>(0.08, 0.3, 0.75),
        liquidIntensity: 0.75,
        animationSpeed: 1.0,
        glowIntensity: 0.0,
        pulseRate: 0.0,
        rimSpinSpeed: 0.0
    )
    
    // Siri-style: multi-color flowing, luminous, gentle breathing
    static let siri = BubblyOrbConfig(
        liquidColor: SIMD3<Float>(0.5, 0.3, 0.9),  // Base purple (shader adds multi-color)
        liquidIntensity: 0.85,
        animationSpeed: 0.8,  // Slower, more organic
        glowIntensity: 0.25,  // Luminous glow
        pulseRate: 0.15,      // Gentle breathing
        rimSpinSpeed: 0.0     // No spinning rim
    )
    
    // Camera button preset
    static let cameraButton = BubblyOrbConfig.siri
    
    // Go Live states - distinctive colors for each state
    static let goLiveIdle = BubblyOrbConfig(
        liquidColor: SIMD3<Float>(0.7, 0.25, 0.3),  // Muted red/coral - hints at "record"
        liquidIntensity: 0.7,
        animationSpeed: 0.6,
        glowIntensity: 0.05,
        pulseRate: 0.1,       // Subtle breathing
        rimSpinSpeed: 0.0     // No spinning
    )
    
    static let goLiveCountdown = BubblyOrbConfig(
        liquidColor: SIMD3<Float>(1.0, 0.5, 0.1),  // Orange
        liquidIntensity: 0.9,
        animationSpeed: 1.5,
        glowIntensity: 0.3,
        pulseRate: 1.5,
        rimSpinSpeed: 8.0     // Fast spinning rim during countdown!
    )
    
    static let goLiveLive = BubblyOrbConfig(
        liquidColor: SIMD3<Float>(1.0, 0.15, 0.15),  // Bright red
        liquidIntensity: 1.0,
        animationSpeed: 1.2,
        glowIntensity: 0.35,
        pulseRate: 0.3,       // Gentle pulse when live
        rimSpinSpeed: 0.0     // No spinning when live
    )
    
    static let goLiveStopping = BubblyOrbConfig(
        liquidColor: SIMD3<Float>(0.5, 0.3, 0.3),  // Fading red/gray
        liquidIntensity: 0.6,
        animationSpeed: 0.5,
        glowIntensity: 0.05,
        pulseRate: 0.0,
        rimSpinSpeed: 0.0
    )
}

// MARK: - Touch State

struct TouchState {
    var position: SIMD2<Float> = .zero
    var targetStrength: Float = 0
    var currentStrength: Float = 0
    var velocity: Float = 0
}

// MARK: - BubblyOrbView

class BubblyOrbView: MTKView {
    
    private var commandQueue: MTLCommandQueue!
    private var renderPipeline: MTLRenderPipelineState!
    private var uniformsBuffer: MTLBuffer!
    
    private var startTime: CFTimeInterval = 0
    private var lastUpdateTime: CFTimeInterval = 0
    private var birthStartTime: CFTimeInterval?  // nil = waiting to start birth animation
    
    // Touch handling
    private var touchStates: [TouchState] = Array(repeating: TouchState(), count: 5)
    private var activeTouches: [UITouch: Int] = [:]
    
    // Physics - tuned for quick tap response
    private let springStiffness: Float = 80.0   // Much higher = instant response to taps
    private let springDamping: Float = 8.0      // Balanced damping
    
    // Wobble effect
    private var wobbleDecay: Float = 0
    private var wobbleCenter: SIMD2<Float> = .zero
    
    // Configuration
    var deformAmount: Float = 1.5  // Increased for more visible squish
    var config: BubblyOrbConfig = .default
    
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
            print("BubblyOrbView: No Metal device")
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
              let vertexFunc = library.makeFunction(name: "bubblyOrbVertex"),
              let fragmentFunc = library.makeFunction(name: "bubblyOrbFragment") else {
            print("BubblyOrbView: Failed to load shaders")
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
            print("BubblyOrbView: Pipeline error: \(error)")
            return
        }
        
        // Uniforms buffer
        uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<BubblyOrbUniforms>.stride,
            options: .storageModeShared
        )
        
        startTime = CACurrentMediaTime()
        lastUpdateTime = startTime
        birthStartTime = nil  // Don't start birth animation until triggered
        
        delegate = self
    }
    
    // MARK: - Birth Animation Control
    
    /// Call this to trigger the birth animation (e.g., after splash screen disappears)
    func triggerBirthAnimation() {
        birthStartTime = CACurrentMediaTime()
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // Find free slot
            if let freeIndex = (0..<5).first(where: { touchStates[$0].targetStrength == 0 && !activeTouches.values.contains($0) }) {
                activeTouches[touch] = freeIndex
                let pos = normalizedTouchPosition(touch)
                touchStates[freeIndex].position = pos
                touchStates[freeIndex].targetStrength = 1.0
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let index = activeTouches[touch] {
                touchStates[index].position = normalizedTouchPosition(touch)
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let index = activeTouches[touch] {
                touchStates[index].targetStrength = 0
                
                // Trigger wobble from release point - stronger for taps
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
        // Convert to [-1, 1] range, centered
        let x = Float(loc.x / bounds.width) * 2.0 - 1.0
        let y = 1.0 - Float(loc.y / bounds.height) * 2.0
        // Account for aspect ratio
        let aspect = Float(bounds.width / bounds.height)
        return SIMD2<Float>(x * aspect, y)
    }
    
    // MARK: - Physics Update
    
    private func updatePhysics(deltaTime: Float) {
        let dt = min(deltaTime, 0.033)  // Cap at ~30fps for stability
        
        for i in 0..<5 {
            // Spring physics for smooth touch response
            let displacement = touchStates[i].targetStrength - touchStates[i].currentStrength
            let springForce = displacement * springStiffness
            let dampingForce = touchStates[i].velocity * springDamping
            
            touchStates[i].velocity += (springForce - dampingForce) * dt
            touchStates[i].currentStrength += touchStates[i].velocity * dt
            
            // Clamp
            touchStates[i].currentStrength = max(0, min(1, touchStates[i].currentStrength))
        }
        
        // Decay wobble - moderate decay
        wobbleDecay *= (1.0 - dt * 3.0)
        if wobbleDecay < 0.01 {
            wobbleDecay = 0
        }
    }
}

// MARK: - MTKViewDelegate

extension BubblyOrbView: MTKViewDelegate {
    
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
        
        // Calculate birth progress (0.8 second intro animation with overshoot)
        // If birthStartTime is nil, orb is invisible (birthProgress = 0)
        let birthDuration: Float = 0.8
        let birthProgress: Float
        if let birthStart = birthStartTime {
            birthProgress = min(Float(currentTime - birthStart) / birthDuration, 1.0)
        } else {
            birthProgress = 0.0  // Not yet born - invisible
        }
        
        // Update uniforms
        var uniforms = BubblyOrbUniforms(
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
            deformAmount: deformAmount,
            wobbleDecay: wobbleDecay,
            wobbleCenter: wobbleCenter,
            birthProgress: birthProgress,
            liquidColor: config.liquidColor,
            liquidIntensity: config.liquidIntensity,
            animationSpeed: config.animationSpeed,
            glowIntensity: config.glowIntensity,
            pulseRate: config.pulseRate,
            rimSpinSpeed: config.rimSpinSpeed
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

struct BubblyOrbSwiftUIView: UIViewRepresentable {
    var deformAmount: Float = 1.0
    
    func makeUIView(context: Context) -> BubblyOrbView {
        let view = BubblyOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.deformAmount = deformAmount
        return view
    }
    
    func updateUIView(_ uiView: BubblyOrbView, context: Context) {
        uiView.deformAmount = deformAmount
    }
}

// MARK: - Preview

#if DEBUG
struct BubblyOrbView_Previews: PreviewProvider {
    static var previews: some View {
        BubblyOrbSwiftUIView()
            .frame(width: 300, height: 300)
            .previewLayout(.sizeThatFits)
    }
}
#endif
