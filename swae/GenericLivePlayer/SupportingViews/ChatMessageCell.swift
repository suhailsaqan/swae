//
//  ChatMessageCell.swift
//  swae
//
//  Chat message cell for live streaming
//

import Kingfisher
import NostrSDK
import SDWebImage
import UIKit

class LiveChatMessageCell: UITableViewCell {
    let userImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = .systemGray
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isUserInteractionEnabled = true
        return iv
    }()

    let userNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }()

    let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.isUserInteractionEnabled = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Use UITextView for tappable links in messages
    let messageTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .secondaryLabel
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isUserInteractionEnabled = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        // Style for links - match regular text but purple, no underline
        tv.linkTextAttributes = [
            .foregroundColor: UIColor.systemPurple,
            .font: UIFont.systemFont(ofSize: 15)
        ]
        return tv
    }()
    
    // Store mention ranges for tap detection
    private var mentionRanges: [(range: NSRange, pubkey: String)] = []
    
    // Store appState for tap handling
    private weak var appState: AppState?
    private var messagePubkeys: [String] = []
    private var currentPubkey: String?
    
    // NIP-30 animated emote overlays
    private var animatedEmoteViews: [SDAnimatedImageView] = []
    
    /// Pause/resume emote animations (set during scroll for performance)
    var emoteAnimationsPaused: Bool = false {
        didSet {
            animatedEmoteViews.forEach { $0.autoPlayAnimatedImage = !emoteAnimationsPaused }
        }
    }
    
    /// Callback when user profile is tapped (profile pic or username)
    var onProfileTap: ((String) -> Void)?
    
    /// Callback when a mention in the message is tapped
    var onMentionTap: ((String) -> Void)?
    
    /// Callback when user taps to retry a failed pending message
    var onRetryTap: (() -> Void)?
    
    // Pending state UI elements
    private let statusIcon: UIImageView = {
        let iv = UIImageView()
        iv.tintColor = .secondaryLabel
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        return iv
    }()
    
    private let retryLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap to retry"
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutAnimatedEmotes()
    }

    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .systemBackground
        transform = CGAffineTransform(rotationAngle: .pi)

        contentView.addSubview(userImageView)
        contentView.addSubview(userNameLabel)
        contentView.addSubview(messageTextView)
        contentView.addSubview(statusIcon)
        contentView.addSubview(retryLabel)
        
        // OVERFLOW FIX: Enable truncation on username
        userNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        userNameLabel.lineBreakMode = .byTruncatingTail
        userNameLabel.numberOfLines = 1
        
        // Set delegate for link handling
        messageTextView.delegate = self
        
        // Add tap gesture as fallback for mention detection (in case links don't work with rotation)
        let messageTap = UITapGestureRecognizer(target: self, action: #selector(messageTextTapped(_:)))
        messageTextView.addGestureRecognizer(messageTap)
        
        // Add tap gestures for profile navigation
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        userImageView.addGestureRecognizer(imageTap)
        
        let nameTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        userNameLabel.addGestureRecognizer(nameTap)

        NSLayoutConstraint.activate([
            userImageView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),
            userImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            userImageView.widthAnchor.constraint(equalToConstant: 24),
            userImageView.heightAnchor.constraint(equalToConstant: 24),

            userNameLabel.leadingAnchor.constraint(
                equalTo: userImageView.trailingAnchor, constant: 8),
            userNameLabel.centerYAnchor.constraint(equalTo: userImageView.centerYAnchor),
            userNameLabel.trailingAnchor.constraint(
                equalTo: statusIcon.leadingAnchor, constant: -4),

            statusIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            statusIcon.centerYAnchor.constraint(equalTo: userImageView.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 14),
            statusIcon.heightAnchor.constraint(equalToConstant: 14),

            messageTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 52),
            messageTextView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),
            messageTextView.topAnchor.constraint(equalTo: userNameLabel.bottomAnchor, constant: 2),
            
            retryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 52),
            retryLabel.topAnchor.constraint(equalTo: messageTextView.bottomAnchor, constant: 2),
            retryLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
        
        // When retryLabel is hidden, messageTextView bottom should pin to contentView
        // Use a lower priority constraint that activates when retryLabel is hidden
        let messageBottomDefault = messageTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -7)
        messageBottomDefault.priority = .defaultLow
        messageBottomDefault.isActive = true
        
        // Add tap gesture for retry
        let retryTap = UITapGestureRecognizer(target: self, action: #selector(retryTapped))
        retryLabel.isUserInteractionEnabled = true
        retryLabel.addGestureRecognizer(retryTap)
    }
    
    @objc private func messageTextTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: messageTextView)
        
        print("📱 Message text tapped at: \(location)")
        print("📱 Mention ranges count: \(mentionRanges.count)")
        
        // Convert tap location to character index
        let layoutManager = messageTextView.layoutManager
        let textContainer = messageTextView.textContainer
        
        // Adjust for text container inset
        var adjustedLocation = location
        adjustedLocation.x -= messageTextView.textContainerInset.left
        adjustedLocation.y -= messageTextView.textContainerInset.top
        
        let characterIndex = layoutManager.characterIndex(
            for: adjustedLocation,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        
        print("📱 Character index: \(characterIndex)")
        
        // Check if tap is within any mention range
        for (range, pubkey) in mentionRanges {
            print("📱 Checking range: \(range) for pubkey: \(pubkey.prefix(8))...")
            if NSLocationInRange(characterIndex, range) {
                print("📱 ✅ Match found! Triggering callback for pubkey: \(pubkey.prefix(8))...")
                
                // Visual feedback
                UIView.animate(withDuration: 0.1, animations: {
                    self.messageTextView.alpha = 0.5
                }) { _ in
                    UIView.animate(withDuration: 0.1) {
                        self.messageTextView.alpha = 1.0
                    }
                }
                
                // Trigger the callback
                onMentionTap?(pubkey)
                return
            }
        }
        
        print("📱 ❌ No mention found at tap location")
    }

    func configure(with message: LiveChatMessageEvent, appState: AppState, precomputedEmojiMap: [String: URL]? = nil) {
        self.appState = appState
        self.currentPubkey = message.pubkey
        
        // Reset pending state
        contentView.alpha = 1.0
        statusIcon.isHidden = true
        retryLabel.isHidden = true
        contentView.backgroundColor = .clear
        
        // Get user metadata
        let metadata = appState.metadataEvents[message.pubkey]?.userMetadata
        let userName = metadata?.displayName ?? metadata?.name ?? "User"

        // OVERFLOW FIX: Truncate username
        userNameLabel.text = userName.smartTruncatedUsername()
        
        // Build NIP-30 emoji map: use precomputed if available, otherwise build from event + cache
        let emojiMap: [String: URL] = precomputedEmojiMap ?? {
            var map: [String: URL] = [:]
            for emoji in message.customEmojis { map[emoji.shortcode] = emoji.imageURL }
            for (sc, url) in appState.emojiPackCache where map[sc] == nil { map[sc] = url }
            return map
        }()
        
        // Parse and render message content with nostr mentions and NIP-30 custom emojis
        messageTextView.attributedText = buildAttributedMessage(message.content, appState: appState, emojiMap: emojiMap)

        // Load profile picture with shimmer
        if let pictureURL = metadata?.pictureURL {
            userImageView.startProfilePicShimmer(size: CGSize(width: 24, height: 24))
            loadImage(from: pictureURL)
        } else {
            userImageView.stopProfilePicShimmer()
            userImageView.image = nil
            userImageView.backgroundColor = .systemGray
        }
        
        // Fix #5: Removed fetchMentionedMetadata() - now handled by LiveChatController
        // Metadata for mentioned pubkeys is prefetched at the controller level
        // during processChatUpdate() to avoid redundant network calls on scroll
    }
    
    /// Configures the cell for a pending (optimistic) message display
    func configurePending(with pending: PendingChatMessage, appState: AppState) {
        self.appState = appState
        self.currentPubkey = pending.pubkey
        
        // Get user metadata (sender is the current user)
        let metadata = appState.metadataEvents[pending.pubkey]?.userMetadata
        let userName = metadata?.displayName ?? metadata?.name ?? "You"
        userNameLabel.text = userName.smartTruncatedUsername()
        
        // Set message content as plain text (no need to parse mentions for own message)
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.secondaryLabel
        ]
        messageTextView.attributedText = NSAttributedString(string: pending.content, attributes: normalAttributes)
        
        // Load profile picture
        if let pictureURL = metadata?.pictureURL {
            userImageView.startProfilePicShimmer(size: CGSize(width: 24, height: 24))
            loadImage(from: pictureURL)
        } else {
            userImageView.stopProfilePicShimmer()
            userImageView.image = nil
            userImageView.backgroundColor = .systemGray
        }
        
        // Apply visual state based on pending status
        switch pending.status {
        case .sending:
            contentView.alpha = 0.6
            statusIcon.image = UIImage(systemName: "clock")
            statusIcon.tintColor = .secondaryLabel
            statusIcon.isHidden = false
            retryLabel.isHidden = true
            contentView.backgroundColor = .clear
            
        case .confirmed:
            contentView.alpha = 0.85
            statusIcon.image = UIImage(systemName: "checkmark.circle")
            statusIcon.tintColor = .systemGreen
            statusIcon.isHidden = false
            retryLabel.isHidden = true
            contentView.backgroundColor = .clear
            
        case .failed:
            contentView.alpha = 1.0
            statusIcon.image = UIImage(systemName: "exclamationmark.circle.fill")
            statusIcon.tintColor = .systemRed
            statusIcon.isHidden = false
            retryLabel.isHidden = false
            contentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.08)
        }
    }
    
    @objc private func retryTapped() {
        onRetryTap?()
    }
    
    @objc private func profileTapped() {
        guard let pubkey = currentPubkey else { return }
        
        // Visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.userImageView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.userImageView.transform = .identity
            }
        }
        
        onProfileTap?(pubkey)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        userImageView.kf.cancelDownloadTask()
        userImageView.stopProfilePicShimmer()
        userImageView.image = nil
        userImageView.backgroundColor = .systemGray
        userImageView.transform = .identity
        userNameLabel.text = nil
        messageTextView.attributedText = nil
        currentPubkey = nil
        onProfileTap = nil
        onMentionTap = nil
        onRetryTap = nil
        messagePubkeys.removeAll()
        mentionRanges.removeAll()
        // Clean up animated emote views
        animatedEmoteViews.forEach { $0.sd_cancelCurrentImageLoad(); $0.removeFromSuperview() }
        animatedEmoteViews.removeAll()
        // Reset pending state
        contentView.alpha = 1.0
        statusIcon.isHidden = true
        retryLabel.isHidden = true
        contentView.backgroundColor = .clear
    }
    
    /// Builds attributed string for message content with nostr mentions and NIP-30 custom emojis
    private func buildAttributedMessage(_ content: String, appState: AppState, emojiMap: [String: URL] = [:]) -> NSAttributedString {
        let segments = NostrTextParser.parse(content)
        let attributedString = NSMutableAttributedString()
        
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.secondaryLabel
        ]
        
        messagePubkeys.removeAll()
        mentionRanges.removeAll()
        animatedEmoteViews.forEach { $0.sd_cancelCurrentImageLoad(); $0.removeFromSuperview() }
        animatedEmoteViews.removeAll()
        
        for segment in segments {
            switch segment {
            case .text(let string):
                attributedString.append(NSAttributedString(string: string, attributes: normalAttributes))
            
            case .customEmoji(let shortcode):
                if let url = emojiMap[shortcode] {
                    let emoteHeight: CGFloat = 22
                    let attachment = NSTextAttachment()
                    attachment.bounds = CGRect(x: 0, y: -4, width: emoteHeight, height: emoteHeight)
                    attributedString.append(NSAttributedString(attachment: attachment))
                    
                    // Cap animated overlays at 5 per cell for scroll performance
                    if animatedEmoteViews.count < 5 {
                        let animatedView = SDAnimatedImageView()
                        animatedView.contentMode = .scaleAspectFit
                        animatedView.autoPlayAnimatedImage = !emoteAnimationsPaused
                        animatedView.sd_setImage(with: url)
                        animatedView.frame = CGRect(x: 0, y: 0, width: emoteHeight, height: emoteHeight)
                        messageTextView.addSubview(animatedView)
                        animatedEmoteViews.append(animatedView)
                    } else {
                        // Static fallback for 6th+ emote
                        SDWebImageManager.shared.loadImage(with: url, options: [.retryFailed], progress: nil) { [weak self] image, _, _, _, _, _ in
                            guard let self, let image else { return }
                            attachment.image = image
                            attachment.bounds = CGRect(x: 0, y: -4, width: emoteHeight * (image.size.width / max(image.size.height, 1)), height: emoteHeight)
                            self.messageTextView.attributedText = self.messageTextView.attributedText
                        }
                    }
                } else {
                    attributedString.append(NSAttributedString(string: ":\(shortcode):", attributes: normalAttributes))
                }
                
            case .reference(_, let reference):
                switch reference {
                case .profile(let pubkeyHex, _):
                    let displayName = NostrTextParser.resolveDisplayName(
                        pubkeyHex: pubkeyHex,
                        metadataEvents: appState.metadataEvents
                    )
                    messagePubkeys.append(pubkeyHex)
                    
                    // Track the range for tap detection
                    let mentionText = "@\(displayName)"
                    let startIndex = attributedString.length
                    let range = NSRange(location: startIndex, length: mentionText.count)
                    mentionRanges.append((range: range, pubkey: pubkeyHex))
                    
                    // Create tappable link for profile mention - same font as regular text, just purple
                    let mentionAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 15),
                        .foregroundColor: UIColor.systemPurple,
                        .link: URL(string: "swae://profile/\(pubkeyHex)")!
                    ]
                    attributedString.append(NSAttributedString(string: mentionText, attributes: mentionAttributes))
                    
                case .event(let eventId, _, _, _):
                    let truncated = String(eventId.prefix(8)) + "..."
                    let eventAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: UIColor.systemBlue,
                        .link: URL(string: "swae://event/\(eventId)")!
                    ]
                    attributedString.append(NSAttributedString(string: "📝\(truncated)", attributes: eventAttributes))
                    
                case .address(_, let pubkey, let identifier, _):
                    let addressAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: UIColor.systemBlue,
                        .link: URL(string: "swae://address/\(pubkey)/\(identifier)")!
                    ]
                    attributedString.append(NSAttributedString(string: "📄\(identifier)", attributes: addressAttributes))
                }
            }
        }
        
        return attributedString
    }
    
    /// Fetches metadata for pubkeys mentioned in the message
    private func fetchMentionedMetadata(_ content: String, appState: AppState) {
        let segments = NostrTextParser.parse(content)
        let pubkeys = NostrTextParser.extractPubkeys(from: segments)
        let missingPubkeys = pubkeys.filter { appState.metadataEvents[$0] == nil }
        
        if !missingPubkeys.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(Array(missingPubkeys))
        }
    }

    private func loadImage(from url: URL) {
        userImageView.kf.setImage(
            with: url,
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 48, height: 48))),
                .scaleFactor(UIScreen.main.scale),
                .cacheOriginalImage,
                .transition(.none),
                .backgroundDecode
            ],
            completionHandler: { [weak self] result in
                self?.userImageView.stopProfilePicShimmer()
                
                if case .failure = result {
                    self?.userImageView.backgroundColor = .systemGray
                }
            }
        )
    }

    /// Positions animated emote SDAnimatedImageViews over their placeholder NSTextAttachments.
    private func layoutAnimatedEmotes() {
        guard !animatedEmoteViews.isEmpty,
              let attributedText = messageTextView.attributedText else { return }
        
        let emoteHeight: CGFloat = 22
        let layoutManager = messageTextView.layoutManager
        let textContainer = messageTextView.textContainer
        let inset = messageTextView.textContainerInset
        
        var idx = 0
        attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length)) { value, range, _ in
            guard value is NSTextAttachment, idx < self.animatedEmoteViews.count else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            self.animatedEmoteViews[idx].frame = CGRect(
                x: rect.origin.x + inset.left,
                y: rect.origin.y + inset.top,
                width: emoteHeight,
                height: emoteHeight
            )
            idx += 1
        }
    }
}

