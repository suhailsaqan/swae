//
//  OnboardingProgressBar.swift
//  swae
//
//  Animated progress bar for onboarding steps
//

import UIKit

final class OnboardingProgressBar: UIView {
    
    // MARK: - Properties
    var totalSteps: Int = 3 {
        didSet { updateProgress(animated: false) }
    }
    
    var currentStep: Int = 0 {
        didSet { updateProgress(animated: true) }
    }
    
    // MARK: - UI Components
    private let trackView = UIView()
    private let fillView = UIView()
    private var fillWidthConstraint: NSLayoutConstraint?
    
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
        // Track (background)
        trackView.backgroundColor = UIColor.systemGray5
        trackView.layer.cornerRadius = 2
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)
        
        // Fill (progress)
        fillView.backgroundColor = .editProfilePurple
        fillView.layer.cornerRadius = 2
        fillView.translatesAutoresizingMaskIntoConstraints = false
        trackView.addSubview(fillView)
        
        let fillWidth = fillView.widthAnchor.constraint(equalToConstant: 0)
        fillWidthConstraint = fillWidth
        
        NSLayoutConstraint.activate([
            trackView.topAnchor.constraint(equalTo: topAnchor),
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            trackView.heightAnchor.constraint(equalToConstant: 4),
            
            fillView.topAnchor.constraint(equalTo: trackView.topAnchor),
            fillView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            fillView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor),
            fillWidth,
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateProgress(animated: false)
    }
    
    // MARK: - Update Progress
    private func updateProgress(animated: Bool) {
        guard totalSteps > 0 else { return }
        
        let progress = CGFloat(currentStep + 1) / CGFloat(totalSteps)
        let newWidth = bounds.width * progress
        
        fillWidthConstraint?.constant = newWidth
        
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5,
                options: .allowUserInteraction
            ) {
                self.layoutIfNeeded()
            }
        } else {
            layoutIfNeeded()
        }
    }
}
