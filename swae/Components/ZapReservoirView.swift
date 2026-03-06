//
//  ZapReservoirView.swift
//  swae
//
//  Liquid level indicator showing accumulated zap energy
//

import UIKit

class ZapReservoirView: UIView {
    
    // MARK: - Properties
    
    private let backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let fillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [
            UIColor(red: 1.0, green: 0.7, blue: 0.1, alpha: 1.0).cgColor,
            UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1.0).cgColor,
            UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 1.0).cgColor,
        ]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }()
    
    private let shimmerLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.4).cgColor,
            UIColor.clear.cgColor,
        ]
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.locations = [0, 0.5, 1]
        return layer
    }()
    
    // Particle emitter for sparkles
    private let sparkleEmitter: CAEmitterLayer = {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.renderMode = .additive
        
        let cell = CAEmitterCell()
        cell.birthRate = 3
        cell.lifetime = 0.8
        cell.velocity = 20
        cell.velocityRange = 10
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi / 4
        cell.scale = 0.05
        cell.scaleRange = 0.02
        cell.alphaSpeed = -1.2
        cell.color = UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1.0).cgColor
        
        // Use a simple circle for the particle
        let size: CGFloat = 8
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()
        cell.contents = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
        UIGraphicsEndImageContext()
        
        emitter.emitterCells = [cell]
        return emitter
    }()
    
    private var fillWidthConstraint: NSLayoutConstraint?
    
    // State
    private var currentFillPercent: CGFloat = 0
    private var targetFillPercent: CGFloat = 0
    private var zapGoal: Int = 100_000  // Default goal: 100k sats
    private var currentZaps: Int = 0
    
    // Milestone callbacks
    var onMilestoneReached: ((Int) -> Void)?
    private var reachedMilestones: Set<Int> = []
    private let milestones = [1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000]
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Setup
    
    private func setup() {
        addSubview(backgroundView)
        addSubview(fillView)
        
        fillView.layer.addSublayer(gradientLayer)
        fillView.layer.addSublayer(shimmerLayer)
        fillView.layer.addSublayer(sparkleEmitter)
        
        // Constraints
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        fillWidthConstraint = fillView.widthAnchor.constraint(equalToConstant: 0)
        fillWidthConstraint?.isActive = true
        
        // Styling
        layer.cornerRadius = 4
        clipsToBounds = true
        backgroundView.layer.cornerRadius = 4
        fillView.layer.cornerRadius = 4
        
        // Start shimmer animation
        startShimmerAnimation()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        gradientLayer.frame = fillView.bounds
        shimmerLayer.frame = fillView.bounds
        
        // Position emitter at the fill edge
        sparkleEmitter.emitterPosition = CGPoint(x: fillView.bounds.width, y: bounds.height / 2)
        sparkleEmitter.emitterSize = CGSize(width: 1, height: bounds.height)
        
        // Update fill width
        updateFillWidth(animated: false)
    }
    
    // MARK: - Public Methods
    
    /// Set the zap goal (denominator for fill percentage)
    func setGoal(_ goal: Int) {
        zapGoal = max(goal, 1)
        updateFillPercent()
    }
    
    /// Update the current zap total
    func setZaps(_ zaps: Int, animated: Bool = true) {
        let previousZaps = currentZaps
        currentZaps = zaps
        
        // Check for milestones
        for milestone in milestones {
            if zaps >= milestone && previousZaps < milestone && !reachedMilestones.contains(milestone) {
                reachedMilestones.insert(milestone)
                onMilestoneReached?(milestone)
                triggerMilestoneEffect()
            }
        }
        
        updateFillPercent()
        updateFillWidth(animated: animated)
    }
    
    /// Add zaps (convenience method)
    func addZaps(_ amount: Int, animated: Bool = true) {
        setZaps(currentZaps + amount, animated: animated)
        
        // Splash effect at fill edge
        if animated {
            triggerSplashEffect()
        }
    }
    
    /// Reset the reservoir
    func reset() {
        currentZaps = 0
        reachedMilestones.removeAll()
        updateFillPercent()
        updateFillWidth(animated: true)
    }
    
    // MARK: - Private Methods
    
    private func updateFillPercent() {
        // Use logarithmic scale for better visualization
        // This makes small zaps visible while still showing progress to large goals
        if currentZaps <= 0 {
            targetFillPercent = 0
        } else {
            let logCurrent = log10(Double(currentZaps + 1))
            let logGoal = log10(Double(zapGoal + 1))
            targetFillPercent = CGFloat(min(logCurrent / logGoal, 1.0))
        }
    }
    
    private func updateFillWidth(animated: Bool) {
        let targetWidth = bounds.width * targetFillPercent
        
        if animated {
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                self.fillWidthConstraint?.constant = targetWidth
                self.layoutIfNeeded()
            }
        } else {
            fillWidthConstraint?.constant = targetWidth
        }
        
        currentFillPercent = targetFillPercent
        
        // Update sparkle emitter visibility
        sparkleEmitter.birthRate = targetFillPercent > 0.05 ? 3 : 0
    }
    
    private func startShimmerAnimation() {
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.3, -0.15, 0]
        animation.toValue = [1, 1.15, 1.3]
        animation.duration = 2.0
        animation.repeatCount = .infinity
        
        shimmerLayer.add(animation, forKey: "shimmer")
    }
    
    private func triggerSplashEffect() {
        // Brief burst of particles
        let originalBirthRate = sparkleEmitter.birthRate
        sparkleEmitter.birthRate = 20
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.sparkleEmitter.birthRate = originalBirthRate
        }
    }
    
    private func triggerMilestoneEffect() {
        // Flash the entire reservoir
        UIView.animate(withDuration: 0.1, animations: {
            self.fillView.alpha = 1.5  // Over-bright
        }) { _ in
            UIView.animate(withDuration: 0.3) {
                self.fillView.alpha = 1.0
            }
        }
        
        // Big particle burst
        sparkleEmitter.birthRate = 50
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sparkleEmitter.birthRate = 3
        }
    }
}

// MARK: - SwiftUI Wrapper

import SwiftUI

struct ZapReservoirSwiftUIView: UIViewRepresentable {
    var zaps: Int
    var goal: Int
    
    func makeUIView(context: Context) -> ZapReservoirView {
        let view = ZapReservoirView()
        view.setGoal(goal)
        view.setZaps(zaps, animated: false)
        return view
    }
    
    func updateUIView(_ uiView: ZapReservoirView, context: Context) {
        uiView.setGoal(goal)
        uiView.setZaps(zaps, animated: true)
    }
}

// MARK: - Preview

#if DEBUG
struct ZapReservoirView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ZapReservoirSwiftUIView(zaps: 0, goal: 100_000)
                .frame(height: 8)
            
            ZapReservoirSwiftUIView(zaps: 1_000, goal: 100_000)
                .frame(height: 8)
            
            ZapReservoirSwiftUIView(zaps: 10_000, goal: 100_000)
                .frame(height: 8)
            
            ZapReservoirSwiftUIView(zaps: 50_000, goal: 100_000)
                .frame(height: 8)
            
            ZapReservoirSwiftUIView(zaps: 100_000, goal: 100_000)
                .frame(height: 8)
        }
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
