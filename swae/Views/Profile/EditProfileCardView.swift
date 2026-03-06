//
//  EditProfileCardView.swift
//  swae
//
//  Reusable card container for Edit Profile sections
//

import UIKit

final class EditProfileCardView: UIView {
    
    // MARK: - Properties
    private let headerLabel = UILabel()
    private let contentStack = UIStackView()
    private var fieldViews: [EditProfileFieldView] = []
    
    // MARK: - Initialization
    init(header: String) {
        super.init(frame: .zero)
        setupUI(header: header)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI(header: String) {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        
        // Header label
        headerLabel.text = header.uppercased()
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .secondaryLabel
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0.5
        headerLabel.attributedText = NSAttributedString(
            string: header.uppercased(),
            attributes: [
                .kern: 0.5,
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)
        
        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            contentStack.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }
    
    // MARK: - Public Methods
    func addField(_ fieldView: EditProfileFieldView) {
        fieldViews.append(fieldView)
        
        // Add separator if not first field
        if fieldViews.count > 1 {
            let separator = UIView()
            separator.backgroundColor = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            contentStack.addArrangedSubview(separator)
        }
        
        contentStack.addArrangedSubview(fieldView)
    }
    
    func getFields() -> [EditProfileFieldView] {
        return fieldViews
    }
}
