//
//  SignInViewController.swift
//  swae
//
//  Sign-in flow in UIKit
//

import Combine
import NostrSDK
import UIKit

protocol SignInViewControllerDelegate: AnyObject {
    func signInDidComplete()
    func signInDidCancel()
}

final class SignInViewController: UIViewController, RelayURLValidating {
    
    // MARK: - Dependencies
    private let appState: AppState
    weak var delegate: SignInViewControllerDelegate?
    
    // MARK: - State
    private var nostrIdentifier: String = ""
    private var primaryRelay: String = ""
    private var showAdvancedOptions: Bool = false
    
    private var validKey: Bool = false
    private var validatedRelayURL: URL?
    private var keypair: Keypair?
    private var publicKey: PublicKey?
    
    // MARK: - UI Components
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    
    private var headerView: OnboardingHeaderView!
    private var keyField: EditProfileFieldView!
    private let keyStatusView = UIView()
    private let keyStatusIcon = UIImageView()
    private let keyStatusLabel = UILabel()
    
    private let infoBox = UIView()
    private let advancedButton = UIButton(type: .system)
    private var advancedCard: EditProfileCardView!
    private var relayField: EditProfileFieldView!
    private let defaultRelayButton = UIButton(type: .system)
    
    private let pasteButton = UIButton(type: .system)
    private let actionButton = OnboardingActionButton()
    
    // MARK: - Initialization
    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
        setupKeyboardHandling()
        
        // Set default relay
        primaryRelay = AppState.defaultRelayURLString
        validatedRelayURL = try? validateRelayURLString(AppState.defaultRelayURLString)
        
