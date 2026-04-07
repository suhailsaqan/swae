import AVKit
import Combine
import Kingfisher
import NostrSDK
import UIKit

// MARK: - Hero Header View (Stretchy Header)
final class HeroHeaderView: UIView, UIGestureRecognizerDelegate {
    static let reuseIdentifier = "HeroHeaderView"

    // MARK: - Video Components
    private let videoContainerView = UIView()
    private var playerLayer: AVPlayerLayer!
    private var videoPlayerModel: VideoPlayerModel?
    private var currentEvent: LiveActivitiesEvent?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Aspect Ratio Handling
    private var videoAspectRatio: CGFloat = 16.0 / 9.0

    // MARK: - Thumbnail Components
    private let thumbnailImageView = UIImageView()

    // MARK: - Transition Support
    /// The view to use as the source rect for the expand transition
    var transitionSourceView: UIView { containerContentView }
    /// The thumbnail image for the transition snapshot
    var transitionThumbnailImage: UIImage? { thumbnailImageView.image }

    // MARK: - Grain Gradient Components
    private let blurContainerView = UIView()
    private let grainGradientView = GrainGradientView()
    private let blurFadeOutMask = CAGradientLayer()
    private var dominantColors: [UIColor] = []
    private var colorExtractionTimer: Timer?

    // MARK: - UI Overlay Components
    private let gradientLayer = CAGradientLayer()
    private let liveBadge = LiveBadgeView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let hostImageView = UIImageView()
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private let containerContentView = UIView()

    // MARK: - Skeleton Loading (image placeholder only)
    private let skeletonImageView = SkeletonView()
    private var isShowingSkeleton = true

    // MARK: - Deferred Video Loading
    private var videoStabilizationTimer: Timer?
    private var metadataFallbackTimer: Timer?
    private var currentStreamURL: URL?
    private var currentEventId: String?
    private var thumbnailLoaded = false

    // MARK: - Interaction
    var onTap: (() -> Void)?
    private var isPlaying = false
    private var hasSetupVideo = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false  // Allow blur to extend beyond bounds
        setupUI()
        setupVideoPlayer()
        setupSkeletonViews()
        showSkeletonState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = UIColor.systemBackground  // Match video/blur background
        clipsToBounds = false  // Critical: allow blur to extend beyond header bounds

