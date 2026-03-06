//
//  OnboardingHeaderView.swift
//  swae
//
//  Reusable header with icon, title, and subtitle for onboarding screens
//

import UIKit

final class OnboardingHeaderView: UIView {
    
    // MARK: - Properties
    var icon: String = "" {
        didSet { updateIcon() }
    }
    
    var iconColor: UIColor = .editProfilePurple {
        didSet { updateIcon() }
    }
    
    var title: String = "" {
        didSet { titleLabel.text = title }
    }
    
    var subtitle: String = "" {
        didSet { subtitleLabel.text = subtitle }
    }
    
    // MARK: - UI Components
    private let containerStack = UIStackView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    convenience init(icon: String, iconColor: UIColor, title: String, subtitle: String) {
        self.init(frame: .zero)
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        updateIcon()
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
    
    // MARK: - Setup
    private func setupUI() {
        containerStack.axis = .vertical
        containerStack.alignment = .center
        containerStack.spacing = 12
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerStack)
        
        // Icon
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(iconImageView)
        
        // Title
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        containerStack.addArrangedSubview(titleLabel)
        
        // Subtitle
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        containerStack.addArrangedSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconImageView.widthAnchor.constraint(equalToConstant: 60),
            iconImageView.heightAnchor.constraint(equalToConstant: 60),
        ])
    }
    
    // MARK: - Update Icon
    private func updateIcon() {
        iconImageView.image = UIImage(systemName: icon)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 50, weight: .medium))
        iconImageView.tintColor = iconColor
    }
}
