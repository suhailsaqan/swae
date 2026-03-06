//
//  CreateProfileViewController.swift
//  swae
//
//  3-step profile creation wizard in UIKit
//

import Combine
import Kingfisher
import NostrSDK
import UIKit

protocol CreateProfileViewControllerDelegate: AnyObject {
    func createProfileDidComplete()
    func createProfileDidCancel()
}

final class CreateProfileViewController: UIViewController, EventCreating {
    
    // MARK: - Dependencies
    private let appState: AppState
    weak var delegate: CreateProfileViewControllerDelegate?
    
    // MARK: - State
    private var currentStep: Int = 0 {
        didSet { updateStep(from: oldValue) }
    }
    private let keypair: Keypair
    private var credentialHandler: CredentialHandler
    
    // Form data
    private var username: String = ""
    private var displayName: String = ""
    private var pictureURL: String = ""
    private var pendingProfileImage: UIImage?
    
    // Key backup state
    private var hasCopiedPublicKey: Bool = false
    private var hasCopiedPrivateKey: Bool = false
    private var hasAcknowledgedBackup: Bool = false
    
    // MARK: - UI Components
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let progressBar = OnboardingProgressBar()
    
    // Step containers
    private var stepViews: [UIView] = []
    private var step1View: UIView!
    private var step2View: UIView!
    private var step3View: UIView!
    
    // Step 1 components
    private var usernameField: EditProfileFieldView!
    private var displayNameField: EditProfileFieldView!
    
    // Step 2 components
    private let profilePicContainer = UIView()
    private let profilePicImageView = UIImageView()
    private let profilePicCameraOverlay = UIView()
    private var pictureURLField: EditProfileFieldView!
    
    // Step 3 components
    private var publicKeyCard: KeyDisplayCardView!
    private var privateKeyCard: KeyDisplayCardView!
    private let acknowledgmentButton = UIButton(type: .system)
    
    // Navigation
    private let actionButton = OnboardingActionButton()
    private let backButton = UIButton(type: .system)
    
    // MARK: - Initialization
    init(appState: AppState) {
        self.appState = appState
        self.keypair = Keypair()!
        self.credentialHandler = CredentialHandler(appState: appState)
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
        setupSteps()
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
        
        // Progress bar
        progressBar.totalSteps = 3
        progressBar.currentStep = 0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(progressBar)
        
        // Action button
        actionButton.setTitle("Continue")
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        view.addSubview(actionButton)
        
        // Back button
        backButton.setTitle("Back", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15)
        backButton.setTitleColor(.secondaryLabel, for: .normal)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        backButton.isHidden = true
        view.addSubview(backButton)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -16),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
            
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            actionButton.bottomAnchor.constraint(equalTo: backButton.topAnchor, constant: -12),
            
            backButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            backButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            backButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        // Tap to dismiss keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }
    
    private func setupNavigation() {
        title = "Create Profile"
        navigationItem.largeTitleDisplayMode = .never
        
        let cancelButton = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.leftBarButtonItem = cancelButton
        
        let stepLabel = UIBarButtonItem(title: "Step 1/3", style: .plain, target: nil, action: nil)
        stepLabel.isEnabled = false
        stepLabel.setTitleTextAttributes([.foregroundColor: UIColor.secondaryLabel], for: .disabled)
        navigationItem.rightBarButtonItem = stepLabel
    }
    
    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Setup Steps
    private func setupSteps() {
        step1View = createStep1()
        step2View = createStep2()
        step3View = createStep3()
        
        stepViews = [step1View, step2View, step3View]
        
        // Add first step
        contentStack.addArrangedSubview(step1View)
        
        // Hide other steps initially
        step2View.alpha = 0
        step3View.alpha = 0
    }
    
    private func createStep1() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        // Header
        let header = OnboardingHeaderView(
            icon: "person.circle.fill",
            iconColor: .editProfilePurple,
            title: "Create Your Profile",
            subtitle: "Choose a username to get started"
        )
        stack.addArrangedSubview(header)
        
