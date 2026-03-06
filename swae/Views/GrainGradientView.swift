//
//  GrainGradientView.swift
//  swae
//
//  A UIView that renders an animated grain gradient using Metal
//

import UIKit
import MetalKit
import SwiftUI

final class GrainGradientView: UIView {
    
    // MARK: - Metal Resources
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var displayLink: CADisplayLink?
    
    // MARK: - Buffers
    private var uniformsBuffer: MTLBuffer!
    private var colorsBuffer: MTLBuffer!
    
    // MARK: - State
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var currentColors: [UIColor] = []
    private let gridSize: Int = 3
    private var grainStrength: Float = 2.0 // Very subtle grain for smooth blur-like appearance
    private var hasCustomColors = false
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupMetal()
        setupDisplayLink()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
        setupDisplayLink()
    }
    
    deinit {
        displayLink?.invalidate()
    }
    
    // MARK: - Setup
    
    private func setupMetal() {
        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal is not supported on this device")
            return
        }
        self.device = device
        
        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            print("❌ Failed to create command queue")
            return
        }
        self.commandQueue = commandQueue
        
        // Setup Metal layer
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = bounds
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.isOpaque = false  // Allow alpha compositing with views behind
        layer.addSublayer(metalLayer)
        
        // Create pipeline state
        setupPipeline()
        
        // Create buffers
        setupBuffers()
        
        // Set default colors (will be replaced when colors are extracted)
        setDefaultColors()
    }
    
    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("❌ Failed to create Metal library")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: "grainGradientVertex"),
              let fragmentFunction = library.makeFunction(name: "grainGradientFragment") else {
            print("❌ Failed to load shader functions")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat
        
        // Enable blending for smooth transitions
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Failed to create pipeline state: \(error)")
        }
    }
    
    private func setupBuffers() {
        // Create uniforms buffer
        let uniformsSize = MemoryLayout<GrainGradientUniforms>.stride
        uniformsBuffer = device.makeBuffer(length: uniformsSize, options: .storageModeShared)
        
        // Create colors buffer (3x3 grid = 9 colors)
        let colorsSize = MemoryLayout<SIMD4<Float>>.stride * 9
        colorsBuffer = device.makeBuffer(length: colorsSize, options: .storageModeShared)
    }
    
    private func setDefaultColors() {
        let isDarkMode = traitCollection.userInterfaceStyle == .dark

        let defaultColors: [UIColor]
        if isDarkMode {
            // Dark mode — low-alpha colors blend well over black
            defaultColors = [
                .systemIndigo.withAlphaComponent(0.4),
                .systemPurple.withAlphaComponent(0.45),
                UIColor.accentPurple.withAlphaComponent(0.5),
                .systemIndigo.withAlphaComponent(0.5),
                .systemPurple.withAlphaComponent(0.55),
                UIColor.accentPurple.withAlphaComponent(0.6),
                .systemIndigo.withAlphaComponent(0.6),
                .systemPurple.withAlphaComponent(0.65),
                UIColor.accentPurple.withAlphaComponent(0.7),
            ]
        } else {
            // Light mode — high-alpha so Metal doesn't darken by mixing with black clear color
            defaultColors = [
                .systemIndigo.withAlphaComponent(0.85),
                .systemPurple.withAlphaComponent(0.9),
                UIColor.accentPurple.withAlphaComponent(0.95),
                .systemIndigo.withAlphaComponent(0.9),
                .systemPurple.withAlphaComponent(0.95),
                UIColor.accentPurple.withAlphaComponent(1.0),
                .systemIndigo.withAlphaComponent(0.95),
                .systemPurple.withAlphaComponent(1.0),
                UIColor.accentPurple.withAlphaComponent(1.0),
            ]
        }

        currentColors = defaultColors
        let gridColors = arrangeColorsInGrid(defaultColors)
        guard let colorsBuffer = colorsBuffer else { return }
        let colorsPointer = colorsBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 9)
        for (index, color) in gridColors.enumerated() {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            colorsPointer[index] = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
        }
        // Don't set hasCustomColors — these are defaults
    }
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(render))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update Metal layer frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * UIScreen.main.scale,
            height: bounds.height * UIScreen.main.scale
        )
        CATransaction.commit()
    }
    
    // MARK: - Appearance
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // traitCollection is now reliable — update defaults if no custom colors yet
        if !hasCustomColors {
            setDefaultColors()
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
           !hasCustomColors {
            setDefaultColors()
        }
    }
    
    // MARK: - Public API
    
    /// Update the gradient colors with smooth transition
    func updateColors(_ colors: [UIColor], animated: Bool = true) {
        guard !colors.isEmpty else { return }
        
        currentColors = colors
        hasCustomColors = true
        
        // Arrange colors in 3x3 grid
        let gridColors = arrangeColorsInGrid(colors)
        
        // Convert to SIMD4<Float> and update buffer
        let colorsPointer = colorsBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 9)
        
        for (index, color) in gridColors.enumerated() {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            colorsPointer[index] = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
        }
    }
    
    /// Set grain strength (default: 16.0)
    func setGrainStrength(_ strength: Float) {
        grainStrength = strength
    }
    
    // MARK: - Color Arrangement
    
    private func arrangeColorsInGrid(_ colors: [UIColor]) -> [UIColor] {
        // Arrange extracted colors into a 3x3 grid
        // If we have fewer than 9 colors, interpolate or repeat
        
        var gridColors: [UIColor] = []
        
        if colors.count >= 9 {
            // Use first 9 colors
            gridColors = Array(colors.prefix(9))
        } else if colors.count >= 4 {
            // Arrange in corners and interpolate
            // TL, TC, TR
            // ML, MC, MR
            // BL, BC, BR
            let tl = colors[0]
            let tr = colors.count > 1 ? colors[1] : colors[0]
            let bl = colors.count > 2 ? colors[2] : colors[0]
            let br = colors.count > 3 ? colors[3] : colors[1]
            
            let tc = interpolateColor(tl, tr, factor: 0.5)
            let ml = interpolateColor(tl, bl, factor: 0.5)
            let mr = interpolateColor(tr, br, factor: 0.5)
            let bc = interpolateColor(bl, br, factor: 0.5)
            let mc = interpolateColor(interpolateColor(tl, br, factor: 0.5), 
                                     interpolateColor(tr, bl, factor: 0.5), 
                                     factor: 0.5)
            
            gridColors = [tl, tc, tr, ml, mc, mr, bl, bc, br]
        } else if colors.count >= 2 {
            // Create gradient from two colors
            let c1 = colors[0]
            let c2 = colors[1]
            
            gridColors = [
                c1,
                interpolateColor(c1, c2, factor: 0.33),
                interpolateColor(c1, c2, factor: 0.66),
                interpolateColor(c1, c2, factor: 0.25),
                interpolateColor(c1, c2, factor: 0.5),
                interpolateColor(c1, c2, factor: 0.75),
                interpolateColor(c1, c2, factor: 0.5),
                interpolateColor(c1, c2, factor: 0.75),
                c2
            ]
        } else {
            // Single color - create variations
            let baseColor = colors[0]
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            baseColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            
            gridColors = [
                UIColor(hue: h, saturation: s * 0.8, brightness: b * 0.9, alpha: a),
                UIColor(hue: h, saturation: s * 0.9, brightness: b * 0.95, alpha: a),
                UIColor(hue: h, saturation: s, brightness: b, alpha: a),
                UIColor(hue: h, saturation: s * 0.85, brightness: b * 0.92, alpha: a),
                baseColor,
                UIColor(hue: h, saturation: s * 1.1, brightness: b * 1.05, alpha: a),
                UIColor(hue: h, saturation: s * 0.9, brightness: b * 0.95, alpha: a),
                UIColor(hue: h, saturation: s * 1.05, brightness: b * 1.02, alpha: a),
                UIColor(hue: h, saturation: s * 1.2, brightness: b * 1.1, alpha: a),
            ]
        }
        
        return gridColors
    }
    
    private func interpolateColor(_ color1: UIColor, _ color2: UIColor, factor: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        return UIColor(
            red: r1 + (r2 - r1) * factor,
            green: g1 + (g2 - g1) * factor,
            blue: b1 + (b2 - b1) * factor,
            alpha: a1 + (a2 - a1) * factor
        )
    }
    
    // MARK: - Rendering
    
    @objc private func render() {
        autoreleasepool {
            guard let drawable = metalLayer.nextDrawable(),
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            
            // Update uniforms
            let currentTime = Float(CACurrentMediaTime() - startTime)
            var uniforms = GrainGradientUniforms(
                time: currentTime,
                gridSize: Int32(gridSize),
                colorCount: Int32(9),
                bounds: SIMD4<Float>(0, 0, Float(bounds.width), Float(bounds.height)),
                grainStrength: grainStrength
            )
            
            let uniformsPointer = uniformsBuffer.contents().bindMemory(
                to: GrainGradientUniforms.self, capacity: 1)
            uniformsPointer.pointee = uniforms
            
            // Setup render pass
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentBuffer(colorsBuffer, offset: 0, index: 1)
            
            // Draw full-screen quad (6 vertices)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// MARK: - Uniforms Structure

struct GrainGradientUniforms {
    var time: Float
    var gridSize: Int32
    var colorCount: Int32
    var bounds: SIMD4<Float>
    var grainStrength: Float
}
