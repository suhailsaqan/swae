//
//  ZapAttachmentBoxView.swift
//  swae
//
//  Compact pill view displaying a pending zap attachment above the text field
//  Shows bolt icon, amount, and remove button
//

import UIKit

/// Displays a pending zap attachment above the text field
class ZapAttachmentBoxView: UIView {
    
    // MARK: - Views
    
    private var glassContainer: GlassContainerView!
    private let boltIcon = UIImageView()
    private let amountLabel = UILabel()
    private let removeButton = UIButton()
    
    // MARK: - State
    
    private(set) var zapAttachment: ZapAttachment?
    
    // MARK: - Callbacks
    
    var onRemoveTapped: (() -> Void)?
    var onTapped: (() -> Void)?  // To edit amount
    
    // MARK: - Layout Constants
    
    private let boxHeight: CGFloat = 36
    private let cornerRadius: CGFloat = 18
    
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
        translatesAutoresizingMaskIntoConstraints = false
        
        // Glass background with orange tint
        glassContainer = GlassFactory.makeGlassView(cornerRadius: cornerRadius)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassContainer)
        
        // Bolt icon
        boltIcon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        boltIcon.image = UIImage(systemName: "bolt.fill", withConfiguration: config)
        boltIcon.tintColor = .systemOrange
        boltIcon.contentMode = .scaleAspectFit
        glassContainer.glassContentView.addSubview(boltIcon)
        
        // Amount label
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        amountLabel.textColor = .label
        glassContainer.glassContentView.addSubview(amountLabel)
        
        // Remove button (X)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        let removeConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: removeConfig), for: .normal)
        removeButton.tintColor = UIColor(white: 0.6, alpha: 1.0)
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        glassContainer.glassContentView.addSubview(removeButton)
        
        // Tap gesture for editing
        let tap = UITapGestureRecognizer(target: self, action: #selector(boxTapped))
        glassContainer.addGestureRecognizer(tap)
        
        NSLayoutConstraint.activate([
            glassContainer.topAnchor.constraint(equalTo: topAnchor),
            glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            heightAnchor.constraint(equalToConstant: boxHeight),
            
            boltIcon.leadingAnchor.constraint(equalTo: glassContainer.glassContentView.leadingAnchor, constant: 12),
            boltIcon.centerYAnchor.constraint(equalTo: glassContainer.glassContentView.centerYAnchor),
            boltIcon.widthAnchor.constraint(equalToConstant: 16),
            boltIcon.heightAnchor.constraint(equalToConstant: 16),
            
            amountLabel.leadingAnchor.constraint(equalTo: boltIcon.trailingAnchor, constant: 6),
            amountLabel.centerYAnchor.constraint(equalTo: glassContainer.glassContentView.centerYAnchor),
            
            removeButton.leadingAnchor.constraint(equalTo: amountLabel.trailingAnchor, constant: 8),
            removeButton.trailingAnchor.constraint(equalTo: glassContainer.glassContentView.trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: glassContainer.glassContentView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with attachment: ZapAttachment) {
        self.zapAttachment = attachment
        amountLabel.text = "\(attachment.formattedAmount) sats"
    }
    
    /// Returns the frame of the visible glass container in the given coordinate space.
    /// Use this instead of the view's bounds when you need the actual visible pill frame,
    /// since the parent view may fill the full stack width while the glass is content-sized.
    func glassContainerFrame(in coordinateSpace: UICoordinateSpace) -> CGRect {
        return glassContainer.convert(glassContainer.bounds, to: coordinateSpace)
    }
    
    // MARK: - Actions
    
    @objc private func removeTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onRemoveTapped?()
    }
    
    @objc private func boxTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTapped?()
    }
}
