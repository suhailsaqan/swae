//
//  ImageCropperViewController.swift
//  swae
//
//  Full-screen image cropper with circle or rectangle crop window.
//

import UIKit

protocol ImageCropperDelegate: AnyObject {
    func imageCropper(_ cropper: ImageCropperViewController, didCropImage image: UIImage)
    func imageCropperDidCancel(_ cropper: ImageCropperViewController)
}

final class ImageCropperViewController: UIViewController {

    // MARK: - Properties

    let sourceImage: UIImage
    let cropShape: CropOverlayView.CropShape
    weak var cropDelegate: ImageCropperDelegate?

    private var hasUserInteracted = false
    private var rotationAngle: Int = 0 // 0, 90, 180, 270
    private var hasPerformedInitialLayout = false
    /// The currently displayed image, rotated from sourceImage by rotationAngle.
    private var displayImage: UIImage

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let overlayView: CropOverlayView
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let rotateButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let doneSpinner = UIActivityIndicatorView(style: .medium)

    // MARK: - Init

    init(image: UIImage, cropShape: CropOverlayView.CropShape) {
        self.sourceImage = Self.normalizeOrientation(image)
        self.displayImage = self.sourceImage
        self.cropShape = cropShape
        self.overlayView = CropOverlayView(cropShape: cropShape)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupScrollView()
        setupOverlay()
        setupTopBar()
        setupBottomBar()
        setupDoubleTap()
        setupAccessibility()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateZoomScale()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - Setup

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.decelerationRate = .fast
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.image = displayImage
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(origin: .zero, size: displayImage.size)
        scrollView.addSubview(imageView)
        scrollView.contentSize = displayImage.size

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupOverlay() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        var doneConfig = UIButton.Configuration.filled()
        doneConfig.title = "Done"
        doneConfig.baseBackgroundColor = .accentPurple
        doneConfig.baseForegroundColor = .white
        doneConfig.cornerStyle = .capsule
        doneConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        doneButton.configuration = doneConfig
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        doneSpinner.color = .white
        doneSpinner.hidesWhenStopped = true
        doneSpinner.translatesAutoresizingMaskIntoConstraints = false

        topBar.contentView.addSubview(cancelButton)
        topBar.contentView.addSubview(doneButton)
        topBar.contentView.addSubview(doneSpinner)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),

