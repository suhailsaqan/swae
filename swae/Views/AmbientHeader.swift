//
//  AmbientHeader.swift
//  swae
//
//  Created by AI Assistant - Ambient blur header with dynamic colors
//

import UIKit

/// A beautiful header with dynamic blur that extracts colors from content
/// and creates an ambient, frosted-glass effect
final class AmbientHeader: UIView {

    // MARK: - UI Components

    private let blurContainerView = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let colorOverlay = UIView()
    private let colorGradientLayer = CAGradientLayer()

    private let contentStack = UIStackView()
    private let logoButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let liveIndicatorContainer = UIView()
    private let liveDot = UIView()
    private let liveCountLabel = UILabel()

    // MARK: - State

    private var dominantColors: [UIColor] = []
    private var headerHeightConstraint: NSLayoutConstraint?

    // MARK: - Callbacks

    var onSearchTapped: (() -> Void)?
    var onLogoTapped: (() -> Void)?
    var onLiveIndicatorTapped: (() -> Void)?

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
        backgroundColor = .clear

        // Blur container - creates frosted glass effect
        addSubview(blurContainerView)
        blurContainerView.translatesAutoresizingMaskIntoConstraints = false

        // Blur effect
        blurContainerView.addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false

        // Color overlay with gradient (extracted from content)
        colorOverlay.translatesAutoresizingMaskIntoConstraints = false
        blurContainerView.addSubview(colorOverlay)
        colorOverlay.layer.addSublayer(colorGradientLayer)
        colorOverlay.alpha = 0  // Start hidden, fade in when colors extracted

        // Content stack
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.distribution = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        // Logo button
        setupLogoButton()

        // Spacer
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Search button
        setupSearchButton()

        // Live indicator
        setupLiveIndicator()

        // Add to stack
        contentStack.addArrangedSubview(logoButton)
        contentStack.addArrangedSubview(spacer)
        contentStack.addArrangedSubview(searchButton)
        contentStack.addArrangedSubview(liveIndicatorContainer)