// MARK: - UITextViewDelegate for LiveChatMessageCell

extension LiveChatMessageCell: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        print("📱 UITextView link tapped: \(URL)")
        
        // Handle our custom swae:// URLs
        guard URL.scheme == "swae" else {
            return true // Let system handle other URLs
        }
        
        let pathComponents = URL.pathComponents.filter { $0 != "/" }
        guard let type = pathComponents.first else {
            return false
        }
        
        switch type {
        case "profile":
            if let pubkeyHex = pathComponents.dropFirst().first {
                print("📱 Profile link detected: \(pubkeyHex.prefix(8))...")
                
                // Visual feedback
                UIView.animate(withDuration: 0.1, animations: {
                    textView.alpha = 0.5
                }) { _ in
                    UIView.animate(withDuration: 0.1) {
                        textView.alpha = 1.0
                    }
                }
                
                // Call the mention tap callback (which should navigate to profile)
                onMentionTap?(pubkeyHex)
            }
        case "event":
            // Handle event taps if needed in the future
            break
        case "address":
            // Handle address taps if needed in the future
            break
        default:
            break
        }
        
        return false // We handled it
    }
}

class LiveChatZapCell: UITableViewCell {
    let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.systemYellow.cgColor
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let userImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 12
        iv.backgroundColor = .systemGray
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isUserInteractionEnabled = true
        return iv
    }()

    let userNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .systemYellow
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        return label
    }()

    let zapInfoLabel: UILabel = {
        let label = UILabel()
        label.text = "zapped"
        label.font = .systemFont(ofSize: 16)
        label.textColor = .systemYellow
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let zapAmountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textColor = .black
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let zapBadge: UIView = {
        let view = UIView()
        view.backgroundColor = .systemYellow
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let zapIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "bolt.fill"))
        iv.tintColor = .black
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var currentPubkey: String?
    
    /// Callback when user profile is tapped (profile pic or username)
    var onProfileTap: ((String) -> Void)?
    
    /// Callback when user taps to retry a failed pending zap
    var onRetryTap: (() -> Void)?
    
    // Pending state UI elements
    private let statusIcon: UIImageView = {
        let iv = UIImageView()
        iv.tintColor = .secondaryLabel
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        return iv
    }()
    
    private let retryLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap to retry"
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .systemBackground
        transform = CGAffineTransform(rotationAngle: .pi)

        contentView.addSubview(containerView)
        containerView.addSubview(userImageView)
        containerView.addSubview(userNameLabel)
        containerView.addSubview(zapInfoLabel)
        containerView.addSubview(zapBadge)
        zapBadge.addSubview(zapIcon)
        zapBadge.addSubview(zapAmountLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(statusIcon)
        containerView.addSubview(retryLabel)
        
        // OVERFLOW FIX: Set compression resistance priorities
        // Username should compress first, zap badge should never compress
        userNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        userNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        zapInfoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        zapBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        zapAmountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        // OVERFLOW FIX: Enable truncation on username
        userNameLabel.lineBreakMode = .byTruncatingTail
        userNameLabel.numberOfLines = 1
        
        // Limit message lines to prevent spam
        messageLabel.numberOfLines = ChatDisplayConstants.maxMessageLines
        
        // Add tap gestures for profile navigation
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        userImageView.addGestureRecognizer(imageTap)
        
        let nameTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        userNameLabel.addGestureRecognizer(nameTap)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            containerView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -8),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),

            userImageView.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 12),
            userImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            userImageView.widthAnchor.constraint(equalToConstant: 24),
            userImageView.heightAnchor.constraint(equalToConstant: 24),

            // OVERFLOW FIX: Username with max width constraint
            userNameLabel.leadingAnchor.constraint(
                equalTo: userImageView.trailingAnchor, constant: 8),
            userNameLabel.centerYAnchor.constraint(equalTo: userImageView.centerYAnchor),
            userNameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: ChatDisplayConstants.maxUsernameDisplayWidth),

            zapInfoLabel.leadingAnchor.constraint(
                equalTo: userNameLabel.trailingAnchor, constant: 4),
            zapInfoLabel.centerYAnchor.constraint(equalTo: userImageView.centerYAnchor),

            // OVERFLOW FIX: Zap badge anchored to trailing edge
            zapBadge.leadingAnchor.constraint(greaterThanOrEqualTo: zapInfoLabel.trailingAnchor, constant: 4),
            zapBadge.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            zapBadge.centerYAnchor.constraint(equalTo: userImageView.centerYAnchor),
            zapBadge.heightAnchor.constraint(equalToConstant: 24),

            zapIcon.leadingAnchor.constraint(equalTo: zapBadge.leadingAnchor, constant: 8),
            zapIcon.centerYAnchor.constraint(equalTo: zapBadge.centerYAnchor),
            zapIcon.widthAnchor.constraint(equalToConstant: 12),
            zapIcon.heightAnchor.constraint(equalToConstant: 12),

            zapAmountLabel.leadingAnchor.constraint(equalTo: zapIcon.trailingAnchor, constant: 4),
            zapAmountLabel.trailingAnchor.constraint(
                equalTo: zapBadge.trailingAnchor, constant: -8),
            zapAmountLabel.centerYAnchor.constraint(equalTo: zapBadge.centerYAnchor),

            messageLabel.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 44),
            messageLabel.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -12),
            messageLabel.topAnchor.constraint(equalTo: userImageView.bottomAnchor, constant: 4),
            messageLabel.bottomAnchor.constraint(equalTo: retryLabel.topAnchor, constant: 0),
            
            // Status icon overlaid on zap badge area
            statusIcon.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            statusIcon.bottomAnchor.constraint(equalTo: userImageView.bottomAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 14),
            statusIcon.heightAnchor.constraint(equalToConstant: 14),
            
            // Retry label below message
            retryLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 44),
            retryLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
        ])
        
        // Default bottom constraint for messageLabel when retryLabel is hidden
        let messageBottomDefault = messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        messageBottomDefault.priority = .defaultLow
        messageBottomDefault.isActive = true
        
        // Add tap gesture for retry
        let retryTap = UITapGestureRecognizer(target: self, action: #selector(retryTapped))
        retryLabel.isUserInteractionEnabled = true
        retryLabel.addGestureRecognizer(retryTap)
    }

    func configure(with zapReceipt: LightningZapsReceiptEvent, appState: AppState) {
        // Get sender info
        let senderPubkey = zapReceipt.zapSenderPubkey ?? ""
        self.currentPubkey = senderPubkey
        
        // Reset pending state
        containerView.alpha = 1.0
        statusIcon.isHidden = true
        retryLabel.isHidden = true
        containerView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
        containerView.layer.borderColor = UIColor.systemYellow.cgColor
        
        let metadata = appState.metadataEvents[senderPubkey]?.userMetadata
        let userName = metadata?.displayName ?? metadata?.name ?? "Anonymous"

        // OVERFLOW FIX: Truncate username
        userNameLabel.text = userName.smartTruncatedUsername()

        // Get zap amount and message
        let amount = (zapReceipt.description?.amount ?? 0) / 1000
        let content = zapReceipt.description?.content ?? ""

        // OVERFLOW FIX: Format large zap amounts with K/M suffixes
        zapAmountLabel.text = formatZapAmount(Int64(amount))
        
        // Parse and render zap message content with nostr mentions
        if !content.isEmpty {
            messageLabel.attributedText = buildAttributedZapMessage(content, appState: appState)
            messageLabel.isHidden = false
            
            // Fix #5: Removed fetchMentionedMetadata() - now handled by LiveChatController
            // Metadata for mentioned pubkeys is prefetched at the controller level
        } else {
            messageLabel.isHidden = true
        }

        // Load profile picture with shimmer
        if !senderPubkey.isEmpty,
            let pictureURL = metadata?.pictureURL
        {
            userImageView.startProfilePicShimmer(size: CGSize(width: 24, height: 24))
            loadImage(from: pictureURL)
        } else {
            userImageView.stopProfilePicShimmer()
            userImageView.image = nil
            userImageView.backgroundColor = .systemGray
        }
    }
    
    /// Configures the cell for a pending (optimistic) zap display
    func configurePending(with pending: PendingChatZap, appState: AppState) {
        self.currentPubkey = pending.senderPubkey
        
        // Get sender metadata
        let metadata = appState.metadataEvents[pending.senderPubkey]?.userMetadata
        let userName = metadata?.displayName ?? metadata?.name ?? "You"
        userNameLabel.text = userName.smartTruncatedUsername()
        
        // Issue 4 fix: Display amount in sats (pending.amount is in millisats)
        let sats = pending.amount / 1000
        zapAmountLabel.text = formatZapAmount(sats)
        
        // Show zap message if present
        if let content = pending.content, !content.isEmpty {
            messageLabel.text = content
            messageLabel.isHidden = false
        } else {
            messageLabel.isHidden = true
        }
        
        // Load profile picture
        if let pictureURL = metadata?.pictureURL {
            userImageView.startProfilePicShimmer(size: CGSize(width: 24, height: 24))
            loadImage(from: pictureURL)
        } else {
            userImageView.stopProfilePicShimmer()
            userImageView.image = nil
            userImageView.backgroundColor = .systemGray
        }
        
        // Apply visual state based on pending status
        switch pending.status {
        case .sending:
            containerView.alpha = 0.6
            statusIcon.image = UIImage(systemName: "clock")
            statusIcon.tintColor = .secondaryLabel
            statusIcon.isHidden = false
            retryLabel.isHidden = true
            containerView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
            containerView.layer.borderColor = UIColor.systemYellow.cgColor
            
        case .confirmed:
            containerView.alpha = 0.85
            statusIcon.image = UIImage(systemName: "checkmark.circle")
            statusIcon.tintColor = .systemGreen
            statusIcon.isHidden = false
            retryLabel.isHidden = true
            containerView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
            containerView.layer.borderColor = UIColor.systemGreen.cgColor
            
        case .failed:
            containerView.alpha = 1.0
            statusIcon.image = UIImage(systemName: "exclamationmark.circle.fill")
            statusIcon.tintColor = .systemRed
            statusIcon.isHidden = false
            retryLabel.isHidden = false
            containerView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
            containerView.layer.borderColor = UIColor.systemRed.cgColor
        }
    }
    
    @objc private func retryTapped() {
        onRetryTap?()
    }
    
    /// Formats large zap amounts with K/M suffixes
    private func formatZapAmount(_ sats: Int64) -> String {
        switch sats {
        case 0..<1_000:
            return "\(sats)"
        case 1_000..<1_000_000:
            let k = Double(sats) / 1_000.0
            return k.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(k))K"
                : String(format: "%.1fK", k)
        default:
            let m = Double(sats) / 1_000_000.0
            return m.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(m))M"
                : String(format: "%.1fM", m)
        }
    }
    
    @objc private func profileTapped() {
        guard let pubkey = currentPubkey, !pubkey.isEmpty else { return }
        
        // Visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.userImageView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.userImageView.transform = .identity
            }
        }
        
        onProfileTap?(pubkey)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        userImageView.kf.cancelDownloadTask()
        userImageView.stopProfilePicShimmer()
        userImageView.image = nil
        userImageView.backgroundColor = .systemGray
        userImageView.transform = .identity
        userNameLabel.text = nil
        zapAmountLabel.text = nil
        messageLabel.attributedText = nil
        messageLabel.text = nil
        messageLabel.isHidden = true
        currentPubkey = nil
        onProfileTap = nil
        onRetryTap = nil
        // Reset pending state
        containerView.alpha = 1.0
        statusIcon.isHidden = true
        retryLabel.isHidden = true
        containerView.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
        containerView.layer.borderColor = UIColor.systemYellow.cgColor
    }
    
    /// Builds attributed string for zap message content with nostr mentions highlighted
    private func buildAttributedZapMessage(_ content: String, appState: AppState) -> NSAttributedString {
        let segments = NostrTextParser.parse(content)
        let attributedString = NSMutableAttributedString()
        
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.label
        ]
        
        let mentionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor.systemPurple
        ]
        
        for segment in segments {
            switch segment {
            case .text(let string):
                attributedString.append(NSAttributedString(string: string, attributes: normalAttributes))
                
            case .reference(_, let reference):
                switch reference {
                case .profile(let pubkeyHex, _):
                    let displayName = NostrTextParser.resolveDisplayName(
                        pubkeyHex: pubkeyHex,
                        metadataEvents: appState.metadataEvents
                    )
                    attributedString.append(NSAttributedString(string: "@\(displayName)", attributes: mentionAttributes))
                    
                case .event(let eventId, _, _, _):
                    let truncated = String(eventId.prefix(8)) + "..."
                    var attrs = mentionAttributes
                    attrs[.foregroundColor] = UIColor.systemBlue
                    attributedString.append(NSAttributedString(string: "📝\(truncated)", attributes: attrs))
                    
                case .address(_, _, let identifier, _):
                    var attrs = mentionAttributes
                    attrs[.foregroundColor] = UIColor.systemBlue
                    attributedString.append(NSAttributedString(string: "📄\(identifier)", attributes: attrs))
                }
            
            case .customEmoji(let shortcode):
                attributedString.append(NSAttributedString(string: ":\(shortcode):", attributes: normalAttributes))
            }
        }
        
        return attributedString
    }
    
    /// Fetches metadata for pubkeys mentioned in the message
    private func fetchMentionedMetadata(_ content: String, appState: AppState) {
        let segments = NostrTextParser.parse(content)
        let pubkeys = NostrTextParser.extractPubkeys(from: segments)
        let missingPubkeys = pubkeys.filter { appState.metadataEvents[$0] == nil }
        
        if !missingPubkeys.isEmpty {
            appState.pullMissingEventsFromPubkeysAndFollows(Array(missingPubkeys))
        }
    }

    private func loadImage(from url: URL) {
        userImageView.kf.setImage(
            with: url,
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 48, height: 48))),
                .scaleFactor(UIScreen.main.scale),
                .cacheOriginalImage,
                .transition(.none),
                .backgroundDecode
            ],
            completionHandler: { [weak self] result in
                self?.userImageView.stopProfilePicShimmer()
                
                if case .failure = result {
                    self?.userImageView.backgroundColor = .systemGray
                }
            }
        )
    }
}


