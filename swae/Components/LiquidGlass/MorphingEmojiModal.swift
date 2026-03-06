//
//  MorphingEmojiModal.swift
//  swae
//
//  Liquid glass emoji picker that morphs from the emoji button.
//  Follows the same pattern as MorphingZapModal.
//

import NostrSDK
import SDWebImage
import UIKit

class MorphingEmojiModal: UIView {

    // MARK: - State

    private(set) var isExpanded = false

    // MARK: - Layout

    private let collapsedSize: CGFloat = 40
    private let collapsedCornerRadius: CGFloat = 20
    private var modalWidth: CGFloat { UIScreen.main.bounds.width - 32 }
    private let modalHeight: CGFloat = 360
    private let modalCornerRadius: CGFloat = 38

    private var sourceFrame: CGRect = .zero
    private weak var sourceButton: UIView?
    
    // Keyboard tracking
    private var currentKeyboardHeight: CGFloat = 0

    // MARK: - Data

    private var emojiPacks: [EmojiPack] = []
    private var filteredEmojis: [(shortcode: String, url: URL)] = []
    private var allEmojis: [(shortcode: String, url: URL)] = []

    // MARK: - Callbacks

    var onEmojiSelected: ((String) -> Void)?  // returns ":shortcode:"
    var onDismissed: (() -> Void)?
    
    // Upload state
    private weak var appState: AppState?
    private var isUploading = false
    
    /// Called when the search field resigns first responder (so the caller can restore its own input bar)
    var onSearchResigned: (() -> Void)?

    // MARK: - Views

    private var morphingGlass: GlassContainerView!
    private let dimmingView = UIView()
    private let searchField = UITextField()
    private let addButton = UIButton(type: .system)
    private var collectionView: UICollectionView!
    private let emptyLabel = UILabel()

    // MARK: - Constraints

    private var glassWidthConstraint: NSLayoutConstraint!
    private var glassHeightConstraint: NSLayoutConstraint!
    private var glassCenterXConstraint: NSLayoutConstraint!
    private var glassCenterYConstraint: NSLayoutConstraint!

    // MARK: - Init

