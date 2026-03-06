//
//  MorphingQRModal.swift
//  swae
//
//  Window-level morphing modal for profile QR code display and scanning.
//  Morphs from the QR button to a full-width glass modal with two paged screens:
//    Page 1 — the viewed user's QR code (their npub)
//    Page 2 — a live camera scanner to scan other profiles
//
//  Follows the same animation pattern as MorphingZapModal.
//

import AVFoundation
import AudioToolbox
import CoreImage.CIFilterBuiltins
import Kingfisher
import NostrSDK
import UIKit

class MorphingQRModal: UIView {

    // MARK: - State

    enum State {
        case collapsed
        case expanded
        case animating(progress: CGFloat)
    }

    private(set) var currentState: State = .collapsed

    // MARK: - Layout Constants

    private let collapsedSize: CGFloat = 40
    private let collapsedCornerRadius: CGFloat = 20
    private var modalWidth: CGFloat { UIScreen.main.bounds.width - 32 }
    private var modalHeight: CGFloat {
        // Scale to fit any screen — leave room for safe areas and source button
        let screenH = UIScreen.main.bounds.height
        return min(screenH * 0.58, 520)
    }
    private let modalCornerRadius: CGFloat = 38
    private let contentHorizontalPadding: CGFloat = 20

    // Positioning
    private var sourceFrame: CGRect = .zero
    private var screenBounds: CGRect { UIScreen.main.bounds }

    // MARK: - Data

    let pubkeyHex: String
    private let displayName: String?
    private let pictureURL: URL?

    // MARK: - Views

    private var morphingGlass: GlassContainerView!
    private let qrIcon = UIImageView()
    private let dimmingView = UIView()

    // Paging
    private let pagingScrollView = UIScrollView()
    private let pageControl = UIPageControl()

    // Page 1 — QR display
    private let page1 = UIView()
    private let qrTitleLabel = UILabel()
    private let profilePicView = UIImageView()
    private let nameLabel = UILabel()
    private let qrImageView = UIImageView()
    private let npubLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private var copiedFeedback: UILabel?

    // Page 2 — Scanner
    private let page2 = UIView()
    private let scanTitleLabel = UILabel()
    private let cameraContainer = UIView()
    private let scanInstruction = UILabel()
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let scanFrame = UIView()
    private var hasScanned = false

    // MARK: - Constraints

    private var glassWidthConstraint: NSLayoutConstraint!
    private var glassHeightConstraint: NSLayoutConstraint!
    private var glassCenterXConstraint: NSLayoutConstraint!
    private var glassCenterYConstraint: NSLayoutConstraint!

    private weak var sourceButton: UIView?

    // MARK: - Callbacks

    var onProfileScanned: ((String) -> Void)?
    var onDismissed: (() -> Void)?
    var onMorphProgress: ((CGFloat) -> Void)?

    // MARK: - Initialization

    init(sourceFrame: CGRect, pubkeyHex: String, displayName: String?, pictureURL: URL?) {
        self.sourceFrame = sourceFrame
        self.pubkeyHex = pubkeyHex
        self.displayName = displayName
        self.pictureURL = pictureURL
        super.init(frame: UIScreen.main.bounds)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    private func setup() {
        frame = UIScreen.main.bounds
        backgroundColor = .clear

        setupDimmingView()
        setupMorphingGlass()
        setupCollapsedContent()
        setupPagingScrollView()
        setupPage1()
        setupPage2()
        setupPageControl()
        setupGestures()

        updateMorphProgress(0)
        currentState = .collapsed
    }

    // MARK: - Dimming

    private func setupDimmingView() {
        dimmingView.frame = bounds
        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0
        addSubview(dimmingView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmingTapped))
        dimmingView.addGestureRecognizer(tap)
    }

    // MARK: - Morphing Glass

    private func setupMorphingGlass() {
        morphingGlass = GlassFactory.makeGlassView(cornerRadius: collapsedCornerRadius)
        morphingGlass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(morphingGlass)

        let cx = sourceFrame.midX
        let cy = sourceFrame.midY

        glassWidthConstraint = morphingGlass.widthAnchor.constraint(equalToConstant: collapsedSize)
        glassHeightConstraint = morphingGlass.heightAnchor.constraint(equalToConstant: collapsedSize)
        glassCenterXConstraint = morphingGlass.centerXAnchor.constraint(equalTo: leadingAnchor, constant: cx)
        glassCenterYConstraint = morphingGlass.centerYAnchor.constraint(equalTo: topAnchor, constant: cy)

        NSLayoutConstraint.activate([glassWidthConstraint, glassHeightConstraint, glassCenterXConstraint, glassCenterYConstraint])
    }

