//
//  AttachmentOptionButton.swift
//  swae
//
//  Smaller button variant for attachment modal options
//  Based on ControlButton but with compact sizing
//

import UIKit

/// Compact glass circle button for attachment options
/// Uses GlassFactory for iOS 26 liquid glass / iOS 18 fallback
class AttachmentOptionButton: UIControl {
    
    // MARK: - Properties
    
    private var circleGlassContainer: GlassContainerView!
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    
    // MARK: - Constants
    
    private let circleSize: CGFloat = 56
    private let iconSize: CGFloat = 24
    
    // MARK: - Initialization
    
    init(symbolName: String, title: String) {
        super.init(frame: .zero)
        setup(symbol: symbolName, title: title)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(symbol: "questionmark", title: "")
    }
    
    // MARK: - Setup
    
    private func setup(symbol: String, title: String) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        
        // Circle background - liquid glass
        circleGlassContainer = GlassFactory.makeGlassView(cornerRadius: circleSize / 2)
        circleGlassContainer.translatesAutoresizingMaskIntoConstraints = false
        circleGlassContainer.isUserInteractionEnabled = false
        addSubview(circleGlassContainer)
        
        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        if let img = UIImage(systemName: symbol, withConfiguration: config) {
            iconView.image = img.withRenderingMode(.alwaysTemplate)
        }
        circleGlassContainer.glassContentView.addSubview(iconView)

        // Label below circle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.9)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            // Circle
            circleGlassContainer.topAnchor.constraint(equalTo: topAnchor),
            circleGlassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleGlassContainer.widthAnchor.constraint(equalToConstant: circleSize),
            circleGlassContainer.heightAnchor.constraint(equalToConstant: circleSize),
            
            // Icon centered in circle
            iconView.centerXAnchor.constraint(equalTo: circleGlassContainer.glassContentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: circleGlassContainer.glassContentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            
            // Label below
            titleLabel.topAnchor.constraint(equalTo: circleGlassContainer.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        // Touch handlers
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchCancel, .touchUpInside, .touchUpOutside, .touchDragExit])
    }
    
    // MARK: - Touch Feedback
    
    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.circleGlassContainer.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.circleGlassContainer.alpha = 0.8
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    @objc private func touchUp() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.circleGlassContainer.transform = .identity
            self.circleGlassContainer.alpha = 1.0
        }
    }
}
