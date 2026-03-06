//
//  ZapPlasmaEffect.swift
//  swae
//
//  Real-time video shader that visualizes incoming Bitcoin Lightning payments (zaps)
//  during a live stream. Plasma tendrils converge on the streamer's face.
//

import AVFoundation
import AVFAudio
import CoreImage
import MetalPetal
import Vision

struct ZapAnimation {
    let id: UUID
    let amount: Int64                    // Zap amount in millisats
    let startTime: Double                // CACurrentMediaTime() when triggered
    let duration: Double                 // How long the animation lasts
    let tendrilOrigins: [SIMD2<Float>]   // 2-4 random edge points
    let intensity: Float                 // Calculated from amount
    var faceCenter: CGPoint?             // Updated each frame if face detected
    
    var progress: Float {
        let elapsed = CACurrentMediaTime() - startTime
        return Float(min(elapsed / duration, 1.0))
    }
    
    var isComplete: Bool {
        return progress >= 1.0
    }
    
    static func calculateIntensity(amount: Int64, multiplier: Float) -> Float {
        // amount is in millisats, convert to sats for calculation
        let sats = Float(amount) / 1000.0
        
        if sats < 1000 {
            return 0.3 * multiplier
        } else if sats < 10000 {
            return 0.6 * multiplier
        } else if sats < 100000 {
            return 0.85 * multiplier
        } else {
            return 1.0 * multiplier
        }
    }
    
    static func calculateDuration(amount: Int64) -> Double {
        let sats = Float(amount) / 1000.0
        
        if sats < 1000 {
            return 1.5
        } else if sats < 10000 {
            return 2.0
        } else if sats < 100000 {
            return 2.5
        } else {
            return 3.0
        }
    }
    
    static func generateTendrilOrigins(count: Int = 3) -> [SIMD2<Float>] {
        // Generate random points along screen edges
        var origins: [SIMD2<Float>] = []
        
        for _ in 0..<count {
            let edge = Int.random(in: 0...3) // 0=top, 1=right, 2=bottom, 3=left
            let position = Float.random(in: 0.2...0.8) // Avoid corners
            
            let origin: SIMD2<Float>
            switch edge {
            case 0: origin = SIMD2<Float>(position * 2 - 1, 1.0)   // Top
            case 1: origin = SIMD2<Float>(1.0, position * 2 - 1)   // Right
            case 2: origin = SIMD2<Float>(position * 2 - 1, -1.0)  // Bottom
            default: origin = SIMD2<Float>(-1.0, position * 2 - 1) // Left
            }
            
            origins.append(origin)
        }
        
        return origins
    }
}

final class ZapPlasmaEffect: VideoEffect {
    // MARK: - Properties
    
    private var activeAnimations: [ZapAnimation] = []
    private var lastKnownFaceCenter: CGPoint?
    private var intensityMultiplier: Float = 1.0
    private var minimumAmount: Int64 = 0
    private var isEnabled: Bool = true
    private var colorPreset: ZapPlasmaColorPreset = .orange
    
    // Sound properties
    private var soundEnabled: Bool = true
    private var soundVolume: Float = 0.7
    private var audioPlayer: AVAudioPlayer?
    private var lastSoundPlayTime: Double = 0
    private let minimumSoundInterval: Double = 0.3
    
    // Time tracking for shader animation
    private var startTime: Double = CACurrentMediaTime()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Configuration
    
    func setSettings(
        enabled: Bool,
        intensityMultiplier: Float,
        minimumAmount: Int64,
        colorPreset: ZapPlasmaColorPreset = .orange,
        soundEnabled: Bool = true,
        soundVolume: Float = 0.7
    ) {
        processorPipelineQueue.async {
            self.isEnabled = enabled
            self.intensityMultiplier = intensityMultiplier
            self.minimumAmount = minimumAmount
            self.colorPreset = colorPreset
            self.soundEnabled = soundEnabled
            self.soundVolume = soundVolume
        }
    }
    
    // MARK: - Zap Triggering
    
    func triggerZap(amount: Int64) {
        guard isEnabled else { return }
        guard amount >= minimumAmount else { return }
        
        let tendrilCount = amount > 10_000_000 ? 4 : (amount > 1_000_000 ? 3 : 2)
        
        let animation = ZapAnimation(
            id: UUID(),
            amount: amount,
            startTime: CACurrentMediaTime(),
            duration: ZapAnimation.calculateDuration(amount: amount),
            tendrilOrigins: ZapAnimation.generateTendrilOrigins(count: tendrilCount),
            intensity: ZapAnimation.calculateIntensity(amount: amount, multiplier: intensityMultiplier),
            faceCenter: lastKnownFaceCenter
        )
        
        processorPipelineQueue.async {
            self.activeAnimations.append(animation)
        }
        
        // Play sound effect
        playZapSound(intensity: ZapAnimation.calculateIntensity(amount: amount, multiplier: intensityMultiplier))
    }
    
