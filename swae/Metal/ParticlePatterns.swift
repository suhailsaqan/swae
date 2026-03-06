//
//  ParticlePatterns.swift
//  swae
//
//  Predefined particle patterns for different states
//

import simd
import UIKit

enum ParticlePattern {
    case circle(radius: Float, thickness: Float)
    case ring(innerRadius: Float, outerRadius: Float)
    case spiral(rotations: Float, radius: Float)
    case wave(amplitude: Float, frequency: Float)
    case grid(rows: Int, cols: Int, spacing: Float)
    case random(bounds: Float)
    case heart
    case star(points: Int, innerRadius: Float, outerRadius: Float)
    case bolt
    case sfSymbol(name: String, size: CGFloat = 200)
}

extension ParticlePattern {
    func generateTargets(count: Int) -> [SIMD2<Float>] {
        var targets: [SIMD2<Float>] = []
        targets.reserveCapacity(count)
        
        switch self {
        case .circle(let radius, let thickness):
            for i in 0..<count {
                let t = Float(i) / Float(count)
                let angle = t * .pi * 2
                let r = radius + Float.random(in: -thickness...thickness)
                targets.append(SIMD2<Float>(cos(angle) * r, sin(angle) * r))
            }
            
        case .ring(let innerRadius, let outerRadius):
            for i in 0..<count {
                let t = Float(i) / Float(count)
                let angle = t * .pi * 2
                let r = Float.random(in: innerRadius...outerRadius)
                targets.append(SIMD2<Float>(cos(angle) * r, sin(angle) * r))
            }
            
        case .spiral(let rotations, let radius):
            for i in 0..<count {
                let t = Float(i) / Float(count)
                let angle = t * .pi * 2 * rotations
                let r = t * radius
                targets.append(SIMD2<Float>(cos(angle) * r, sin(angle) * r))
            }
            
        case .wave(let amplitude, let frequency):
            for i in 0..<count {
                let x = (Float(i) / Float(count)) * 2.0 - 1.0
                let y = sin(x * .pi * frequency) * amplitude
                targets.append(SIMD2<Float>(x, y))
            }
            
        case .grid(let rows, let cols, let spacing):
            let totalCells = rows * cols
            for i in 0..<count {
                let cellIndex = i % totalCells
                let row = cellIndex / cols
                let col = cellIndex % cols
                
                let x = (Float(col) - Float(cols) / 2.0) * spacing
                let y = (Float(row) - Float(rows) / 2.0) * spacing
                
                targets.append(SIMD2<Float>(x, y))
            }
            
        case .random(let bounds):
            for _ in 0..<count {
                let x = Float.random(in: -bounds...bounds)
                let y = Float.random(in: -bounds...bounds)
                targets.append(SIMD2<Float>(x, y))
            }
            
        case .heart:
            for i in 0..<count {
                let t = Float(i) / Float(count) * .pi * 2
                let x = 16 * pow(sin(t), 3)
                let y = 13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)
                
                // Scale to fit [-1, 1]
                let scale: Float = 0.04
                targets.append(SIMD2<Float>(x * scale, -y * scale))
            }
            
        case .star(let points, let innerRadius, let outerRadius):
            for i in 0..<count {
                let t = Float(i) / Float(count)
                let angle = t * .pi * 2
                
                // Determine if this point is on inner or outer radius
                let pointAngle = angle * Float(points)
                let isOuter = Int(pointAngle / .pi) % 2 == 0
                let r = isOuter ? outerRadius : innerRadius
                
                targets.append(SIMD2<Float>(cos(angle) * r, sin(angle) * r))
            }
            
        case .bolt:
            // Lightning bolt as a single path from top to bottom with zigzags
            let boltPath: [SIMD2<Float>] = [
                SIMD2<Float>(0.0, 0.7),      // Top point
                SIMD2<Float>(-0.1, 0.4),     // Zig left
                SIMD2<Float>(0.05, 0.15),    // Zag right
                SIMD2<Float>(-0.08, -0.1),   // Zig left
                SIMD2<Float>(0.12, -0.35),   // Zag right
                SIMD2<Float>(0.0, -0.7)      // Bottom point
            ]
            
            // Calculate total path length for even distribution
            var segmentLengths: [Float] = []
            var totalLength: Float = 0
            for i in 0..<(boltPath.count - 1) {
                let length = distance(boltPath[i], boltPath[i + 1])
                segmentLengths.append(length)
                totalLength += length
            }
            
            // Distribute particles along the path
            for i in 0..<count {
                let t = Float(i) / Float(count)
                let targetDist = t * totalLength
                
                // Find which segment this particle belongs to
                var accumulatedDist: Float = 0
                var segmentIndex = 0
                var segmentT: Float = 0
                
                for (idx, length) in segmentLengths.enumerated() {
                    if accumulatedDist + length >= targetDist {
                        segmentIndex = idx
                        segmentT = (targetDist - accumulatedDist) / length
                        break
                    }
                    accumulatedDist += length
                }
                
                // Interpolate along the segment
                let p1 = boltPath[segmentIndex]
                let p2 = boltPath[segmentIndex + 1]
                let centerPoint = SIMD2<Float>(
                    p1.x + (p2.x - p1.x) * segmentT,
                    p1.y + (p2.y - p1.y) * segmentT
                )
                
                // Add thickness by offsetting perpendicular to the segment
                let direction = normalize(p2 - p1)
                let perpendicular = SIMD2<Float>(-direction.y, direction.x)
                let thickness: Float = 0.03
                let offset = perpendicular * Float.random(in: -thickness...thickness)
                
                targets.append(centerPoint + offset)
            }
            
        case .sfSymbol(let name, let size):
            // Render SF Symbol to image and sample particles from it
            let symbolTargets = ParticlePattern.generateTargetsFromSFSymbol(
                symbolName: name,
                size: size,
                particleCount: count
            )
            return symbolTargets
        }
        
