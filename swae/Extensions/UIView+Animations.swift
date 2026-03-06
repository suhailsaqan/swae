//
//  UIView+Animations.swift
//  swae
//
//  Reusable animation helpers for Edit Profile and other views
//

import UIKit
import ObjectiveC

// MARK: - Animation Helpers
extension UIView {
    
    /// Adds a ripple effect from a tap point
    func addRippleEffect(at point: CGPoint, color: UIColor = .white) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        
        let rippleLayer = CAShapeLayer()
        rippleLayer.path = UIBezierPath(ovalIn: CGRect(x: -25, y: -25, width: 50, height: 50)).cgPath
        rippleLayer.fillColor = color.withAlphaComponent(0.3).cgColor
        rippleLayer.position = point
        layer.addSublayer(rippleLayer)
        
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.5
        scaleAnimation.toValue = 3.0
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.0
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, opacityAnimation]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            rippleLayer.removeFromSuperlayer()
        }
        rippleLayer.add(group, forKey: "ripple")
        CATransaction.commit()
    }
    
    /// Shake animation for validation errors
    func shake() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shake.values = [-8, 8, -6, 6, -4, 4, 0]
        shake.duration = 0.4
        layer.add(shake, forKey: "shake")
    }
    
    /// Pulse animation
    func startPulseAnimation(scale: CGFloat = 1.03, duration: TimeInterval = 0.8) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.repeat, .autoreverse, .allowUserInteraction]
        ) {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
    
    func stopPulseAnimation() {
        layer.removeAllAnimations()
        transform = .identity
    }
    
    /// Spring animation helper
    func animateSpring(
        duration: TimeInterval = 0.4,
        delay: TimeInterval = 0,
        damping: CGFloat = 0.7,
        velocity: CGFloat = 0.5,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, animations: animations, completion: completion)
        } else {
            UIView.animate(
                withDuration: duration,
                delay: delay,
                usingSpringWithDamping: damping,
                initialSpringVelocity: velocity,
                options: .allowUserInteraction,
                animations: animations,
                completion: completion
            )
        }
    }
    
    /// Fade in from bottom animation
    func fadeInFromBottom(delay: TimeInterval = 0, offset: CGFloat = 30) {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: offset)
        
        animateSpring(delay: delay) {
            self.alpha = 1
            self.transform = .identity
        }
    }
    
    /// Add shimmer loading effect
    func addShimmerEffect() -> CAGradientLayer {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.clear.cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.frame = bounds
        layer.addSublayer(gradientLayer)
        
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = 1.2
        animation.repeatCount = .infinity
        
        gradientLayer.add(animation, forKey: "shimmer")
        
        return gradientLayer
    }
}

// MARK: - Color Helpers
extension UIColor {
    
    static var editProfilePurple: UIColor {
        // Use app's primary accent purple #5500FF
        .accentPurple
    }
    
    static var editProfileAmber: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 251/255, green: 191/255, blue: 36/255, alpha: 1)  // #FBBF24
                : UIColor(red: 245/255, green: 158/255, blue: 11/255, alpha: 1)  // #F59E0B
        }
    }
    
    static var editProfileSuccess: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 52/255, green: 211/255, blue: 153/255, alpha: 1)  // #34D399
                : UIColor(red: 16/255, green: 185/255, blue: 129/255, alpha: 1)  // #10B981
        }
    }
    
    static var editProfileError: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 248/255, green: 113/255, blue: 113/255, alpha: 1) // #F87171
                : UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)   // #EF4444
        }
    }
}

// MARK: - Checkmark Drawing Layer
class CheckmarkLayer: CAShapeLayer {
    
    func configure(size: CGSize, color: UIColor = .white, lineWidth: CGFloat = 3) {
        let checkmarkPath = UIBezierPath()
        let padding: CGFloat = size.width * 0.25
        
        checkmarkPath.move(to: CGPoint(x: padding, y: size.height * 0.5))
        checkmarkPath.addLine(to: CGPoint(x: size.width * 0.4, y: size.height - padding))
        checkmarkPath.addLine(to: CGPoint(x: size.width - padding, y: padding))
        
        path = checkmarkPath.cgPath
        strokeColor = color.cgColor
        self.lineWidth = lineWidth
        lineCap = .round
        lineJoin = .round
        fillColor = nil
        strokeEnd = 0
    }
    