        // Video container - anchored to bottom with fixed height
        videoContainerView.backgroundColor = .clear  // Transparent to allow shadow
        videoContainerView.layer.cornerRadius = 16  // Slightly smaller radius for modern look
        videoContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoContainerView)
        // Allow scroll/tap gestures on the header/scroll view to receive touches from the video area
        videoContainerView.isUserInteractionEnabled = false

        videoContainerView.layer.shadowColor = UIColor.black.cgColor
        videoContainerView.layer.shadowOffset = CGSize(width: 0, height: 8)
        videoContainerView.layer.shadowRadius = 24
        videoContainerView.layer.shadowOpacity = 0.3
        videoContainerView.layer.masksToBounds = false  // Allow shadow to extend

        containerContentView.backgroundColor = .black
        containerContentView.layer.cornerRadius = 16
        containerContentView.clipsToBounds = true
        containerContentView.translatesAutoresizingMaskIntoConstraints = false
        videoContainerView.addSubview(containerContentView)
        containerContentView.isUserInteractionEnabled = false

        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = .systemGray6
        thumbnailImageView.alpha = 1.0
        thumbnailImageView.isHidden = false
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        containerContentView.addSubview(thumbnailImageView)
        thumbnailImageView.isUserInteractionEnabled = false

        blurContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurContainerView)
        blurContainerView.isUserInteractionEnabled = false

        // Setup grain gradient view
        grainGradientView.translatesAutoresizingMaskIntoConstraints = false
        blurContainerView.addSubview(grainGradientView)
        grainGradientView.isUserInteractionEnabled = false

        // Setup fade-out mask for smooth transition
        blurFadeOutMask.startPoint = CGPoint(x: 0.5, y: 0.0)
        blurFadeOutMask.endPoint = CGPoint(x: 0.5, y: 1.0)
        blurContainerView.layer.mask = blurFadeOutMask
        updateBlurMaskForAppearance()

        // Simplified gradient - just bottom fade for text readability
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.3).cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor,
        ]
        gradientLayer.locations = [0.0, 0.5, 0.8, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        videoContainerView.layer.addSublayer(gradientLayer)

        // Live badge — top-left of video container (includes connected viewer count)
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liveBadge)

        // Title — bottom-left, compact, same visual weight as badge pill
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Text shadow for readability on any background
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel.layer.shadowRadius = 3
        titleLabel.layer.shadowOpacity = 0.8

        // Host avatar — top-right, small
        hostImageView.contentMode = .scaleAspectFill
        hostImageView.clipsToBounds = true
        hostImageView.layer.cornerRadius = 10
        hostImageView.backgroundColor = .systemGray5
        hostImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostImageView)

        // Host name — top-right, next to avatar
        hostLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        hostLabel.textColor = .white
        hostLabel.numberOfLines = 1
        hostLabel.lineBreakMode = .byTruncatingTail
        hostLabel.textAlignment = .right
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostLabel)

        // Text shadow for host label
        hostLabel.layer.shadowColor = UIColor.black.cgColor
        hostLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        hostLabel.layer.shadowRadius = 3
        hostLabel.layer.shadowOpacity = 0.8

        errorView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        errorView.layer.cornerRadius = 12
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        addSubview(errorView)

        errorLabel.text = "Unable to load video"
        errorLabel.font = .systemFont(ofSize: 16, weight: .medium)
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            // Video container anchored to bottom with fixed height, respects safe area
            // Account for header bar height (44pt) + original padding (12pt) = 56pt
            videoContainerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            videoContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            videoContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            videoContainerView.topAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 56),  // Stay below safe area + header bar (44 + 12)
            videoContainerView.heightAnchor.constraint(equalToConstant: 240).with(
                priority: .defaultHigh),  // Smaller, more compact size

            containerContentView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            containerContentView.leadingAnchor.constraint(
                equalTo: videoContainerView.leadingAnchor),
            containerContentView.trailingAnchor.constraint(
                equalTo: videoContainerView.trailingAnchor),
            containerContentView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            thumbnailImageView.topAnchor.constraint(equalTo: containerContentView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(
                equalTo: containerContentView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(
                equalTo: containerContentView.trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: containerContentView.bottomAnchor),

            // Blur container extends to fill header (will stretch on pull-down)
            blurContainerView.topAnchor.constraint(equalTo: topAnchor, constant: -600),
            blurContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -50),
            blurContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 50),
            blurContainerView.bottomAnchor.constraint(
                equalTo: videoContainerView.bottomAnchor, constant: 60),

            grainGradientView.topAnchor.constraint(equalTo: blurContainerView.topAnchor),
            grainGradientView.leadingAnchor.constraint(equalTo: blurContainerView.leadingAnchor),
            grainGradientView.trailingAnchor.constraint(equalTo: blurContainerView.trailingAnchor),
            grainGradientView.bottomAnchor.constraint(equalTo: blurContainerView.bottomAnchor),

            // Live badge — top-left of video container
            liveBadge.topAnchor.constraint(equalTo: videoContainerView.topAnchor, constant: 12),
            liveBadge.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor, constant: 12),

            // Host avatar — top-right
            hostImageView.topAnchor.constraint(equalTo: videoContainerView.topAnchor, constant: 12),
            hostImageView.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor, constant: -12),
            hostImageView.widthAnchor.constraint(equalToConstant: 20),
            hostImageView.heightAnchor.constraint(equalToConstant: 20),

            // Host label — left of avatar, top-right area, max width capped
            hostLabel.centerYAnchor.constraint(equalTo: hostImageView.centerYAnchor),
            hostLabel.trailingAnchor.constraint(equalTo: hostImageView.leadingAnchor, constant: -6),
            hostLabel.leadingAnchor.constraint(greaterThanOrEqualTo: liveBadge.trailingAnchor, constant: 8),
            hostLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 150),

            // Title — bottom-left, same row height as badge pill
            titleLabel.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor, constant: -12),
            titleLabel.leadingAnchor.constraint(equalTo: videoContainerView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: videoContainerView.trailingAnchor, constant: -12),

            errorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorView.widthAnchor.constraint(equalToConstant: 200),
            errorView.heightAnchor.constraint(equalToConstant: 60),

            errorLabel.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -16),
        ])

        bringSubviewToFront(videoContainerView)
        bringSubviewToFront(liveBadge)
        bringSubviewToFront(titleLabel)
        bringSubviewToFront(hostImageView)
        bringSubviewToFront(hostLabel)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)

        // No entrance animation - instant display for snappiness
    }
    
    private func setupSkeletonViews() {
        skeletonImageView.layer.cornerRadius = 16
        skeletonImageView.translatesAutoresizingMaskIntoConstraints = false
        containerContentView.addSubview(skeletonImageView)
        
        NSLayoutConstraint.activate([
            skeletonImageView.topAnchor.constraint(equalTo: containerContentView.topAnchor),
            skeletonImageView.leadingAnchor.constraint(equalTo: containerContentView.leadingAnchor),
            skeletonImageView.trailingAnchor.constraint(equalTo: containerContentView.trailingAnchor),
            skeletonImageView.bottomAnchor.constraint(equalTo: containerContentView.bottomAnchor),
        ])
        
        skeletonImageView.startAnimating()
    }
    
    private func showSkeletonState() {
        isShowingSkeleton = true
        skeletonImageView.isHidden = false
        thumbnailImageView.isHidden = true
    }
    
    func restartSkeletonAnimations() {
        guard isShowingSkeleton else { return }
        skeletonImageView.stopAnimating()
        skeletonImageView.startAnimating()
    }
    
    private func hideSkeletonState() {
        guard isShowingSkeleton else { return }
        isShowingSkeleton = false
        
        UIView.animate(withDuration: 0.3) {
            self.skeletonImageView.alpha = 0
            self.layoutIfNeeded()
        } completion: { _ in
            self.skeletonImageView.isHidden = true
            self.skeletonImageView.alpha = 1
        }
    }

    // MARK: - UIGestureRecognizerDelegate
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow header tap gestures to recognize alongside the collection view's pan
        return true
    }

    // MARK: - Stretchy Header Behavior
    // Note: Stretching is now handled by the parent view controller
    // via direct frame manipulation in scrollViewDidScroll

    private func setupVideoPlayer() {
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.isHidden = true  // Thumbnail-only mode: hide video layer
        containerContentView.layer.addSublayer(playerLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Ensure we have valid bounds before updating layers
        guard bounds.width > 0 && bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        gradientLayer.frame = videoContainerView.bounds
        gradientLayer.cornerRadius = 16
        playerLayer.frame = containerContentView.bounds
        blurFadeOutMask.frame = blurContainerView.bounds

        videoContainerView.layer.shadowPath =
            UIBezierPath(roundedRect: videoContainerView.bounds, cornerRadius: 16).cgPath

        CATransaction.commit()
    }

    @objc private func handleTap() {
        // Prepare haptic in advance for instant response
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        // Instant callback
        onTap?()
    }

    func updateBlurForScrollOffset(_ offset: CGFloat) {
        // Keep grain gradient visible at all times for consistent background
        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        blurContainerView.alpha = 1.0
        grainGradientView.alpha = isDarkMode ? 0.8 : 1.0
    }

    private func extractDominantColors(from image: UIImage) -> [UIColor] {
        guard let cgImage = image.cgImage else { return [] }

        let targetSize = CGSize(width: 150, height: 150)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let resizedCGImage = resizedImage.cgImage else { return [] }

        let width = resizedCGImage.width
        let height = resizedCGImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard
            let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return [] }

        context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var colors: [UIColor] = []
        let samplePoints = [
            CGPoint(x: Double(width) * 0.15, y: Double(height) * 0.15),
            CGPoint(x: Double(width) * 0.85, y: Double(height) * 0.15),
            CGPoint(x: Double(width) * 0.5, y: Double(height) * 0.3),
            CGPoint(x: Double(width) * 0.25, y: Double(height) * 0.5),
            CGPoint(x: Double(width) * 0.75, y: Double(height) * 0.5),
            CGPoint(x: Double(width) * 0.5, y: Double(height) * 0.7),
            CGPoint(x: Double(width) * 0.15, y: Double(height) * 0.85),
            CGPoint(x: Double(width) * 0.85, y: Double(height) * 0.85),
        ]

        for point in samplePoints {
            let x = Int(point.x)
            let y = Int(point.y)
            let pixelIndex = (y * width + x) * bytesPerPixel

            if pixelIndex + 2 < pixelData.count {
                let r = CGFloat(pixelData[pixelIndex]) / 255.0
                let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0

                let color = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                colors.append(color)
            }
        }

        return colors.filter { color in
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            return brightness > 0.15 && brightness < 0.85 && saturation > 0.2
        }.prefix(4).map { $0 }
    }

    private func enhanceColors(_ colors: [UIColor]) -> [UIColor] {
        let isDarkMode = traitCollection.userInterfaceStyle == .dark

        return colors.map { color in
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            if isDarkMode {
                // Dark mode — muted colors blend well over black
                let enhancedSaturation = min(saturation * 1.2, 1.0)
                let enhancedBrightness = max(min(brightness * 0.8, 0.7), 0.3)
                return UIColor(
                    hue: hue, saturation: enhancedSaturation, brightness: enhancedBrightness,
                    alpha: 0.7)
            } else {
                // Light mode — full alpha so Metal doesn't darken by mixing with black,
                // higher saturation and brightness to stay visible over white
                let enhancedSaturation = min(saturation * 1.5, 1.0)
                let enhancedBrightness = max(min(brightness * 1.0, 0.85), 0.45)
                return UIColor(
                    hue: hue, saturation: enhancedSaturation, brightness: enhancedBrightness,
                    alpha: 1.0)
            }
        }
    }

    private func updateDynamicBlur(with colors: [UIColor]) {
        let enhancedColors = enhanceColors(colors)
        grainGradientView.updateColors(enhancedColors, animated: true)

        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        let targetAlpha: CGFloat = isDarkMode ? 0.8 : 1.0

        UIView.animate(
            withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.1
        ) {
            self.grainGradientView.alpha = targetAlpha
        }

        updateTextColorForBackground(colors)
    }

    /// Computes average luminance from dominant colors and picks white or dark text + shadow accordingly
    private func updateTextColorForBackground(_ colors: [UIColor]) {
        guard !colors.isEmpty else { return }

        // Compute average luminance (perceived brightness using ITU-R BT.709)
        var totalLuminance: CGFloat = 0
        for color in colors {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            totalLuminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let avgLuminance = totalLuminance / CGFloat(colors.count)

        // Bright background → dark text with light shadow; dark background → white text with dark shadow
        let isBright = avgLuminance > 0.55

        UIView.animate(withDuration: 0.4) {
            if isBright {
                let textColor = UIColor.black.withAlphaComponent(0.85)
                self.titleLabel.textColor = textColor
                self.titleLabel.layer.shadowColor = UIColor.white.cgColor
                self.titleLabel.layer.shadowOpacity = 0.6

                self.hostLabel.textColor = UIColor.black.withAlphaComponent(0.7)
                self.hostLabel.layer.shadowColor = UIColor.white.cgColor
                self.hostLabel.layer.shadowOpacity = 0.6
            } else {
                self.titleLabel.textColor = .white
                self.titleLabel.layer.shadowColor = UIColor.black.cgColor
                self.titleLabel.layer.shadowOpacity = 0.8

                self.hostLabel.textColor = UIColor.white.withAlphaComponent(0.9)
                self.hostLabel.layer.shadowColor = UIColor.black.cgColor
                self.hostLabel.layer.shadowOpacity = 0.8
            }
        }
    }

    private func stopColorExtractionTimer() {
        colorExtractionTimer?.invalidate()
        colorExtractionTimer = nil
    }

    // MARK: - Appearance

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }

        updateBlurMaskForAppearance()

        let isDarkMode = traitCollection.userInterfaceStyle == .dark
        grainGradientView.alpha = isDarkMode ? 0.8 : 1.0

        // Re-enhance and re-apply colors if we have extracted colors
        if !dominantColors.isEmpty {
            updateDynamicBlur(with: dominantColors)
        }
    }

    private func updateBlurMaskForAppearance() {
        let isDarkMode = traitCollection.userInterfaceStyle == .dark

        if isDarkMode {
            blurFadeOutMask.colors = [
                UIColor.white.cgColor,
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.9).cgColor,
                UIColor.white.withAlphaComponent(0.7).cgColor,
                UIColor.white.withAlphaComponent(0.4).cgColor,
                UIColor.white.withAlphaComponent(0.15).cgColor,
                UIColor.clear.cgColor,
            ]
            blurFadeOutMask.locations = [0.0, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0]
        } else {
            // Light mode — keep gradient visible longer, fade more gradually
            blurFadeOutMask.colors = [
                UIColor.white.cgColor,
                UIColor.white.cgColor,
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.85).cgColor,
                UIColor.white.withAlphaComponent(0.5).cgColor,
                UIColor.white.withAlphaComponent(0.2).cgColor,
                UIColor.clear.cgColor,
            ]
            blurFadeOutMask.locations = [0.0, 0.25, 0.5, 0.65, 0.8, 0.93, 1.0]
        }
    }

    func configure(with event: LiveActivitiesEvent, appState: AppState) {
        // Skip redundant configuration for the same event
        let eventId = event.id
        let isNewEvent = eventId != currentEventId
        currentEventId = eventId
        currentEvent = event

        // Always update live metadata (viewer count changes frequently)
        titleLabel.text = event.title ?? "Untitled Stream"
        liveBadge.setViewerCount(event.currentParticipants)
        if event.isActuallyLive {
            liveBadge.setLive(true)
        } else if event.recording != nil {
            liveBadge.setReplay()
        } else {
            liveBadge.setLive(false)
        }

        // Get host pubkey - per NIP-53, host is in `p` tag with role "host", fallback to event author
        let hostPubkey = event.hostPubkeyHex

        if let metadata = appState.metadataEvents[hostPubkey] {
            metadataFallbackTimer?.invalidate()
            metadataFallbackTimer = nil
            hostLabel.text =
                metadata.userMetadata?.displayName ?? metadata.userMetadata?.name ?? "Unknown Host"
            hostLabel.isHidden = false
            hostImageView.isHidden = false
            if let pictureURL = metadata.userMetadata?.pictureURL {
                hostImageView.kf.setImage(
                    with: pictureURL,
                    options: [
                        .transition(.none),
                        .memoryCacheExpiration(.days(7)),
                        .backgroundDecode,
                    ])
            }
        } else {
            // Show truncated pubkey immediately instead of skeleton
            let truncated = String(hostPubkey.prefix(8)) + "..." + String(hostPubkey.suffix(4))
            hostLabel.text = truncated
            hostLabel.isHidden = false
            hostImageView.isHidden = true

            // Update with real name if metadata arrives later
            metadataFallbackTimer?.invalidate()
            let pubkey = hostPubkey
            metadataFallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if let metadata = appState.metadataEvents[pubkey] {
                    self.hostLabel.text = metadata.userMetadata?.displayName ?? metadata.userMetadata?.name ?? "Unknown Host"
                    self.hostImageView.isHidden = false
                }
            }
        }

        // If same event and video is already playing or loading, just update text and return
        if !isNewEvent && (isPlaying || hasSetupVideo) {
            return
        }

        // Same event from cache — thumbnail already visible, just schedule video
        if !isNewEvent && thumbnailLoaded {
            scheduleDeferredVideoLoad()
            return
        }

        // New event — tear down any existing video and reset state
        if isNewEvent {
            tearDownVideo()
        }

        // Resolve stream URL for deferred video loading
        // For ended streams, prefer recording URL (streaming may be dead)
        if event.status == .ended {
            currentStreamURL = event.recording ?? event.streaming
        } else {
            currentStreamURL = event.streaming ?? event.recording
        }

        let thumbnailURL = event.image

        if let thumbnailURL = thumbnailURL {
            thumbnailImageView.kf.setImage(
                with: thumbnailURL,
                options: [
                    .transition(.none),
                    .memoryCacheExpiration(.days(7)),
                    .diskCacheExpiration(.days(30)),
                    .backgroundDecode,
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 400, height: 300))),
                ]
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(_):
                    self.hideSkeletonState()
                    self.thumbnailImageView.isHidden = false
                    self.thumbnailLoaded = true

                    // Extract dominant colors on background thread
                    if let thumbnail = self.thumbnailImageView.image {
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            let colors = self?.extractDominantColors(from: thumbnail) ?? []
                            if !colors.isEmpty {
                                DispatchQueue.main.async { [weak self] in
                                    self?.dominantColors = colors
                                    self?.updateDynamicBlur(with: colors)
                                }
                            }
                        }
                    }

                    // Schedule deferred video load
                    self.scheduleDeferredVideoLoad()

                case .failure(let error):
                    print("❌ Thumbnail failed to load: \(error)")
                    // Still try to load video even without thumbnail
                    self.hideSkeletonState()
                    self.thumbnailLoaded = true
                    self.scheduleDeferredVideoLoad()
                }
            }
        } else {
            // No thumbnail URL — skip straight to deferred video
            hideSkeletonState()
            thumbnailLoaded = true
            scheduleDeferredVideoLoad()
        }

        setNeedsLayout()
        layoutIfNeeded()

        // Cache hero data for instant startup preview
        let hostName = appState.metadataEvents[hostPubkey]?.userMetadata?.displayName
            ?? appState.metadataEvents[hostPubkey]?.userMetadata?.name
        CachedHeroData.save(CachedHeroData(
            eventId: event.id,
            title: event.title ?? "Untitled Stream",
            hostPubkeyHex: hostPubkey,
            hostDisplayName: hostName,
            thumbnailURLString: event.image?.absoluteString,
            viewerCount: event.currentParticipants,
            isLive: event.isActuallyLive,
            streamingURLString: event.streaming?.absoluteString,
            recordingURLString: event.recording?.absoluteString
        ))
    }

    /// Configures the hero with cached data for instant startup preview.
    /// Shows thumbnail from Kingfisher's disk cache (no network needed).
    /// Will be replaced by real data when relay responds.
    func configureFromCache(_ cached: CachedHeroData) {
        currentEventId = cached.eventId
        titleLabel.text = cached.title
        liveBadge.setViewerCount(cached.viewerCount)
        liveBadge.setLive(cached.isLive)

        if let name = cached.hostDisplayName {
            hostLabel.text = name
            hostLabel.isHidden = false
        } else {
            let truncated = String(cached.hostPubkeyHex.prefix(8)) + "..."
                + String(cached.hostPubkeyHex.suffix(4))
            hostLabel.text = truncated
            hostLabel.isHidden = false
        }
        // No cached avatar URL — hide explicitly until real data arrives
        hostImageView.isHidden = true

        // Load thumbnail from Kingfisher's disk cache (no network request).
        // Must use the same DownsamplingImageProcessor as configure(with:appState:)
        // because Kingfisher appends the processor identifier to the cache key.
        if let urlString = cached.thumbnailURLString, let url = URL(string: urlString) {
            thumbnailImageView.kf.setImage(
                with: url,
                options: [
                    .onlyFromCache,
                    .transition(.none),
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 400, height: 300))),
                ]
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(_):
                    self.hideSkeletonState()
                    self.thumbnailImageView.isHidden = false
                    self.thumbnailLoaded = true

                    if let thumbnail = self.thumbnailImageView.image {
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            let colors = self?.extractDominantColors(from: thumbnail) ?? []
                            if !colors.isEmpty {
                                DispatchQueue.main.async { [weak self] in
                                    self?.dominantColors = colors
                                    self?.updateDynamicBlur(with: colors)
                                }
                            }
                        }
                    }
                case .failure:
                    // Cache miss — stay in skeleton state, relay data will arrive soon
                    break
                }
            }
        }
    }

    // MARK: - Deferred Video Loading

    /// Schedules video loading after a stabilization delay.
    /// Each call resets the timer, so rapid `configure()` calls during relay churn
    /// won't create wasted AVPlayer instances.
    private func scheduleDeferredVideoLoad() {
        videoStabilizationTimer?.invalidate()

        guard currentStreamURL != nil else { return }

        videoStabilizationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.beginVideoLoad()
        }
    }

    /// Creates the AVPlayer and starts buffering. Called only after the stabilization timer fires.
    private func beginVideoLoad() {
        guard let streamURL = currentStreamURL, !hasSetupVideo else { return }
        hasSetupVideo = true
        errorView.isHidden = true

        videoPlayerModel = VideoPlayerModel(url: streamURL)
        videoPlayerModel?.player.isMuted = true  // Always muted on hero
        playerLayer.player = videoPlayerModel?.player

        setupPlayerObservers()
    }

    /// Tears down the current video player and resets all video state.
    private func tearDownVideo() {
        videoStabilizationTimer?.invalidate()
        videoStabilizationTimer = nil

        videoPlayerModel?.player.pause()
        videoPlayerModel = nil
        playerLayer.player = nil
        playerLayer.isHidden = true

        cancellables.removeAll()

        // Restore thumbnail visibility
        thumbnailImageView.alpha = 1.0
        thumbnailImageView.isHidden = !thumbnailLoaded

        isPlaying = false
        hasSetupVideo = false
        thumbnailLoaded = false
        currentStreamURL = nil
    }

    // MARK: - Visibility Management

    /// Pauses hero video with a crossfade back to thumbnail, then fully
    /// releases the AVPlayer and all associated resources (Combine observers,
    /// network buffers, decode session). Guarantees zero CPU/GPU cost.
    func pauseVideo() {
        videoStabilizationTimer?.invalidate()
        videoStabilizationTimer = nil

        guard hasSetupVideo else { return }

        // Pause immediately to stop decode
        videoPlayerModel?.player.pause()

        // Crossfade thumbnail back in, then destroy the player entirely
        thumbnailImageView.isHidden = false
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
            self.thumbnailImageView.alpha = 1.0
        } completion: { [weak self] _ in
            guard let self = self else { return }
            // Fully release player resources after thumbnail is visible
            self.videoPlayerModel?.cleanup()
            self.videoPlayerModel = nil
            self.playerLayer.player = nil
            self.playerLayer.isHidden = true
            self.cancellables.removeAll()
            self.isPlaying = false
            self.hasSetupVideo = false
            // Keep currentStreamURL, currentEventId, thumbnailLoaded
            // so resumeVideo() can recreate from scratch
        }
    }

    /// Resumes hero video by recreating the player from scratch.
    /// Crossfades from thumbnail to live video once the first frame is decoded.
    func resumeVideo() {
        guard !hasSetupVideo, currentStreamURL != nil, thumbnailLoaded else { return }
        // Recreate the player — scheduleDeferredVideoLoad uses a 1.5s timer
        // but on resume we want it faster since the event is already stable
        beginVideoLoad()
    }

    // MARK: - Player Observers

    private func setupPlayerObservers() {
        guard let playerModel = videoPlayerModel else { return }
        playerModel.player.currentItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handlePlayerStatusChange(status)
            }
            .store(in: &cancellables)
        playerModel.player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handlePlaybackStatusChange(status)
            }
            .store(in: &cancellables)
    }

    private func handlePlayerStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            errorView.isHidden = true
            videoPlayerModel?.player.isMuted = true
            videoPlayerModel?.player.play()
            isPlaying = true

            // Crossfade: reveal the player layer, fade out thumbnail
            playerLayer.isHidden = false
            UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut]) {
                self.thumbnailImageView.alpha = 0
            }

        case .failed:
            // Video failed — keep thumbnail visible, no error UI needed
            print("❌ Hero video failed to load — staying on thumbnail")

        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handlePlaybackStatusChange(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isPlaying = true
        case .paused:
            isPlaying = false
        case .waitingToPlayAtSpecifiedRate:
            break
        @unknown default:
            break
        }
    }

}
