//
//  OnboardingPageIndicator.swift
//  swae
//
//  Animated page indicator dots for onboarding carousel
//

import UIKit

final class OnboardingPageIndicator: UIView {
    
    // MARK: - Properties
    var numberOfPages: Int = 4 {
        didSet { setupDots() }
    }
    
    var currentPage: Int = 0 {
        didSet { updateDots(animated: true) }
    }
    
    var activeColor: UIColor = .editProfilePurple {
        didSet { updateDots(animated: false) }
    }
    
    var inactiveColor: UIColor = .systemGray4 {
        didSet { updateDots(animated: false) }
    }
    
    private var dotViews: [UIView] = []
    private let dotStack = UIStackView()
    
    private let dotSize: CGFloat = 8
    private let activeDotWidth: CGFloat = 32
    private let dotSpacing: CGFloat = 8
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        dotStack.axis = .horizontal
        dotStack.spacing = dotSpacing
        dotStack.alignment = .center
        dotStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotStack)
        
        NSLayoutConstraint.activate([
            dotStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: dotSize + 16),
        ])
        
        setupDots()
    }
    
    private func setupDots() {
        // Remove existing dots
        dotViews.forEach { $0.removeFromSuperview() }
        dotViews.removeAll()
        
        // Create new dots
        for i in 0..<numberOfPages {
            let dot = UIView()
            dot.backgroundColor = i == currentPage ? activeColor : inactiveColor
            dot.layer.cornerRadius = dotSize / 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            
            let width = i == currentPage ? activeDotWidth : dotSize
            dot.widthAnchor.constraint(equalToConstant: width).isActive = true
            dot.heightAnchor.constraint(equalToConstant: dotSize).isActive = true
            
            // Make tappable
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dotTapped(_:)))
            dot.addGestureRecognizer(tapGesture)
            dot.isUserInteractionEnabled = true
            dot.tag = i
            
            dotStack.addArrangedSubview(dot)
            dotViews.append(dot)
        }
    }
    
    private func updateDots(animated: Bool) {
        guard dotViews.count == numberOfPages else { return }
        
        for (index, dot) in dotViews.enumerated() {
            let isActive = index == currentPage
            let targetWidth = isActive ? activeDotWidth : dotSize
            let targetColor = isActive ? activeColor : inactiveColor
            
            // Find and update width constraint
            if let widthConstraint = dot.constraints.first(where: { $0.firstAttribute == .width }) {
                widthConstraint.constant = targetWidth
            }
            
            if animated && !UIAccessibility.isReduceMotionEnabled {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0.5
                ) {
                    dot.backgroundColor = targetColor
                    self.layoutIfNeeded()
                }
            } else {
                dot.backgroundColor = targetColor
                layoutIfNeeded()
            }
        }
    }
    
    // MARK: - Actions
    @objc private func dotTapped(_ gesture: UITapGestureRecognizer) {
        guard let dot = gesture.view else { return }
        let index = dot.tag
        
        if index != currentPage {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            currentPage = index
            // Note: Parent view controller observes currentPage changes via didSet
        }
    }
}
