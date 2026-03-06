//
//  ImageSourcePickerViewController.swift
//  swae
//
//  Bottom sheet picker for image source selection
//

import PhotosUI
import UIKit

protocol ImageSourcePickerDelegate: AnyObject {
    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didEnterURL url: URL)
    func imageSourcePicker(_ picker: ImageSourcePickerViewController, didSelectImage image: UIImage)
    func imageSourcePickerDidRemoveImage(_ picker: ImageSourcePickerViewController)
    func imageSourcePickerDidCancel(_ picker: ImageSourcePickerViewController)
}

final class ImageSourcePickerViewController: UIViewController {
    
    enum ImageType {
        case profilePicture
        case banner
        case streamCover
        
        var title: String {
            switch self {
            case .profilePicture: return "Change Profile Picture"
            case .banner: return "Change Banner"
            case .streamCover: return "Change Cover Image"
            }
        }
    }
    
    // MARK: - Properties
    weak var delegate: ImageSourcePickerDelegate?
    let imageType: ImageType  // Made public for delegate access
    private let hasExistingImage: Bool
    
    // MARK: - UI Components
    private let containerStack = UIStackView()
    private let titleLabel = UILabel()
    private let chooseFromLibraryButton = UIButton(type: .system)
    private let takePhotoButton = UIButton(type: .system)
    private let enterURLButton = UIButton(type: .system)
    private let removeButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    
    // MARK: - Initialization
    init(imageType: ImageType, hasExistingImage: Bool) {
        self.imageType = imageType
        self.hasExistingImage = hasExistingImage
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureSheetPresentation()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Container stack
        containerStack.axis = .vertical
        containerStack.spacing = 12
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerStack)
        
        // Title
        titleLabel.text = imageType.title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textAlignment = .center
        containerStack.addArrangedSubview(titleLabel)
        
        // Spacer
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        containerStack.addArrangedSubview(spacer)
        
        // Choose from Library button
        configureButton(
            chooseFromLibraryButton,
            title: "Choose from Library",
            icon: "photo.on.rectangle",
            backgroundColor: .secondarySystemGroupedBackground
        )
        chooseFromLibraryButton.addTarget(self, action: #selector(chooseFromLibraryTapped), for: .touchUpInside)
        containerStack.addArrangedSubview(chooseFromLibraryButton)
        
        // Take Photo button (only if camera is available)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            configureButton(
                takePhotoButton,
                title: "Take Photo",
                icon: "camera",
                backgroundColor: .secondarySystemGroupedBackground
            )
            takePhotoButton.addTarget(self, action: #selector(takePhotoTapped), for: .touchUpInside)
            containerStack.addArrangedSubview(takePhotoButton)
        }
        
        // Enter URL button
        configureButton(
            enterURLButton,
            title: "Enter Image URL",
            icon: "link",
            backgroundColor: .secondarySystemGroupedBackground
        )
        enterURLButton.addTarget(self, action: #selector(enterURLTapped), for: .touchUpInside)
        containerStack.addArrangedSubview(enterURLButton)
        
        // Remove button (only if has existing image)
        if hasExistingImage {
            configureButton(
                removeButton,
                title: "Remove Current Image",
                icon: "trash",
                backgroundColor: .secondarySystemGroupedBackground,
                tintColor: .editProfileError
            )
            removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
            containerStack.addArrangedSubview(removeButton)
        }
        
        // Cancel button
        configureButton(
            cancelButton,
            title: "Cancel",
            icon: "xmark",
            backgroundColor: .tertiarySystemGroupedBackground
        )
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        containerStack.addArrangedSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            containerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }
    
    private func configureButton(
        _ button: UIButton,
        title: String,
        icon: String,
        backgroundColor: UIColor,
        tintColor: UIColor = .label
    ) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        config.imagePadding = 12
        config.baseForegroundColor = tintColor
        config.baseBackgroundColor = backgroundColor
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true
    }
    
    private func configureSheetPresentation() {
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
    }
    
    // MARK: - Actions
    @objc private func enterURLTapped() {
        showURLInputAlert()
    }
    
    @objc private func chooseFromLibraryTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func takePhotoTapped() {
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.allowsEditing = false
        camera.delegate = self
        present(camera, animated: true)
    }
    
    @objc private func removeTapped() {
        delegate?.imageSourcePickerDidRemoveImage(self)
        dismiss(animated: true)
    }
    
    @objc private func cancelTapped() {
        delegate?.imageSourcePickerDidCancel(self)
        dismiss(animated: true)
    }
    
    // MARK: - URL Input Alert
    private func showURLInputAlert() {
        let alert = UIAlertController(
            title: "Enter Image URL",
            message: "Paste a direct link to an image (PNG, JPG, GIF)",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/image.png"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        let confirmAction = UIAlertAction(title: "Confirm", style: .default) { [weak self, weak alert] _ in
            guard let self = self,
                  let urlString = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: urlString),
                  url.scheme == "http" || url.scheme == "https" else {
                self?.showInvalidURLAlert()
                return
            }
            
            self.delegate?.imageSourcePicker(self, didEnterURL: url)
            self.dismiss(animated: true)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        
        alert.addAction(confirmAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
    }
    
    private func showInvalidURLAlert() {
        let alert = UIAlertController(
            title: "Invalid URL",
            message: "Please enter a valid image URL starting with http:// or https://",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.showURLInputAlert()
        })
        present(alert, animated: true)
    }
}


// MARK: - PHPickerViewControllerDelegate
extension ImageSourcePickerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let provider = results.first?.itemProvider else { return }
        
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                guard let self else { return }
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.dismiss(animated: true) {
                            self.delegate?.imageSourcePicker(self, didSelectImage: image)
                        }
                    }
                } else {
                    // UIImage load failed — try file-based fallback (handles RAW)
                    self.loadImageViaFile(provider: provider)
                }
            }
        } else {
            // canLoadObject returned false — try file-based fallback (handles RAW)
            loadImageViaFile(provider: provider)
        }
    }
    
    private func loadImageViaFile(provider: NSItemProvider) {
        let typeIdentifier = provider.registeredTypeIdentifiers.first ?? "public.image"
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
            guard let self else { return }
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self.showUnsupportedImageAlert()
                }
                return
            }
            DispatchQueue.main.async {
                self.dismiss(animated: true) {
                    self.delegate?.imageSourcePicker(self, didSelectImage: image)
                }
            }
        }
    }
    
    private func showUnsupportedImageAlert() {
        let alert = UIAlertController(
            title: "Unsupported Image",
            message: "This image format couldn't be loaded. Try using a JPEG or PNG instead.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIImagePickerControllerDelegate
extension ImageSourcePickerViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.originalImage] as? UIImage else {
            picker.dismiss(animated: true)
            return
        }
        // Dismiss camera, then dismiss ourselves, then notify delegate
        picker.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.delegate?.imageSourcePicker(self, didSelectImage: image)
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
