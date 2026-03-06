//
//  ChaosLinesRenderer.swift
//  swae
//
//  Metal renderer for chaos lines effect
//

import Metal
import MetalKit
import simd

class ChaosLinesRenderer: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    var tapValue: Float = 0.0
    var tapLocation: SIMD2<Float> = SIMD2<Float>(0.5, 0.5)
    var randomSeed: Float = 0.0
    
    init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        super.init()
        
        buildPipeline()
    }
    
    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create Metal library")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: "chaosLinesVertex"),
              let fragmentFunction = library.makeFunction(name: "chaosLinesFragment") else {
            print("Failed to load shader functions")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }
    
    func render(to view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pipelineState = pipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Pass time, tap value, location, and random seed as uniforms
        let currentTime = Float(CACurrentMediaTime() - startTime)
        var uniforms = ChaosLinesUniforms(
            time: currentTime,
            tapValue: tapValue,
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            tapLocation: tapLocation,
            randomSeed: randomSeed
        )
        
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<ChaosLinesUniforms>.stride, index: 0)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<ChaosLinesUniforms>.stride, index: 0)
        
        // Draw full-screen quad
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func resetTime() {
        startTime = CACurrentMediaTime()
    }
}

struct ChaosLinesUniforms {
    var time: Float
    var tapValue: Float
    var resolution: SIMD2<Float>
    var tapLocation: SIMD2<Float>
    var randomSeed: Float
}
