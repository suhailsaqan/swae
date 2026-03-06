//
//  ParticleRenderer.swift
//  swae
//
//  Metal renderer for compute-based particle system
//

import Metal
import MetalKit
import simd
import UIKit

class ParticleRenderer: NSObject {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let computePipeline: MTLComputePipelineState
    let renderPipeline: MTLRenderPipelineState
    
    var particleBuffer: MTLBuffer
    var uniformsBuffer: MTLBuffer
    
    let particleCount: Int
    var time: Float = 0
    
    // Touch state
    var touchPoint: SIMD2<Float> = SIMD2<Float>(0, 0)
    var isTouching: Bool = false
    
    // Physics parameters
    var repulsionRadius: Float = 0.30  // Touch influence radius in clip space
    var repulsionForce: Float = 2.0    // How far particles push out (0-10, higher = further)
    var springStiffness: Float = 10.0  // Movement speed (5-20, higher = faster transitions)
    var damping: Float = 2.0           // Falloff curve sharpness (1-4, higher = sharper edge)
    
    init?(particleCount: Int = 15000, maskImage: UIImage? = nil, sfSymbol: String? = nil, symbolSize: CGFloat = 200, startScattered: Bool = true) {
        self.particleCount = particleCount
        
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        // Create compute pipeline
        guard let library = device.makeDefaultLibrary(),
              let computeFunction = library.makeFunction(name: "computeUpdateParticles"),
              let computePipeline = try? device.makeComputePipelineState(function: computeFunction) else {
            return nil
        }
        self.computePipeline = computePipeline
        
        // Create render pipeline
        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.vertexFunction = library.makeFunction(name: "computeParticleVertex")
        renderDescriptor.fragmentFunction = library.makeFunction(name: "computeParticleFragment")
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        renderDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        guard let renderPipeline = try? device.makeRenderPipelineState(descriptor: renderDescriptor) else {
            return nil
        }
        self.renderPipeline = renderPipeline
        
        // Create buffers
        let particleBufferSize = MemoryLayout<Particle>.stride * particleCount
        guard let particleBuffer = device.makeBuffer(length: particleBufferSize, options: .storageModeShared) else {
            return nil
        }
        self.particleBuffer = particleBuffer
        
        let uniformsBufferSize = MemoryLayout<ParticleUniforms>.stride
        guard let uniformsBuffer = device.makeBuffer(length: uniformsBufferSize, options: .storageModeShared) else {
            return nil
        }
        self.uniformsBuffer = uniformsBuffer
        
        super.init()
        
        // Initialize particles
        if let sfSymbol = sfSymbol {
            initializeParticlesWithSFSymbol(symbolName: sfSymbol, size: symbolSize, startScattered: startScattered)
        } else {
            initializeParticles(maskImage: maskImage, startScattered: startScattered)
        }
    }
    
    func initializeParticlesWithSFSymbol(symbolName: String, size: CGFloat, color: SIMD4<Float> = SIMD4<Float>(0.4, 0.9, 0.8, 1.0), startScattered: Bool = true) {
        let targets = ParticlePattern.generateTargetsFromSFSymbol(
            symbolName: symbolName,
            size: size,
            particleCount: particleCount
        )
        
        let particles = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        
        for i in 0..<particleCount {
            var p = Particle()
            p.target = targets[i]
            
            if startScattered {
                // Start particles scattered around target for animation effect
                let angle = Float.random(in: 0..<(Float.pi * 2))
                let radius = Float.random(in: 0.1...0.3)
                p.position = p.target + SIMD2<Float>(cos(angle) * radius, sin(angle) * radius)
            } else {
                // Start particles at their target position
                p.position = p.target
            }
            
            p.velocity = SIMD2<Float>(0, 0)
            p.life = Float.random(in: 0...1)
            p.size = 5.0  // Smaller size for sand-like effect
            p.color = color
            
            particles[i] = p
        }
    }
    
    func initializeParticles(maskImage: UIImage?, color: SIMD4<Float> = SIMD4<Float>(0.4, 0.9, 0.8, 1.0), startScattered: Bool = true) {
        let targets = buildTargetsFromMask(count: particleCount, maskImage: maskImage)
        let particles = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        
        for i in 0..<particleCount {
            var p = Particle()
            p.target = targets[i]
            
            if startScattered {
                // Start particles scattered around target for animation effect
                let angle = Float.random(in: 0..<(Float.pi * 2))
                let radius = Float.random(in: 0.1...0.3)
                p.position = p.target + SIMD2<Float>(cos(angle) * radius, sin(angle) * radius)
            } else {
                // Start particles at their target position
                p.position = p.target
            }
            
            p.velocity = SIMD2<Float>(0, 0)
            p.life = Float.random(in: 0...1)
            p.size = 5.0  // Smaller size for sand-like effect
            p.color = color
            
            particles[i] = p
        }
    }
    