// MARK: - Raid Cell

/// A special chat cell for displaying raid events with distinctive styling
/// Raids are Kind 1312 events with two "a" tags (root=source, mention=target)
class LiveChatRaidCell: UITableViewCell {
    
    // Container with gradient background
    private let containerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Gradient layer for the container
    private let gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.colors = [
            UIColor.systemBlue.withAlphaComponent(0.3).cgColor,
            UIColor.systemPurple.withAlphaComponent(0.3).cgColor
        ]
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        return layer
    }()
    
    // Wave emoji
    private let waveLabel: UILabel = {
        let label = UILabel()
        label.text = "🌊"
        label.font = .systemFont(ofSize: 24)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Streamer profile picture
    private let userImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 14
        iv.layer.borderWidth = 1.5
        iv.layer.borderColor = UIColor.systemBlue.cgColor
        iv.backgroundColor = .systemGray5
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isUserInteractionEnabled = true
        return iv
    }()
    
    // Streamer name
    private let userNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = true
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    
    // Raid direction text
    private let raidingLabel: UILabel = {
        let label = UILabel()
        label.text = "raided in!"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // Join/View button
    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("View Stream →", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var displayPubkey: String?
    private var targetStreamCoordinate: String?
    
    /// Callback when user profile is tapped
    var onProfileTap: ((String) -> Void)?
    
    /// Callback when action button is tapped - passes target stream coordinate
    var onJoinRaid: ((String) -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = containerView.bounds
    }
    
    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        transform = CGAffineTransform(rotationAngle: .pi)
        
        contentView.addSubview(containerView)
        containerView.layer.insertSublayer(gradientLayer, at: 0)
        
        containerView.addSubview(waveLabel)
        containerView.addSubview(userImageView)
        containerView.addSubview(userNameLabel)
        containerView.addSubview(raidingLabel)
        containerView.addSubview(actionButton)
        
        // Add tap gestures
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        userImageView.addGestureRecognizer(imageTap)
        
        let nameTap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        userNameLabel.addGestureRecognizer(nameTap)
        
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            // Container fills cell with padding
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            // Wave emoji on the left
            waveLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            waveLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            // Profile pic next to wave
            userImageView.leadingAnchor.constraint(equalTo: waveLabel.trailingAnchor, constant: 8),
            userImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            userImageView.widthAnchor.constraint(equalToConstant: 28),
            userImageView.heightAnchor.constraint(equalToConstant: 28),
            
            // Username next to profile pic
            userNameLabel.leadingAnchor.constraint(equalTo: userImageView.trailingAnchor, constant: 8),
            userNameLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            // "raided in!" text next to username
            raidingLabel.leadingAnchor.constraint(equalTo: userNameLabel.trailingAnchor, constant: 4),
            raidingLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            // Action button on the right
            actionButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            actionButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            // Constrain username to not overlap with button
            raidingLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -8),
            
            // Minimum height for container
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        
        // Set content hugging/compression priorities
        userNameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        userNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        raidingLabel.setContentHuggingPriority(.required, for: .horizontal)
        raidingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    
    func configure(with raid: LiveStreamRaidEvent, appState: AppState, currentStreamCoordinate: String? = nil) {
        // Determine raid direction based on current stream
        // If source matches current stream -> outgoing raid ("Raiding {target}")
        // If target matches current stream -> incoming raid ("Raid from {source}")
        let isOutgoing = currentStreamCoordinate != nil && raid.isOutgoingRaid(from: currentStreamCoordinate!)
        
        // Get the "other" stream coordinate (the one we're raiding to/from)
        let otherStreamCoordinate = isOutgoing ? raid.targetStreamCoordinate : raid.sourceStreamCoordinate
        let otherStreamRef = isOutgoing ? raid.targetStreamReference : raid.sourceStreamReference
        
        // Look up the LiveActivitiesEvent to get the actual host (not the event author which may be zap.stream)
        // Per NIP-53, the actual streamer is in the `p` tag with role "host"
        var pubkeyToDisplay: String
        if let coordinate = otherStreamCoordinate,
           let liveEvent = appState.liveActivitiesEvents[coordinate]?.first {
            // Get host participant pubkey, fallback to event author
            pubkeyToDisplay = liveEvent.hostPubkeyHex
        } else {
            // Fallback to the pubkey from the a tag if we can't find the LiveActivitiesEvent
            pubkeyToDisplay = otherStreamRef?.pubkey ?? raid.pubkey
        }
        
        self.displayPubkey = pubkeyToDisplay
        self.targetStreamCoordinate = otherStreamCoordinate
        
        // Get metadata for the relevant streamer - same way we do for live activities
        let metadata = appState.metadataEvents[pubkeyToDisplay]?.userMetadata
        let userName = metadata?.displayName?.trimmedOrNilIfEmpty ?? metadata?.name?.trimmedOrNilIfEmpty ?? String(pubkeyToDisplay.prefix(8)) + "..."
        userNameLabel.text = userName
        
        // Update raid direction text and button
        if isOutgoing {
            raidingLabel.text = "raiding!"
            actionButton.setTitle("Join →", for: .normal)
        } else {
            raidingLabel.text = "raided in!"
            actionButton.setTitle("View →", for: .normal)
        }
        
        // Load profile picture
        if let pictureURL = metadata?.pictureURL {
            loadImage(from: pictureURL)
        } else {
            userImageView.image = nil
            userImageView.backgroundColor = .systemGray5
        }
    }
    
    @objc private func profileTapped() {
        guard let pubkey = displayPubkey else { return }
        
        UIView.animate(withDuration: 0.1, animations: {
            self.userImageView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.userImageView.transform = .identity
            }
        }
        
        onProfileTap?(pubkey)
    }
    
    @objc private func actionButtonTapped() {
        guard let targetCoordinate = targetStreamCoordinate else { return }
        
        // Button press animation
        UIView.animate(withDuration: 0.1, animations: {
            self.actionButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.actionButton.transform = .identity
            }
        }
        
        onJoinRaid?(targetCoordinate)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        userImageView.kf.cancelDownloadTask()
        userImageView.image = nil
        userImageView.backgroundColor = .systemGray5
        userImageView.transform = .identity
        userNameLabel.text = nil
        raidingLabel.text = "raided in!"
        displayPubkey = nil
        targetStreamCoordinate = nil
        onProfileTap = nil
        onJoinRaid = nil
    }
    
    private func loadImage(from url: URL) {
        userImageView.kf.setImage(
            with: url,
            options: [
                .processor(DownsamplingImageProcessor(size: CGSize(width: 56, height: 56))),
                .scaleFactor(UIScreen.main.scale),
                .cacheOriginalImage,
                .transition(.none),
                .backgroundDecode
            ],
            completionHandler: { [weak self] result in
                if case .failure = result {
                    self?.userImageView.backgroundColor = .systemGray5
                }
            }
        )
    }
}