        updateActionButton()
    }
    
    // MARK: - Setup UI
    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        
        // Scroll view
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        // Content stack
        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        
        setupHeader()
        setupKeyInput()
        setupInfoBox()
        setupAdvancedOptions()
        setupActionButton()
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -16),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])
        
        // Tap to dismiss keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }
    
    private func setupNavigation() {
        title = "Sign In"
        navigationItem.largeTitleDisplayMode = .never
        
        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.leftBarButtonItem = cancelButton
    }
    
    private func setupHeader() {
        headerView = OnboardingHeaderView(
            icon: "person.badge.key.fill",
            iconColor: .editProfilePurple,
            title: "Sign In",
            subtitle: "Enter your Nostr key to access your account"
        )
        contentStack.addArrangedSubview(headerView)
    }
    
    private func setupKeyInput() {
        // Key card container
        let keyCardContainer = UIView()
        keyCardContainer.backgroundColor = .secondarySystemGroupedBackground
        keyCardContainer.layer.cornerRadius = 16
        keyCardContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Header label
        let headerLabel = UILabel()
        headerLabel.text = "YOUR KEY"
        headerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .secondaryLabel
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        keyCardContainer.addSubview(headerLabel)
        
        // Key field (using EditProfileFieldView)
        keyField = EditProfileFieldView(configuration: .init(
            icon: "key.fill",
            label: "Nostr Key",
            placeholder: "nsec... or npub...",
            keyboardType: .asciiCapable,
            autocapitalization: .none
        ))
        keyField.delegate = self
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyCardContainer.addSubview(keyField)
        
        // Paste button - positioned to align with the input container (bottom 44pt of field)
        pasteButton.setImage(
            UIImage(systemName: "doc.on.clipboard")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        pasteButton.tintColor = .editProfilePurple
        pasteButton.backgroundColor = .tertiarySystemGroupedBackground
        pasteButton.layer.cornerRadius = 10
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
        keyCardContainer.addSubview(pasteButton)
        
        // Key status (added directly to content stack, below the card)
        setupKeyStatus()
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: keyCardContainer.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: keyCardContainer.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: keyCardContainer.trailingAnchor, constant: -16),
            
            keyField.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            keyField.leadingAnchor.constraint(equalTo: keyCardContainer.leadingAnchor, constant: 16),
            keyField.trailingAnchor.constraint(equalTo: pasteButton.leadingAnchor, constant: -8),
            keyField.bottomAnchor.constraint(equalTo: keyCardContainer.bottomAnchor, constant: -16),
            
            // Align paste button with the input container inside the field view
            pasteButton.trailingAnchor.constraint(equalTo: keyCardContainer.trailingAnchor, constant: -16),
            pasteButton.centerYAnchor.constraint(equalTo: keyField.inputContainer.centerYAnchor),
            pasteButton.widthAnchor.constraint(equalToConstant: 44),
            pasteButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        contentStack.addArrangedSubview(keyCardContainer)
        contentStack.addArrangedSubview(keyStatusView)
        contentStack.setCustomSpacing(8, after: keyCardContainer)
    }
    
    private func setupKeyStatus() {
        keyStatusView.isHidden = true
        keyStatusView.alpha = 0
        keyStatusView.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        keyStatusView.addSubview(stack)
        
        keyStatusIcon.contentMode = .scaleAspectFit
        keyStatusIcon.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(keyStatusIcon)
        
        keyStatusLabel.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(keyStatusLabel)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: keyStatusView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: keyStatusView.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: keyStatusView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: keyStatusView.bottomAnchor),
        ])
    }
    
    private func setupInfoBox() {
        infoBox.backgroundColor = UIColor.accentPurple.withAlphaComponent(0.1)
        infoBox.layer.cornerRadius = 12
        infoBox.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        infoBox.addSubview(stack)
        
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.spacing = 8
        
        let icon = UIImageView()
        icon.image = UIImage(systemName: "info.circle.fill")
        icon.tintColor = .accentPurple
        icon.setContentHuggingPriority(.required, for: .horizontal)
        
        let titleLabel = UILabel()
        titleLabel.text = "Key Format"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        
        headerStack.addArrangedSubview(icon)
        headerStack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(headerStack)
        
        let infoLabel = UILabel()
        infoLabel.text = "• Private key (nsec...): Full access to post and interact\n• Public key (npub...): View-only access"
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
        stack.addArrangedSubview(infoLabel)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: infoBox.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: infoBox.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: infoBox.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: infoBox.bottomAnchor, constant: -12),
        ])
        
        contentStack.addArrangedSubview(infoBox)
    }
    
    private func setupAdvancedOptions() {
        // Advanced toggle button
        var config = UIButton.Configuration.plain()
        config.title = "Advanced Options"
        config.image = UIImage(systemName: "chevron.down")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.baseForegroundColor = .secondaryLabel
        
        advancedButton.configuration = config
        advancedButton.addTarget(self, action: #selector(advancedToggleTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(advancedButton)
        
        // Advanced card (hidden initially)
        advancedCard = EditProfileCardView(header: "Relay Settings")
        advancedCard.isHidden = true
        advancedCard.alpha = 0
        
        relayField = EditProfileFieldView(configuration: .init(
            icon: "globe",
            label: "Primary Relay",
            placeholder: "wss://relay.example.com",
            keyboardType: .URL,
            autocapitalization: .none
        ))
        relayField.delegate = self
        relayField.text = AppState.defaultRelayURLString
        advancedCard.addField(relayField)
        
        contentStack.addArrangedSubview(advancedCard)
        
        // Default relay button
        defaultRelayButton.setTitle("Use Default Relay", for: .normal)
        defaultRelayButton.titleLabel?.font = .systemFont(ofSize: 13)
        defaultRelayButton.setTitleColor(.editProfilePurple, for: .normal)
        defaultRelayButton.isHidden = true
        defaultRelayButton.addTarget(self, action: #selector(useDefaultRelayTapped), for: .touchUpInside)
        contentStack.addArrangedSubview(defaultRelayButton)
    }
    
    private func setupActionButton() {
        actionButton.setTitle("Sign In")
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        view.addSubview(actionButton)
        
        NSLayoutConstraint.activate([
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }
    
    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Validation
    private func validateKey(_ value: String) {
        let filtered = value.trimmingCharacters(in: .whitespacesAndNewlines)
        nostrIdentifier = filtered
        
        if let kp = Keypair(nsec: filtered) {
            keypair = kp
            publicKey = kp.publicKey
            validKey = true
            updateKeyStatus(valid: true, isPrivate: true)
        } else if let pk = PublicKey(npub: filtered) {
            keypair = nil
            publicKey = pk
            validKey = true
            updateKeyStatus(valid: true, isPrivate: false)
        } else {
            keypair = nil
            publicKey = nil
            validKey = false
            if !filtered.isEmpty {
                updateKeyStatus(valid: false, isPrivate: false)
            } else {
                hideKeyStatus()
            }
        }
        
        updateActionButton()
    }
    
    private func updateKeyStatus(valid: Bool, isPrivate: Bool) {
        if valid {
            keyStatusIcon.image = UIImage(systemName: "checkmark.circle.fill")
            keyStatusIcon.tintColor = isPrivate ? .editProfileSuccess : .editProfileAmber
            keyStatusLabel.text = isPrivate ? "Private key detected - Full access" : "Public key detected - Read-only access"
            keyStatusLabel.textColor = isPrivate ? .editProfileSuccess : .editProfileAmber
        } else {
            keyStatusIcon.image = UIImage(systemName: "exclamationmark.circle.fill")
            keyStatusIcon.tintColor = .editProfileError
            keyStatusLabel.text = "Invalid key format"
            keyStatusLabel.textColor = .editProfileError
        }
        
        showKeyStatus()
    }
    
    private func showKeyStatus() {
        guard keyStatusView.isHidden else { return }
        keyStatusView.isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.keyStatusView.alpha = 1
        }
    }
    
    private func hideKeyStatus() {
        guard !keyStatusView.isHidden else { return }
        UIView.animate(withDuration: 0.2) {
            self.keyStatusView.alpha = 0
        } completion: { _ in
            self.keyStatusView.isHidden = true
        }
    }
    
    private func validateRelay(_ value: String) {
        let filtered = value.trimmingCharacters(in: .whitespacesAndNewlines)
        primaryRelay = filtered
        
        if filtered.isEmpty {
            validatedRelayURL = nil
        } else {
            validatedRelayURL = try? validateRelayURLString(filtered)
        }
        
        updateActionButton()
    }
    
    private func updateActionButton() {
        actionButton.isEnabled = validKey && validatedRelayURL != nil
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        delegate?.signInDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func pasteTapped() {
        if let clipboardString = UIPasteboard.general.string {
            keyField.text = clipboardString
            validateKey(clipboardString)
        }
    }
    
    @objc private func advancedToggleTapped() {
        showAdvancedOptions.toggle()
        
        let chevron = showAdvancedOptions ? "chevron.up" : "chevron.down"
        advancedButton.configuration?.image = UIImage(systemName: chevron)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        
        UIView.animate(withDuration: 0.3) {
            self.advancedCard.isHidden = !self.showAdvancedOptions
            self.advancedCard.alpha = self.showAdvancedOptions ? 1 : 0
            self.defaultRelayButton.isHidden = !self.showAdvancedOptions
        }
    }
    
    @objc private func useDefaultRelayTapped() {
        relayField.text = AppState.defaultRelayURLString
        validateRelay(AppState.defaultRelayURLString)
    }
    
    @objc private func signInTapped() {
        guard let validatedRelayURL = validatedRelayURL else {
            showError("Please enter a valid relay URL")
            return
        }
        
        actionButton.isLoading = true
        
        // Build relay list: user-entered relay + any missing defaults
        var relayURLs = [validatedRelayURL]
        for defaultRelay in AppState.defaultRelayURLStrings {
            if let url = try? validateRelayURLString(defaultRelay),
               url.absoluteString != validatedRelayURL.absoluteString {
                relayURLs.append(url)
            }
        }
        
        if let keypair = keypair {
            appState.signIn(keypair: keypair, relayURLs: relayURLs)
        } else if let publicKey = publicKey {
            appState.signIn(publicKey: publicKey, relayURLs: relayURLs)
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        actionButton.isLoading = false
        delegate?.signInDidComplete()
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = keyboardFrame.height
            self.scrollView.scrollIndicatorInsets.bottom = keyboardFrame.height
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.scrollIndicatorInsets.bottom = 0
        }
    }
    
    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - EditProfileFieldViewDelegate
extension SignInViewController: EditProfileFieldViewDelegate {
    
    func fieldDidBeginEditing(_ field: EditProfileFieldView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let fieldFrame = field.convert(field.bounds, to: self.scrollView)
            let visibleRect = CGRect(x: 0, y: fieldFrame.minY - 20, width: self.scrollView.bounds.width, height: fieldFrame.height + 40)
            self.scrollView.scrollRectToVisible(visibleRect, animated: true)
        }
    }
    
    func fieldDidEndEditing(_ field: EditProfileFieldView) {}
    
    func fieldDidChangeText(_ field: EditProfileFieldView, text: String) {
        if field === keyField {
            validateKey(text)
        } else if field === relayField {
            validateRelay(text)
        }
    }
}