    init(sourceFrame: CGRect, emojiPacks: [EmojiPack], appState: AppState?) {
        self.sourceFrame = sourceFrame
        self.emojiPacks = emojiPacks
        self.appState = appState
        super.init(frame: UIScreen.main.bounds)
        rebuildAllEmojis()
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        setupDimming()
        setupGlass()
        setupSearch()
        setupCollection()
        setupEmptyLabel()
        updateMorphProgress(0)
        
        // Keyboard observation
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    private func setupDimming() {
        dimmingView.frame = bounds
        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0
        addSubview(dimmingView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
        dimmingView.addGestureRecognizer(tap)
    }

    private func setupGlass() {
        morphingGlass = GlassFactory.makeGlassView(cornerRadius: collapsedCornerRadius)
        morphingGlass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(morphingGlass)

        glassWidthConstraint = morphingGlass.widthAnchor.constraint(equalToConstant: collapsedSize)
        glassHeightConstraint = morphingGlass.heightAnchor.constraint(equalToConstant: collapsedSize)
        glassCenterXConstraint = morphingGlass.centerXAnchor.constraint(equalTo: leadingAnchor, constant: sourceFrame.midX)
        glassCenterYConstraint = morphingGlass.centerYAnchor.constraint(equalTo: topAnchor, constant: sourceFrame.midY)

        NSLayoutConstraint.activate([glassWidthConstraint, glassHeightConstraint, glassCenterXConstraint, glassCenterYConstraint])
    }

    private func setupSearch() {
        // NOTE: Search is temporarily disabled to avoid input bar conflicts.
        // Uncomment to re-enable search functionality.
        /*
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search emotes..."
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = .label
        searchField.backgroundColor = UIColor.systemFill
        searchField.layer.cornerRadius = 12
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        searchField.leftViewMode = .always
        searchField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        searchField.rightViewMode = .always
        searchField.alpha = 0
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.delegate = self
        morphingGlass.glassContentView.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor, constant: -48),
            searchField.heightAnchor.constraint(equalToConstant: 36),
        ])
        */
    }

    private func setupCollection() {
        let itemSize: CGFloat = 52
        let spacing: CGFloat = 8
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: itemSize, height: itemSize + 16)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(EmoteCell.self, forCellWithReuseIdentifier: EmoteCell.reuseId)
        collectionView.alpha = 0
        morphingGlass.glassContentView.addSubview(collectionView)
        
        // Add emote button at bottom
        addButton.translatesAutoresizingMaskIntoConstraints = false
        var btnConfig = UIButton.Configuration.filled()
        btnConfig.title = "Add Emote"
        btnConfig.image = UIImage(systemName: "plus.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        btnConfig.imagePadding = 6
        btnConfig.baseForegroundColor = .white
        btnConfig.baseBackgroundColor = .systemBlue.withAlphaComponent(0.6)
        btnConfig.cornerStyle = .capsule
        btnConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        addButton.configuration = btnConfig
        addButton.alpha = 0
        addButton.addTarget(self, action: #selector(addEmoteTapped), for: .touchUpInside)
        morphingGlass.glassContentView.addSubview(addButton)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),
            
            addButton.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            addButton.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor, constant: -12),
            addButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }
    
    @objc private func addEmoteTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        
        // Find the presenting view controller
        if let vc = findViewController() {
            vc.present(picker, animated: true)
        }
    }
    
    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        // Fallback: root VC
        return window?.rootViewController?.presentedViewController ?? window?.rootViewController
    }
    
    /// After image is picked, prompt for shortcode then upload
    fileprivate func handlePickedImage(_ image: UIImage) {
        // Resize to 128x128
        let size = CGSize(width: 128, height: 128)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let data = resized?.pngData() else { return }
        
        // Show shortcode prompt
        let alert = UIAlertController(title: "Emote Name", message: "Letters, numbers, underscores only", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "e.g. KEKW"
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Upload", style: .default) { [weak self] _ in
            let shortcode = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !shortcode.isEmpty,
                  shortcode.range(of: "^[_a-zA-Z0-9]+$", options: .regularExpression) != nil else { return }
            self?.uploadEmote(data: data, shortcode: shortcode)
        })
        
        findViewController()?.present(alert, animated: true)
    }
    
    private func uploadEmote(data: Data, shortcode: String) {
        guard let appState, let keypair = appState.keypair else { return }
        isUploading = true
        
        // Update button to show uploading state
        var uploadingConfig = addButton.configuration
        uploadingConfig?.title = "Uploading..."
        uploadingConfig?.showsActivityIndicator = true
        addButton.configuration = uploadingConfig
        addButton.isEnabled = false
        
        Task {
            do {
                let result = try await NostrBuildUploadService.shared.upload(
                    imageData: data,
                    mimeType: "image/png",
                    filename: "\(shortcode).png",
                    keypair: keypair
                )
                
                await MainActor.run {
                    // Add to local emoji cache immediately
                    appState.emojiPackCache[shortcode] = result.url
                    
                    // Publish updated kind 10030 event
                    var tags: [Tag] = []
                    // Keep existing emojis
                    for (sc, url) in appState.emojiPackCache {
                        tags.append(Tag(name: "emoji", value: sc, otherParameters: [url.absoluteString]))
                    }
                    if let event = try? NostrEvent(kind: .emojiList, content: "", tags: tags, signedBy: keypair) {
                        appState.relayWritePool.publishEvent(event)
                    }
                    
                    // Add to the picker grid
                    allEmojis.append((shortcode: shortcode, url: result.url))
                    filteredEmojis = allEmojis
                    collectionView.reloadData()
                    emptyLabel.alpha = 0
                    
                    // Reset button
                    resetAddButton()
                    isUploading = false
                }
            } catch {
                await MainActor.run {
                    resetAddButton()
                    isUploading = false
                    // Brief error flash
                    var errorConfig = addButton.configuration
                    errorConfig?.title = "Failed"
                    errorConfig?.baseBackgroundColor = .systemRed.withAlphaComponent(0.6)
                    addButton.configuration = errorConfig
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.resetAddButton()
                    }
                }
            }
        }
    }
    
    private func resetAddButton() {
        var btnConfig = UIButton.Configuration.filled()
        btnConfig.title = "Add Emote"
        btnConfig.image = UIImage(systemName: "plus.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        btnConfig.imagePadding = 6
        btnConfig.baseForegroundColor = .white
        btnConfig.baseBackgroundColor = .systemBlue.withAlphaComponent(0.6)
        btnConfig.cornerStyle = .capsule
        btnConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        btnConfig.showsActivityIndicator = false
        addButton.configuration = btnConfig
        addButton.isEnabled = true
    }

    private func setupEmptyLabel() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No emotes available"
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.alpha = 0
        morphingGlass.glassContentView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor, constant: 20),
        ])
    }

    // MARK: - Data

    private func rebuildAllEmojis() {
        allEmojis = emojiPacks.flatMap { pack in
            pack.emojis.map { (shortcode: $0.shortcode, url: $0.imageURL) }
        }
        filteredEmojis = allEmojis
    }

    @objc private func searchChanged() {
        let query = searchField.text?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        if query.isEmpty {
            filteredEmojis = allEmojis
        } else {
            filteredEmojis = allEmojis.filter { $0.shortcode.lowercased().contains(query) }
        }
        collectionView.reloadData()
        emptyLabel.alpha = filteredEmojis.isEmpty ? 1 : 0
    }

    // MARK: - Morph
    
    /// Computes the expanded center Y accounting for keyboard
    private func expandedCenterY() -> CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        let safeTop = safeAreaInsets.top + 20
        let bottomLimit = screenHeight - currentKeyboardHeight - 10
        let availableHeight = bottomLimit - safeTop
        let cappedHeight = min(modalHeight, availableHeight)
        let ideal = sourceFrame.minY - cappedHeight / 2 - 20
        let minY = safeTop + cappedHeight / 2
        let maxY = bottomLimit - cappedHeight / 2
        return min(max(minY, ideal), maxY)
    }
    
    /// Computes the capped modal height accounting for keyboard
    private func cappedModalHeight() -> CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        let safeTop = safeAreaInsets.top + 20
        let bottomLimit = screenHeight - currentKeyboardHeight - 10
        return min(modalHeight, bottomLimit - safeTop)
    }

    private func updateMorphProgress(_ p: CGFloat) {
        let progress = max(0, min(1, p))

        let expandedCenterX = UIScreen.main.bounds.midX
        let targetCenterY = expandedCenterY()
        let targetHeight = cappedModalHeight()

        glassWidthConstraint.constant = collapsedSize + (modalWidth - collapsedSize) * progress
        glassHeightConstraint.constant = collapsedSize + (targetHeight - collapsedSize) * progress
        glassCenterXConstraint.constant = sourceFrame.midX + (expandedCenterX - sourceFrame.midX) * progress
        glassCenterYConstraint.constant = sourceFrame.midY + (targetCenterY - sourceFrame.midY) * progress

        morphingGlass.effectView.layer.cornerRadius = collapsedCornerRadius + (modalCornerRadius - collapsedCornerRadius) * progress

        dimmingView.alpha = 0.3 * progress
        // searchField.alpha = progress  // Search disabled temporarily
        collectionView.alpha = progress
        addButton.alpha = progress
        emptyLabel.alpha = filteredEmojis.isEmpty ? progress : 0

        layoutIfNeeded()
    }
    
    // MARK: - Keyboard Handling
    
    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screenHeight = UIScreen.main.bounds.height
        currentKeyboardHeight = max(0, screenHeight - endFrame.origin.y)
        
        guard isExpanded else { return }
        
        let targetHeight = cappedModalHeight()
        let targetCenterY = expandedCenterY()
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curveRaw << 16),
            animations: {
                self.glassHeightConstraint.constant = targetHeight
                self.glassCenterYConstraint.constant = targetCenterY
                self.layoutIfNeeded()
            }
        )
    }

    func present() {
        let animator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.85) {
            self.updateMorphProgress(1)
        }
        animator.addCompletion { [weak self] _ in
            self?.isExpanded = true
        }
        animator.startAnimation()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func dismiss() {
        // searchField.resignFirstResponder()  // Search disabled temporarily
        let animator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.85) {
            self.updateMorphProgress(0)
        }
        animator.addCompletion { [weak self] _ in
            self?.isExpanded = false
            self?.removeFromSuperview()
            self?.onDismissed?()
        }
        animator.startAnimation()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @objc private func dismissTapped() { dismiss() }

    // MARK: - Convenience

    @discardableResult
    static func present(
        from button: UIView,
        in window: UIWindow,
        emojiPacks: [EmojiPack],
        appState: AppState?,
        onEmojiSelected: @escaping (String) -> Void
    ) -> MorphingEmojiModal {
        let frame = button.convert(button.bounds, to: window)
        let modal = MorphingEmojiModal(sourceFrame: frame, emojiPacks: emojiPacks, appState: appState)
        modal.sourceButton = button
        modal.onEmojiSelected = onEmojiSelected
        window.addSubview(modal)
        modal.present()
        return modal
    }
}

// MARK: - UICollectionView

extension MorphingEmojiModal: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredEmojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmoteCell.reuseId, for: indexPath) as! EmoteCell
        let emoji = filteredEmojis[indexPath.item]
        cell.configure(shortcode: emoji.shortcode, url: emoji.url)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = filteredEmojis[indexPath.item]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onEmojiSelected?(":\(emoji.shortcode):")
        // Don't dismiss — user may want to add multiple emojis
    }
}

// MARK: - UIImagePickerControllerDelegate

extension MorphingEmojiModal: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        handlePickedImage(image)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension MorphingEmojiModal: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Search field resigned — notify caller to restore its input bar
        onSearchResigned?()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - EmoteCell

private class EmoteCell: UICollectionViewCell {
    static let reuseId = "EmoteCell"

    private let imageView: SDAnimatedImageView = {
        let iv = SDAnimatedImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let label: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 36),
            imageView.heightAnchor.constraint(equalToConstant: 36),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(shortcode: String, url: URL) {
        label.text = shortcode
        imageView.sd_setImage(with: url)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
        label.text = nil
    }
}
