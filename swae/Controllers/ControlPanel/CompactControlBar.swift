//
//  CompactControlBar.swift
//  swae
//
//  Compact liquid glass toolbar shown when chat is expanded
//  Contains essential controls: Mic, Mute, Flip, Zap total, overflow menu
//

import MetalKit
import UIKit

class CompactControlBar: UIView {
    
    // MARK: - Properties
    
    private let liquidPoolView: LiquidPoolView
    
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Essential orbs
    private var micOrb: MiniOrbView!
    private var muteOrb: MiniOrbView!
    private var flipOrb: MiniOrbView!
    
    // Orb containers with labels
    private func makeOrbContainer(orb: MiniOrbView, title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        orb.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(orb)
        
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.8)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            orb.topAnchor.constraint(equalTo: container.topAnchor),
            orb.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            orb.widthAnchor.constraint(equalToConstant: 36),
            orb.heightAnchor.constraint(equalToConstant: 36),
            
            label.topAnchor.constraint(equalTo: orb.bottomAnchor, constant: 2),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            container.widthAnchor.constraint(equalToConstant: 44),
        ])
        
        return container
    }
    
    // Zap display
    private let zapStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }()
    
    private let zapIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let imageView = UIImageView(image: UIImage(systemName: "bolt.fill", withConfiguration: config))
        imageView.tintColor = .systemOrange  // Adapts to light/dark mode
        return imageView
    }()
    
    private let zapLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .label  // Adapts to light/dark mode
        label.text = "0"
        return label
    }()
    
    // Overflow button
    private let overflowButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        button.setImage(UIImage(systemName: "ellipsis.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .white.withAlphaComponent(0.8)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // Separator
    private let separator: UIView = {
        let view = UIView()
        view.backgroundColor = .white.withAlphaComponent(0.2)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Callbacks
    var onMicTapped: (() -> Void)?
    var onMuteTapped: (() -> Void)?
    var onFlipTapped: (() -> Void)?
    var onZapTapped: (() -> Void)?
    var onOverflowTapped: (() -> Void)?
    
    // State
    private var isMicOn: Bool = true
    private var isMuteOn: Bool = false
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        liquidPoolView = LiquidPoolView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        liquidPoolView = LiquidPoolView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Setup
    
    private func setup() {
        // Add liquid pool background
        liquidPoolView.translatesAutoresizingMaskIntoConstraints = false
        liquidPoolView.config = .normal
        addSubview(liquidPoolView)
        
        // Create orbs
        micOrb = MiniOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        micOrb.config = .mic(isOn: true)
        
        muteOrb = MiniOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        muteOrb.config = .mute(isOn: false)
        
        flipOrb = MiniOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        flipOrb.config = .flip(isOn: false)
        
        // Create orb containers
        let micContainer = makeOrbContainer(orb: micOrb, title: "Mic")
        let muteContainer = makeOrbContainer(orb: muteOrb, title: "Mute")
        let flipContainer = makeOrbContainer(orb: flipOrb, title: "Flip")
        
        // Add tap gestures to containers
        let micTap = UITapGestureRecognizer(target: self, action: #selector(handleMicTap))
        micContainer.addGestureRecognizer(micTap)
        
        let muteTap = UITapGestureRecognizer(target: self, action: #selector(handleMuteTap))
        muteContainer.addGestureRecognizer(muteTap)
        
        let flipTap = UITapGestureRecognizer(target: self, action: #selector(handleFlipTap))
        flipContainer.addGestureRecognizer(flipTap)
        
        // Build zap stack
        zapStack.addArrangedSubview(zapIcon)
        zapStack.addArrangedSubview(zapLabel)
        
        let zapTap = UITapGestureRecognizer(target: self, action: #selector(handleZapTap))
        zapStack.addGestureRecognizer(zapTap)
        zapStack.isUserInteractionEnabled = true
        
        // Build content stack
        contentStack.addArrangedSubview(micContainer)
        contentStack.addArrangedSubview(muteContainer)
        contentStack.addArrangedSubview(flipContainer)
        contentStack.addArrangedSubview(separator)
        contentStack.addArrangedSubview(zapStack)
        
        addSubview(contentStack)
        addSubview(overflowButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            liquidPoolView.topAnchor.constraint(equalTo: topAnchor),
            liquidPoolView.leadingAnchor.constraint(equalTo: leadingAnchor),
            liquidPoolView.trailingAnchor.constraint(equalTo: trailingAnchor),
            liquidPoolView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 30),
            
            overflowButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            overflowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            overflowButton.widthAnchor.constraint(equalToConstant: 44),
            overflowButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        // Styling
        layer.cornerRadius = 16
        clipsToBounds = true
        
        // Border
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        
        // Overflow action
        overflowButton.addAction(UIAction { [weak self] _ in
            self?.handleOverflowTap()
        }, for: .touchUpInside)
    }
    
    // MARK: - Public Methods
    
    func updateState(isMicOn: Bool, isMuteOn: Bool) {
        self.isMicOn = isMicOn
        self.isMuteOn = isMuteOn
        
        micOrb.config = .mic(isOn: isMicOn)
        muteOrb.config = .mute(isOn: isMuteOn)
    }
    
    func updateZaps(_ zaps: Int) {
        zapLabel.text = formatSats(zaps)
    }
    
    /// Trigger ripple effect (e.g., when zap received)
    func triggerRipple(at point: CGPoint) {
        let normalized = SIMD2<Float>(
            Float(point.x / bounds.width),
            1.0 - Float(point.y / bounds.height)
        )
        liquidPoolView.triggerRipple(at: normalized)
    }
    
    /// Trigger zap effect
    func triggerZapEffect() {
        liquidPoolView.triggerZap(at: SIMD2<Float>(0.7, 0.5), intensity: 0.8)
        
        // Animate zap label
        UIView.animate(withDuration: 0.1, animations: {
            self.zapIcon.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
                self.zapIcon.transform = .identity
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleMicTap() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        
        micOrb.flash()
        onMicTapped?()
    }
    
    @objc private func handleMuteTap() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        
        muteOrb.flash()
        onMuteTapped?()
    }
    
    @objc private func handleFlipTap() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        
        flipOrb.flash()
        onFlipTapped?()
    }
    
    @objc private func handleZapTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        onZapTapped?()
    }
    
    private func handleOverflowTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        onOverflowTapped?()
    }
    
    // MARK: - Helpers
    
    private func formatSats(_ sats: Int) -> String {
        if sats >= 1_000_000 {
            return String(format: "%.1fM", Double(sats) / 1_000_000)
        } else if sats >= 1_000 {
            return String(format: "%.1fK", Double(sats) / 1_000)
        }
        return "\(sats)"
    }
}
