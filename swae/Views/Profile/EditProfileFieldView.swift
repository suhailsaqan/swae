//
//  EditProfileFieldView.swift
//  swae
//
//  Minimal field component for Edit Profile - inspired by iOS Settings
//

import UIKit

protocol EditProfileFieldViewDelegate: AnyObject {
    func fieldDidBeginEditing(_ field: EditProfileFieldView)
    func fieldDidEndEditing(_ field: EditProfileFieldView)
    func fieldDidChangeText(_ field: EditProfileFieldView, text: String)
}

final class EditProfileFieldView: UIView {
    
    // MARK: - Configuration
    struct Configuration {
        let icon: String
        let label: String
        let placeholder: String
        let maxCharacters: Int?
        let isMultiline: Bool
        let keyboardType: UIKeyboardType
        let autocapitalization: UITextAutocapitalizationType
        let helpText: String?
        
        init(
            icon: String,
            label: String,
            placeholder: String,
            maxCharacters: Int? = nil,
            isMultiline: Bool = false,
            keyboardType: UIKeyboardType = .default,
            autocapitalization: UITextAutocapitalizationType = .sentences,
            helpText: String? = nil
        ) {
            self.icon = icon
            self.label = label
            self.placeholder = placeholder
            self.maxCharacters = maxCharacters
            self.isMultiline = isMultiline
            self.keyboardType = keyboardType
            self.autocapitalization = autocapitalization
            self.helpText = helpText
        }
    }
    
    // MARK: - Properties
    weak var delegate: EditProfileFieldViewDelegate?
    private let configuration: Configuration
    
    var text: String {
        get { configuration.isMultiline ? textView.text : textField.text ?? "" }
        set {
            if configuration.isMultiline {
                textView.text = newValue
                placeholderLabel.isHidden = !newValue.isEmpty
            } else {
                textField.text = newValue
            }
        }
    }
    
    var isValid: Bool = true {
        didSet { updateValidationState() }
    }
    
    var errorMessage: String? {
        didSet { updateErrorMessage() }
    }
    
    // For external access
    let inputContainer = UIView()
    
    // MARK: - UI Components
    private let labelView = UILabel()
    private let textField = UITextField()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let errorLabel = UILabel()
    
    // MARK: - Initialization
    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        // Simple label above input
        labelView.text = configuration.label
        labelView.font = .systemFont(ofSize: 13, weight: .medium)
        labelView.textColor = .secondaryLabel
        labelView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelView)
        
        // Clean input container
        inputContainer.backgroundColor = .clear
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inputContainer)
        
        // Error label
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.alpha = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(errorLabel)
        
        if configuration.isMultiline {
            setupTextView()
        } else {
            setupTextField()
        }
        
        NSLayoutConstraint.activate([
            labelView.topAnchor.constraint(equalTo: topAnchor),
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            inputContainer.topAnchor.constraint(equalTo: labelView.bottomAnchor, constant: 6),
            inputContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            errorLabel.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 4),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    private func setupTextField() {
        textField.font = .systemFont(ofSize: 17)
        textField.textColor = .label
        textField.attributedPlaceholder = NSAttributedString(
            string: configuration.placeholder,
            attributes: [.foregroundColor: UIColor.tertiaryLabel]
        )
        textField.keyboardType = configuration.keyboardType
        textField.autocapitalizationType = configuration.autocapitalization
        textField.autocorrectionType = .no
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        inputContainer.addSubview(textField)
        
        // Bottom border line
        let borderLine = UIView()
        borderLine.backgroundColor = .separator
        borderLine.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(borderLine)
        
        NSLayoutConstraint.activate([
            inputContainer.heightAnchor.constraint(equalToConstant: 44),
            
            textField.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            textField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            textField.bottomAnchor.constraint(equalTo: borderLine.topAnchor),
            
            borderLine.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            borderLine.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            borderLine.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            borderLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
    
    private func setupTextView() {
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.keyboardType = configuration.keyboardType
        textView.autocapitalizationType = configuration.autocapitalization
        textView.autocorrectionType = .no
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: -4, bottom: 8, right: 0)
        textView.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(textView)
        
        // Placeholder
        placeholderLabel.text = configuration.placeholder
        placeholderLabel.font = .systemFont(ofSize: 17)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(placeholderLabel)
        
        // Bottom border line
        let borderLine = UIView()
        borderLine.backgroundColor = .separator
        borderLine.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(borderLine)
        
        NSLayoutConstraint.activate([
            inputContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            
            textView.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: borderLine.topAnchor),
            
            placeholderLabel.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            placeholderLabel.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            
            borderLine.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            borderLine.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            borderLine.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            borderLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
    
    // MARK: - Validation
    private func updateValidationState() {
        // Simple red text color for invalid state
        if !isValid {
            textField.textColor = .systemRed
            textView.textColor = .systemRed
        } else {
            textField.textColor = .label
            textView.textColor = .label
        }
    }
    
    private func updateErrorMessage() {
        if let message = errorMessage {
            errorLabel.text = message
            UIView.animate(withDuration: 0.2) {
                self.errorLabel.alpha = 1
            }
        } else {
            UIView.animate(withDuration: 0.2) {
                self.errorLabel.alpha = 0
            }
        }
    }
    
    // MARK: - Validation helpers (kept for compatibility)
    func showValidationSuccess() {}
    func hideValidationIcon() {}
    
    // MARK: - Actions
    @objc private func textFieldDidChange() {
        enforceCharacterLimit()
        delegate?.fieldDidChangeText(self, text: text)
    }
    
    private func enforceCharacterLimit() {
        guard let maxChars = configuration.maxCharacters else { return }
        
        if configuration.isMultiline {
            if textView.text.count > maxChars {
                textView.text = String(textView.text.prefix(maxChars))
            }
        } else {
            if let currentText = textField.text, currentText.count > maxChars {
                textField.text = String(currentText.prefix(maxChars))
            }
        }
    }
}

// MARK: - UITextFieldDelegate
extension EditProfileFieldView: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        delegate?.fieldDidBeginEditing(self)
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        delegate?.fieldDidEndEditing(self)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - UITextViewDelegate
extension EditProfileFieldView: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        delegate?.fieldDidBeginEditing(self)
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        delegate?.fieldDidEndEditing(self)
    }
    
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        enforceCharacterLimit()
        delegate?.fieldDidChangeText(self, text: text)
    }
}
