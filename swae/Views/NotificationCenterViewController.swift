//
//  NotificationCenterViewController.swift
//  swae
//
//  Placeholder notification center view - presented with iOS 18 zoom transition
//

import UIKit

final class NotificationCenterViewController: UIViewController {
    
    // MARK: - UI Components
    private let titleLabel = UILabel()
    private let emptyStateLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    
    // MARK: - Callbacks
    var onDismiss: (() -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Close button (top right)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        
        // Title
        titleLabel.text = "Notifications"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // Empty state
        emptyStateLabel.text = "No notifications yet"
        emptyStateLabel.font = .systemFont(ofSize: 17, weight: .regular)
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
    
    @objc private func closeTapped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        onDismiss?()
        dismiss(animated: true)
    }
}