    private func playZapSound(intensity: Float) {
        guard soundEnabled else { return }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastSoundPlayTime > minimumSoundInterval else { return }
        lastSoundPlayTime = currentTime
        
        DispatchQueue.main.async {
            guard let url = Bundle.main.url(forResource: "zap_electric", withExtension: "mp3") else {
                return
            }
            
            do {
                self.audioPlayer = try AVAudioPlayer(contentsOf: url)
                self.audioPlayer?.volume = self.soundVolume * intensity
                self.audioPlayer?.play()
            } catch {
                // Sound file not found or couldn't play - silently fail
            }
        }
    }
    
    // MARK: - VideoEffect Overrides
    
    override func getName() -> String {
        return "zap plasma"
    }
    
    override func needsFaceDetections(_ presentationTimeStamp: Double) -> VideoEffectDetectionsMode {
        // Only request face detection when we have active animations
        if !activeAnimations.isEmpty {
            return .interval(nil, 0.1)
        } else {
            return .off
        }
    }

    
    override func execute(_ image: CIImage, _ info: VideoEffectInfo) -> CIImage {
        // Early exit - zero cost when no active animations
        guard !activeAnimations.isEmpty else {
            return image
        }
        
        // Remove completed animations
        activeAnimations.removeAll { $0.isComplete }
        
        // If all animations just completed, return original
        guard !activeAnimations.isEmpty else {
            return image
        }
        
        // Update face center if detection available
        if let faceDetections = info.sceneFaceDetections(),
           let face = faceDetections.first {
            let bounds = face.boundingBox
            let centerX = bounds.midX * image.extent.width
            let centerY = bounds.midY * image.extent.height
            lastKnownFaceCenter = CGPoint(x: centerX, y: centerY)
            
            // Update all active animations with new face position
            for i in 0..<activeAnimations.count {
                activeAnimations[i].faceCenter = lastKnownFaceCenter
            }
        }
        
        // Apply plasma effect using CIFilter chain
        return applyPlasmaEffect(to: image)
    }
    
    override func executeMetalPetal(_ image: MTIImage?, _ info: VideoEffectInfo) -> MTIImage? {
        guard let image = image else { return nil }
        
        // Early exit - zero cost when no active animations
        guard !activeAnimations.isEmpty else {
            return image
        }
        
        // Remove completed animations
        activeAnimations.removeAll { $0.isComplete }
        
        guard !activeAnimations.isEmpty else {
            return image
        }
        
        // Update face center if detection available
        if let faceDetections = info.sceneFaceDetections(),
           let face = faceDetections.first {
            let bounds = face.boundingBox
            let centerX = bounds.midX * image.extent.width
            let centerY = bounds.midY * image.extent.height
            lastKnownFaceCenter = CGPoint(x: centerX, y: centerY)
            
            for i in 0..<activeAnimations.count {
                activeAnimations[i].faceCenter = lastKnownFaceCenter
            }
        }
        
        // Apply plasma effect using MetalPetal
        return applyPlasmaEffectMetalPetal(to: image)
    }
    
    // MARK: - Plasma Rendering (CIFilter)
    
    private func applyPlasmaEffect(to image: CIImage) -> CIImage {
        var outputImage = image
        let currentTime = Float(CACurrentMediaTime() - startTime)
        
        // Calculate combined effect parameters from all active animations
        var totalIntensity: Float = 0
        var combinedProgress: Float = 0
        
        for animation in activeAnimations {
            totalIntensity += animation.intensity * (1.0 - animation.progress)
            combinedProgress = max(combinedProgress, animation.progress)
        }
        
        totalIntensity = min(totalIntensity, 1.5) // Cap combined intensity
        
        // Determine target point (face center or screen center)
        let targetPoint: CGPoint
        if let faceCenter = lastKnownFaceCenter {
            targetPoint = faceCenter
        } else {
            targetPoint = CGPoint(
                x: image.extent.width / 2,
                y: image.extent.height / 2
            )
        }
        
        // Apply chromatic aberration based on intensity
        if totalIntensity > 0.1 {
            outputImage = applyChromaAberration(
                to: outputImage,
                intensity: totalIntensity,
                time: currentTime
            )
        }
        
        // Apply radial glow toward face/center
        outputImage = applyRadialGlow(
            to: outputImage,
            targetPoint: targetPoint,
            intensity: totalIntensity,
            progress: combinedProgress
        )
        
        // Apply tendril effects
        outputImage = applyTendrilEffects(
            to: outputImage,
            targetPoint: targetPoint,
            intensity: totalIntensity,
            time: currentTime
        )
        
        return outputImage
    }
    
