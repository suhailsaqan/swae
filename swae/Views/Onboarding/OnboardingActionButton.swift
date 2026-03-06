//
//  OnboardingActionButton.swift
//  swae
//
//  Primary action button with gradient and animation for onboarding
//

import UIKit

final class OnboardingActionButton: UIButton {
    
    // MARK: - Properties
    var accentColor: UIColor = .editProfilePurple {
        didSet { updateAppearance() }
    }
    
    var isLoading: Bool = false {
        didSet { updateLoadingState() }
    }
    
    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }
    
    private let gradientLayer = CAGradientLayer()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var originalTitle: String?
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
    
    // MARK: - Setup
    private func setupUI() {
        layer.cornerRadius = 12
        clipsToBounds = true
        
        // Gradient layer
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)
        
        // Title
        titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        setTitleColor(.white, for: .normal)
        setTitleColor(.white.withAlphaComponent(0.7), for: .disabled)
        
        // Activity indicator
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 52),
        ])
        
        updateAppearance()
        
        // Touch feedback
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    // MARK: - Appearance
    private func updateAppearance() {
        if isEnabled {
            gradientLayer.colors = [
                accentColor.cgColor,
                accentColor.withAlphaComponent(0.8).cgColor
            ]
            
            // Add shadow
            layer.shadowColor = accentColor.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 4)
            layer.shadowRadius = 12
            layer.shadowOpacity = 0.3
        } else {
            gradientLayer.colors = [
                UIColor.systemGray.cgColor,
                UIColor.systemGray.cgColor
            ]
            
            layer.shadowOpacity = 0
        }
    }
    
    private func updateLoadingState() {
        if isLoading {
            originalTitle = title(for: .normal)
            setTitle("", for: .normal)
            activityIndicator.startAnimating()
            isUserInteractionEnabled = false
        } else {
            setTitle(originalTitle, for: .normal)
            activityIndicator.stopAnimating()
            isUserInteractionEnabled = true
        }
    }
    
    // MARK: - Touch Feedback
    @objc private func touchDown() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
    }
    
    @objc private func touchUp() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.transform = .identity
        }
    }
    
    // MARK: - Convenience
    func setTitle(_ title: String) {
        setTitle(title, for: .normal)
        originalTitle = title
    }
}
