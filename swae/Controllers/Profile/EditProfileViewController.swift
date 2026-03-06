//
//  EditProfileViewController.swift
//  swae
//
//  Clean, minimal profile editor
//

import Combine
import Kingfisher
import NostrSDK
import UIKit

final class EditProfileViewController: UIViewController {
    
    // MARK: - Dependencies
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Original Values
    private var originalDisplayName: String = ""
    private var originalUsername: String = ""
    private var originalBio: String = ""
    private var originalWebsite: String = ""
    private var originalNip05: String = ""
    private var originalLightningAddress: String = ""
    private var originalPictureURL: String = ""
    private var originalBannerURL: String = ""
    
    // MARK: - Current Values
    private var currentPictureURL: String = ""
    private var currentBannerURL: String = ""
    private var pendingUploadImage: UIImage?
    private var uploadProgressView: ImageUploadProgressView?
    private var activeUploadTask: Task<Void, Never>?
    private var isUploadInProgress = false
    
    // MARK: - Save State
    private enum SaveState: Equatable {
        case idle
        case saving
        case success
        case error(String)
    }
    private var saveState: SaveState = .idle {
        didSet { updateSaveButtonState() }
    }
    
    // MARK: - UI Components
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    
    // Profile images
    private let bannerImageView = UIImageView()
    private let profileImageView = UIImageView()
    private var bannerContainer: UIView!
    private var profileEditBadge: UIView!
    
    // Fields - simple flat list
    private var displayNameField: EditProfileFieldView!
    private var usernameField: EditProfileFieldView!
    private var bioField: EditProfileFieldView!
    private var websiteField: EditProfileFieldView!
    private var nip05Field: EditProfileFieldView!
    private var lightningAddressField: EditProfileFieldView!
    