    private func setupCollapsedContent() {
        qrIcon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        qrIcon.image = UIImage(systemName: "qrcode", withConfiguration: config)
        qrIcon.tintColor = .white
        qrIcon.contentMode = .scaleAspectFit
        morphingGlass.glassContentView.addSubview(qrIcon)
        NSLayoutConstraint.activate([
            qrIcon.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            qrIcon.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor),
            qrIcon.widthAnchor.constraint(equalToConstant: 22),
            qrIcon.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - Paging Scroll View

    private func setupPagingScrollView() {
        pagingScrollView.isPagingEnabled = true
        pagingScrollView.showsHorizontalScrollIndicator = false
        pagingScrollView.bounces = false
        pagingScrollView.delegate = self
        pagingScrollView.alpha = 0
        pagingScrollView.translatesAutoresizingMaskIntoConstraints = false
        morphingGlass.glassContentView.addSubview(pagingScrollView)

        NSLayoutConstraint.activate([
            pagingScrollView.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor),
            pagingScrollView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor),
            pagingScrollView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor),
            pagingScrollView.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor, constant: -30),
        ])

        // Use Auto Layout for pages inside the scroll view
        page1.translatesAutoresizingMaskIntoConstraints = false
        page2.translatesAutoresizingMaskIntoConstraints = false
        pagingScrollView.addSubview(page1)
        pagingScrollView.addSubview(page2)

        NSLayoutConstraint.activate([
            // Page 1: pinned to scroll view content leading
            page1.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
            page1.leadingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.leadingAnchor),
            page1.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
            page1.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor),
            page1.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),

            // Page 2: immediately after page 1
            page2.topAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.topAnchor),
            page2.leadingAnchor.constraint(equalTo: page1.trailingAnchor),
            page2.trailingAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.trailingAnchor),
            page2.bottomAnchor.constraint(equalTo: pagingScrollView.contentLayoutGuide.bottomAnchor),
            page2.widthAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.widthAnchor),
            page2.heightAnchor.constraint(equalTo: pagingScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update camera preview layer to match container bounds
        previewLayer?.frame = cameraContainer.bounds
    }

    // MARK: - Page 1: QR Code Display

    private func setupPage1() {
        // Title
        qrTitleLabel.text = "Scan to Follow"
        qrTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        qrTitleLabel.textColor = .white
        qrTitleLabel.textAlignment = .center
        qrTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        page1.addSubview(qrTitleLabel)

        // Profile picture with accent ring
        profilePicView.contentMode = .scaleAspectFill
        profilePicView.clipsToBounds = true
        profilePicView.layer.cornerRadius = 28
        profilePicView.layer.borderWidth = 2
        profilePicView.layer.borderColor = UIColor.accentPurple.cgColor
        profilePicView.backgroundColor = .systemGray5
        profilePicView.translatesAutoresizingMaskIntoConstraints = false
        page1.addSubview(profilePicView)

        if let url = pictureURL {
            profilePicView.kf.setImage(with: url, options: [.transition(.fade(0.2))])
        } else {
            profilePicView.image = UIImage(named: "swae")
        }

        // Display name
        nameLabel.text = displayName ?? "Anonymous"
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        page1.addSubview(nameLabel)

        // QR card — dark rounded rect with subtle purple border
        let qrCard = UIView()
        qrCard.backgroundColor = UIColor(white: 0.08, alpha: 1)
        qrCard.layer.cornerRadius = 20
        qrCard.layer.borderWidth = 3
        qrCard.layer.borderColor = UIColor.accentPurple.withAlphaComponent(0.3).cgColor
        qrCard.translatesAutoresizingMaskIntoConstraints = false
        page1.addSubview(qrCard)

        // QR code image — white bg for scannability, inset inside card
        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 12
        qrImageView.clipsToBounds = true
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        qrCard.addSubview(qrImageView)

        // Generate QR
        let npub = PublicKey(hex: pubkeyHex)?.npub ?? pubkeyHex
        let nostrURI = "nostr:\(npub)"
        qrImageView.image = generateQRCode(from: nostrURI, size: 200 * UIScreen.main.scale)

        // npub label
        let truncated = npub.count > 20
            ? "\(npub.prefix(12))...\(npub.suffix(6))"
            : npub
        npubLabel.text = truncated
        npubLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        npubLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        npubLabel.textAlignment = .center
        npubLabel.translatesAutoresizingMaskIntoConstraints = false
        page1.addSubview(npubLabel)

        // Copy button — accent purple
        var copyConfig = UIButton.Configuration.filled()
        copyConfig.title = "Copy"
        copyConfig.image = UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        copyConfig.imagePadding = 4
        copyConfig.baseBackgroundColor = UIColor.accentPurple.withAlphaComponent(0.25)
        copyConfig.baseForegroundColor = .accentPurple
        copyConfig.cornerStyle = .capsule
        copyConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)
        copyButton.configuration = copyConfig
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyNpubTapped), for: .touchUpInside)
        page1.addSubview(copyButton)

        NSLayoutConstraint.activate([
            qrTitleLabel.topAnchor.constraint(equalTo: page1.topAnchor, constant: 20),
            qrTitleLabel.centerXAnchor.constraint(equalTo: page1.centerXAnchor),

            profilePicView.topAnchor.constraint(equalTo: qrTitleLabel.bottomAnchor, constant: 14),
            profilePicView.centerXAnchor.constraint(equalTo: page1.centerXAnchor),
            profilePicView.widthAnchor.constraint(equalToConstant: 56),
            profilePicView.heightAnchor.constraint(equalToConstant: 56),

            nameLabel.topAnchor.constraint(equalTo: profilePicView.bottomAnchor, constant: 6),
            nameLabel.centerXAnchor.constraint(equalTo: page1.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: page1.leadingAnchor, constant: contentHorizontalPadding),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: page1.trailingAnchor, constant: -contentHorizontalPadding),

            qrCard.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 14),
            qrCard.centerXAnchor.constraint(equalTo: page1.centerXAnchor),
            // Scale QR card to fill available width with padding, keep square
            qrCard.leadingAnchor.constraint(greaterThanOrEqualTo: page1.leadingAnchor, constant: 40),
            qrCard.trailingAnchor.constraint(lessThanOrEqualTo: page1.trailingAnchor, constant: -40),
            qrCard.widthAnchor.constraint(lessThanOrEqualToConstant: 230),
            qrCard.heightAnchor.constraint(equalTo: qrCard.widthAnchor),

            qrImageView.topAnchor.constraint(equalTo: qrCard.topAnchor, constant: 15),
            qrImageView.leadingAnchor.constraint(equalTo: qrCard.leadingAnchor, constant: 15),
            qrImageView.trailingAnchor.constraint(equalTo: qrCard.trailingAnchor, constant: -15),
            qrImageView.bottomAnchor.constraint(equalTo: qrCard.bottomAnchor, constant: -15),

            npubLabel.topAnchor.constraint(equalTo: qrCard.bottomAnchor, constant: 10),
            npubLabel.centerXAnchor.constraint(equalTo: page1.centerXAnchor),

            copyButton.topAnchor.constraint(equalTo: npubLabel.bottomAnchor, constant: 8),
            copyButton.centerXAnchor.constraint(equalTo: page1.centerXAnchor),
        ])
    }

    // MARK: - Page 2: Scanner

    private func setupPage2() {
        scanTitleLabel.text = "Scan Profile"
        scanTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        scanTitleLabel.textColor = .white
        scanTitleLabel.textAlignment = .center
        scanTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        page2.addSubview(scanTitleLabel)

        cameraContainer.backgroundColor = .black
        cameraContainer.layer.cornerRadius = 16
        cameraContainer.clipsToBounds = true
        cameraContainer.translatesAutoresizingMaskIntoConstraints = false
        page2.addSubview(cameraContainer)

        // Scan frame overlay — purple accent border
        scanFrame.backgroundColor = .clear
        scanFrame.layer.borderColor = UIColor.accentPurple.withAlphaComponent(0.6).cgColor
        scanFrame.layer.borderWidth = 2
        scanFrame.layer.cornerRadius = 12
        scanFrame.translatesAutoresizingMaskIntoConstraints = false
        cameraContainer.addSubview(scanFrame)

        scanInstruction.text = "Point at a Nostr QR code"
        scanInstruction.font = .systemFont(ofSize: 13, weight: .regular)
        scanInstruction.textColor = .secondaryLabel
        scanInstruction.textAlignment = .center
        scanInstruction.translatesAutoresizingMaskIntoConstraints = false
        page2.addSubview(scanInstruction)

        NSLayoutConstraint.activate([
            scanTitleLabel.topAnchor.constraint(equalTo: page2.topAnchor, constant: 20),
            scanTitleLabel.centerXAnchor.constraint(equalTo: page2.centerXAnchor),

            cameraContainer.topAnchor.constraint(equalTo: scanTitleLabel.bottomAnchor, constant: 16),
            cameraContainer.leadingAnchor.constraint(equalTo: page2.leadingAnchor, constant: contentHorizontalPadding),
            cameraContainer.trailingAnchor.constraint(equalTo: page2.trailingAnchor, constant: -contentHorizontalPadding),
            cameraContainer.bottomAnchor.constraint(equalTo: scanInstruction.topAnchor, constant: -12),

            scanFrame.centerXAnchor.constraint(equalTo: cameraContainer.centerXAnchor),
            scanFrame.centerYAnchor.constraint(equalTo: cameraContainer.centerYAnchor),
            scanFrame.widthAnchor.constraint(equalToConstant: 180),
            scanFrame.heightAnchor.constraint(equalToConstant: 180),

            scanInstruction.bottomAnchor.constraint(equalTo: page2.bottomAnchor, constant: -8),
            scanInstruction.centerXAnchor.constraint(equalTo: page2.centerXAnchor),
        ])
    }

    // MARK: - Page Control

    private func setupPageControl() {
        pageControl.numberOfPages = 2
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.3)
        pageControl.alpha = 0
        pageControl.isUserInteractionEnabled = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        morphingGlass.glassContentView.addSubview(pageControl)

        NSLayoutConstraint.activate([
            pageControl.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor, constant: -6),
            pageControl.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
        ])
    }

    // MARK: - Gestures

    private func setupGestures() {
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        morphingGlass.addGestureRecognizer(swipeDown)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        morphingGlass.addGestureRecognizer(pan)
    }

    @objc private func dimmingTapped() { dismiss() }
    @objc private func handleSwipeDown() { dismiss() }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        switch gesture.state {
        case .changed:
            guard case .expanded = currentState else { return }
            let progress = max(0, 1 - (translation.y / 200))
            updateMorphProgress(progress)
        case .ended, .cancelled:
            guard case .animating = currentState else { return }
            let progress = 1 - (translation.y / 200)
            let shouldCollapse = progress < 0.6 || velocity.y > 500
            completeMorph(expand: !shouldCollapse)
        default: break
        }
    }

    // MARK: - Copy npub

    @objc private func copyNpubTapped() {
        let npub = PublicKey(hex: pubkeyHex)?.npub ?? pubkeyHex
        UIPasteboard.general.string = npub
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Brief "Copied!" feedback
        var config = copyButton.configuration
        config?.title = "Copied!"
        config?.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        copyButton.configuration = config

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            var restore = self.copyButton.configuration
            restore?.title = "Copy"
            restore?.image = UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            self.copyButton.configuration = restore
        }
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String, size: CGFloat) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        return UIImage(cgImage: cg)
    }

    // MARK: - Camera Scanner

    private func startScanner() {
        guard captureSession == nil else {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
            return
        }

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showCameraUnavailable()
            return
        }
        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            showCameraUnavailable()
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = cameraContainer.bounds
        cameraContainer.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func stopScanner() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    private func showCameraUnavailable() {
        let label = UILabel()
        label.text = "Camera unavailable"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        cameraContainer.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cameraContainer.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: cameraContainer.centerYAnchor),
        ])
    }

    // MARK: - Nostr Pubkey Parsing

    static func parseNostrPubkey(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // nostr: URI scheme (NIP-21)
        if trimmed.lowercased().hasPrefix("nostr:") {
            return parseNostrPubkey(from: String(trimmed.dropFirst(6)))
        }

        // npub bech32
        if trimmed.lowercased().hasPrefix("npub1") {
            return PublicKey(npub: trimmed)?.hex
        }

        // Raw 64-char hex
        if trimmed.count == 64, trimmed.allSatisfy({ $0.isHexDigit }) {
            return PublicKey(hex: trimmed)?.hex
        }

        return nil
    }

    // MARK: - Morph Animation

    private func updateMorphProgress(_ progress: CGFloat) {
        let p = max(0, min(1, progress))

        let collapsedFrame: CGRect
        if let button = sourceButton, let window = self.window {
            collapsedFrame = button.convert(button.bounds, to: window)
        } else {
            collapsedFrame = sourceFrame
        }

        // Size interpolation
        let width = collapsedSize + (modalWidth - collapsedSize) * p
        let height = collapsedSize + (modalHeight - collapsedSize) * p
        let cornerRadius = collapsedCornerRadius + (modalCornerRadius - collapsedCornerRadius) * p

        // Position interpolation
        let collapsedCX = collapsedFrame.midX
        let collapsedCY = collapsedFrame.midY
        let expandedCX = screenBounds.width / 2
        let safeTop = safeAreaInsets.top + 20
        let idealExpandedCY = collapsedFrame.minY - (modalHeight / 2) - 20
        let expandedCY = max(safeTop + modalHeight / 2, idealExpandedCY)

        let cx = collapsedCX + (expandedCX - collapsedCX) * p
        let cy = collapsedCY + (expandedCY - collapsedCY) * p

        glassWidthConstraint.constant = width
        glassHeightConstraint.constant = height
        glassCenterXConstraint.constant = cx
        glassCenterYConstraint.constant = cy
        morphingGlass.layer.cornerRadius = cornerRadius

        // Collapsed icon fades out, glass stays visible
        qrIcon.alpha = max(0, 1 - (p * 3.33))
        morphingGlass.alpha = min(1, p / 0.15)

        // Content fades in after 30%
        let contentAlpha = p > 0.3 ? (p - 0.3) / 0.7 : 0
        pagingScrollView.alpha = contentAlpha
        pageControl.alpha = contentAlpha

        dimmingView.alpha = p * 0.4
        layoutIfNeeded()
        onMorphProgress?(p)
        currentState = .animating(progress: p)
    }

    private func completeMorph(expand: Bool) {
        let target: CGFloat = expand ? 1 : 0

        let animator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.85) { [weak self] in
            self?.updateMorphProgress(target)
        }
        animator.addCompletion { [weak self] _ in
            guard let self = self else { return }
            self.currentState = expand ? .expanded : .collapsed
            if expand {
                // Start scanner if already on page 2
                if self.pageControl.currentPage == 1 {
                    self.startScanner()
                }
            } else {
                self.stopScanner()
                self.removeFromSuperview()
                self.onDismissed?()
            }
        }
        animator.startAnimation()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Public API

    var isExpanded: Bool {
        if case .expanded = currentState { return true }
        return false
    }

    func present() { completeMorph(expand: true) }

    func dismiss() {
        if let button = sourceButton, let window = self.window {
            sourceFrame = button.convert(button.bounds, to: window)
        }
        completeMorph(expand: false)
    }

    @discardableResult
    static func present(
        from button: UIView,
        in window: UIWindow,
        pubkeyHex: String,
        displayName: String?,
        pictureURL: URL?
    ) -> MorphingQRModal {
        let frame = button.convert(button.bounds, to: window)
        let modal = MorphingQRModal(
            sourceFrame: frame,
            pubkeyHex: pubkeyHex,
            displayName: displayName,
            pictureURL: pictureURL
        )
        modal.sourceButton = button
        window.addSubview(modal)
        modal.present()
        return modal
    }
}

// MARK: - UIScrollViewDelegate (paging)

extension MorphingQRModal: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        let page = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        pageControl.currentPage = page
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        if pageControl.currentPage == 1 {
            startScanner()
        } else {
            stopScanner()
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension MorphingQRModal: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = readable.stringValue,
              let hex = Self.parseNostrPubkey(from: value) else { return }

        hasScanned = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        stopScanner()

        // Brief delay so the user sees the scan happened
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.dismiss()
            self?.onProfileScanned?(hex)
        }
    }
}