        // Identity card
        let card = EditProfileCardView(header: "Identity")
        
        usernameField = EditProfileFieldView(configuration: .init(
            icon: "at",
            label: "Username",
            placeholder: "Enter username",
            maxCharacters: 30,
            keyboardType: .asciiCapable,
            autocapitalization: .none,
            helpText: "Your username is how others will find you"
        ))
        usernameField.delegate = self
        card.addField(usernameField)
        
        displayNameField = EditProfileFieldView(configuration: .init(
            icon: "person.fill",
            label: "Display Name (Optional)",
            placeholder: "Enter display name",
            maxCharacters: 50,
            helpText: "A friendly name that appears on your profile"
        ))
        displayNameField.delegate = self
        card.addField(displayNameField)
        
        stack.addArrangedSubview(card)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        
        return container
    }
    
    private func createStep2() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        // Header
        let header = OnboardingHeaderView(
            icon: "photo.circle.fill",
            iconColor: .editProfilePurple,
            title: "Customize Your Profile",
            subtitle: "Add a profile picture (optional)"
        )
        stack.addArrangedSubview(header)
        
        // Profile picture preview
        setupProfilePicPreview()
        stack.addArrangedSubview(profilePicContainer)
        
        // URL input card
        let card = EditProfileCardView(header: "Or enter a URL")
        
        pictureURLField = EditProfileFieldView(configuration: .init(
            icon: "link",
            label: "Profile Picture URL",
            placeholder: "https://example.com/image.png",
            keyboardType: .URL,
            autocapitalization: .none
        ))
        pictureURLField.delegate = self
        card.addField(pictureURLField)
        
        stack.addArrangedSubview(card)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        
        return container
    }
    
    private func setupProfilePicPreview() {
        profilePicContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Profile pic image
        profilePicImageView.contentMode = .scaleAspectFill
        profilePicImageView.clipsToBounds = true
        profilePicImageView.layer.cornerRadius = 60
        profilePicImageView.layer.borderWidth = 4
        profilePicImageView.layer.borderColor = UIColor.editProfilePurple.cgColor
        profilePicImageView.backgroundColor = .systemGray5
        profilePicImageView.image = UIImage(named: "swae")
        profilePicImageView.translatesAutoresizingMaskIntoConstraints = false
        profilePicContainer.addSubview(profilePicImageView)
        
        // Camera overlay
        profilePicCameraOverlay.backgroundColor = .editProfilePurple
        profilePicCameraOverlay.layer.cornerRadius = 16
        profilePicCameraOverlay.translatesAutoresizingMaskIntoConstraints = false
        profilePicContainer.addSubview(profilePicCameraOverlay)
        
        let cameraIcon = UIImageView()
        cameraIcon.image = UIImage(systemName: "camera.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        cameraIcon.tintColor = .white
        cameraIcon.translatesAutoresizingMaskIntoConstraints = false
        profilePicCameraOverlay.addSubview(cameraIcon)
        
        NSLayoutConstraint.activate([
            profilePicContainer.heightAnchor.constraint(equalToConstant: 140),
            
            profilePicImageView.centerXAnchor.constraint(equalTo: profilePicContainer.centerXAnchor),
            profilePicImageView.centerYAnchor.constraint(equalTo: profilePicContainer.centerYAnchor),
            profilePicImageView.widthAnchor.constraint(equalToConstant: 120),
            profilePicImageView.heightAnchor.constraint(equalToConstant: 120),
            
            profilePicCameraOverlay.trailingAnchor.constraint(equalTo: profilePicImageView.trailingAnchor),
            profilePicCameraOverlay.bottomAnchor.constraint(equalTo: profilePicImageView.bottomAnchor),
            profilePicCameraOverlay.widthAnchor.constraint(equalToConstant: 32),
            profilePicCameraOverlay.heightAnchor.constraint(equalToConstant: 32),
            
            cameraIcon.centerXAnchor.constraint(equalTo: profilePicCameraOverlay.centerXAnchor),
            cameraIcon.centerYAnchor.constraint(equalTo: profilePicCameraOverlay.centerYAnchor),
        ])
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(profilePicTapped))
        profilePicContainer.addGestureRecognizer(tap)
        profilePicContainer.isUserInteractionEnabled = true
    }
    
    private func createStep3() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        // Header
        let header = OnboardingHeaderView(
            icon: "key.fill",
            iconColor: .editProfileAmber,
            title: "Backup Your Keys",
            subtitle: "Save these keys securely - you'll need them to sign in"
        )
        stack.addArrangedSubview(header)
        
        // Warning box
        let warningBox = createWarningBox()
        stack.addArrangedSubview(warningBox)
        
        // Public key card
        publicKeyCard = KeyDisplayCardView(keyType: .publicKey)
        publicKeyCard.setKey(keypair.publicKey.npub)
        publicKeyCard.onCopy = { [weak self] in
            self?.hasCopiedPublicKey = true
        }
        stack.addArrangedSubview(publicKeyCard)
        
        // Private key card
        privateKeyCard = KeyDisplayCardView(keyType: .privateKey)
        privateKeyCard.setKey(keypair.privateKey.nsec)
        privateKeyCard.onCopy = { [weak self] in
            self?.hasCopiedPrivateKey = true
            self?.updateAcknowledgmentVisibility()
        }
        stack.addArrangedSubview(privateKeyCard)
        
        // Acknowledgment button
        setupAcknowledgmentButton()
        stack.addArrangedSubview(acknowledgmentButton)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        
        return container
    }
    
    private func createWarningBox() -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.editProfileAmber.withAlphaComponent(0.1)
        box.layer.cornerRadius = 12
        box.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.spacing = 8
        
        let icon = UIImageView()
        icon.image = UIImage(systemName: "exclamationmark.triangle.fill")
        icon.tintColor = .editProfileAmber
        icon.setContentHuggingPriority(.required, for: .horizontal)
        
        let titleLabel = UILabel()
        titleLabel.text = "Important"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        
        headerStack.addArrangedSubview(icon)
        headerStack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(headerStack)
        
        let messageLabel = UILabel()
        messageLabel.text = "Your private key cannot be recovered if lost. Save it in a secure password manager."
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        stack.addArrangedSubview(messageLabel)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        
        return box
    }
    
    private func setupAcknowledgmentButton() {
        acknowledgmentButton.isHidden = true
        acknowledgmentButton.translatesAutoresizingMaskIntoConstraints = false
        acknowledgmentButton.addTarget(self, action: #selector(acknowledgmentTapped), for: .touchUpInside)
        updateAcknowledgmentButton()
    }
    
    private func updateAcknowledgmentButton() {
        let icon = hasAcknowledgedBackup ? "checkmark.square.fill" : "square"
        let color: UIColor = hasAcknowledgedBackup ? .editProfilePurple : .secondaryLabel
        
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18))
        config.title = "I've saved my private key securely"
        config.imagePadding = 12
        config.baseForegroundColor = color
        
        acknowledgmentButton.configuration = config
    }
    
    private func updateAcknowledgmentVisibility() {
        guard hasCopiedPrivateKey else { return }
        
        acknowledgmentButton.isHidden = false
        acknowledgmentButton.alpha = 0
        acknowledgmentButton.transform = CGAffineTransform(translationX: 0, y: 10)
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.acknowledgmentButton.alpha = 1
            self.acknowledgmentButton.transform = .identity
        }
    }

    
    // MARK: - Step Navigation
    private func updateStep(from oldStep: Int) {
        progressBar.currentStep = currentStep
        
        // Update navigation
        navigationItem.rightBarButtonItem?.title = "Step \(currentStep + 1)/3"
        backButton.isHidden = currentStep == 0
        
        // Transition views
        let oldView = stepViews[oldStep]
        let newView = stepViews[currentStep]
        
        let isForward = currentStep > oldStep
        let offset: CGFloat = isForward ? 50 : -50
        
        // Add new view if needed
        if newView.superview == nil {
            contentStack.addArrangedSubview(newView)
        }
        
        newView.alpha = 0
        newView.transform = CGAffineTransform(translationX: offset, y: 0)
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            oldView.alpha = 0
            oldView.transform = CGAffineTransform(translationX: -offset, y: 0)
        } completion: { _ in
            oldView.removeFromSuperview()
            oldView.transform = .identity
        }
        
        UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseOut) {
            newView.alpha = 1
            newView.transform = .identity
        }
        
        updateActionButton()
    }
    
    private func updateActionButton() {
        switch currentStep {
        case 0:
            actionButton.setTitle("Continue")
            actionButton.isEnabled = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            actionButton.setTitle("Next")
            actionButton.isEnabled = true // Profile pic is optional
        case 2:
            actionButton.setTitle("Create Profile")
            actionButton.isEnabled = hasCopiedPrivateKey && hasAcknowledgedBackup
        default:
            break
        }
    }
    
    // MARK: - Actions
    @objc private func actionButtonTapped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if currentStep < 2 {
            currentStep += 1
        } else {
            createProfile()
        }
    }
    
    @objc private func backButtonTapped() {
        if currentStep > 0 {
            currentStep -= 1
        }
    }
    
    @objc private func cancelTapped() {
        delegate?.createProfileDidCancel()
        dismiss(animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func profilePicTapped() {
        let picker = ImageSourcePickerViewController(
            imageType: .profilePicture,
            hasExistingImage: pendingProfileImage != nil || !pictureURL.isEmpty
        )
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func acknowledgmentTapped() {
        let alert = UIAlertController(
            title: "Backup Your Keys",
            message: "Make sure you've copied and saved your private key. You won't be able to recover it later!",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Go Back", style: .cancel))
        alert.addAction(UIAlertAction(title: "I've Saved My Keys", style: .destructive) { [weak self] _ in
            self?.hasAcknowledgedBackup = true
            self?.updateAcknowledgmentButton()
            self?.updateActionButton()
        })
        
        present(alert, animated: true)
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
    
    // MARK: - Profile Picture
    private func loadProfilePicture(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        profilePicImageView.kf.setImage(
            with: url,
            placeholder: UIImage(named: "swae"),
            options: [.transition(.fade(0.3))]
        )
    }
    
    // MARK: - Create Profile
    private func createProfile() {
        actionButton.isLoading = true
        
        Task { [weak self] in
            guard let self else { return }
            
            // Upload pending image if we have one
            var finalPictureURL = self.pictureURL
            if let pendingImage = self.pendingProfileImage {
                do {
                    let url = try await ImageUploadManager.shared.uploadImage(
                        pendingImage,
                        purpose: .profilePicture,
                        keypair: self.keypair
                    )
                    finalPictureURL = url.absoluteString
                } catch {
                    await MainActor.run {
                        self.actionButton.isLoading = false
                        let alert = UIAlertController(
                            title: "Upload Failed",
                            message: "Could not upload profile picture. Try again or skip.",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
                            self.createProfile()
                        })
                        alert.addAction(UIAlertAction(title: "Skip Photo", style: .destructive) { _ in
                            self.pendingProfileImage = nil
                            self.createProfile()
                        })
                        self.present(alert, animated: true)
                    }
                    return
                }
            }
            
            await MainActor.run {
                self.finishProfileCreation(pictureURLString: finalPictureURL)
            }
        }
    }
    
    private func finishProfileCreation(pictureURLString: String) {
        credentialHandler.saveCredential(keypair: keypair)
        
        let validatedPictureURL = URL(string: pictureURLString.trimmingCharacters(in: .whitespacesAndNewlines))
        
        let userMetadata = UserMetadata(
            name: username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            pictureURL: validatedPictureURL
        )
        
        do {
            let readRelayURLs = appState.relayReadPool.relays.map { $0.url }
            let writeRelayURLs = appState.relayWritePool.relays.map { $0.url }
            
            let metadataEvent = try metadataEvent(withUserMetadata: userMetadata, signedBy: keypair)
            let followListEvent = try followList(withPubkeys: [keypair.publicKey.hex], signedBy: keypair)
            
            appState.relayWritePool.publishEvent(metadataEvent)
            appState.relayWritePool.publishEvent(followListEvent)
            
            let persistentNostrEvents = [
                PersistentNostrEvent(nostrEvent: metadataEvent),
                PersistentNostrEvent(nostrEvent: followListEvent)
            ]
            persistentNostrEvents.forEach {
                appState.modelContext.insert($0)
            }
            
            try appState.modelContext.save()
            appState.loadPersistentNostrEvents(persistentNostrEvents)
            appState.signIn(keypair: keypair, relayURLs: Array(Set(readRelayURLs + writeRelayURLs)))
            
            // Cache display metadata on the newly created profile for offline account picker
            if let profile = appState.profiles.first(where: { $0.publicKeyHex == keypair.publicKey.hex }) {
                profile.cachedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.cachedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.cachedProfilePictureURL = validatedPictureURL?.absoluteString
                try? appState.modelContext.save()
            }
            
            actionButton.isLoading = false
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            delegate?.createProfileDidComplete()
            
        } catch {
            actionButton.isLoading = false
            
            let alert = UIAlertController(
                title: "Error",
                message: "Failed to create profile. Please try again.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

// MARK: - EditProfileFieldViewDelegate
extension CreateProfileViewController: EditProfileFieldViewDelegate {
    
    func fieldDidBeginEditing(_ field: EditProfileFieldView) {
        // Scroll to field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let fieldFrame = field.convert(field.bounds, to: self.scrollView)
            let visibleRect = CGRect(x: 0, y: fieldFrame.minY - 20, width: self.scrollView.bounds.width, height: fieldFrame.height + 40)
            self.scrollView.scrollRectToVisible(visibleRect, animated: true)
        }
    }
    
    func fieldDidEndEditing(_ field: EditProfileFieldView) {
        updateActionButton()
    }
    
    func fieldDidChangeText(_ field: EditProfileFieldView, text: String) {
        if field === usernameField {
            username = text
        } else if field === displayNameField {
            displayName = text
        } else if field === pictureURLField {
            pictureURL = text
            if !text.isEmpty {
                loadProfilePicture(from: text)
            }
        }
        updateActionButton()
    }
}

// MARK: - ImageSourcePickerDelegate
extension CreateProfileViewController: ImageSourcePickerDelegate {
    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didEnterURL url: URL) {
        pictureURL = url.absoluteString
        pictureURLField.text = url.absoluteString
        pendingProfileImage = nil
        loadProfilePicture(from: url.absoluteString)
    }
    
    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didSelectImage image: UIImage) {
        let cropper = ImageCropperViewController(image: image, cropShape: .circle)
        cropper.cropDelegate = self
        present(cropper, animated: true)
    }
    
    func imageSourcePickerDidRemoveImage(_ picker: ImageSourcePickerViewController) {
        pictureURL = ""
        pictureURLField.text = ""
        pendingProfileImage = nil
        profilePicImageView.image = UIImage(named: "swae")
    }
    
    func imageSourcePickerDidCancel(_ picker: ImageSourcePickerViewController) {}
}

// MARK: - ImageCropperDelegate
extension CreateProfileViewController: ImageCropperDelegate {
    func imageCropper(_ cropper: ImageCropperViewController, didCropImage image: UIImage) {
        pendingProfileImage = image
        profilePicImageView.image = image
        // Clear URL field since we're using a local image now
        pictureURL = ""
        pictureURLField.text = ""
    }
    
    func imageCropperDidCancel(_ cropper: ImageCropperViewController) {}
}
