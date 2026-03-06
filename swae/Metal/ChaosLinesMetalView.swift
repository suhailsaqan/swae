//
//  ChaosLinesMetalView.swift
//  swae
//
//  UIKit Metal view for chaos lines effect
//

import UIKit
import MetalKit

class ChaosLinesMetalView: MTKView {
    var renderer: ChaosLinesRenderer?
    private var tapAnimationStartTime: CFTimeInterval = 0
    private var isAnimatingTap = false
    
    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        setup()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        guard let device = device else {
            print("Metal device not available")
            return
        }
        
        backgroundColor = .clear
        isOpaque = false
        framebufferOnly = false
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = false
        
        renderer = ChaosLinesRenderer(device: device)
        delegate = self
    }
    
    func triggerTap(at location: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)) {
        tapAnimationStartTime = CACurrentMediaTime()
        isAnimatingTap = true
        renderer?.tapValue = 1.0
        renderer?.tapLocation = location
        
        // Generate random seed for variation
        renderer?.randomSeed = Float.random(in: 0...1000)
    }
    
    private func updateTapAnimation() {
        guard isAnimatingTap else { return }
        
        let elapsed = CACurrentMediaTime() - tapAnimationStartTime
        let duration = 0.6 // Duration in seconds
        
        if elapsed >= duration {
            renderer?.tapValue = 0.0
            isAnimatingTap = false
        } else {
            // Ease out animation
            let progress = Float(elapsed / duration)
            let eased = 1.0 - pow(1.0 - progress, 3.0) // Cubic ease out
            renderer?.tapValue = 1.0 - eased
        }
    }
}

extension ChaosLinesMetalView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed
    }
    
    func draw(in view: MTKView) {
        updateTapAnimation()
        renderer?.render(to: self)
    }
}
