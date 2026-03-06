//
//  ChatMessageCell.swift
//  swae
//
//  UICollectionView cell for rendering a single chat message.
//  Replaces the SwiftUI LineView / HighlightMessageView / PostView.
//

import Combine
import SDWebImage
import UIKit

class ChatMessageCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatMessageCell"

    // MARK: - Views

    private let messageTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 2, left: 3, bottom: 2, right: 3)
        tv.textContainer.lineFragmentPadding = 0
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let highlightBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let highlightTitleTextView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 1, left: 3, bottom: 1, right: 3)
        tv.textContainer.lineFragmentPadding = 0
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isHidden = true
        return tv
    }()

    private let cellBackground: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 5
        v.clipsToBounds = true
        return v
    }()

    // MARK: - State

    private var stateCancellable: AnyCancellable?
    private var currentPost: ChatPost?
    private var currentSettings: SettingsChat?
    private var animatedImageViews: [SDAnimatedImageView] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(cellBackground)
        cellBackground.addSubview(highlightBar)
        cellBackground.addSubview(highlightTitleTextView)
        cellBackground.addSubview(messageTextView)

        let highlightBarWidth = highlightBar.widthAnchor.constraint(equalToConstant: 3)
        let highlightTitleTop = highlightTitleTextView.topAnchor.constraint(equalTo: cellBackground.topAnchor)
        let messageTop = messageTextView.topAnchor.constraint(equalTo: cellBackground.topAnchor)

        NSLayoutConstraint.activate([
            cellBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
            cellBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cellBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cellBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            highlightBar.topAnchor.constraint(equalTo: cellBackground.topAnchor),
            highlightBar.leadingAnchor.constraint(equalTo: cellBackground.leadingAnchor),
            highlightBar.bottomAnchor.constraint(equalTo: cellBackground.bottomAnchor),
            highlightBarWidth,

            highlightTitleTop,
            highlightTitleTextView.leadingAnchor.constraint(equalTo: highlightBar.trailingAnchor),
            highlightTitleTextView.trailingAnchor.constraint(equalTo: cellBackground.trailingAnchor),

            messageTop,
            messageTextView.leadingAnchor.constraint(equalTo: cellBackground.leadingAnchor, constant: 3),
            messageTextView.trailingAnchor.constraint(equalTo: cellBackground.trailingAnchor),
            messageTextView.bottomAnchor.constraint(equalTo: cellBackground.bottomAnchor),
        ])

        // Store references for dynamic constraint changes
        self.highlightTitleTopConstraint = highlightTitleTop
        self.messageTopConstraint = messageTop
    }

    private var highlightTitleTopConstraint: NSLayoutConstraint!
    private var messageTopConstraint: NSLayoutConstraint!

    // MARK: - Configuration

    func configure(with post: ChatPost, settings: SettingsChat, moreThanOnePlatform: Bool) {
        currentPost = post
        currentSettings = settings

        // Clean up animated image views from previous configuration
        animatedImageViews.forEach { $0.removeFromSuperview() }
        animatedImageViews.removeAll()

        let deleted = post.state.deleted
        let fontSize = CGFloat(settings.fontSize)
        let font = UIFont.systemFont(ofSize: fontSize)
        let boldFont = UIFont.boldSystemFont(ofSize: fontSize)

        // Build message attributed string
        let message = NSMutableAttributedString()

        // Shadow
        let shadow: NSShadow? = settings.shadowColorEnabled ? {
            let s = NSShadow()
            s.shadowColor = UIColor(settings.shadowColor.color())
            s.shadowBlurRadius = 1.5
            s.shadowOffset = .zero
            return s
        }() : nil

        // Timestamp
        if settings.timestampColorEnabled {
            let attrs = baseAttrs(font: font, color: UIColor(settings.timestampColor.color()), shadow: shadow, deleted: deleted)
            message.append(NSAttributedString(string: "\(post.timestamp) ", attributes: attrs))
        }

        // Platform icon
        if settings.platform, moreThanOnePlatform, let imageName = post.platform?.imageName() {
            if let img = UIImage(named: imageName) {
                appendImageAttachment(to: message, image: img, height: fontSize * 1.4, opacity: deleted ? 0.25 : 1.0)
            }
        }

        // Badges
        if settings.badges {
            for badgeURL in post.userBadges {
                let placeholder = appendPlaceholderAttachment(to: message, height: fontSize * 1.4)
                loadImage(url: badgeURL, into: placeholder, in: message, height: fontSize * 1.4)
            }
        }

        // Username
        let usernameColor = deleted ? UIColor.gray : UIColor(post.userColor.color())
        let usernameFont = settings.boldUsername ? boldFont : font
        var usernameAttrs = baseAttrs(font: usernameFont, color: usernameColor, shadow: shadow, deleted: deleted)
        if deleted { usernameAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        message.append(NSAttributedString(string: post.user ?? "", attributes: usernameAttrs))

        // Separator
        let sepAttrs = baseAttrs(font: font, color: .white, shadow: shadow, deleted: deleted)
        message.append(NSAttributedString(string: post.isRedemption() ? " " : ": ", attributes: sepAttrs))

        // Message segments
        let msgColor: UIColor = {
            if deleted { return .gray }
            if post.isAction && settings.meInUsernameColor {
                return UIColor(post.userColor.color())
            }
            return UIColor(settings.messageColor.color())
        }()
        let msgFont: UIFont = {
            var f = settings.boldMessage ? boldFont : font
            if post.isAction, let italic = f.withTraits(.traitItalic) { f = italic }
            return f
        }()

        for segment in post.segments {
            if let text = segment.text {
                var attrs = baseAttrs(font: msgFont, color: msgColor, shadow: shadow, deleted: deleted)
                if deleted { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                message.append(NSAttributedString(string: text, attributes: attrs))
            }
            if let url = segment.url {
                let emoteHeight = fontSize * 1.7
                if settings.animatedEmotes {
                    // Placeholder for animated emote — SDAnimatedImageView will overlay
                    appendPlaceholderAttachment(to: message, height: emoteHeight)
                    loadAnimatedEmote(url: url, height: emoteHeight, deleted: deleted)
                } else {
                    let placeholder = appendPlaceholderAttachment(to: message, height: emoteHeight)
                    loadImage(url: url, into: placeholder, in: message, height: emoteHeight)
                }
                message.append(NSAttributedString(string: " ", attributes: baseAttrs(font: font, color: .white, shadow: shadow, deleted: deleted)))
            }
        }

        messageTextView.attributedText = message

        // Background
        if settings.backgroundColorEnabled {
            cellBackground.backgroundColor = UIColor(settings.backgroundColor.color()).withAlphaComponent(0.6)
        } else {
            cellBackground.backgroundColor = .clear
        }

        // Highlight
        if let highlight = post.highlight {
            highlightBar.isHidden = false
            highlightBar.backgroundColor = UIColor(highlight.barColor)
            highlightTitleTextView.isHidden = false

            let titleStr = buildHighlightTitle(highlight: highlight, settings: settings, deleted: deleted, shadow: shadow)
            highlightTitleTextView.attributedText = titleStr

            // Adjust constraints: title above message, both after bar
            messageTopConstraint.isActive = false
            messageTopConstraint = messageTextView.topAnchor.constraint(equalTo: highlightTitleTextView.bottomAnchor)
            messageTopConstraint.isActive = true
            messageTextView.leadingAnchor.constraint(equalTo: highlightBar.trailingAnchor).isActive = true
        } else {
            highlightBar.isHidden = true
            highlightTitleTextView.isHidden = true
            messageTopConstraint.isActive = false
            messageTopConstraint = messageTextView.topAnchor.constraint(equalTo: cellBackground.topAnchor)
            messageTopConstraint.isActive = true
        }

        // Observe deletion state
        stateCancellable?.cancel()
        stateCancellable = post.state.$deleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deleted in
                self?.updateDeletedAppearance(deleted: deleted)
            }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stateCancellable?.cancel()
        stateCancellable = nil
        animatedImageViews.forEach { $0.removeFromSuperview() }
        animatedImageViews.removeAll()
        highlightBar.isHidden = true
        highlightTitleTextView.isHidden = true
        messageTextView.attributedText = nil
        cellBackground.backgroundColor = .clear
        currentPost = nil
    }

    // MARK: - Helpers

    private func baseAttrs(font: UIFont, color: UIColor, shadow: NSShadow?, deleted: Bool) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        if let shadow { attrs[.shadow] = shadow }
        return attrs
    }

    @discardableResult
    private func appendImageAttachment(to str: NSMutableAttributedString, image: UIImage, height: CGFloat, opacity: CGFloat = 1.0) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        let ratio = image.size.width / image.size.height
        attachment.image = opacity < 1.0 ? image.withAlpha(opacity) : image
        attachment.bounds = CGRect(x: 0, y: -4, width: height * ratio, height: height)
        str.append(NSAttributedString(attachment: attachment))
        str.append(NSAttributedString(string: " "))
        return attachment
    }

    @discardableResult
    private func appendPlaceholderAttachment(to str: NSMutableAttributedString, height: CGFloat) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.bounds = CGRect(x: 0, y: -4, width: height, height: height)
        str.append(NSAttributedString(attachment: attachment))
        return attachment
    }

    private func loadImage(url: URL, into attachment: NSTextAttachment, in str: NSMutableAttributedString, height: CGFloat) {
        SDWebImageManager.shared.loadImage(with: url, options: [.retryFailed], progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self, let image else { return }
            let ratio = image.size.width / image.size.height
            let deleted = self.currentPost?.state.deleted ?? false
            attachment.image = deleted ? image.withAlpha(0.25) : image
            attachment.bounds = CGRect(x: 0, y: -4, width: height * ratio, height: height)
            // Force re-layout
            self.messageTextView.attributedText = self.messageTextView.attributedText
        }
    }

    private func loadAnimatedEmote(url: URL, height: CGFloat, deleted: Bool) {
        let imageView = SDAnimatedImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = deleted ? 0.25 : 1.0
        imageView.sd_setImage(with: url)
        imageView.frame = CGRect(x: 0, y: 0, width: height, height: height)
        // Position will be approximate — placed at the end of current text
        messageTextView.addSubview(imageView)
        animatedImageViews.append(imageView)
    }

    private func updateDeletedAppearance(deleted: Bool) {
        guard let post = currentPost, let settings = currentSettings else { return }
        // Re-configure with updated deleted state
        configure(with: post, settings: settings, moreThanOnePlatform: false)
    }

    private func buildHighlightTitle(highlight: ChatHighlight, settings: SettingsChat, deleted: Bool, shadow: NSShadow?) -> NSAttributedString {
        let fontSize = CGFloat(settings.fontSize)
        let font = UIFont.systemFont(ofSize: fontSize)
        let color = UIColor(highlight.messageColor(defaultColor: settings.messageColor.color()))
        let str = NSMutableAttributedString()

        // Icon
        if let iconImage = UIImage(systemName: highlight.image) {
            let attachment = NSTextAttachment()
            attachment.image = iconImage.withTintColor(.white, renderingMode: .alwaysOriginal)
            attachment.bounds = CGRect(x: 0, y: -2, width: fontSize, height: fontSize)
            str.append(NSAttributedString(attachment: attachment))
            str.append(NSAttributedString(string: " ", attributes: baseAttrs(font: font, color: color, shadow: shadow, deleted: deleted)))
        }

        // Title segments
        for segment in highlight.titleSegments {
            if let text = segment.text {
                str.append(NSAttributedString(string: text, attributes: baseAttrs(font: font, color: color, shadow: shadow, deleted: deleted)))
            }
            if let url = segment.url {
                let placeholder = appendPlaceholderAttachment(to: str, height: fontSize * 1.7)
                loadImage(url: url, into: placeholder, in: str, height: fontSize * 1.7)
            }
        }

        return str
    }
}

// MARK: - ChatRedLineCell

class ChatRedLineCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatRedLineCell"

    private let lineView: UIView = {
        let v = UIView()
        v.backgroundColor = .red
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(lineView)
        NSLayoutConstraint.activate([
            lineView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            lineView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            lineView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            lineView.heightAnchor.constraint(equalToConstant: 1.5),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - UIFont Extension

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return nil }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

// MARK: - UIImage Extension

private extension UIImage {
    func withAlpha(_ alpha: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(at: .zero, blendMode: .normal, alpha: alpha)
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return result
    }
}
