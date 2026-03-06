//
//  ParticleMetalView.swift
//  swae
//
//  MTKView wrapper for particle system
//

import MetalKit
import SwiftUI

class ParticleMetalView: MTKView {
    var renderer: ParticleRenderer?
    var lastUpdateTime: CFTimeInterval = 0
    
    var sfSymbol: String?
    var symbolSize: CGFloat = 200
    var startScattered: Bool = true
    var particleCount: Int = 15000
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }
    
    convenience init(frame frameRect: CGRect, device: MTLDevice?, startScattered: Bool) {
        self.init(frame: frameRect, device: device)
        self.startScattered = startScattered
        // Re-setup with the correct startScattered value
        setup()
    }
    
    convenience init(frame frameRect: CGRect, device: MTLDevice?, config: ParticleConfig, startScattered: Bool = true) {
        self.init(frame: frameRect, device: device)
        self.startScattered = startScattered
        self.particleCount = config.particleCount
        setup()
        
        // Apply config to renderer after setup
        if let renderer = renderer {
            renderer.repulsionRadius = config.repulsionRadius
            renderer.repulsionForce = config.repulsionForce
            renderer.springStiffness = config.springStiffness
            renderer.damping = config.damping
        }
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    func setup() {
        guard let device = self.device else { return }
        
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = false
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.isOpaque = false
        self.backgroundColor = .clear
        
        // Initialize with SF Symbol if provided, otherwise try mask image
        if let sfSymbol = sfSymbol {
            renderer = ParticleRenderer(particleCount: particleCount, sfSymbol: sfSymbol, symbolSize: symbolSize, startScattered: startScattered)
        } else {
            let maskImage = UIImage(named: "mask3") // Add your mask image to assets
            renderer = ParticleRenderer(particleCount: particleCount, maskImage: maskImage, startScattered: startScattered)
        }
        
        self.delegate = self
        
        lastUpdateTime = CACurrentMediaTime()
    }
    
    func setupWithSFSymbol(_ symbolName: String, size: CGFloat = 200) {
        self.sfSymbol = symbolName
        self.symbolSize = size
        setup()
    }
    
    func updateTouch(location: CGPoint?, isTouching: Bool) {
        guard let renderer = renderer else { return }
        
        renderer.isTouching = isTouching
        
        if let location = location {
            // Convert touch location to clip space [-1, 1]
            let x = (location.x / bounds.width) * 2.0 - 1.0
            let y = 1.0 - (location.y / bounds.height) * 2.0
            renderer.touchPoint = SIMD2<Float>(Float(x), Float(y))
        }
    }
}

extension ParticleMetalView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
    func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = Float(currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        
        guard let renderer = renderer,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        // Update particle physics
        renderer.update(deltaTime: min(deltaTime, 0.033)) // Cap at ~30fps
        
        // Render particles
        renderer.draw(in: view, commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - SwiftUI Wrapper (Basic)

struct MetalParticleView: UIViewRepresentable {
    @Binding var touchLocation: CGPoint?
    @Binding var isTouching: Bool
    
    func makeUIView(context: Context) -> ParticleMetalView {
        let metalView = ParticleMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        
        // Add gesture recognizer
        let gesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        metalView.addGestureRecognizer(gesture)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        metalView.addGestureRecognizer(tapGesture)
        
        return metalView
    }
    
    func updateUIView(_ uiView: ParticleMetalView, context: Context) {
        uiView.updateTouch(location: touchLocation, isTouching: isTouching)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MetalParticleView
        
        init(_ parent: MetalParticleView) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            switch gesture.state {
            case .began, .changed:
                parent.touchLocation = location
                parent.isTouching = true
            case .ended, .cancelled:
                parent.isTouching = false
            default:
                break
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.touchLocation = location
            parent.isTouching = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.parent.isTouching = false
            }
        }
    }
}

// MARK: - SwiftUI Wrapper (With Coordinator & Config)

struct MetalParticleViewWithCoordinator: UIViewRepresentable {
    @Binding var touchLocation: CGPoint?
    @Binding var isTouching: Bool
    @Binding var metalView: ParticleMetalView?
    
    var config: ParticleConfig = .default
    
    func makeUIView(context: Context) -> ParticleMetalView {
        // Use config-based initializer to set particle count at creation time
        let view = ParticleMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice(), config: config)
        
        // Add gesture recognizers
        let gesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        view.addGestureRecognizer(gesture)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
        // Add long press for immediate touch response (fires on touch down)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.0  // Fire immediately on touch
        view.addGestureRecognizer(longPress)
        
        // Store reference
        DispatchQueue.main.async {
            self.metalView = view
        }
        
        return view
    }
    
    func updateUIView(_ uiView: ParticleMetalView, context: Context) {
        uiView.updateTouch(location: touchLocation, isTouching: isTouching)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MetalParticleViewWithCoordinator
        
        init(_ parent: MetalParticleViewWithCoordinator) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            switch gesture.state {
            case .began, .changed:
                parent.touchLocation = location
                parent.isTouching = true
            case .ended, .cancelled:
                parent.isTouching = false
            default:
                break
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.touchLocation = location
            parent.isTouching = true
            
            // Keep touch active longer so particles have time to visibly move away
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.parent.isTouching = false
            }
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            switch gesture.state {
            case .began, .changed:
                parent.touchLocation = location
                parent.isTouching = true
            case .ended, .cancelled:
                parent.isTouching = false
            default:
                break
            }
        }
    }
}
