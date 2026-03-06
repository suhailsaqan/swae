//
//  StreamCardCell.swift
//  swae
//
//  Reusable stream card cell used on home page and profile page
//

import Kingfisher
import NostrSDK
import UIKit

/// Configuration options for StreamCardCell
struct StreamCardConfiguration {
    /// Whether to show the host avatar and name
    /// Set to false on profile pages where host is already known
    var showHostInfo: Bool = true
    
    /// Card corner radius
    var cornerRadius: CGFloat = 12
    
    /// Whether to show shadow
    var showShadow: Bool = true
    
    static let `default` = StreamCardConfiguration()
    
    /// Configuration for profile view (no host info needed)
    static let profile = StreamCardConfiguration(showHostInfo: false)
}

/// Reusable stream card cell used on home page and profile page
final class StreamCardCell: UICollectionViewCell {
    static let reuseIdentifier = "StreamCardCell"

    // MARK: - UI Components
    private let containerView = UIView()
    private let imageView = UIImageView()
    private let liveBadge = LiveBadgeView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let hostImageView = UIImageView()
    private let infoContainer = UIView()
    
    // Replay play icon overlay
    private let replayPlayIcon: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "play.circle.fill", withConfiguration: config))
        iv.tintColor = UIColor.white.withAlphaComponent(0.9)
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        iv.layer.shadowColor = UIColor.black.cgColor
        iv.layer.shadowOffset = CGSize(width: 0, height: 2)
        iv.layer.shadowRadius = 4
        iv.layer.shadowOpacity = 0.5
        return iv
    }()
    
    // MARK: - Configuration
    private var configuration: StreamCardConfiguration = .default
    
    // Host info constraints (to toggle visibility)
    private var hostImageWidthConstraint: NSLayoutConstraint!
    private var titleLeadingToHostConstraint: NSLayoutConstraint!
    private var titleLeadingToContainerConstraint: NSLayoutConstraint!
    
    // Store host pubkey for tap handling
    private var currentHostPubkey: String?
    private var metadataFallbackTimer: Timer?

    var onTap: (() -> Void)?
    
    /// Callback when host profile picture is tapped
    var onHostTap: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // Container for shadow
        containerView.backgroundColor = .clear
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Image view - 16:9 aspect ratio
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray4
        imageView.layer.cornerRadius = 12
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)

        // Add shadow to container
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.layer.shadowRadius = 12
        containerView.layer.shadowOpacity = 0.15

        // Live badge (includes connected viewer count)
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        imageView.addSubview(liveBadge)

        // Replay play icon overlay (centered on thumbnail)
        imageView.addSubview(replayPlayIcon)

        // Info container
        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(infoContainer)

        // Host image
        hostImageView.contentMode = .scaleAspectFill
        hostImageView.clipsToBounds = true
        hostImageView.backgroundColor = .systemGray5
        hostImageView.layer.cornerRadius = 16
        hostImageView.translatesAutoresizingMaskIntoConstraints = false
        hostImageView.isUserInteractionEnabled = true
        infoContainer.addSubview(hostImageView)
        
        // Add tap gesture to host image for profile navigation
        let hostTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleHostTap))
        hostImageView.addGestureRecognizer(hostTapGesture)

        // Title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(titleLabel)

        // Host name
        hostLabel.font = .systemFont(ofSize: 13, weight: .regular)
        hostLabel.textColor = .secondaryLabel
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(hostLabel)
        
        // Create constraints that we'll toggle
        hostImageWidthConstraint = hostImageView.widthAnchor.constraint(equalToConstant: 32)
        titleLeadingToHostConstraint = titleLabel.leadingAnchor.constraint(equalTo: hostImageView.trailingAnchor, constant: 8)
        titleLeadingToContainerConstraint = titleLabel.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor)

        NSLayoutConstraint.activate([
            // Container fills cell
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Image view with 16:9 aspect ratio
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 9.0/16.0),

            // Live badge
            liveBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 8),
            liveBadge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 8),

            // Replay play icon (centered on thumbnail)
            replayPlayIcon.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            replayPlayIcon.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            // Info container below image (8pt gap)
            infoContainer.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            infoContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            infoContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            infoContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // Host image
            hostImageView.topAnchor.constraint(equalTo: infoContainer.topAnchor),
            hostImageView.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor),
            hostImageWidthConstraint,
            hostImageView.heightAnchor.constraint(equalTo: hostImageView.widthAnchor),

            // Title - leading constraint set dynamically
            titleLabel.topAnchor.constraint(equalTo: infoContainer.topAnchor),
            titleLeadingToHostConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor),

            // Host label
            hostLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            hostLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hostLabel.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor),
            hostLabel.bottomAnchor.constraint(lessThanOrEqualTo: infoContainer.bottomAnchor),
        ])

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap() {
        // Instant callback - no animation delay
        onTap?()
        
        // Visual feedback happens in parallel (non-blocking)
        UIView.animate(
            withDuration: 0.08,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            },
            completion: { _ in
                UIView.animate(
                    withDuration: 0.08,
                    delay: 0,
                    options: [.curveEaseIn, .allowUserInteraction]
                ) {
                    self.transform = .identity
                }
            })
    }
    
    @objc private func handleHostTap(_ gesture: UITapGestureRecognizer) {
        guard let pubkey = currentHostPubkey, configuration.showHostInfo else { return }
        
        // Visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.hostImageView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.hostImageView.transform = .identity
            }
        }
        
        onHostTap?(pubkey)
    }
    
    /// Apply configuration (call before configure(with:appState:))
    func applyConfiguration(_ config: StreamCardConfiguration) {
        self.configuration = config
        
        // Toggle host info visibility
        hostImageView.isHidden = !config.showHostInfo
        hostLabel.isHidden = !config.showHostInfo
        
        // Adjust title leading constraint
        if config.showHostInfo {
            titleLeadingToContainerConstraint.isActive = false
            titleLeadingToHostConstraint.isActive = true
            hostImageWidthConstraint.constant = 32
        } else {
            titleLeadingToHostConstraint.isActive = false
            titleLeadingToContainerConstraint.isActive = true
            hostImageWidthConstraint.constant = 0
        }
        
        // Shadow
        containerView.layer.shadowOpacity = config.showShadow ? 0.15 : 0
        
        // Corner radius
        imageView.layer.cornerRadius = config.cornerRadius
    }

    func configure(with event: LiveActivitiesEvent, appState: AppState) {
        // Set text immediately (no delay)
        titleLabel.text = event.title ?? "Untitled Stream"
        liveBadge.setViewerCount(event.currentParticipants)
        if event.isActuallyLive {
            liveBadge.setLive(true)
            replayPlayIcon.isHidden = true
        } else if event.recording != nil {
            liveBadge.setReplay()
            replayPlayIcon.isHidden = false
        } else {
            liveBadge.setLive(false)
            replayPlayIcon.isHidden = true
        }
        
        // Get host pubkey - per NIP-53, host is in `p` tag with role "host", fallback to event author
        let hostPubkey = event.hostPubkeyHex
        
        // Store host pubkey for tap handling
        currentHostPubkey = hostPubkey
        
        // Only load host info if showing
        if configuration.showHostInfo {
            // Host name from metadata
            if let metadata = appState.metadataEvents[hostPubkey] {
                metadataFallbackTimer?.invalidate()
                metadataFallbackTimer = nil
                hostLabel.text = metadata.userMetadata?.displayName ?? metadata.userMetadata?.name ?? "Unknown"
                hostLabel.isHidden = false
            } else {
                // Show truncated pubkey immediately instead of skeleton
                hostLabel.text = String(hostPubkey.prefix(8)) + "..."
                hostLabel.isHidden = false

                // Update with real name if metadata arrives later
                metadataFallbackTimer?.invalidate()
                let pubkey = hostPubkey
                metadataFallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    if let metadata = appState.metadataEvents[pubkey] {
                        self.hostLabel.text = metadata.userMetadata?.displayName ?? metadata.userMetadata?.name ?? "Unknown"
                    }
                }
            }
            
            // Load host image with same optimizations
            if let metadata = appState.metadataEvents[hostPubkey],
               let pictureURL = metadata.userMetadata?.pictureURL {
                hostImageView.kf.setImage(
                    with: pictureURL,
                    options: [
                        .transition(.none),
                        .memoryCacheExpiration(.days(7)),
                        .diskCacheExpiration(.days(30)),
                        .backgroundDecode,
                        .processor(DownsamplingImageProcessor(size: CGSize(width: 64, height: 64))),
                    ])
            }
        }
        
        // Load thumbnail - use larger size for better quality
        if let imageURL = event.image {
            imageView.kf.setImage(
                with: imageURL,
                options: [
                    .transition(.none),
                    .cacheOriginalImage,
                    .memoryCacheExpiration(.days(7)),
                    .diskCacheExpiration(.days(30)),
                    .backgroundDecode,
                    .processor(DownsamplingImageProcessor(size: CGSize(width: 400, height: 225))),
                ])
        } else {
            imageView.image = nil
            imageView.backgroundColor = .systemGray4
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        imageView.backgroundColor = .systemGray4
        hostImageView.kf.cancelDownloadTask()
        hostImageView.image = nil
        hostImageView.transform = .identity
        titleLabel.text = nil
        hostLabel.text = nil
        hostLabel.isHidden = false
        metadataFallbackTimer?.invalidate()
        metadataFallbackTimer = nil
        onTap = nil
        onHostTap = nil
        currentHostPubkey = nil
        liveBadge.resetAnimations()
        replayPlayIcon.isHidden = true
    }
}
