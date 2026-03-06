import UIKit
import AVKit
import NostrSDK
import Combine

// MARK: - Hero Cell with Live Video
private final class HeroCell: UICollectionViewCell {
    static let reuseIdentifier = "HeroCell"

    // MARK: - Video Components
    private let videoContainerView = UIView()
    private var playerLayer: AVPlayerLayer!
    private var videoPlayerModel: VideoPlayerModel?
    private var currentEvent: LiveActivitiesEvent?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Aspect Ratio Handling
    private var videoAspectRatio: CGFloat = 16.0 / 9.0  // Default aspect ratio

    // MARK: - Thumbnail Components
    private let thumbnailImageView = UIImageView()

    // MARK: - Dynamic Blur Components
    private let blurContainerView = UIView()
    private let dynamicBlurView = UIVisualEffectView()
    private let colorOverlayView = UIView()
    private let gradientBlendLayer = CAGradientLayer()
    private let blurFadeOutMask = CAGradientLayer()  // Mask to fade out blur at bottom
    private var dominantColors: [UIColor] = []
    private var colorExtractionTimer: Timer?

    // MARK: - UI Overlay Components
    private let gradientLayer = CAGradientLayer()
    private let liveBadge = LiveBadgeView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let hostImageView = UIImageView()
    private let playPauseButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorView = UIView()
    private let errorLabel = UILabel()
    private let infoCardView = UIView()
    private let containerContentView = UIView()

    // MARK: - Deferred Video Loading
    private var videoStabilizationTimer: Timer?
    private var currentStreamURL: URL?
    private var currentEventId: String?
    private var thumbnailLoaded = false

    // MARK: - Interaction
    var onTap: (() -> Void)?
    private var isPlaying = false
    private var hasSetupVideo = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupVideoPlayer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Add subtle background to make video container pop
        contentView.backgroundColor = UIColor.systemBackground

        // Video container - centered with increased padding and enhanced styling
        videoContainerView.backgroundColor = .black
        videoContainerView.layer.cornerRadius = 24  // Ensure rounded edges on video container
        videoContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(videoContainerView)

        // Add shadow with glow effect (outside clipsToBounds to avoid clipping)
        videoContainerView.layer.shadowColor = UIColor.black.withAlphaComponent(0.2).cgColor
        videoContainerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        videoContainerView.layer.shadowRadius = 16
        videoContainerView.layer.shadowOpacity = 0.4
        videoContainerView.layer.masksToBounds = false  // Allow shadow to extend beyond bounds

        // Inner content view for rounded clipping
        containerContentView.backgroundColor = .black
        containerContentView.layer.cornerRadius = 24
        containerContentView.clipsToBounds = true  // Clip inner content to rounded edges
        containerContentView.translatesAutoresizingMaskIntoConstraints = false
        videoContainerView.addSubview(containerContentView)

        // Thumbnail image view - shows while video loads
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = .systemGray6
        thumbnailImageView.alpha = 1.0  // Ensure thumbnail is visible
        thumbnailImageView.isHidden = false  // Ensure thumbnail is not hidden
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        containerContentView.addSubview(thumbnailImageView)