    // Navigation
    private var saveButton: UIBarButtonItem!
    
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
        loadExistingProfile()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        setupScrollView()
        setupProfileImage()
        setupFields()
        setupTapToDismissKeyboard()
    }
    
    private func setupScrollView() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }
    
    private func setupProfileImage() {
        // Banner container
        bannerContainer = UIView()
        bannerContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // Banner image
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.backgroundColor = .secondarySystemBackground
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(bannerImageView)
        
        // Banner gradient overlay for better visibility
        let gradientView = UIView()
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(gradientView)
        
        // Banner edit button
        let bannerEditButton = UIButton(type: .system)
        bannerEditButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        bannerEditButton.tintColor = .white
        bannerEditButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        bannerEditButton.layer.cornerRadius = 16
        bannerEditButton.translatesAutoresizingMaskIntoConstraints = false
        bannerEditButton.addTarget(self, action: #selector(bannerTapped), for: .touchUpInside)
        bannerContainer.addSubview(bannerEditButton)
        
        // "Change Banner" label
        let bannerLabel = UILabel()
        bannerLabel.text = "Change Banner"
        bannerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        bannerLabel.textColor = .white
        bannerLabel.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(bannerLabel)
        
        // Profile image - overlapping banner (88x88 circle)
        profileImageView.clipsToBounds = true
        profileImageView.layer.cornerRadius = 44
        profileImageView.layer.borderWidth = 2
        profileImageView.layer.borderColor = UIColor.systemBackground.cgColor
        profileImageView.backgroundColor = .systemGray5
        let placeholderConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        profileImageView.image = UIImage(systemName: "person.fill", withConfiguration: placeholderConfig)
        profileImageView.tintColor = .systemGray2
        profileImageView.contentMode = .center
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(profileImageView)
        
        // Profile edit badge
        profileEditBadge = UIView()
        profileEditBadge.backgroundColor = .accentPurple
        profileEditBadge.layer.cornerRadius = 14
        profileEditBadge.translatesAutoresizingMaskIntoConstraints = false
        bannerContainer.addSubview(profileEditBadge)
        
        let cameraIcon = UIImageView(image: UIImage(systemName: "camera.fill"))
        cameraIcon.tintColor = .white
        cameraIcon.contentMode = .scaleAspectFit
        cameraIcon.translatesAutoresizingMaskIntoConstraints = false
        profileEditBadge.addSubview(cameraIcon)
        
        // Profile tap gesture
        let profileTap = UITapGestureRecognizer(target: self, action: #selector(profileImageTapped))
        profileImageView.isUserInteractionEnabled = true
        profileImageView.addGestureRecognizer(profileTap)
        profileEditBadge.isUserInteractionEnabled = true
        profileEditBadge.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profileImageTapped)))
        
        contentStack.addArrangedSubview(bannerContainer)
        
        // Fields container with padding
        let fieldsContainer = UIView()
        fieldsContainer.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(fieldsContainer)
        
        NSLayoutConstraint.activate([
            bannerContainer.heightAnchor.constraint(equalToConstant: 180),
            
            bannerImageView.topAnchor.constraint(equalTo: bannerContainer.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: 130),
            
            gradientView.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),
            
            bannerEditButton.centerXAnchor.constraint(equalTo: bannerImageView.centerXAnchor),
            bannerEditButton.centerYAnchor.constraint(equalTo: bannerImageView.centerYAnchor, constant: -10),
            bannerEditButton.widthAnchor.constraint(equalToConstant: 32),
            bannerEditButton.heightAnchor.constraint(equalToConstant: 32),
            
            bannerLabel.centerXAnchor.constraint(equalTo: bannerImageView.centerXAnchor),
            bannerLabel.topAnchor.constraint(equalTo: bannerEditButton.bottomAnchor, constant: 4),
            
            profileImageView.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor, constant: 16),
            profileImageView.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 88),
            profileImageView.heightAnchor.constraint(equalTo: profileImageView.widthAnchor),  // Force square aspect ratio
            
            profileEditBadge.trailingAnchor.constraint(equalTo: profileImageView.trailingAnchor),
            profileEditBadge.bottomAnchor.constraint(equalTo: profileImageView.bottomAnchor),
            profileEditBadge.widthAnchor.constraint(equalToConstant: 28),
            profileEditBadge.heightAnchor.constraint(equalToConstant: 28),
            
            cameraIcon.centerXAnchor.constraint(equalTo: profileEditBadge.centerXAnchor),
            cameraIcon.centerYAnchor.constraint(equalTo: profileEditBadge.centerYAnchor),
            cameraIcon.widthAnchor.constraint(equalToConstant: 14),
            cameraIcon.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
    
    private func setupFields() {
        // Create a container with horizontal padding for fields
        let fieldsStack = UIStackView()
        fieldsStack.axis = .vertical
        fieldsStack.spacing = 24
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false
        fieldsStack.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 0, right: 20)
        fieldsStack.isLayoutMarginsRelativeArrangement = true
        
        // Display Name
        displayNameField = EditProfileFieldView(configuration: .init(
            icon: "person.fill",
            label: "Name",
            placeholder: "Display name"
        ))
        displayNameField.delegate = self
        fieldsStack.addArrangedSubview(displayNameField)
        
        // Username
        usernameField = EditProfileFieldView(configuration: .init(
            icon: "at",
            label: "Username",
            placeholder: "username",
            keyboardType: .asciiCapable,
            autocapitalization: .none
        ))
        usernameField.delegate = self
        fieldsStack.addArrangedSubview(usernameField)
        
        // Bio
        bioField = EditProfileFieldView(configuration: .init(
            icon: "text.alignleft",
            label: "Bio",
            placeholder: "Write something about yourself",
            isMultiline: true
        ))
        bioField.delegate = self
        fieldsStack.addArrangedSubview(bioField)
        
        // Website
        websiteField = EditProfileFieldView(configuration: .init(
            icon: "globe",
            label: "Website",
            placeholder: "https://",
            keyboardType: .URL,
            autocapitalization: .none
        ))
        websiteField.delegate = self
        fieldsStack.addArrangedSubview(websiteField)
        
        // NIP-05
        nip05Field = EditProfileFieldView(configuration: .init(
            icon: "checkmark.seal.fill",
            label: "Verification (NIP-05)",
            placeholder: "you@domain.com",
            keyboardType: .emailAddress,
            autocapitalization: .none
        ))
        nip05Field.delegate = self
        fieldsStack.addArrangedSubview(nip05Field)
        
        // Lightning Address
        lightningAddressField = EditProfileFieldView(configuration: .init(
            icon: "bolt.fill",
            label: "Lightning Address",
            placeholder: "you@wallet.com",
            keyboardType: .emailAddress,
            autocapitalization: .none
        ))
        lightningAddressField.delegate = self
        fieldsStack.addArrangedSubview(lightningAddressField)
        
        contentStack.addArrangedSubview(fieldsStack)
    }
    
    private func setupNavigation() {
        title = "Edit Profile"
        navigationItem.largeTitleDisplayMode = .never
        
        // Cancel button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        
        // Save button
        saveButton = UIBarButtonItem(
            title: "Save",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        saveButton.tintColor = .accentPurple
        saveButton.isEnabled = false
        navigationItem.rightBarButtonItem = saveButton
    }
    
    private func setupTapToDismissKeyboard() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }
    
    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    // MARK: - Load Profile
    private func loadExistingProfile() {
        guard let publicKeyHex = appState.publicKey?.hex,
              let metadataEvent = appState.metadataEvents[publicKeyHex] else {
            return
        }
        
        let metadata = metadataEvent.userMetadata
        
        // Store originals
        originalDisplayName = metadata?.displayName ?? ""
        originalUsername = metadata?.name ?? ""
        originalBio = metadata?.about ?? ""
        originalWebsite = metadata?.website?.absoluteString ?? ""
        originalNip05 = metadata?.nostrAddress ?? ""
        originalLightningAddress = metadata?.lightningAddress ?? ""
        originalPictureURL = metadata?.pictureURL?.absoluteString ?? ""
        originalBannerURL = metadata?.bannerPictureURL?.absoluteString ?? ""
        
        currentPictureURL = originalPictureURL
        currentBannerURL = originalBannerURL
        
        // Populate fields
        displayNameField.text = originalDisplayName
        usernameField.text = originalUsername
        bioField.text = originalBio
        websiteField.text = originalWebsite
        nip05Field.text = originalNip05
        lightningAddressField.text = originalLightningAddress
        
        // Load profile image
        if let pictureURL = metadata?.pictureURL {
            profileImageView.contentMode = .scaleAspectFill  // Switch to fill mode for actual image
            profileImageView.kf.setImage(
                with: pictureURL,
                options: [.transition(.fade(0.2))]
            )
        }
        
        // Load banner image
        if let bannerURL = metadata?.bannerPictureURL {
            bannerImageView.kf.setImage(
                with: bannerURL,
                options: [.transition(.fade(0.2))]
            )
        }
    }
    
    // MARK: - Change Detection
    private func hasUnsavedChanges() -> Bool {
        return displayNameField.text != originalDisplayName ||
               usernameField.text != originalUsername ||
               bioField.text != originalBio ||
               websiteField.text != originalWebsite ||
               nip05Field.text != originalNip05 ||
               lightningAddressField.text != originalLightningAddress ||
               currentPictureURL != originalPictureURL ||
               currentBannerURL != originalBannerURL
    }
    
    private func updateSaveButtonState() {
        let hasChanges = hasUnsavedChanges()
        
        switch saveState {
        case .idle:
            saveButton.isEnabled = hasChanges && !isUploadInProgress
            saveButton.title = isUploadInProgress ? "Uploading..." : "Save"
        case .saving:
            saveButton.isEnabled = false
            saveButton.title = "Saving..."
        case .success:
            saveButton.isEnabled = false
            saveButton.title = "✓"
        case .error:
            saveButton.isEnabled = true
            saveButton.title = "Retry"
        }
    }
    
    // MARK: - Validation
    private func validateFields() -> Bool {
        var isValid = true
        
        // Username
        let username = usernameField.text
        if !username.isEmpty {
            let regex = "^[a-zA-Z0-9_]+$"
            if !NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: username) {
                usernameField.isValid = false
                usernameField.errorMessage = "Letters, numbers, and underscores only"
                isValid = false
            } else {
                usernameField.isValid = true
                usernameField.errorMessage = nil
            }
        }
        
        // Website
        let website = websiteField.text
        if !website.isEmpty {
            if URL(string: website) == nil || (!website.hasPrefix("http://") && !website.hasPrefix("https://")) {
                websiteField.isValid = false
                websiteField.errorMessage = "Enter a valid URL"
                isValid = false
            } else {
                websiteField.isValid = true
                websiteField.errorMessage = nil
            }
        }
        
        // NIP-05
        let nip05 = nip05Field.text
        if !nip05.isEmpty {
            let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
            if !NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: nip05) {
                nip05Field.isValid = false
                nip05Field.errorMessage = "Enter a valid address"
                isValid = false
            } else {
                nip05Field.isValid = true
                nip05Field.errorMessage = nil
            }
        }
        
        // Lightning
        let lnAddress = lightningAddressField.text
        if !lnAddress.isEmpty {
            let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
            if !NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: lnAddress) {
                lightningAddressField.isValid = false
                lightningAddressField.errorMessage = "Enter a valid address"
                isValid = false
            } else {
                lightningAddressField.isValid = true
                lightningAddressField.errorMessage = nil
            }
        }
        
        return isValid
    }
    
    // MARK: - Save
    private func saveProfile() {
        guard validateFields() else { return }
        guard let keypair = appState.keypair else { return }
        
        saveState = .saving
        
        let userMetadata = UserMetadata(
            name: usernameField.text.trimmedOrNilIfEmpty,
            displayName: displayNameField.text.trimmedOrNilIfEmpty,
            about: bioField.text.trimmedOrNilIfEmpty,
            website: URL(string: websiteField.text),
            nostrAddress: nip05Field.text.trimmedOrNilIfEmpty,
            pictureURL: URL(string: currentPictureURL),
            bannerPictureURL: URL(string: currentBannerURL),
            lightningAddress: lightningAddressField.text.trimmedOrNilIfEmpty
        )
        
        do {
            let metadataEvent = try MetadataEvent.Builder()
                .userMetadata(userMetadata)
                .build(signedBy: keypair)
            
            appState.relayWritePool.publishEvent(metadataEvent)
            appState.metadataEvents[keypair.publicKey.hex] = metadataEvent
            
            let persistentEvent = PersistentNostrEvent(nostrEvent: metadataEvent)
            appState.modelContext.insert(persistentEvent)
            try? appState.modelContext.save()
            
            saveState = .success
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.dismiss(animated: true)
            }
        } catch {
            saveState = .error(error.localizedDescription)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        if hasUnsavedChanges() {
            let alert = UIAlertController(
                title: "Discard Changes?",
                message: nil,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
            present(alert, animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    @objc private func saveTapped() {
        saveProfile()
    }
    
    @objc private func profileImageTapped() {
        let picker = ImageSourcePickerViewController(
            imageType: .profilePicture,
            hasExistingImage: !currentPictureURL.isEmpty
        )
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func bannerTapped() {
        let picker = ImageSourcePickerViewController(
            imageType: .banner,
            hasExistingImage: !currentBannerURL.isEmpty
        )
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = keyboardFrame.height
            self.scrollView.scrollIndicatorInsets.bottom = keyboardFrame.height
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.scrollIndicatorInsets.bottom = 0
        }
    }
}

// MARK: - ImageSourcePickerDelegate
extension EditProfileViewController: ImageSourcePickerDelegate {
    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didEnterURL url: URL) {
        switch picker.imageType {
        case .profilePicture:
            currentPictureURL = url.absoluteString
            profileImageView.contentMode = .scaleAspectFill
            profileImageView.kf.setImage(with: url, options: [.transition(.fade(0.2))])
        case .banner:
            currentBannerURL = url.absoluteString
            bannerImageView.kf.setImage(with: url, options: [.transition(.fade(0.2))])
        case .streamCover:
            break // Not used in profile editing
        }
        updateSaveButtonState()
    }
    
    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didSelectImage image: UIImage) {
        let imageType = picker.imageType
        let cropShape: CropOverlayView.CropShape
        switch imageType {
        case .profilePicture: cropShape = .circle
        case .banner: cropShape = .rect(aspectRatio: 3.0)
        case .streamCover: cropShape = .rect(aspectRatio: 16.0 / 9.0)
        }
        
        let cropper = ImageCropperViewController(image: image, cropShape: cropShape)
        cropper.cropDelegate = self
        cropper.view.tag = imageType == .profilePicture ? 0 : 1
        present(cropper, animated: true)
    }
    
    func imageSourcePickerDidRemoveImage(_ picker: ImageSourcePickerViewController) {
        switch picker.imageType {
        case .profilePicture:
            currentPictureURL = ""
            let placeholderConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .regular)
            profileImageView.image = UIImage(systemName: "person.fill", withConfiguration: placeholderConfig)
            profileImageView.contentMode = .center
            profileImageView.tintColor = .tertiaryLabel
        case .banner:
            currentBannerURL = ""
            bannerImageView.image = nil
        case .streamCover:
            break // Not used in profile editing
        }
        updateSaveButtonState()
    }
    
    func imageSourcePickerDidCancel(_ picker: ImageSourcePickerViewController) {}
}

