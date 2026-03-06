//
//  StreamInfoRibbon.swift
//  swae
//
//  Liquid glass ribbon showing stream status, duration, viewers, and zaps
//

import UIKit

class StreamInfoRibbon: UIView {
    
    // MARK: - Properties
    
    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Live indicator
    private let liveIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let liveLabel: UILabel = {
        let label = UILabel()
        label.text = "Live"
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        return label
    }()
    
    // Stream name
    private let streamNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.8)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    // Duration
    private let durationLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.8)
        return label
    }()
    
    // Viewers
    private let viewerIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        let imageView = UIImageView(image: UIImage(systemName: "eye.fill", withConfiguration: config))
        imageView.tintColor = .white.withAlphaComponent(0.7)
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let viewerCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.8)
        return label
    }()
    
    // Zaps
    private let zapIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let imageView = UIImageView(image: UIImage(systemName: "bolt.fill", withConfiguration: config))
        imageView.tintColor = .systemOrange  // Adapts to light/dark mode
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()
    
    private let zapCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .systemOrange  // Adapts to light/dark mode
        return label
    }()
    
    // Zap button
    private let zapButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        button.setImage(UIImage(systemName: "bolt.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .systemOrange  // Adapts to light/dark mode
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // Separators
    private func makeSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .white.withAlphaComponent(0.2)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return view
    }
    
    // State
    private var isLive: Bool = false
    private var pulseAnimator: UIViewPropertyAnimator?
    
    // Callbacks
    var onZapTapped: (() -> Void)?
    var onZapCountTapped: (() -> Void)?
    
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
        // Add blur background
        addSubview(blurView)
        
        // Add content
        addSubview(contentStack)
        addSubview(zapButton)
        
        // Build content stack
        let liveStack = UIStackView(arrangedSubviews: [liveIndicator, liveLabel])
        liveStack.axis = .horizontal
        liveStack.spacing = 6
        liveStack.alignment = .center
        
        let viewerStack = UIStackView(arrangedSubviews: [viewerIcon, viewerCountLabel])
        viewerStack.axis = .horizontal
        viewerStack.spacing = 4
        viewerStack.alignment = .center
        
        let zapStack = UIStackView(arrangedSubviews: [zapIcon, zapCountLabel])
        zapStack.axis = .horizontal
        zapStack.spacing = 4
        zapStack.alignment = .center
        
        // Make zap stack tappable
        let zapTap = UITapGestureRecognizer(target: self, action: #selector(handleZapCountTap))
        zapStack.addGestureRecognizer(zapTap)
        zapStack.isUserInteractionEnabled = true
        
        contentStack.addArrangedSubview(liveStack)
        contentStack.addArrangedSubview(makeSeparator())
        contentStack.addArrangedSubview(streamNameLabel)
        contentStack.addArrangedSubview(makeSeparator())
        contentStack.addArrangedSubview(durationLabel)
        contentStack.addArrangedSubview(makeSeparator())
        contentStack.addArrangedSubview(viewerStack)
        contentStack.addArrangedSubview(makeSeparator())
        contentStack.addArrangedSubview(zapStack)
        
        // Constraints
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: zapButton.leadingAnchor, constant: -12),
            
            liveIndicator.widthAnchor.constraint(equalToConstant: 8),
            liveIndicator.heightAnchor.constraint(equalToConstant: 8),
            
            zapButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            zapButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            zapButton.widthAnchor.constraint(equalToConstant: 32),
            zapButton.heightAnchor.constraint(equalToConstant: 32),
        ])
        
        // Styling
        layer.cornerRadius = 12
        clipsToBounds = true
        
        // Border
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        
        // Zap button action
        zapButton.addAction(UIAction { [weak self] _ in
            self?.handleZapButtonTap()
        }, for: .touchUpInside)
        
        // Initial state
        update(isLive: false, streamName: "Not streaming", duration: 0, viewers: 0, zaps: 0)
    }
    
    // MARK: - Public Methods
    
    func update(isLive: Bool, streamName: String, duration: TimeInterval, viewers: Int, zaps: Int) {
        self.isLive = isLive
        
        // Live indicator
        liveIndicator.isHidden = !isLive
        liveLabel.text = isLive ? "Live" : "Offline"
        liveLabel.textColor = isLive ? .white : .white.withAlphaComponent(0.5)
        
        // Stream name
        streamNameLabel.text = streamName
        
        // Duration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        durationLabel.text = String(format: "%d:%02d", minutes, seconds)
        
        // Viewers
        viewerCountLabel.text = formatNumber(viewers)
        
        // Zaps
        zapCountLabel.text = formatSats(zaps)
        
        // Start/stop pulse animation
        if isLive && pulseAnimator == nil {
            startLiveIndicatorPulse()
        } else if !isLive {
            stopLiveIndicatorPulse()
        }
    }
    
    /// Animate zap count increase (call when zap received)
    func animateZapReceived(amount: Int) {
        // Flash the zap icon
        UIView.animate(withDuration: 0.1, animations: {
            self.zapIcon.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            self.zapCountLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
                self.zapIcon.transform = .identity
                self.zapCountLabel.transform = .identity
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func startLiveIndicatorPulse() {
        guard pulseAnimator == nil else { return }
        animateLiveIndicatorPulse()
    }
    
    private func animateLiveIndicatorPulse() {
        guard isLive else { return }
        
        pulseAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .easeInOut) {
            self.liveIndicator.alpha = 0.3
        }
        
        pulseAnimator?.addCompletion { [weak self] _ in
            guard let self = self, self.isLive else { return }
            
            self.pulseAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .easeInOut) {
                self.liveIndicator.alpha = 1.0
            }
            
            self.pulseAnimator?.addCompletion { [weak self] _ in
                self?.animateLiveIndicatorPulse()
            }
            
            self.pulseAnimator?.startAnimation()
        }
        
        pulseAnimator?.startAnimation()
    }
    
    private func stopLiveIndicatorPulse() {
        pulseAnimator?.stopAnimation(true)
        pulseAnimator = nil
        liveIndicator.alpha = 1.0
    }
    
    @objc private func handleZapButtonTap() {
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        onZapTapped?()
    }
    
    @objc private func handleZapCountTap() {
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        onZapCountTapped?()
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        }
        return "\(number)"
    }
    
    private func formatSats(_ sats: Int) -> String {
        if sats >= 1_000_000 {
            return String(format: "%.2fM", Double(sats) / 1_000_000)
        } else if sats >= 1_000 {
            return String(format: "%.1fK", Double(sats) / 1_000)
        }
        return "\(sats)"
    }
}
