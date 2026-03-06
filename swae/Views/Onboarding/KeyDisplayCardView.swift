//
//  KeyDisplayCardView.swift
//  swae
//
//  Reusable card for displaying public/private keys with copy functionality
//

import UIKit

final class KeyDisplayCardView: UIView {
    
    // MARK: - Types
    enum KeyType {
        case publicKey
        case privateKey
        
        var title: String {
            switch self {
            case .publicKey: return "PUBLIC KEY"
            case .privateKey: return "PRIVATE KEY"
            }
        }
        
        var helpText: String {
            switch self {
            case .publicKey: return "Share this to let others find you"
            case .privateKey: return "Keep this secret - full access to your account"
            }
        }
        
        var helpTextColor: UIColor {
            switch self {
            case .publicKey: return .secondaryLabel
            case .privateKey: return .editProfileError
            }
        }
    }
    
    // MARK: - Properties
    private let keyType: KeyType
    private var keyString: String = ""
    private var isCopied: Bool = false
    var onCopy: (() -> Void)?
    
    // MARK: - UI Components
    private let containerView = UIView()
    private let headerLabel = UILabel()
    private let keyContainer = UIView()
    private let keyLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let helpLabel = UILabel()
    
    // MARK: - Initialization
    init(keyType: KeyType) {
        self.keyType = keyType
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        // Container
        containerView.backgroundColor = .secondarySystemGroupedBackground
        containerView.layer.cornerRadius = 16
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOpacity = 0.08
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        
        // Header
        headerLabel.text = keyType.title
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .secondaryLabel
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerLabel)
        
        // Key container
        keyContainer.backgroundColor = .tertiarySystemGroupedBackground
        keyContainer.layer.cornerRadius = 10
        keyContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(keyContainer)
        
        // Key label
        keyLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        keyLabel.textColor = .label
        keyLabel.numberOfLines = 2
        keyLabel.lineBreakMode = .byTruncatingMiddle
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyContainer.addSubview(keyLabel)
        
        // Copy button
        copyButton.setImage(
            UIImage(systemName: "doc.on.doc")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal
        )
        copyButton.tintColor = .editProfilePurple
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        keyContainer.addSubview(copyButton)
        
        // Help label
        helpLabel.text = keyType.helpText
        helpLabel.font = .systemFont(ofSize: 13)
        helpLabel.textColor = keyType.helpTextColor
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(helpLabel)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            headerLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            
            keyContainer.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            keyContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            keyContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            keyLabel.topAnchor.constraint(equalTo: keyContainer.topAnchor, constant: 12),
            keyLabel.leadingAnchor.constraint(equalTo: keyContainer.leadingAnchor, constant: 12),
            keyLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            keyLabel.bottomAnchor.constraint(equalTo: keyContainer.bottomAnchor, constant: -12),
            
            copyButton.centerYAnchor.constraint(equalTo: keyContainer.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: keyContainer.trailingAnchor, constant: -12),
            copyButton.widthAnchor.constraint(equalToConstant: 44),
            copyButton.heightAnchor.constraint(equalToConstant: 44),
            
            helpLabel.topAnchor.constraint(equalTo: keyContainer.bottomAnchor, constant: 8),
            helpLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            helpLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            helpLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
        ])
        
        // Accessibility
        keyContainer.isAccessibilityElement = true
        keyContainer.accessibilityLabel = "\(keyType.title). Double tap to copy."
        keyContainer.accessibilityTraits = .button
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(copyTapped))
        keyContainer.addGestureRecognizer(tapGesture)
        keyContainer.isUserInteractionEnabled = true
    }
    
    // MARK: - Public Methods
    func setKey(_ key: String) {
        keyString = key
        keyLabel.text = key
        keyContainer.accessibilityValue = key
    }
    
    // MARK: - Actions
    @objc private func copyTapped() {
        guard !isCopied else { return }
        
        UIPasteboard.general.string = keyString
        isCopied = true
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Animate checkmark
        copyButton.setImage(
            UIImage(systemName: "checkmark.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal
        )
        copyButton.tintColor = .editProfileSuccess
        
        copyButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8
        ) {
            self.copyButton.transform = .identity
        }
        
        onCopy?()
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.copyButton.setImage(
                UIImage(systemName: "doc.on.doc")?
                    .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
                for: .normal
            )
            self.copyButton.tintColor = .editProfilePurple
            self.isCopied = false
        }
    }
}
