//
//  MiniOrbButton.swift
//  swae
//
//  Small orb button for control bar (Mic, Flip, Torch)
//

import MetalKit
import UIKit

// MARK: - Mini Orb Type

enum MiniOrbType {
    case mic
    case flip
    case torch
    
    var icon: String {
        switch self {
        case .mic: return "mic.fill"
        case .flip: return "camera.rotate"
        case .torch: return "flashlight.on.fill"
        }
    }
    
    var onColor: SIMD3<Float> {
        switch self {
        case .mic: return SIMD3<Float>(0.2, 0.8, 0.4)    // Green
        case .flip: return SIMD3<Float>(0.3, 0.6, 1.0)   // Blue
        case .torch: return SIMD3<Float>(1.0, 0.8, 0.2)  // Yellow
        }
    }
    
    var offColor: SIMD3<Float> {
        return SIMD3<Float>(0.4, 0.4, 0.45)  // Gray
    }
}

// MARK: - MiniOrbButton

class MiniOrbButton: UIControl {
    
    // MARK: - Properties
    
    private let type: MiniOrbType
    private var isOn: Bool = false
    
    // Views
    private let orbView: MiniOrbMetalView
    private let iconView = UIImageView()
    
    // MARK: - Initialization
    
    init(type: MiniOrbType) {
        self.type = type
        self.orbView = MiniOrbMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundColor = .clear
        
        // Metal orb view
        orbView.translatesAutoresizingMaskIntoConstraints = false
        orbView.isUserInteractionEnabled = false
        orbView.setColor(type.offColor)
        addSubview(orbView)
        
        // Icon overlay
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconView.image = UIImage(systemName: type.icon, withConfiguration: config)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        
        NSLayoutConstraint.activate([
            orbView.topAnchor.constraint(equalTo: topAnchor),
            orbView.leadingAnchor.constraint(equalTo: leadingAnchor),
            orbView.trailingAnchor.constraint(equalTo: trailingAnchor),
            orbView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
        ])
        
        // Trigger birth animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.orbView.triggerBirthAnimation()
        }
    }
    
    // MARK: - State
    
    func setOn(_ on: Bool) {
        guard isOn != on else { return }
        isOn = on
        
        UIView.animate(withDuration: 0.2) {
            self.orbView.setColor(on ? self.type.onColor : self.type.offColor)
            self.iconView.tintColor = on ? .white : .white.withAlphaComponent(0.8)
        }
    }
    
    // MARK: - Touch Feedback
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.92, y: 0.92)
                    : .identity
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        orbView.simulateTouch(at: CGPoint(x: bounds.midX, y: bounds.midY), strength: 1.0)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        orbView.releaseTouch()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        orbView.releaseTouch()
    }
}

// MARK: - MiniOrbMetalView

class MiniOrbMetalView: MTKView {
    
    private var commandQueue: MTLCommandQueue!
    private var renderPipeline: MTLRenderPipelineState!
    private var uniformsBuffer: MTLBuffer!
    
    private var startTime: CFTimeInterval = 0
    private var birthStartTime: CFTimeInterval?
    
    private var liquidColor: SIMD3<Float> = SIMD3<Float>(0.4, 0.4, 0.45)
    private var targetColor: SIMD3<Float> = SIMD3<Float>(0.4, 0.4, 0.45)
    
    private var touchStrength: Float = 0
    private var targetTouchStrength: Float = 0
    
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
        
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isPaused = false
        enableSetNeedsDisplay = false
        isOpaque = false
        backgroundColor = .clear
        layer.isOpaque = false
        
        commandQueue = device.makeCommandQueue()
        
        guard let library = device.makeDefaultLibrary(),
              let vertexFunc = library.makeFunction(name: "bubblyOrbVertex"),
              let fragmentFunc = library.makeFunction(name: "bubblyOrbFragment") else {
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
        
        renderPipeline = try? device.makeRenderPipelineState(descriptor: pipelineDesc)
        uniformsBuffer = device.makeBuffer(
            length: MemoryLayout<BubblyOrbUniforms>.stride,
            options: .storageModeShared
        )
        
        startTime = CACurrentMediaTime()
        delegate = self
    }
    
    func triggerBirthAnimation() {
        birthStartTime = CACurrentMediaTime()
    }
    
    func setColor(_ color: SIMD3<Float>) {
        targetColor = color
    }
    
    func simulateTouch(at point: CGPoint, strength: Float) {
        targetTouchStrength = strength
    }
    
    func releaseTouch() {
        targetTouchStrength = 0
    }
}

extension MiniOrbMetalView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        let dt = Float(1.0 / 60.0)
        
        // Animate color
        liquidColor = liquidColor + (targetColor - liquidColor) * dt * 8.0
        
        // Animate touch
        touchStrength += (targetTouchStrength - touchStrength) * dt * 15.0
        
        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        let birthDuration: Float = 0.6
        let birthProgress: Float
        if let birthStart = birthStartTime {
            birthProgress = min(Float(currentTime - birthStart) / birthDuration, 1.0)
        } else {
            birthProgress = 0.0
        }
        
        var uniforms = BubblyOrbUniforms(
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            time: Float(currentTime - startTime),
            touchPoints: (.zero, .zero, .zero, .zero, .zero),
            touchStrengths: (touchStrength, 0, 0, 0, 0),
            activeTouchCount: touchStrength > 0.01 ? 1 : 0,
            deformAmount: 1.0,
            wobbleDecay: 0,
            wobbleCenter: .zero,
            birthProgress: birthProgress,
            liquidColor: liquidColor,
            liquidIntensity: 0.7,
            animationSpeed: 0.6,
            glowIntensity: 0.1,
            pulseRate: 0.05,
            rimSpinSpeed: 0
        )
        
        uniformsBuffer.contents().copyMemory(
            from: &uniforms,
            byteCount: MemoryLayout<BubblyOrbUniforms>.stride
        )
        
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