            cancelButton.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 16),
            cancelButton.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -10),

            doneButton.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -16),
            doneButton.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -6),
            doneButton.heightAnchor.constraint(equalToConstant: 32),

            doneSpinner.centerXAnchor.constraint(equalTo: doneButton.centerXAnchor),
            doneSpinner.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        let rotateIcon = UIImage(systemName: "rotate.right")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22))
        rotateButton.setImage(rotateIcon, for: .normal)
        rotateButton.tintColor = .white
        rotateButton.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)
        rotateButton.translatesAutoresizingMaskIntoConstraints = false

        let resetIcon = UIImage(systemName: "arrow.counterclockwise")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22))
        resetButton.setImage(resetIcon, for: .normal)
        resetButton.tintColor = .white
        resetButton.alpha = 0.3
        resetButton.isEnabled = false
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.contentView.addSubview(rotateButton)
        bottomBar.contentView.addSubview(resetButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -44),

            rotateButton.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 24),
            rotateButton.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            rotateButton.widthAnchor.constraint(equalToConstant: 44),
            rotateButton.heightAnchor.constraint(equalToConstant: 44),

            resetButton.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -24),
            resetButton.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            resetButton.widthAnchor.constraint(equalToConstant: 44),
            resetButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupDoubleTap() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    private func setupAccessibility() {
        cancelButton.accessibilityLabel = "Cancel"
        doneButton.accessibilityLabel = "Done, crop image"
        rotateButton.accessibilityLabel = "Rotate image right"
        resetButton.accessibilityLabel = "Reset crop"

        let shapeDesc: String
        switch cropShape {
        case .circle: shapeDesc = "Crop image to circle for profile picture"
        case .rect: shapeDesc = "Crop image to rectangle for banner"
        }
        overlayView.accessibilityLabel = shapeDesc
        overlayView.isAccessibilityElement = true
    }

    // MARK: - Zoom & Insets

    private func updateZoomScale() {
        let cropRect = overlayView.cropRect
        guard cropRect.width > 0, displayImage.size.width > 0 else { return }

        let widthScale = cropRect.width / displayImage.size.width
        let heightScale = cropRect.height / displayImage.size.height
        let minZoom = max(widthScale, heightScale)

        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = minZoom * 5

        if !hasPerformedInitialLayout {
            hasPerformedInitialLayout = true
            scrollView.zoomScale = minZoom
            updateContentInsets()
            centerContent()
        } else if scrollView.zoomScale < minZoom {
            scrollView.zoomScale = minZoom
            updateContentInsets()
        } else {
            updateContentInsets()
        }
    }

    private func centerContent() {
        let insets = scrollView.contentInset
        let contentSize = scrollView.contentSize
        let boundsSize = scrollView.bounds.size

        let offsetX = (contentSize.width - boundsSize.width + insets.left + insets.right) / 2 - insets.left
        let offsetY = (contentSize.height - boundsSize.height + insets.top + insets.bottom) / 2 - insets.top

        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    private func updateContentInsets() {
        let cropRect = overlayView.cropRect
        guard cropRect.width > 0 else { return }

        let imageFrame = imageView.frame

        // Insets ensure the image edges can reach the crop rect edges.
        // When the image is smaller than the crop rect in a dimension,
        // add extra inset to center it.
        let topInset = cropRect.minY + max(0, (cropRect.height - imageFrame.height) / 2)
        let leftInset = cropRect.minX + max(0, (cropRect.width - imageFrame.width) / 2)
        let bottomInset = (view.bounds.height - cropRect.maxY) + max(0, (cropRect.height - imageFrame.height) / 2)
        let rightInset = (view.bounds.width - cropRect.maxX) + max(0, (cropRect.width - imageFrame.width) / 2)

        scrollView.contentInset = UIEdgeInsets(
            top: max(topInset, 0),
            left: max(leftInset, 0),
            bottom: max(bottomInset, 0),
            right: max(rightInset, 0)
        )
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        if hasUserInteracted {
            let alert = UIAlertController(title: "Discard Changes?", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.cropDelegate?.imageCropperDidCancel(self)
                self.dismiss(animated: true)
            })
            alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
            present(alert, animated: true)
        } else {
            cropDelegate?.imageCropperDidCancel(self)
            dismiss(animated: true)
        }
    }

    @objc private func doneTapped() {
        doneButton.isHidden = true
        doneSpinner.startAnimating()

        // Capture all UIKit state on the main thread — accessing these
        // from a background thread returns unreliable values in production.
        let cropRect = overlayView.cropRect
        let zoomScale = scrollView.zoomScale
        let offset = scrollView.contentOffset
        let insets = scrollView.contentInset
        let imageFrame = imageView.frame

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self,
                  let cropped = self.cropImage(
                    cropRect: cropRect,
                    zoomScale: zoomScale,
                    offset: offset,
                    insets: insets,
                    imageFrame: imageFrame
                  ) else {
                DispatchQueue.main.async {
                    self?.doneSpinner.stopAnimating()
                    self?.doneButton.isHidden = false
                }
                return
            }
            DispatchQueue.main.async {
                self.doneSpinner.stopAnimating()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.cropDelegate?.imageCropper(self, didCropImage: cropped)
                self.dismiss(animated: true)
            }
        }
    }

    @objc private func rotateTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        hasUserInteracted = true
        rotationAngle = (rotationAngle + 90) % 360

        displayImage = Self.rotateImage90CW(displayImage)
        applyDisplayImage()

        updateResetButton()
    }

    @objc private func resetTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        rotationAngle = 0
        hasUserInteracted = false

        displayImage = sourceImage
        applyDisplayImage()

        updateResetButton()
    }

    /// Updates the imageView and scroll view state to reflect the current displayImage.
    private func applyDisplayImage() {
        imageView.image = displayImage
        imageView.transform = .identity
        imageView.frame = CGRect(origin: .zero, size: displayImage.size)
        scrollView.contentSize = displayImage.size

        // Recalculate zoom for the new dimensions and center
        let cropRect = overlayView.cropRect
        guard cropRect.width > 0, displayImage.size.width > 0 else { return }

        let widthScale = cropRect.width / displayImage.size.width
        let heightScale = cropRect.height / displayImage.size.height
        let minZoom = max(widthScale, heightScale)

        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = minZoom * 5
        scrollView.zoomScale = minZoom
        updateContentInsets()
        centerContent()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        hasUserInteracted = true
        let point = gesture.location(in: imageView)

        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let targetZoom = scrollView.minimumZoomScale * 2
            let size = CGSize(
                width: scrollView.bounds.width / targetZoom,
                height: scrollView.bounds.height / targetZoom
            )
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
        }

        updateResetButton()
    }

    private func updateResetButton() {
        let isDefault = rotationAngle == 0 && abs(scrollView.zoomScale - scrollView.minimumZoomScale) < 0.01
        resetButton.isEnabled = !isDefault
        UIView.animate(withDuration: 0.2) {
            self.resetButton.alpha = isDefault ? 0.3 : 1.0
        }
    }

    // MARK: - Crop Computation

    private func cropImage(
        cropRect: CGRect,
        zoomScale: CGFloat,
        offset: CGPoint,
        insets: UIEdgeInsets,
        imageFrame: CGRect
    ) -> UIImage? {
        guard let cgImage = displayImage.cgImage else { return nil }

        let imageScale = displayImage.scale

        // Convert crop rect from view coordinates to image coordinates.
        // displayImage is already rotated, so no rotation transform needed.
        var x = (offset.x + cropRect.minX - imageFrame.minX) / zoomScale * imageScale
        var y = (offset.y + cropRect.minY - imageFrame.minY) / zoomScale * imageScale
        let w = cropRect.width / zoomScale * imageScale
        let h = cropRect.height / zoomScale * imageScale

        let fullW = CGFloat(cgImage.width)
        let fullH = CGFloat(cgImage.height)

        // Clamp origin so the rect stays fully within image bounds.
        // This handles the case where the user taps Done while the
        // scroll view is in a bounced/overscrolled state.
        x = min(max(x, 0), fullW - w)
        y = min(max(y, 0), fullH - h)

        let imageRect = CGRect(x: x, y: y, width: w, height: h)

        guard let croppedCG = cgImage.cropping(to: imageRect) else { return nil }

        return UIImage(cgImage: croppedCG, scale: imageScale, orientation: .up)
    }

    // MARK: - Orientation Normalization

    static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(at: .zero)
        }
    }

    /// Rotates the image 90° clockwise by redrawing into a new bitmap.
    static func rotateImage90CW(_ image: UIImage) -> UIImage {
        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            ctx.rotate(by: .pi / 2)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }
}

// MARK: - UIScrollViewDelegate

extension ImageCropperViewController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentInsets()
        hasUserInteracted = true
        updateResetButton()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging {
            hasUserInteracted = true
        }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale < scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }
    }
}