// MARK: - ImageCropperDelegate
extension EditProfileViewController: ImageCropperDelegate {
    func imageCropper(_ cropper: ImageCropperViewController, didCropImage image: UIImage) {
        let isProfilePic = cropper.view.tag == 0
        let purpose: ImageUploadManager.ImagePurpose = isProfilePic ? .profilePicture : .banner
        
        // Remove any existing progress view
        uploadProgressView?.removeFromSuperview()
        
        // Show preview immediately
        if isProfilePic {
            profileImageView.contentMode = .scaleAspectFill
            profileImageView.image = image
        } else {
            bannerImageView.image = image
        }
        
        // Create progress indicator
        let progress: ImageUploadProgressView
        
        if isProfilePic {
            // Spinning ring around the profile pic circle
            progress = ImageUploadProgressView(style: .ring)
            progress.translatesAutoresizingMaskIntoConstraints = false
            progress.isUserInteractionEnabled = false
            // Insert below the profile edit badge so the purple camera circle stays on top
            bannerContainer.insertSubview(progress, belowSubview: profileEditBadge)
            NSLayoutConstraint.activate([
                progress.centerXAnchor.constraint(equalTo: profileImageView.centerXAnchor),
                progress.centerYAnchor.constraint(equalTo: profileImageView.centerYAnchor),
                progress.widthAnchor.constraint(equalTo: profileImageView.widthAnchor, constant: 4),
                progress.heightAnchor.constraint(equalTo: profileImageView.heightAnchor, constant: 4),
            ])
        } else {
            // Small pill badge at bottom-right of banner
            progress = ImageUploadProgressView(style: .badge)
            progress.translatesAutoresizingMaskIntoConstraints = false
            bannerContainer.addSubview(progress)
            NSLayoutConstraint.activate([
                progress.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor, constant: -8),
                progress.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -8),
                progress.widthAnchor.constraint(equalToConstant: 28),
            ])
        }
        
        progress.setState(.uploading)
        uploadProgressView = progress
        isUploadInProgress = true
        updateSaveButtonState()
        
        // Start upload
        activeUploadTask = Task { [weak self] in
            do {
                let url = try await ImageUploadManager.shared.uploadImage(
                    image,
                    purpose: purpose,
                    keypair: self?.appState.keypair
                )
                
                await MainActor.run {
                    guard let self else { return }
                    if isProfilePic {
                        self.currentPictureURL = url.absoluteString
                    } else {
                        self.currentBannerURL = url.absoluteString
                    }
                    progress.setState(.success)
                    self.isUploadInProgress = false
                    self.updateSaveButtonState()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    progress.setState(.failed)
                    self.isUploadInProgress = false
                    progress.onRetryTapped = { [weak self, weak progress] in
                        progress?.removeFromSuperview()
                        self?.imageCropper(cropper, didCropImage: image)
                    }
                    self.updateSaveButtonState()
                }
            }
        }
    }
    
    func imageCropperDidCancel(_ cropper: ImageCropperViewController) {}
}

// MARK: - EditProfileFieldViewDelegate
extension EditProfileViewController: EditProfileFieldViewDelegate {
    func fieldDidBeginEditing(_ field: EditProfileFieldView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let fieldFrame = field.convert(field.bounds, to: self.scrollView)
            let visibleRect = CGRect(x: 0, y: fieldFrame.minY - 20, width: self.scrollView.bounds.width, height: fieldFrame.height + 40)
            self.scrollView.scrollRectToVisible(visibleRect, animated: true)
        }
    }
    
    func fieldDidEndEditing(_ field: EditProfileFieldView) {
        updateSaveButtonState()
    }
    
    func fieldDidChangeText(_ field: EditProfileFieldView, text: String) {
        updateSaveButtonState()
    }
}
