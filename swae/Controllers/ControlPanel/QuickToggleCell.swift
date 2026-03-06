//
//  QuickToggleCell.swift
//  swae
//
//  UICollectionViewCell for quick toggle buttons
//

import UIKit

class QuickToggleCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    static let reuseIdentifier = "QuickToggleCell"
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private var action: (() -> Void)?
    
    var isOn: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGesture()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        contentView.addSubview(containerStack)
        containerStack.addArrangedSubview(iconImageView)
        containerStack.addArrangedSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            containerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            containerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            iconImageView.heightAnchor.constraint(equalToConstant: 24),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
        ])
        
        // Initial appearance
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true
        updateAppearance()
    }
    
    private func setupGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Configuration
    
    func configure(icon: String, title: String, isOn: Bool, action: @escaping () -> Void) {
        // Set icon (SF Symbol)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconImageView.image = UIImage(systemName: icon, withConfiguration: config)
        
        // Set title
        titleLabel.text = title
        
        // Set state
        self.isOn = isOn
        
        // Set action
        self.action = action
        
        // Update appearance
        updateAppearance()
        
        // Accessibility
        contentView.isAccessibilityElement = true
        contentView.accessibilityLabel = title
        contentView.accessibilityValue = isOn ? "On" : "Off"
        contentView.accessibilityHint = "Double tap to toggle"
        contentView.accessibilityTraits = .button
    }
    
    // MARK: - Appearance
    
    private func updateAppearance() {
        if isOn {
            // Active state - blue background
            contentView.backgroundColor = UIColor.accentPurple.withAlphaComponent(0.3)
            iconImageView.tintColor = .accentPurple
            titleLabel.textColor = .white
        } else {
            // Inactive state - subtle background
            contentView.backgroundColor = UIColor.white.withAlphaComponent(0.1)
            iconImageView.tintColor = .white
            titleLabel.textColor = .white
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleTap() {
        // Haptic feedback
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        
        // Animate tap
        UIView.animate(withDuration: 0.1, animations: {
            self.contentView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.contentView.transform = .identity
            }
        }
        
        // Execute action
        action?()
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
        titleLabel.text = nil
        isOn = false
        action = nil
    }
}