        // Constraints
        NSLayoutConstraint.activate([
            blurContainerView.topAnchor.constraint(equalTo: topAnchor),
            blurContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurView.topAnchor.constraint(equalTo: blurContainerView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: blurContainerView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: blurContainerView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: blurContainerView.bottomAnchor),

            colorOverlay.topAnchor.constraint(equalTo: blurContainerView.topAnchor),
            colorOverlay.leadingAnchor.constraint(equalTo: blurContainerView.leadingAnchor),
            colorOverlay.trailingAnchor.constraint(equalTo: blurContainerView.trailingAnchor),
            colorOverlay.bottomAnchor.constraint(equalTo: blurContainerView.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            contentStack.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupLogoButton() {
        // Create attributed string for logo with custom letter spacing
        let logoText = "swae"
        let attributedString = NSMutableAttributedString(string: logoText)
        attributedString.addAttribute(
            .kern, value: -0.5, range: NSRange(location: 0, length: logoText.count))

        logoButton.setAttributedTitle(attributedString, for: .normal)
        logoButton.titleLabel?.font = .systemFont(ofSize: 28, weight: .black)
        logoButton.setTitleColor(.label, for: .normal)
        logoButton.addTarget(self, action: #selector(logoButtonTapped), for: .touchUpInside)

        // Add subtle shadow for depth
        logoButton.titleLabel?.layer.shadowColor = UIColor.black.cgColor
        logoButton.titleLabel?.layer.shadowOffset = CGSize(width: 0, height: 1)
        logoButton.titleLabel?.layer.shadowRadius = 2
        logoButton.titleLabel?.layer.shadowOpacity = 0.3

        // Enable user interaction
        logoButton.isUserInteractionEnabled = true
    }

    private func setupSearchButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let searchImage = UIImage(systemName: "magnifyingglass", withConfiguration: config)

        searchButton.setImage(searchImage, for: .normal)
        searchButton.tintColor = .label
        searchButton.backgroundColor = UIColor.label.withAlphaComponent(0.1)
        searchButton.layer.cornerRadius = 12
        searchButton.addTarget(self, action: #selector(searchButtonTapped), for: .touchUpInside)

        // Add subtle hover effect
        searchButton.layer.shadowColor = UIColor.black.cgColor
        searchButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        searchButton.layer.shadowRadius = 4
        searchButton.layer.shadowOpacity = 0

        // Size constraints
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchButton.widthAnchor.constraint(equalToConstant: 40),
            searchButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func setupLiveIndicator() {
        liveIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        liveIndicatorContainer.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        liveIndicatorContainer.layer.cornerRadius = 12
        liveIndicatorContainer.clipsToBounds = false

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(
            target: self, action: #selector(liveIndicatorTapped))
        liveIndicatorContainer.addGestureRecognizer(tapGesture)
        liveIndicatorContainer.isUserInteractionEnabled = true

        // Pulsing red dot
        liveDot.backgroundColor = .white
        liveDot.layer.cornerRadius = 3
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        liveIndicatorContainer.addSubview(liveDot)

        // Live count label
        liveCountLabel.font = .systemFont(ofSize: 13, weight: .bold)
        liveCountLabel.textColor = .white
        liveCountLabel.text = "0"
        liveCountLabel.translatesAutoresizingMaskIntoConstraints = false
        liveIndicatorContainer.addSubview(liveCountLabel)

        NSLayoutConstraint.activate([
            liveIndicatorContainer.heightAnchor.constraint(equalToConstant: 28),

            liveDot.leadingAnchor.constraint(
                equalTo: liveIndicatorContainer.leadingAnchor, constant: 8),
            liveDot.centerYAnchor.constraint(equalTo: liveIndicatorContainer.centerYAnchor),
            liveDot.widthAnchor.constraint(equalToConstant: 6),
            liveDot.heightAnchor.constraint(equalToConstant: 6),

            liveCountLabel.leadingAnchor.constraint(equalTo: liveDot.trailingAnchor, constant: 6),
            liveCountLabel.trailingAnchor.constraint(
                equalTo: liveIndicatorContainer.trailingAnchor, constant: -8),
            liveCountLabel.centerYAnchor.constraint(equalTo: liveIndicatorContainer.centerYAnchor),
        ])

        // Start pulse animation
        startPulseAnimation()

        // Initially hidden
        liveIndicatorContainer.alpha = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        colorGradientLayer.frame = colorOverlay.bounds
    }

    // MARK: - Animations

    private func startPulseAnimation() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.3
        animation.duration = 1.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        liveDot.layer.add(animation, forKey: "pulse")
    }

    // MARK: - Public Methods

    func updateVisibility(percent: CGFloat) {
        // Fade out content as header hides (faster than transform)
        let alpha = 1.0 - (percent * 2.0)
        logoButton.alpha = max(0, alpha)
        searchButton.alpha = max(0, alpha)
        liveIndicatorContainer.alpha = liveIndicatorContainer.alpha > 0.1 ? max(0, alpha) : 0

        // Scale down buttons slightly for smoother effect
        let scale = 1.0 - (percent * 0.15)
        searchButton.transform = .init(scaleX: scale, y: scale)
        liveIndicatorContainer.transform = .init(scaleX: scale, y: scale)
    }

    func updateColors(from colors: [UIColor]) {
        self.dominantColors = colors

        guard !colors.isEmpty else { return }

        // Create beautiful gradient from extracted colors
        let gradientColors: [CGColor]
        if colors.count >= 2 {
            // Multiple colors: create rich, vibrant gradient
            gradientColors = [
                colors[0].withAlphaComponent(0.25).cgColor,
                colors[1].withAlphaComponent(0.35).cgColor,
            ]
        } else {
            // Single color: create variations
            let color = colors[0]
            gradientColors = [
                color.withAlphaComponent(0.2).cgColor,
                color.withAlphaComponent(0.35).cgColor,
            ]
        }

        colorGradientLayer.colors = gradientColors
        colorGradientLayer.locations = [0.0, 1.0]
        colorGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        colorGradientLayer.endPoint = CGPoint(x: 1, y: 1)

        // Smooth fade in
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut]) {
            self.colorOverlay.alpha = 1.0
        }
    }

    func setLiveCount(_ count: Int) {
        liveCountLabel.text = "\(count)"

        let shouldShow = count > 0
        let targetAlpha: CGFloat = shouldShow ? 1.0 : 0.0

        if liveIndicatorContainer.alpha != targetAlpha {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
                self.liveIndicatorContainer.alpha = targetAlpha
            }

            // Scale animation when appearing
            if shouldShow {
                liveIndicatorContainer.transform = .init(scaleX: 0.8, y: 0.8)
                UIView.animate(
                    withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6,
                    initialSpringVelocity: 0.5
                ) {
                    self.liveIndicatorContainer.transform = .identity
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func logoButtonTapped() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Scale animation
        UIView.animate(
            withDuration: 0.1,
            animations: {
                self.logoButton.transform = .init(scaleX: 0.95, y: 0.95)
            }
        ) { _ in
            UIView.animate(
                withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.5,
                initialSpringVelocity: 0.5
            ) {
                self.logoButton.transform = .identity
            }
        }

        onLogoTapped?()
    }

    @objc private func searchButtonTapped() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Scale animation with shadow
        UIView.animate(
            withDuration: 0.1,
            animations: {
                self.searchButton.transform = .init(scaleX: 0.9, y: 0.9)
                self.searchButton.layer.shadowOpacity = 0.2
            }
        ) { _ in
            UIView.animate(
                withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.6,
                initialSpringVelocity: 0.5
            ) {
                self.searchButton.transform = .identity
                self.searchButton.layer.shadowOpacity = 0
            }
        }

        onSearchTapped?()
    }

    @objc private func liveIndicatorTapped() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Bounce animation
        UIView.animate(
            withDuration: 0.1,
            animations: {
                self.liveIndicatorContainer.transform = .init(scaleX: 0.92, y: 0.92)
            }
        ) { _ in
            UIView.animate(
                withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8
            ) {
                self.liveIndicatorContainer.transform = .identity
            }
        }

        onLiveIndicatorTapped?()
    }
}