    func animateCheckmark(duration: TimeInterval = 0.3) {
        let drawAnimation = CABasicAnimation(keyPath: "strokeEnd")
        drawAnimation.fromValue = 0
        drawAnimation.toValue = 1
        drawAnimation.duration = duration
        drawAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        drawAnimation.fillMode = .forwards
        drawAnimation.isRemovedOnCompletion = false
        
        add(drawAnimation, forKey: "draw")
    }
}

// MARK: - Circular Shimmer Layer for Profile Pictures
/// A circular shimmer layer for profile picture loading states
final class CircularShimmerLayer: CAGradientLayer {
    
    private let shimmerAnimationKey = "circularShimmer"
    
    override init() {
        super.init()
        setupGradient()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGradient()
    }
    
    private func setupGradient() {
        // Use more visible shimmer colors - dark base with lighter highlight sweep
        let baseColor = UIColor.systemGray4.cgColor
        let highlightColor = UIColor.systemGray2.cgColor
        
        colors = [baseColor, highlightColor, baseColor]
        locations = [0, 0.5, 1]
        startPoint = CGPoint(x: 0, y: 0.5)
        endPoint = CGPoint(x: 1, y: 0.5)
    }
    
    func updateForTraitCollection() {
        let baseColor = UIColor.systemGray4.cgColor
        let highlightColor = UIColor.systemGray2.cgColor
        colors = [baseColor, highlightColor, baseColor]
    }
    
    func startAnimating() {
        guard animation(forKey: shimmerAnimationKey) == nil else { return }
        
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = 1.0
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        add(animation, forKey: shimmerAnimationKey)
    }
    
    func stopAnimating() {
        removeAnimation(forKey: shimmerAnimationKey)
    }
}

// MARK: - Profile Picture Shimmer Extension
extension UIImageView {
    
    private static var shimmerLayerKey: UInt8 = 0
    private static var shimmerSizeKey: UInt8 = 1
    
    /// The shimmer layer associated with this image view
    private var shimmerLayer: CircularShimmerLayer? {
        get { objc_getAssociatedObject(self, &Self.shimmerLayerKey) as? CircularShimmerLayer }
        set { objc_setAssociatedObject(self, &Self.shimmerLayerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// Stored size for shimmer (used when bounds aren't available yet)
    private var shimmerSize: CGSize? {
        get { objc_getAssociatedObject(self, &Self.shimmerSizeKey) as? CGSize }
        set { objc_setAssociatedObject(self, &Self.shimmerSizeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// Adds and starts a circular shimmer animation for profile picture loading
    /// - Parameter size: Optional explicit size. If nil, uses the view's bounds (or constraints if bounds are zero)
    func startProfilePicShimmer(size: CGSize? = nil) {
        // Don't add shimmer if image is already loaded
        guard image == nil else { return }
        
        // Determine the size to use
        let effectiveSize: CGSize
        if let size = size, size.width > 0 {
            effectiveSize = size
            shimmerSize = size
        } else if bounds.width > 0 {
            effectiveSize = bounds.size
        } else if let stored = shimmerSize, stored.width > 0 {
            effectiveSize = stored
        } else {
            // Default fallback for 24x24 profile pics in chat
            effectiveSize = CGSize(width: 24, height: 24)
        }
        
        // Reuse existing layer if present
        if let existingLayer = shimmerLayer {
            existingLayer.frame = CGRect(origin: .zero, size: effectiveSize)
            existingLayer.cornerRadius = effectiveSize.width / 2
            existingLayer.startAnimating()
            return
        }
        
        // Create new shimmer layer
        let shimmer = CircularShimmerLayer()
        shimmer.frame = CGRect(origin: .zero, size: effectiveSize)
        shimmer.cornerRadius = effectiveSize.width / 2
        shimmer.masksToBounds = true
        
        layer.addSublayer(shimmer)
        shimmerLayer = shimmer
        shimmer.startAnimating()
    }
    
    /// Stops and removes the shimmer animation
    func stopProfilePicShimmer() {
        shimmerLayer?.stopAnimating()
        shimmerLayer?.removeFromSuperlayer()
        shimmerLayer = nil
        shimmerSize = nil
    }
    
    /// Updates shimmer colors for trait collection changes
    func updateShimmerForTraitCollection() {
        shimmerLayer?.updateForTraitCollection()
    }
}