        // Dynamic blur container - positioned above video
        blurContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blurContainerView)

        // Gradient blend layer - smooth transition from content to blur
        gradientBlendLayer.colors = [
            UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.3).cgColor,
        ]
        gradientBlendLayer.locations = [0.0, 1.0]
        gradientBlendLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientBlendLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        blurContainerView.layer.addSublayer(gradientBlendLayer)

        // Blur fade-out mask - creates smooth gradient from top to video area
        blurFadeOutMask.colors = [
            UIColor.white.cgColor,  // Fully opaque at very top (status bar area)
            UIColor.white.cgColor,  // Keep opaque through notch/status bar
            UIColor.white.withAlphaComponent(0.9).cgColor,  // Start gentle fade after safe area
            UIColor.white.withAlphaComponent(0.7).cgColor,  // Progressive fade
            UIColor.white.withAlphaComponent(0.4).cgColor,  // More transparent
            UIColor.white.withAlphaComponent(0.15).cgColor,  // Nearly transparent
            UIColor.clear.cgColor,  // Fully transparent at video
        ]
        blurFadeOutMask.locations = [0.0, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0]
        blurFadeOutMask.startPoint = CGPoint(x: 0.5, y: 0.0)
        blurFadeOutMask.endPoint = CGPoint(x: 0.5, y: 1.0)
        blurContainerView.layer.mask = blurFadeOutMask

        // Dynamic blur view for tinted effect
        dynamicBlurView.effect = UIBlurEffect(style: .dark)
        dynamicBlurView.translatesAutoresizingMaskIntoConstraints = false
        blurContainerView.addSubview(dynamicBlurView)

        // Color overlay for dynamic gradient
        colorOverlayView.translatesAutoresizingMaskIntoConstraints = false
        blurContainerView.addSubview(colorOverlayView)

        // Video no longer needs a fade mask since it starts below the blur
        // The blur's fade-out mask handles the smooth transition

        // Gradient overlay for better text readability
        gradientLayer.colors = [
            UIColor.clear.cgColor,  // 0%   - Fully transparent
            UIColor.clear.cgColor,  // 55%  - Keep content fully visible
            UIColor.black.withAlphaComponent(0.0).cgColor,  // 60%  - Imperceptible start
            UIColor.black.withAlphaComponent(0.05).cgColor,  // 65%  - Very subtle
            UIColor.black.withAlphaComponent(0.15).cgColor,  // 70%  - Gentle fade begins
            UIColor.black.withAlphaComponent(0.30).cgColor,  // 75%  - Gradual increase
            UIColor.black.withAlphaComponent(0.50).cgColor,  // 80%  - Noticeable but smooth
            UIColor.black.withAlphaComponent(0.70).cgColor,  // 85%  - More prominent
            UIColor.black.withAlphaComponent(0.85).cgColor,  // 90%  - Almost there
            UIColor.black.withAlphaComponent(0.95).cgColor,  // 95%  - Nearly solid
            UIColor.black.cgColor,  // 100% - Fully opaque black
        ]
        gradientLayer.locations = [0.0, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        videoContainerView.layer.addSublayer(gradientLayer)

        // Info card for text overlay
        infoCardView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        infoCardView.layer.cornerRadius = 12
        infoCardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoCardView)

        // Live badge with enhanced styling
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        infoCardView.addSubview(liveBadge)

        // Host image with enhanced styling
        hostImageView.contentMode = .scaleAspectFill
        hostImageView.clipsToBounds = true
        hostImageView.backgroundColor = .systemGray5
        hostImageView.layer.cornerRadius = 20
        hostImageView.layer.borderWidth = 2
        hostImageView.layer.borderColor = UIColor.white.cgColor
        hostImageView.layer.shadowColor = UIColor.black.cgColor
        hostImageView.layer.shadowOffset = CGSize(width: 0, height: 2)
        hostImageView.layer.shadowRadius = 4
        hostImageView.layer.shadowOpacity = 0.3
        hostImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hostImageView)

        // Title with enhanced styling
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel.layer.shadowRadius = 2
        titleLabel.layer.shadowOpacity = 0.8
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        infoCardView.addSubview(titleLabel)

        // Host name with enhanced styling
        hostLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hostLabel.textColor = .white.withAlphaComponent(0.95)
        hostLabel.layer.shadowColor = UIColor.black.cgColor
        hostLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        hostLabel.layer.shadowRadius = 2
        hostLabel.layer.shadowOpacity = 0.8
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        infoCardView.addSubview(hostLabel)

        // Play/Pause button - removed for cleaner hero experience
        // playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        // playPauseButton.tintColor = .white
        // playPauseButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        // playPauseButton.layer.cornerRadius = 30
        // playPauseButton.layer.shadowColor = UIColor.black.cgColor
        // playPauseButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        // playPauseButton.layer.shadowRadius = 4
        // playPauseButton.layer.shadowOpacity = 0.3
        // playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        // playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        // playPauseButton.alpha = 0
        // contentView.addSubview(playPauseButton)

        // Loading indicator - removed for smoother thumbnail experience
        // loadingIndicator.color = .white
        // loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        // loadingIndicator.hidesWhenStopped = true
        // contentView.addSubview(loadingIndicator)

        // Error view
        errorView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        errorView.layer.cornerRadius = 12
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        contentView.addSubview(errorView)

        errorLabel.text = "Unable to load video"
        errorLabel.font = .systemFont(ofSize: 16, weight: .medium)
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            // Video container - positioned below safe area with proper spacing
            videoContainerView.topAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 20),
            videoContainerView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 30),
            videoContainerView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -30),
            videoContainerView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -12),

            // Dynamic height based on aspect ratio
            videoContainerView.heightAnchor.constraint(
                equalTo: videoContainerView.widthAnchor, multiplier: videoAspectRatio
            ).with(priority: .defaultHigh),
            videoContainerView.heightAnchor.constraint(
                lessThanOrEqualTo: videoContainerView.widthAnchor, multiplier: 1.5
            ).with(priority: .required),

            // Inner container content view
            containerContentView.topAnchor.constraint(equalTo: videoContainerView.topAnchor),
            containerContentView.leadingAnchor.constraint(
                equalTo: videoContainerView.leadingAnchor),
            containerContentView.trailingAnchor.constraint(
                equalTo: videoContainerView.trailingAnchor),
            containerContentView.bottomAnchor.constraint(equalTo: videoContainerView.bottomAnchor),

            // Thumbnail image fills container content view
            thumbnailImageView.topAnchor.constraint(equalTo: containerContentView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(
                equalTo: containerContentView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(
                equalTo: containerContentView.trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: containerContentView.bottomAnchor),

            // Blur container extends way beyond top to handle any bounce scenario
            blurContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -600),  // Extend much further above
            blurContainerView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: -50),  // Extend sides too
            blurContainerView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: 50),
            blurContainerView.bottomAnchor.constraint(
                equalTo: videoContainerView.bottomAnchor, constant: 60),

            // Dynamic blur view
            dynamicBlurView.topAnchor.constraint(equalTo: blurContainerView.topAnchor),
            dynamicBlurView.leadingAnchor.constraint(equalTo: blurContainerView.leadingAnchor),
            dynamicBlurView.trailingAnchor.constraint(equalTo: blurContainerView.trailingAnchor),
            dynamicBlurView.bottomAnchor.constraint(equalTo: blurContainerView.bottomAnchor),

            // Color overlay view
            colorOverlayView.topAnchor.constraint(equalTo: blurContainerView.topAnchor),
            colorOverlayView.leadingAnchor.constraint(equalTo: blurContainerView.leadingAnchor),
            colorOverlayView.trailingAnchor.constraint(equalTo: blurContainerView.trailingAnchor),
            colorOverlayView.bottomAnchor.constraint(equalTo: blurContainerView.bottomAnchor),

            // Info card for text overlay
            infoCardView.leadingAnchor.constraint(
                equalTo: videoContainerView.leadingAnchor, constant: 16),
            infoCardView.trailingAnchor.constraint(
                equalTo: videoContainerView.trailingAnchor, constant: -16),
            infoCardView.bottomAnchor.constraint(
                equalTo: videoContainerView.bottomAnchor, constant: -16),
            infoCardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),

            // Live badge positioned inside info card
            liveBadge.topAnchor.constraint(equalTo: infoCardView.topAnchor, constant: 12),
            liveBadge.leadingAnchor.constraint(equalTo: infoCardView.leadingAnchor, constant: 12),

            // Host image positioned above title
            hostImageView.leadingAnchor.constraint(
                equalTo: videoContainerView.leadingAnchor, constant: 16),
            hostImageView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -12),
            hostImageView.widthAnchor.constraint(equalToConstant: 40),
            hostImageView.heightAnchor.constraint(equalToConstant: 40),

            // Title positioned inside info card
            titleLabel.topAnchor.constraint(equalTo: liveBadge.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: infoCardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(
                equalTo: infoCardView.trailingAnchor, constant: -12),

            // Host name at bottom of info card
            hostLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            hostLabel.leadingAnchor.constraint(equalTo: infoCardView.leadingAnchor, constant: 12),
            hostLabel.trailingAnchor.constraint(
                equalTo: infoCardView.trailingAnchor, constant: -12),
            hostLabel.bottomAnchor.constraint(equalTo: infoCardView.bottomAnchor, constant: -12),

            // Error view centered
            errorView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            errorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            errorView.widthAnchor.constraint(equalToConstant: 200),
            errorView.heightAnchor.constraint(equalToConstant: 60),

            errorLabel.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -16),
        ])

        // Ensure blur container is above video (z-order)
        contentView.bringSubviewToFront(videoContainerView)
        contentView.bringSubviewToFront(infoCardView)
        contentView.bringSubviewToFront(hostImageView)

        // Add tap gesture for full interaction
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tapGesture)

        // Animate info card on load
        infoCardView.alpha = 0
        infoCardView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        UIView.animate(withDuration: 0.3, delay: 0.1, options: [.curveEaseOut]) {
            self.infoCardView.alpha = 1.0
            self.infoCardView.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.2) {
                self.liveBadge.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            } completion: { _ in
                UIView.animate(withDuration: 0.2) {
                    self.liveBadge.transform = .identity
                }
            }
        }
    }

    // MARK: - Aspect Ratio Management

    private func updateVideoAspectRatio(_ aspectRatio: CGFloat) {
        videoAspectRatio = aspectRatio

        // For portrait videos, switch to .resizeAspect to avoid cropping
        if aspectRatio < 1.0 {
            playerLayer.videoGravity = .resizeAspect
        } else {
            playerLayer.videoGravity = .resizeAspectFill
        }

        // Update height constraint
        videoContainerView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height && constraint.secondAttribute == .width {
                constraint.isActive = false
            }
        }

        // Add new constraint with updated aspect ratio
        let newHeightConstraint = videoContainerView.heightAnchor.constraint(
            equalTo: videoContainerView.widthAnchor,
            multiplier: aspectRatio
        )
        newHeightConstraint.priority = .defaultHigh
        newHeightConstraint.isActive = true

        self.layoutIfNeeded()
    }

    private func detectVideoAspectRatio(from player: AVPlayer) {
        guard let currentItem = player.currentItem else { return }
        let videoTracks = currentItem.tracks.filter { $0.assetTrack?.mediaType == .video }
        if let videoTrack = videoTracks.first, let assetTrack = videoTrack.assetTrack {
            let size = assetTrack.naturalSize
            let aspectRatio = size.width / size.height
            DispatchQueue.main.async {
                self.updateVideoAspectRatio(aspectRatio)
                self.setNeedsLayout()
            }
        }
    }

    private func setupVideoPlayer() {
        // Create AVPlayerLayer
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.isHidden = true  // Thumbnail-only mode: hide video layer
        containerContentView.layer.addSublayer(playerLayer)  // Add to containerContentView
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        gradientLayer.frame = videoContainerView.bounds
        gradientLayer.cornerRadius = 24
        playerLayer.frame = containerContentView.bounds
        gradientBlendLayer.frame = blurContainerView.bounds
        blurFadeOutMask.frame = blurContainerView.bounds
        dynamicBlurView.frame = blurContainerView.bounds
        colorOverlayView.frame = blurContainerView.bounds

        // Update dynamic gradient frame
        if let dynamicGradient = colorOverlayView.layer.sublayers?.first(where: {
            $0 is CAGradientLayer
        }) {
            dynamicGradient.frame = colorOverlayView.bounds
        }

        videoContainerView.layer.shadowPath =
            UIBezierPath(roundedRect: videoContainerView.bounds, cornerRadius: 24).cgPath

        CATransaction.commit()
    }

    @objc private func handleTap() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        onTap?()
    }

    // MARK: - Scroll Handling for Spotify-like Blur Behavior

    func updateBlurForScrollOffset(_ offset: CGFloat) {
        // When pulling down (negative offset), extend the blur height dynamically
        if offset < 0 {
            // Calculate how much to extend the blur container
            let extensionAmount = abs(offset)

            // Update the blur container's top constraint to extend upward
            blurContainerView.transform = CGAffineTransform(translationX: 0, y: offset)

            // Dynamically adjust the blur fade mask to handle the extended area
            let extendedLocations: [NSNumber] = [
                0.0,  // Top (fully opaque)
                0.1,  // Still opaque through extended area
                0.3,  // Start gentle fade
                0.5,  // Progressive fade
                0.7,  // More transparent
                0.9,  // Nearly transparent
                1.0,  // Fully transparent at video
            ]

            blurFadeOutMask.locations = extendedLocations
            blurContainerView.alpha = 1.0

        } else {
            // When scrolling up, gradually fade out the blur
            let fadeThreshold: CGFloat = 80

            if offset < fadeThreshold {
                // Keep blur visible and reset mask to normal
                blurContainerView.transform = .identity
                blurContainerView.alpha = 1.0

                // Reset to normal fade mask
                blurFadeOutMask.locations = [0.0, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0]

            } else {
                // Fade out the blur as we scroll up
                let fadeDistance: CGFloat = 60
                let fadeProgress = min(1.0, (offset - fadeThreshold) / fadeDistance)
                blurContainerView.alpha = 1.0 - (fadeProgress * 0.8)  // Don't fade completely
                blurContainerView.transform = CGAffineTransform(translationX: 0, y: -offset * 0.2)
            }
        }
    }

    func resetBlurPosition() {
        UIView.animate(
            withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.blurContainerView.transform = .identity
            self.blurContainerView.alpha = 1.0

            // Reset blur fade mask to normal state
            self.blurFadeOutMask.locations = [0.0, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0]
        }
    }

    private func extractDominantColors(from image: UIImage) -> [UIColor] {
        guard let cgImage = image.cgImage else { return [] }

        // Create a smaller version for faster processing
        let targetSize = CGSize(width: 150, height: 150)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let resizedCGImage = resizedImage.cgImage else { return [] }

        // Extract pixel data
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

        // Sample colors from different regions with more strategic points
        var colors: [UIColor] = []
        let samplePoints = [
            CGPoint(x: Double(width) * 0.15, y: Double(height) * 0.15),  // Top-left
            CGPoint(x: Double(width) * 0.85, y: Double(height) * 0.15),  // Top-right
            CGPoint(x: Double(width) * 0.5, y: Double(height) * 0.3),  // Top-center
            CGPoint(x: Double(width) * 0.25, y: Double(height) * 0.5),  // Left-center
            CGPoint(x: Double(width) * 0.75, y: Double(height) * 0.5),  // Right-center
            CGPoint(x: Double(width) * 0.5, y: Double(height) * 0.7),  // Bottom-center
            CGPoint(x: Double(width) * 0.15, y: Double(height) * 0.85),  // Bottom-left
            CGPoint(x: Double(width) * 0.85, y: Double(height) * 0.85),  // Bottom-right
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

        // Enhanced filtering - keep vibrant, saturated colors
        return colors.filter { color in
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            // Keep colors that are vibrant and not too dark/light
            return brightness > 0.15 && brightness < 0.85 && saturation > 0.2
        }.prefix(4).map { $0 }  // Limit to 4 best colors
    }

    private func createDynamicGradient(from colors: [UIColor]) -> CAGradientLayer {
        let gradient = CAGradientLayer()

        if colors.count >= 3 {
            let enhancedColors = colors.map { color in
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0

                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

                let enhancedSaturation = min(saturation * 1.2, 1.0)
                let enhancedBrightness = max(min(brightness * 0.8, 0.7), 0.3)

                return UIColor(
                    hue: hue, saturation: enhancedSaturation, brightness: enhancedBrightness,
                    alpha: 0.7)
            }

            gradient.colors = enhancedColors.map { $0.cgColor }
            gradient.locations = (0..<enhancedColors.count).map {
                NSNumber(value: Double($0) / Double(enhancedColors.count - 1))
            }
        } else if colors.count >= 2 {
            let color1 = colors[0]
            let color2 = colors[1]

            var hue1: CGFloat = 0
            var hue2: CGFloat = 0
            var sat1: CGFloat = 0
            var sat2: CGFloat = 0
            var bright1: CGFloat = 0
            var bright2: CGFloat = 0
            var alpha1: CGFloat = 0
            var alpha2: CGFloat = 0

            color1.getHue(&hue1, saturation: &sat1, brightness: &bright1, alpha: &alpha1)
            color2.getHue(&hue2, saturation: &sat2, brightness: &bright2, alpha: &alpha2)

            let enhanced1 = UIColor(
                hue: hue1, saturation: min(sat1 * 1.3, 1.0),
                brightness: max(min(bright1 * 0.7, 0.6), 0.4), alpha: 0.6)
            let enhanced2 = UIColor(
                hue: hue2, saturation: min(sat2 * 1.3, 1.0),
                brightness: max(min(bright2 * 0.7, 0.6), 0.4), alpha: 0.8)

            gradient.colors = [enhanced1.cgColor, enhanced2.cgColor]
            gradient.locations = [0.0, 1.0]
        } else if let firstColor = colors.first {
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0

            firstColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            let lighter = UIColor(
                hue: hue, saturation: min(saturation * 1.2, 1.0),
                brightness: max(min(brightness * 0.6, 0.5), 0.3), alpha: 0.4)
            let darker = UIColor(
                hue: hue, saturation: min(saturation * 1.4, 1.0),
                brightness: max(min(brightness * 0.8, 0.7), 0.5), alpha: 0.8)

            gradient.colors = [lighter.cgColor, darker.cgColor]
            gradient.locations = [0.0, 1.0]
        } else {
            gradient.colors = [
                UIColor.systemIndigo.withAlphaComponent(0.5).cgColor,
                UIColor.systemPurple.withAlphaComponent(0.6).cgColor,
                UIColor.systemPink.withAlphaComponent(0.7).cgColor,
            ]
            gradient.locations = [0.0, 0.5, 1.0]
        }

        gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)

        return gradient
    }

    private func updateDynamicBlur(with colors: [UIColor]) {
        let dynamicGradient = createDynamicGradient(from: colors)
        dynamicGradient.frame = colorOverlayView.bounds
        colorOverlayView.layer.sublayers?.removeAll { $0 is CAGradientLayer }
        colorOverlayView.layer.addSublayer(dynamicGradient)

        if colors.count >= 2 {
            let blendColors = [
                colors.first!.withAlphaComponent(0.0).cgColor,
                colors.first!.withAlphaComponent(0.4).cgColor,
                colors.last!.withAlphaComponent(0.6).cgColor,
            ]
            gradientBlendLayer.colors = blendColors
            gradientBlendLayer.locations = [0.0, 0.7, 1.0]
        }

        UIView.animate(
            withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2
        ) {
            self.colorOverlayView.alpha = 1.0
            self.dynamicBlurView.alpha = 0.8
        }
    }

    private func startColorExtractionTimer() {
        colorExtractionTimer?.invalidate()
        colorExtractionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            self?.extractColorsFromCurrentContent()
        }
    }

    private func stopColorExtractionTimer() {
        colorExtractionTimer?.invalidate()
        colorExtractionTimer = nil
    }

    private func extractColorsFromVideoFrame() -> [UIColor] {
        guard let player = videoPlayerModel?.player,
            let currentItem = player.currentItem
        else { return [] }

        if let thumbnail = thumbnailImageView.image {
            return extractDominantColors(from: thumbnail)
        }

        return []
    }

    private func extractColorsFromCurrentContent() {
        var colors: [UIColor] = []

        if isPlaying,
            let videoColors = videoPlayerModel?.player.currentItem?.asset != nil
                ? extractColorsFromVideoFrame() : nil
        {
            colors = videoColors
        }

        if colors.isEmpty, let thumbnail = thumbnailImageView.image {
            colors = extractDominantColors(from: thumbnail)
        }

        if !colors.isEmpty {
            dominantColors = colors
            updateDynamicBlur(with: colors)
        }
    }

    func configure(with event: LiveActivitiesEvent, appState: AppState) {
        let eventId = event.id
        let isNewEvent = eventId != currentEventId
        currentEventId = eventId
        currentEvent = event

        // Always update live metadata
        titleLabel.text = event.title ?? "Untitled Stream"
        liveBadge.setViewerCount(event.currentParticipants)
        liveBadge.setLive(event.isActuallyLive)

        let hostPubkey = event.hostPubkeyHex

        if let metadata = appState.metadataEvents[hostPubkey] {
            hostLabel.text =
                metadata.userMetadata?.displayName ?? metadata.userMetadata?.name ?? "Unknown Host"
            if let pictureURL = metadata.userMetadata?.pictureURL {
                hostImageView.kf.setImage(with: pictureURL, options: [.transition(.fade(0.3))])
            }
        } else {
            hostLabel.text = "Loading..."
        }

        // If same event and video is already playing or loading, just update text and return
        if !isNewEvent && (isPlaying || hasSetupVideo) {
            return
        }

        // New event — tear down any existing video
        if isNewEvent {
            tearDownVideo()
        }

        currentStreamURL = event.streaming ?? event.recording

        let thumbnailURL = event.image

        if let thumbnailURL = thumbnailURL {
            thumbnailImageView.kf.setImage(
                with: thumbnailURL,
                options: [.transition(.fade(0.2))]
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(_):
                    self.thumbnailLoaded = true
                    self.extractColorsFromCurrentContent()
                    self.startColorExtractionTimer()
                    self.scheduleDeferredVideoLoad()
                case .failure(let error):
                    print("❌ Thumbnail failed to load: \(error)")
                    self.thumbnailLoaded = true
                    self.scheduleDeferredVideoLoad()
                }
            }
        } else {
            thumbnailLoaded = true
            scheduleDeferredVideoLoad()
        }

        setNeedsLayout()
        layoutIfNeeded()
    }

    // MARK: - Deferred Video Loading

    private func scheduleDeferredVideoLoad() {
        videoStabilizationTimer?.invalidate()
        guard currentStreamURL != nil else { return }

        videoStabilizationTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.beginVideoLoad()
        }
    }

    private func beginVideoLoad() {
        guard let streamURL = currentStreamURL, !hasSetupVideo else { return }
        hasSetupVideo = true
        errorView.isHidden = true

        videoPlayerModel = VideoPlayerModel(url: streamURL)
        videoPlayerModel?.player.isMuted = true
        playerLayer.player = videoPlayerModel?.player

        if let player = videoPlayerModel?.player {
            detectVideoAspectRatio(from: player)
        }

        setupPlayerObservers()
    }

    private func tearDownVideo() {
        videoStabilizationTimer?.invalidate()
        videoStabilizationTimer = nil

        videoPlayerModel?.player.pause()
        videoPlayerModel = nil
        playerLayer.player = nil
        playerLayer.isHidden = true

        cancellables.removeAll()

        thumbnailImageView.alpha = 1.0
        thumbnailImageView.isHidden = !thumbnailLoaded

        isPlaying = false
        hasSetupVideo = false
        thumbnailLoaded = false
        currentStreamURL = nil
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
            if let player = videoPlayerModel?.player {
                detectVideoAspectRatio(from: player)
            }
            videoPlayerModel?.player.isMuted = true
            videoPlayerModel?.player.play()
            isPlaying = true

            // Crossfade: reveal the player layer, fade out thumbnail
            playerLayer.isHidden = false
            UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseInOut]) {
                self.thumbnailImageView.alpha = 0
            }

        case .failed:
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

    override func prepareForReuse() {
        super.prepareForReuse()
        tearDownVideo()
        titleLabel.text = nil
        hostLabel.text = nil
        hostImageView.image = nil
        thumbnailImageView.image = nil
        thumbnailImageView.alpha = 1
        thumbnailImageView.isHidden = false
        errorView.isHidden = true
        currentEventId = nil
        onTap = nil
        stopColorExtractionTimer()
        dominantColors.removeAll()
        colorOverlayView.layer.sublayers?.removeAll { $0 is CAGradientLayer }
        colorOverlayView.alpha = 0
        gradientBlendLayer.colors = [
            UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.3).cgColor,
        ]
        resetBlurPosition()
    }
}