    private func applyChromaAberration(to image: CIImage, intensity: Float, time: Float) -> CIImage {
        let aberrationAmount = Double(intensity) * 4.0
        
        // Pulsing aberration
        let pulse = Double(1.0 + sin(time * 8.0) * 0.3)
        let finalAberration = aberrationAmount * pulse
        
        // Create color channel shifts
        guard let redShifted = image.applyingFilter("CIAffineTransform", parameters: [
            "inputTransform": NSValue(cgAffineTransform: CGAffineTransform(translationX: finalAberration, y: 0))
        ]).cropped(to: image.extent).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]) as CIImage? else {
            return image
        }
        
        guard let blueShifted = image.applyingFilter("CIAffineTransform", parameters: [
            "inputTransform": NSValue(cgAffineTransform: CGAffineTransform(translationX: -finalAberration, y: 0))
        ]).cropped(to: image.extent).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]) as CIImage? else {
            return image
        }
        
        // Extract green channel from original
        guard let greenOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]) as CIImage? else {
            return image
        }
        
        // Combine channels using additive blending
        let combined = redShifted
            .applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": greenOnly])
            .applyingFilter("CIAdditionCompositing", parameters: ["inputBackgroundImage": blueShifted])
        
        // Blend with original based on intensity
        let blendAmount = CGFloat(intensity) * 0.5
        return combined.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": image,
            "inputMaskImage": CIImage(color: CIColor(red: blendAmount, green: blendAmount, blue: blendAmount))
                .cropped(to: image.extent)
        ]).cropped(to: image.extent)
    }

    
    private func applyRadialGlow(to image: CIImage, targetPoint: CGPoint, intensity: Float, progress: Float) -> CIImage {
        // Fade out as animation progresses
        let fadeOut = 1.0 - smoothstep(0.7, 1.0, progress)
        let glowIntensity = CGFloat(intensity * fadeOut)
        
        guard glowIntensity > 0.05 else { return image }
        
        // Create radial gradient for glow
        let glowFilter = CIFilter.radialGradient()
        glowFilter.center = targetPoint
        glowFilter.radius0 = Float(min(image.extent.width, image.extent.height) * 0.05)
        glowFilter.radius1 = Float(min(image.extent.width, image.extent.height) * 0.4)
        
        // Use color preset for glow
        let coolColor = colorPreset.coolColor
        let hotColor = colorPreset.hotColor
        
        glowFilter.color0 = CIColor(
            red: CGFloat(hotColor.x),
            green: CGFloat(hotColor.y),
            blue: CGFloat(hotColor.z),
            alpha: glowIntensity * 0.5
        )
        glowFilter.color1 = CIColor(
            red: CGFloat(coolColor.x),
            green: CGFloat(coolColor.y),
            blue: CGFloat(coolColor.z),
            alpha: 0.0
        )
        
        guard let glowImage = glowFilter.outputImage?.cropped(to: image.extent) else {
            return image
        }
        
        // Use screen blend mode for glow effect
        return glowImage.applyingFilter("CIScreenBlendMode", parameters: [
            "inputBackgroundImage": image
        ]).cropped(to: image.extent)
    }
    
    private func applyTendrilEffects(to image: CIImage, targetPoint: CGPoint, intensity: Float, time: Float) -> CIImage {
        var outputImage = image
        
        for animation in activeAnimations {
            let progress = animation.progress
            let animIntensity = animation.intensity * (1.0 - progress)
            
            // Skip if too faint
            guard animIntensity > 0.1 else { continue }
            
            // For each tendril origin, create a line effect toward target
            for origin in animation.tendrilOrigins {
                outputImage = applyTendril(
                    to: outputImage,
                    from: origin,
                    to: targetPoint,
                    progress: progress,
                    intensity: animIntensity,
                    time: time
                )
            }
        }
        
        return outputImage
    }
    
    private func applyTendril(to image: CIImage, from origin: SIMD2<Float>, to target: CGPoint, progress: Float, intensity: Float, time: Float) -> CIImage {
        // Convert origin from clip space (-1 to 1) to image coordinates
        let originX = CGFloat((origin.x + 1) / 2) * image.extent.width
        let originY = CGFloat((origin.y + 1) / 2) * image.extent.height
        let originPoint = CGPoint(x: originX, y: originY)
        
        // Calculate current tendril head position (moves toward target over time)
        let currentX = originPoint.x + (target.x - originPoint.x) * CGFloat(progress)
        let currentY = originPoint.y + (target.y - originPoint.y) * CGFloat(progress)
        let currentPoint = CGPoint(x: currentX, y: currentY)
        
        // Create a bright spot at the tendril head (energy packet)
        let packetRadius = Float(min(image.extent.width, image.extent.height) * 0.03)
        let packetIntensity = CGFloat(intensity) * CGFloat(1.0 - progress)
        
        // Pulsing packet brightness
        let pulse = 0.7 + sin(time * 15.0) * 0.3
        
        // Use color preset
        let coolColor = colorPreset.coolColor
        let hotColor = colorPreset.hotColor
        
        let packetFilter = CIFilter.radialGradient()
        packetFilter.center = currentPoint
        packetFilter.radius0 = 0
        packetFilter.radius1 = packetRadius
        packetFilter.color0 = CIColor(
            red: CGFloat(hotColor.x),
            green: CGFloat(hotColor.y),
            blue: CGFloat(hotColor.z),
            alpha: packetIntensity * CGFloat(pulse)
        )
        packetFilter.color1 = CIColor(
            red: CGFloat(coolColor.x),
            green: CGFloat(coolColor.y),
            blue: CGFloat(coolColor.z),
            alpha: 0.0
        )
        
        guard let packetImage = packetFilter.outputImage?.cropped(to: image.extent) else {
            return image
        }
        
        // Add the packet glow to the image
        return packetImage.applyingFilter("CIAdditionCompositing", parameters: [
            "inputBackgroundImage": image
        ]).cropped(to: image.extent)
    }
    
    // MARK: - Plasma Rendering (MetalPetal)
    
    private func applyPlasmaEffectMetalPetal(to image: MTIImage) -> MTIImage {
        // For MetalPetal, we use a similar approach with MTI filters
        var outputImage = image
        let currentTime = Float(CACurrentMediaTime() - startTime)
        
        // Calculate combined effect parameters
        var totalIntensity: Float = 0
        var combinedProgress: Float = 0
        
        for animation in activeAnimations {
            totalIntensity += animation.intensity * (1.0 - animation.progress)
            combinedProgress = max(combinedProgress, animation.progress)
        }
        
        totalIntensity = min(totalIntensity, 1.5)
        
        // Determine target point
        let targetPoint: CGPoint
        if let faceCenter = lastKnownFaceCenter {
            targetPoint = faceCenter
        } else {
            targetPoint = CGPoint(
                x: image.extent.width / 2,
                y: image.extent.height / 2
            )
        }
        
        // Apply chromatic aberration using MTI
        if totalIntensity > 0.1 {
            outputImage = applyChromaAberrationMetalPetal(
                to: outputImage,
                intensity: totalIntensity,
                time: currentTime
            )
        }
        
        // Apply glow effect
        outputImage = applyRadialGlowMetalPetal(
            to: outputImage,
            targetPoint: targetPoint,
            intensity: totalIntensity,
            progress: combinedProgress
        )
        
        return outputImage
    }
    
    private func applyChromaAberrationMetalPetal(to image: MTIImage, intensity: Float, time: Float) -> MTIImage {
        // Simplified chromatic aberration for MetalPetal
        // Full implementation would use custom MTI kernel
        let aberrationAmount = intensity * 4.0
        let pulse = 1.0 + sin(time * 8.0) * 0.3
        let _ = aberrationAmount * pulse
        
        // For now, return original - full implementation requires custom shader
        return image
    }
    
    private func applyRadialGlowMetalPetal(to image: MTIImage, targetPoint: CGPoint, intensity: Float, progress: Float) -> MTIImage {
        let fadeOut = 1.0 - smoothstep(0.7, 1.0, progress)
        let glowIntensity = intensity * fadeOut
        
        guard glowIntensity > 0.05 else { return image }
        
        // Create glow overlay using MTI
        // For now, return original - full implementation requires custom shader
        return image
    }
    
    // MARK: - Utility Functions
    
    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = max(0, min((x - edge0) / (edge1 - edge0), 1))
        return t * t * (3 - 2 * t)
    }
}