        return targets
    }
    
    // MARK: - SF Symbol Support
    
    static func generateTargetsFromSFSymbol(
        symbolName: String,
        size: CGFloat,
        particleCount: Int
    ) -> [SIMD2<Float>] {
        guard let symbolImage = createSFSymbolImage(name: symbolName, size: size) else {
            return ParticlePattern.circle(radius: 0.5, thickness: 0.05).generateTargets(count: particleCount)
        }
        
        return sampleParticlesFromImage(symbolImage, count: particleCount)
    }
    
    private static func createSFSymbolImage(name: String, size: CGFloat) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .bold, scale: .large)
        guard let symbolImage = UIImage(systemName: name, withConfiguration: config) else {
            return nil
        }
        
        let canvasSize = CGSize(width: size * 2, height: size * 2)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        
        let renderedImage = renderer.image { context in
            let cgContext = context.cgContext
            
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: canvasSize))
            
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.setBlendMode(.normal)
            
            let symbolSize = symbolImage.size
            let drawRect = CGRect(
                x: (canvasSize.width - symbolSize.width) / 2,
                y: (canvasSize.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            
            symbolImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: drawRect)
        }
        
        return renderedImage
    }
    
    private static func sampleParticlesFromImage(_ image: UIImage, count: Int) -> [SIMD2<Float>] {
        guard let cgImage = image.cgImage else {
            return []
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return []
        }
        
        // Find all bright pixels (the symbol)
        var brightPixels: [(x: Int, y: Int)] = []
        let threshold: UInt8 = 128
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * bytesPerPixel
                let r = data[idx]
                let g = data[idx + 1]
                let b = data[idx + 2]
                let luminance = UInt8((UInt16(r) + UInt16(g) + UInt16(b)) / 3)
                
                if luminance > threshold {
                    brightPixels.append((x, y))
                }
            }
        }
        
        guard !brightPixels.isEmpty else {
            return []
        }
        
        // Sample particles from bright pixels
        var targets: [SIMD2<Float>] = []
        targets.reserveCapacity(count)
        
        if brightPixels.count >= count {
            // Randomly sample from available pixels
            var indices = Array(brightPixels.indices)
            indices.shuffle()
            
            for i in 0..<count {
                let pixel = brightPixels[indices[i]]
                targets.append(pixelToClipSpace(x: pixel.x, y: pixel.y, width: width, height: height))
            }
        } else {
            // Repeat pixels with slight jitter
            for i in 0..<count {
                let pixel = brightPixels[i % brightPixels.count]
                var point = pixelToClipSpace(x: pixel.x, y: pixel.y, width: width, height: height)
                // Add slight jitter
                point.x += Float.random(in: -0.005...0.005)
                point.y += Float.random(in: -0.005...0.005)
                targets.append(point)
            }
        }
        
        return targets
    }
    
    private static func pixelToClipSpace(x: Int, y: Int, width: Int, height: Int) -> SIMD2<Float> {
        // Convert pixel coordinates to normalized [0, 1]
        let u = (Float(x) + 0.5) / Float(width)
        let v = (Float(y) + 0.5) / Float(height)
        
        // Convert to clip space [-1, 1] with y-flip
        var clipX = (u - 0.5) * 2.0
        var clipY = (0.5 - v) * 2.0
        
        // Adjust for aspect ratio to maintain symbol proportions
        let aspect = Float(width) / Float(height)
        if aspect > 1 {
            clipX /= aspect
        } else {
            clipY *= aspect
        }
        
        return SIMD2<Float>(clipX, clipY)
    }
}

// MARK: - Voice Activity Patterns

extension ParticlePattern {
    static var idle: ParticlePattern {
        .circle(radius: 0.3, thickness: 0.05)
    }
    
    static var listening: ParticlePattern {
        .ring(innerRadius: 0.4, outerRadius: 0.5)
    }
    
    static var speaking: ParticlePattern {
        .ring(innerRadius: 0.5, outerRadius: 0.7)
    }
    
    static var question: ParticlePattern {
        .wave(amplitude: 0.3, frequency: 3.0)
    }
}

// MARK: - Convenience Extension

extension ParticleRenderer {
    func transitionToPattern(_ pattern: ParticlePattern) {
        let newTargets = pattern.generateTargets(count: particleCount)
        transitionToTargets(newTargets)
    }
    
    func transitionToSFSymbol(_ symbolName: String, size: CGFloat = 200) {
        transitionToPattern(.sfSymbol(name: symbolName, size: size))
    }
}