    func transitionToTargets(_ newTargets: [SIMD2<Float>]) {
        guard newTargets.count == particleCount else { return }
        
        let particles = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        
        for i in 0..<particleCount {
            particles[i].target = newTargets[i]
        }
    }
    
    func setParticleColor(_ color: SIMD4<Float>) {
        let particles = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        
        for i in 0..<particleCount {
            particles[i].color = color
        }
    }
    
    // Transition to new mask image
    func transitionToMask(maskImage: UIImage?) {
        let newTargets = buildTargetsFromMask(count: particleCount, maskImage: maskImage)
        transitionToTargets(newTargets)
    }
    
    func update(deltaTime: Float) {
        time += deltaTime
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        // Update uniforms
        var uniforms = ParticleUniforms(
            deltaTime: deltaTime,
            touchPoint: touchPoint,
            isTouching: isTouching ? 1.0 : 0.0,
            repulsionRadius: repulsionRadius,
            repulsionForce: repulsionForce,
            springStiffness: springStiffness,
            damping: damping,
            time: time
        )
        
        uniformsBuffer.contents().copyMemory(
            from: &uniforms,
            byteCount: MemoryLayout<ParticleUniforms>.stride
        )
        
        // Dispatch compute shader
        computeEncoder.setComputePipelineState(computePipeline)
        computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(uniformsBuffer, offset: 0, index: 1)
        
        let threadGroupSize = MTLSize(width: 256, height: 1, depth: 1)
        let threadGroups = MTLSize(
            width: (particleCount + 255) / 256,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
    }
    
    func draw(in view: MTKView, commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(renderPipeline)
        renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        renderEncoder.endEncoding()
    }
}

// MARK: - Mask Processing

extension ParticleRenderer {
    func buildTargetsFromMask(count: Int, maskImage: UIImage?) -> [SIMD2<Float>] {
        guard let mask = maskImage?.cgImage else {
            return buildCircleTargets(count: count)
        }
        
        let w = mask.width
        let h = mask.height
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return buildCircleTargets(count: count)
        }
        
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else {
            return buildCircleTargets(count: count)
        }
        
        var brightPixels: [SIMD2<Int>] = []
        let threshold: UInt8 = 40
        
        for y in 0..<h {
            for x in 0..<w {
                let idx = y * bytesPerRow + x * bytesPerPixel
                let r = data[idx]
                let g = data[idx + 1]
                let b = data[idx + 2]
                let lum = UInt8((UInt16(r) + UInt16(g) + UInt16(b)) / 3)
                
                if lum > threshold {
                    brightPixels.append(SIMD2<Int>(x, y))
                }
            }
        }
        
        if brightPixels.isEmpty {
            return buildCircleTargets(count: count)
        }
        
        var targets: [SIMD2<Float>] = []
        targets.reserveCapacity(count)
        
        if brightPixels.count >= count {
            var indices = Array(brightPixels.indices)
            indices.shuffle()
            
            for i in 0..<count {
                let px = brightPixels[indices[i]]
                targets.append(pixelToClipSpace(pixel: px, imgW: w, imgH: h))
            }
        } else {
            for i in 0..<count {
                let px = brightPixels[i % brightPixels.count]
                var p = pixelToClipSpace(pixel: px, imgW: w, imgH: h)
                p.x += Float.random(in: -0.01...0.01)
                p.y += Float.random(in: -0.01...0.01)
                targets.append(p)
            }
        }
        
        return targets
    }
    
    func pixelToClipSpace(pixel: SIMD2<Int>, imgW: Int, imgH: Int) -> SIMD2<Float> {
        let u = (Float(pixel.x) + 0.5) / Float(imgW)
        let v = (Float(pixel.y) + 0.5) / Float(imgH)
        
        var x = (u - 0.5) * 2.0
        var y = (0.5 - v) * 2.0
        
        let aspect = Float(imgW) / Float(imgH)
        if aspect > 1 {
            x /= aspect
        } else {
            y *= aspect
        }
        
        return SIMD2<Float>(x, y)
    }
    
    func buildCircleTargets(count: Int) -> [SIMD2<Float>] {
        var targets: [SIMD2<Float>] = []
        for i in 0..<count {
            let t = Float(i) / Float(count)
            let angle = t * .pi * 2
            let r = 0.6 + Float.random(in: -0.05...0.05)
            targets.append(SIMD2<Float>(cos(angle) * r, sin(angle) * r))
        }
        return targets
    }
}
