//
//  TelegramChatInputBar.swift
//  swae
//
//  Telegram-style liquid glass chat input bar with morphing animations
//  Implements the iOS 26 liquid glass aesthetic with smooth spring animations
//

import SDWebImage
import UIKit

// MARK: - Animation Constants

/// Carefully tuned animation parameters for Telegram-like feel
struct TelegramInputAnimations {
    // Spring for button morphing (mic ↔ send)
    static let morphDamping: CGFloat = 0.68
    static let morphResponse: TimeInterval = 0.38
    
    // Spring for icon transitions (slightly bouncier)
    static let iconDamping: CGFloat = 0.62
    static let iconResponse: TimeInterval = 0.32
    
    // Scale pulse when transitioning
    static let pulseScale: CGFloat = 1.12
    static let pulseDuration: TimeInterval = 0.12
    
    // Icon crossfade
    static let iconFadeDuration: TimeInterval = 0.15
    
    // Path morphing duration
    static let pathMorphDuration: TimeInterval = 0.35
    
    // Haptic timing
    static let hapticDelay: TimeInterval = 0.05
}

// MARK: - Morphing Icon View

/// Custom view that morphs between microphone and send arrow using SF Symbols
/// with smooth crossfade and scale animations
class MorphingIconView: UIView {
    
    enum IconState {
        case microphone
        case sendArrow
    }
    
    private(set) var currentState: IconState = .microphone
    
    // Icon image views for crossfade
    private let microphoneIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .label  // Dynamic: black in light mode, white in dark mode
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        iv.image = UIImage(systemName: "ellipsis", withConfiguration: config)
        iv.transform = CGAffineTransform(rotationAngle: .pi / 2)  // Rotate to vertical
        return iv
    }()
    
    private let sendArrowIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .white  // Always white on blue background
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        iv.image = UIImage(systemName: "paperplane.fill", withConfiguration: config)
        iv.alpha = 0
        iv.transform = CGAffineTransform(scaleX: 0.5, y: 0.5).rotated(by: -.pi / 4)
        return iv
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        addSubview(microphoneIcon)
        addSubview(sendArrowIcon)
        
        NSLayoutConstraint.activate([
            microphoneIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            microphoneIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            microphoneIcon.widthAnchor.constraint(equalToConstant: 24),
            microphoneIcon.heightAnchor.constraint(equalToConstant: 24),
            
            sendArrowIcon.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 1),
            sendArrowIcon.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            sendArrowIcon.widthAnchor.constraint(equalToConstant: 24),
            sendArrowIcon.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
    
    func morphTo(_ state: IconState, animated: Bool = true) {
        guard state != currentState else { return }
        
        let isSend = state == .sendArrow
        
        if animated {
            // Spring animation for the morph
            let springParams = UISpringTimingParameters(
                dampingRatio: TelegramInputAnimations.iconDamping,
                initialVelocity: CGVector(dx: 0, dy: 0)
            )
            
            let animator = UIViewPropertyAnimator(
                duration: TelegramInputAnimations.iconResponse,
                timingParameters: springParams
            )
            
            animator.addAnimations {
                // Fade and scale microphone
                self.microphoneIcon.alpha = isSend ? 0 : 1
                self.microphoneIcon.transform = isSend ?
                    CGAffineTransform(scaleX: 0.5, y: 0.5) : .identity
                
                // Fade and scale send arrow
                self.sendArrowIcon.alpha = isSend ? 1 : 0
                self.sendArrowIcon.transform = isSend ?
                    CGAffineTransform(rotationAngle: 0) :
                    CGAffineTransform(scaleX: 0.5, y: 0.5).rotated(by: -.pi / 4)
            }
            
            animator.startAnimation()
        } else {
            microphoneIcon.alpha = isSend ? 0 : 1
            microphoneIcon.transform = isSend ? CGAffineTransform(scaleX: 0.5, y: 0.5) : .identity
            sendArrowIcon.alpha = isSend ? 1 : 0
            sendArrowIcon.transform = isSend ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5).rotated(by: -.pi / 4)
        }
        
        currentState = state
    }
}

// MARK: - Morphing Action Button

/// The right-side button that morphs between microphone and send
/// Both states use liquid glass background, send state adds blue tint
class MorphingActionButton: UIView {
    
    enum State {
        case microphone
        case send
    }
    
    private(set) var currentState: State = .microphone
    
    // Glass background (used for both states)
    private var glassBackground: GlassContainerView!
    
    // Blue tint overlay (for send state - sits inside glass)
    private let blueTintOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.5)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        view.layer.cornerRadius = 20
        view.clipsToBounds = true
        return view
    }()
    
    // Icon view (using SF Symbols with crossfade)
    private let morphingIcon = MorphingIconView()
    
    // Callbacks
    var onMicrophoneTapped: (() -> Void)?
    var onSendTapped: (() -> Void)?
    
    // Animation state
    private var currentAnimator: UIViewPropertyAnimator?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        // Glass background
        glassBackground = GlassFactory.makeGlassView(cornerRadius: 20)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)
        
        // Blue tint overlay (inside glass content view)
        glassBackground.glassContentView.addSubview(blueTintOverlay)
        
        // Morphing icon view
        morphingIcon.translatesAutoresizingMaskIntoConstraints = false
        morphingIcon.isUserInteractionEnabled = false
        addSubview(morphingIcon)
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        
        // Long press for voice recording (mic state only)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.2
        addGestureRecognizer(longPress)
        
        NSLayoutConstraint.activate([
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            blueTintOverlay.topAnchor.constraint(equalTo: glassBackground.glassContentView.topAnchor),
            blueTintOverlay.leadingAnchor.constraint(equalTo: glassBackground.glassContentView.leadingAnchor),
            blueTintOverlay.trailingAnchor.constraint(equalTo: glassBackground.glassContentView.trailingAnchor),
            blueTintOverlay.bottomAnchor.constraint(equalTo: glassBackground.glassContentView.bottomAnchor),
            
            morphingIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            morphingIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            morphingIcon.widthAnchor.constraint(equalToConstant: 28),
            morphingIcon.heightAnchor.constraint(equalToConstant: 28),
        ])
    }
    
    @objc private func handleTap() {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        // Scale animation
        animatePress()
        
        // Callback based on state
        switch currentState {
        case .microphone:
            onMicrophoneTapped?()
        case .send:
            onSendTapped?()
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard currentState == .microphone else { return }
        
        switch gesture.state {
        case .began:
            // Start recording visual feedback
            UIView.animate(withDuration: 0.2) {
                self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            
        case .ended, .cancelled:
            UIView.animate(withDuration: 0.2) {
                self.transform = .identity
            }
            
        default:
            break
        }
    }
    
    private func animatePress() {
        UIView.animate(withDuration: TelegramInputAnimations.pulseDuration, animations: {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(
                withDuration: TelegramInputAnimations.pulseDuration,
                delay: 0,
                usingSpringWithDamping: 0.5,
                initialSpringVelocity: 0.5
            ) {
                self.transform = .identity
            }
        }
    }

    
    /// Morph to the specified state with full animation
    func morphTo(_ state: State, animated: Bool = true) {
        guard state != currentState else { return }
        
        // Cancel any in-progress animation and immediately sync visuals
        if let animator = currentAnimator, animator.isRunning {
            animator.stopAnimation(true)
            animator.finishAnimation(at: .current)
        }
        currentAnimator = nil
        
        // Update state IMMEDIATELY to prevent race conditions
        currentState = state
        
        let targetState = state
        
        if animated {
            // Phase 1: Scale pulse
            let pulseAnimator = UIViewPropertyAnimator(
                duration: TelegramInputAnimations.pulseDuration,
                curve: .easeOut
            ) {
                self.transform = CGAffineTransform(scaleX: TelegramInputAnimations.pulseScale,
                                                    y: TelegramInputAnimations.pulseScale)
            }
            
            pulseAnimator.addCompletion { [weak self] position in
                guard let self = self else { return }
                
                // If cancelled or state changed during pulse, sync to current state
                guard position == .end, self.currentState == targetState else {
                    self.syncVisualState()
                    return
                }
                
                // Phase 2: Morph icon and tint
                self.morphingIcon.morphTo(targetState == .send ? .sendArrow : .microphone, animated: true)
                
                // Spring animation for scale and tint
                let springParams = UISpringTimingParameters(
                    dampingRatio: TelegramInputAnimations.morphDamping,
                    initialVelocity: CGVector(dx: 0, dy: 0)
                )
                
                let morphAnimator = UIViewPropertyAnimator(
                    duration: TelegramInputAnimations.morphResponse,
                    timingParameters: springParams
                )
                
                morphAnimator.addAnimations {
                    self.transform = .identity
                    self.blueTintOverlay.alpha = targetState == .send ? 1 : 0
                }
                
                morphAnimator.addCompletion { [weak self] position in
                    guard let self = self else { return }
                    // Always sync visuals at the end to ensure consistency
                    if position != .end || self.currentState != targetState {
                        self.syncVisualState()
                    }
                }
                
                self.currentAnimator = morphAnimator
                morphAnimator.startAnimation()
            }
            
            pulseAnimator.startAnimation()
            
            // Haptic at the right moment
            DispatchQueue.main.asyncAfter(deadline: .now() + TelegramInputAnimations.hapticDelay) {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
        } else {
            syncVisualState()
        }
    }
    
    /// Force visual state to match currentState (no animation)
    private func syncVisualState() {
        let isSend = currentState == .send
        morphingIcon.morphTo(isSend ? .sendArrow : .microphone, animated: false)
        blueTintOverlay.alpha = isSend ? 1 : 0
        transform = .identity
    }
}

// MARK: - Attachment Button

/// Left-side attachment button with liquid glass
class AttachmentButton: UIView {
    
    private var glassBackground: GlassContainerView!
    private let iconView = UIImageView()
    
    var onTapped: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        // Glass background
        glassBackground = GlassFactory.makeGlassView(cornerRadius: 20)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)
        
        // Paperclip icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "paperclip", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        iconView.tintColor = .label  // Dynamic: black in light mode, white in dark mode
        iconView.contentMode = .scaleAspectFit
        glassBackground.glassContentView.addSubview(iconView)
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        
        NSLayoutConstraint.activate([
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.centerXAnchor.constraint(equalTo: glassBackground.glassContentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: glassBackground.glassContentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
    
    @objc private func handleTap() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // Press animation
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
                self.transform = .identity
            }
        }
        
        onTapped?()
    }
    
    /// Change the button icon
    func setIcon(_ systemName: String, tintColor: UIColor = .label) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconView.image = UIImage(systemName: systemName, withConfiguration: config)
        iconView.tintColor = tintColor
    }
}

// MARK: - Emoji Button

/// Emoji/sticker button inside the text field
class EmojiButton: UIView {
    
    private let iconView = UIImageView()
    
    var onTapped: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        // Emoji icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
        iconView.tintColor = .secondaryLabel  // Dynamic: adapts to light/dark mode
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        
        addGestureRecognizer(tap)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
    
    @objc private func handleTap() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // Bounce animation
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
                self.transform = .identity
            }
        }
        
        onTapped?()
    }
}

// MARK: - Emote Text Attachment

/// Custom NSTextAttachment that stores the shortcode for plain-text extraction.
/// When the attributed string is converted to plain text for sending, each
/// EmoteTextAttachment is replaced with `:shortcode:`.
class EmoteTextAttachment: NSTextAttachment {
    let shortcode: String
    
    init(shortcode: String, image: UIImage, height: CGFloat) {
        self.shortcode = shortcode
        super.init(data: nil, ofType: nil)
        let ratio = image.size.width / max(image.size.height, 1)
        self.image = image
        self.bounds = CGRect(x: 0, y: -4, width: height * ratio, height: height)
    }
    
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Text Field Container

/// The main text input area with liquid glass background
class LiquidGlassTextField: UIView {
    
    let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 17)
        tv.textColor = .label  // Dynamic: black in light mode, white in dark mode
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 4, bottom: 10, right: 36)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.showsVerticalScrollIndicator = false
        return tv
    }()
    
    let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "Message"
        label.textColor = .placeholderText  // Dynamic: adapts to light/dark mode
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    let emojiButton = EmojiButton()
    
    private var glassBackground: GlassContainerView!
    
    // Height constraint for dynamic sizing
    private var heightConstraint: NSLayoutConstraint!
    private let minHeight: CGFloat = 44
    private let maxHeight: CGFloat = 120
    
    // Callbacks
    var onTextChanged: ((String) -> Void)?
    var onEmojiTapped: (() -> Void)?
    var onBeginEditing: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        // Glass background
        glassBackground = GlassFactory.makeGlassView(cornerRadius: 22)
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)
        
        // Text view
        glassBackground.glassContentView.addSubview(textView)
        
        // Placeholder
        glassBackground.glassContentView.addSubview(placeholderLabel)
        
        // Emoji button
        glassBackground.glassContentView.addSubview(emojiButton)
        emojiButton.onTapped = { [weak self] in
            self?.onEmojiTapped?()
        }
        
        // Height constraint
        heightConstraint = heightAnchor.constraint(equalToConstant: minHeight)
        heightConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            textView.topAnchor.constraint(equalTo: glassBackground.glassContentView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: glassBackground.glassContentView.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: glassBackground.glassContentView.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: glassBackground.glassContentView.bottomAnchor),
            
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 9),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10),
            
            emojiButton.trailingAnchor.constraint(equalTo: glassBackground.glassContentView.trailingAnchor, constant: -8),
            emojiButton.centerYAnchor.constraint(equalTo: glassBackground.glassContentView.centerYAnchor),
            emojiButton.widthAnchor.constraint(equalToConstant: 32),
            emojiButton.heightAnchor.constraint(equalToConstant: 32),
            
            heightConstraint,
        ])
        
        // Text view delegate
        textView.delegate = self
        
        // Observe text changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: UITextView.textDidChangeNotification,
            object: textView
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func textDidChange() {
        // Update placeholder visibility (check both plain text and attachments)
        placeholderLabel.isHidden = !isEmpty
        
        // Update height
        updateHeight()
        
        // Notify callback with the extracted text (shortcodes, not attachment chars)
        onTextChanged?(text)
    }
    
    private func updateHeight() {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(size.height, minHeight), maxHeight)
        
        if abs(heightConstraint.constant - newHeight) > 1 {
            heightConstraint.constant = newHeight
            textView.isScrollEnabled = newHeight >= maxHeight
            
            // Animate height change
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                self.superview?.layoutIfNeeded()
            }
        }
    }
    
    var text: String {
        get {
            // Extract plain text, replacing EmoteTextAttachments with :shortcode:
            guard let attrText = textView.attributedText else { return textView.text ?? "" }
            var result = ""
            attrText.enumerateAttributes(in: NSRange(location: 0, length: attrText.length)) { attrs, range, _ in
                if let attachment = attrs[.attachment] as? EmoteTextAttachment {
                    result += ":\(attachment.shortcode):"
                } else {
                    result += (attrText.string as NSString).substring(with: range)
                }
            }
            return result
        }
        set {
            textView.text = newValue
            textDidChange()
        }
    }
    
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Inserts an emote image at the current cursor position.
    /// The image is stored as an EmoteTextAttachment so it can be extracted as :shortcode: when sending.
    func insertEmote(shortcode: String, url: URL) {
        // Load image synchronously from cache, or use placeholder
        let emoteHeight: CGFloat = 22
        let placeholderImage = UIImage(systemName: "face.smiling") ?? UIImage()
        
        let attachment = EmoteTextAttachment(shortcode: shortcode, image: placeholderImage, height: emoteHeight)
        let attrString = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString())
        
        let insertionPoint = textView.selectedRange.location
        let attachmentString = NSAttributedString(attachment: attachment)
        
        // Build the insertion with matching font so surrounding text isn't affected
        let styled = NSMutableAttributedString(attributedString: attachmentString)
        styled.addAttributes([
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ], range: NSRange(location: 0, length: styled.length))
        
        attrString.insert(styled, at: insertionPoint)
        
        // Add a trailing space so emojis don't stick together
        let space = NSAttributedString(string: " ", attributes: [
            .font: UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ])
        attrString.insert(space, at: insertionPoint + 1)
        
        textView.attributedText = attrString
        textView.selectedRange = NSRange(location: insertionPoint + 2, length: 0)
        textDidChange()
        
        // Load the real image asynchronously and update the attachment
        SDWebImageManager.shared.loadImage(with: url, options: [.retryFailed], progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self, let image else { return }
            let ratio = image.size.width / max(image.size.height, 1)
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: -4, width: emoteHeight * ratio, height: emoteHeight)
            // Force re-layout to show the loaded image
            let currentSelection = self.textView.selectedRange
            self.textView.attributedText = self.textView.attributedText
            self.textView.selectedRange = currentSelection
        }
    }
}

extension LiquidGlassTextField: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        onBeginEditing?()
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        // Reset any highlight
    }
}


// MARK: - Telegram Chat Input Bar

/// Main chat input bar component - Telegram-style with liquid glass
/// Use as inputAccessoryView for keyboard-attached behavior
class TelegramChatInputBar: UIView {
    
    // MARK: - Components
    
    let attachmentButton = AttachmentButton()
    let textField = LiquidGlassTextField()
    let actionButton = MorphingActionButton()
    
    // MARK: - Zap Components
    
    private let zapAttachmentBox = ZapAttachmentBoxView()
    private var pendingZapAttachment: ZapAttachment?
    private var activeZapModal: MorphingZapModal?
    
    // MARK: - State
    
    /// Computed property - always checks actual text field state
    private var hasText: Bool {
        !textField.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Computed property - checks if there's a pending zap
    private var hasZap: Bool {
        pendingZapAttachment != nil
    }
    
    /// Whether the send button should be shown (text OR zap present)
    private var shouldShowSendButton: Bool {
        hasText || hasZap
    }
    
    // MARK: - Attachment Modal
    
    private var activeModal: MorphingAttachmentModal?
    
    // MARK: - Callbacks
    
    var onSendMessage: ((String) -> Void)?
    var onSendZap: ((Int64, String?) -> Void)?  // (amount in millisats, optional message)
    var onAttachmentTapped: (() -> Void)?
    var onAttachmentSelected: ((AttachmentType) -> Void)?
    var onMicrophoneTapped: (() -> Void)?
    var onEmojiTapped: (() -> Void)?
    
    /// Called when the user taps the zap button but has no wallet connected.
    /// The parent controller should show a prompt to set up a wallet.
    var onNoWallet: (() -> Void)?
    
    /// Set by the parent controller to indicate whether the user has a connected wallet.
    /// When false, tapping the zap button triggers onNoWallet instead of the zap modal.
    var hasConnectedWallet: Bool = true
    
    // MARK: - Zap Target (set by parent controller)
    
    var zapTargetPubkey: String?
    var zapEventCoordinate: String?
    
    // MARK: - Zap Mode
    
    /// When true, the attachment button becomes a zap button
    var isZapMode: Bool = false {
        didSet {
            if isZapMode {
                attachmentButton.setIcon("bolt.fill", tintColor: .systemOrange)
            } else {
                attachmentButton.setIcon("paperclip", tintColor: .label)
            }
        }
    }
    
    // MARK: - Attachment Types
    
    enum AttachmentType {
        case camera
        case photoLibrary
        case document
        case location
        case contact
        case poll
    }
    
    // MARK: - Layout
    
    private let mainContainer: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let inputRow: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .bottom
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Intrinsic Size (for inputAccessoryView)
    
    override var intrinsicContentSize: CGSize {
        var height: CGFloat = 60  // Base height
        
        // Add space for zap box if visible
        if !zapAttachmentBox.isHidden {
            height += 36 + 8  // Box height + spacing
        }
        
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
    
    // MARK: - Setup
    
    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        autoresizingMask = .flexibleHeight
        
        // Main container (vertical)
        addSubview(mainContainer)
        
        // Zap attachment box (hidden by default)
        zapAttachmentBox.isHidden = true
        zapAttachmentBox.onRemoveTapped = { [weak self] in
            self?.removeZapAttachment()
        }
        zapAttachmentBox.onTapped = { [weak self] in
            self?.editZapAttachment()
        }
        mainContainer.addArrangedSubview(zapAttachmentBox)
        
        // Input row (horizontal)
        inputRow.addArrangedSubview(attachmentButton)
        inputRow.addArrangedSubview(textField)
        inputRow.addArrangedSubview(actionButton)
        mainContainer.addArrangedSubview(inputRow)
        
        // Constraints
        NSLayoutConstraint.activate([
            mainContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            mainContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            mainContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            mainContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            
            attachmentButton.widthAnchor.constraint(equalToConstant: 40),
            attachmentButton.heightAnchor.constraint(equalToConstant: 40),
            
            actionButton.widthAnchor.constraint(equalToConstant: 40),
            actionButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        
        // Wire up callbacks
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        // Text changes - update button state on every change
        textField.onTextChanged = { [weak self] _ in
            self?.updateActionButtonState()
        }
        
        // Attachment/Zap button
        attachmentButton.onTapped = { [weak self] in
            guard let self = self else { return }
            if self.isZapMode {
                self.presentZapModal()
            } else {
                self.presentAttachmentModal()
            }
        }
        
        // Emoji
        textField.onEmojiTapped = { [weak self] in
            self?.onEmojiTapped?()
        }
        
        // Action button
        actionButton.onSendTapped = { [weak self] in
            self?.handleSend()
        }
        
        actionButton.onMicrophoneTapped = { [weak self] in
            self?.onMicrophoneTapped?()
        }
    }
    
    // MARK: - Action Button State
    
    private func updateActionButtonState() {
        let targetState: MorphingActionButton.State = shouldShowSendButton ? .send : .microphone
        actionButton.morphTo(targetState, animated: true)
    }
    
    // MARK: - Send Handler
    
    private func handleSend() {
        let text = textField.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let zapAttachment = pendingZapAttachment {
            // Send zap with optional message
            onSendZap?(zapAttachment.amount, text.isEmpty ? nil : text)
            removeZapAttachmentAnimated()
            clearText()
        } else if !text.isEmpty {
            // Normal message send
            onSendMessage?(text)
            clearText()
        }
    }
    
    // MARK: - Zap Modal
    
    private func presentZapModal() {
        guard let window = window,
              let targetPubkey = zapTargetPubkey else { return }
        
        // Hide button during morph
        attachmentButton.alpha = 0
        
        // Present modal
        activeZapModal = MorphingZapModal.present(
            from: attachmentButton,
            in: window,
            targetPubkey: targetPubkey,
            eventCoordinate: zapEventCoordinate,
            noWallet: !hasConnectedWallet
        )
        
        // If no wallet connected, wire up the "Set Up Wallet" button
        if !hasConnectedWallet {
            activeZapModal?.onSetupWallet = { [weak self] in
                self?.onNoWallet?()
            }
        }
        
        // Pass current keyboard height so the modal positions above it.
        // The modal's bottom limit = screenHeight - this value.
        // We want the modal to sit just above the zap button, so measure from
        // the button's top edge to the bottom of the screen.
        let buttonFrame = attachmentButton.convert(attachmentButton.bounds, to: window)
        activeZapModal?.preExistingKeyboardHeight = max(0, UIScreen.main.bounds.height - buttonFrame.origin.y + 4)
        
        // Handle amount selection
        activeZapModal?.onAmountSelected = { [weak self] amount in
            self?.handleZapAmountSelected(amount)
        }
        
        // Handle dismiss without selection
        activeZapModal?.onDismissed = { [weak self] in
            self?.attachmentButton.alpha = 1
            self?.activeZapModal = nil
        }
        
        // Sync button alpha with morph
        activeZapModal?.onMorphProgress = { [weak self] progress in
            self?.attachmentButton.alpha = 1 - progress
        }
    }
    
    private func handleZapAmountSelected(_ amount: Int64) {
        guard let targetPubkey = zapTargetPubkey else { return }
        
        // Create attachment
        let attachment = ZapAttachment(
            amount: amount,
            targetPubkey: targetPubkey,
            eventCoordinate: zapEventCoordinate
        )
        
        // Configure the box
        zapAttachmentBox.configure(with: attachment)
        pendingZapAttachment = attachment
        
        // Prepare box (hidden) and expand input bar height
        prepareZapAttachmentBox { [weak self] in
            guard let self = self,
                  let window = self.window else { return }
            
            // FIX: Get the GLASS CONTAINER frame, not the parent view frame
            // The parent view fills the stack width, but the glass is content-sized
            let boxFrame = self.zapAttachmentBox.glassContainerFrame(in: window)
            self.activeZapModal?.targetBoxFrame = boxFrame
            
            // Start modal → box animation
            self.activeZapModal?.dismissToAttachmentBox { [weak self] in
                guard let self = self else { return }
                
                // Reveal box instantly (modal glass is now at box position)
                self.zapAttachmentBox.alpha = 1
                self.attachmentButton.alpha = 1
                self.updateActionButtonState()
                self.activeZapModal = nil
            }
        }
    }
    
    private func prepareZapAttachmentBox(completion: @escaping () -> Void) {
        // Show box in hierarchy but invisible
        zapAttachmentBox.isHidden = false
        zapAttachmentBox.alpha = 0
        
        // Trigger height expansion
        invalidateIntrinsicContentSize()
        
        // Animate height change, call completion when done
        UIView.animate(withDuration: 0.25, animations: {
            // Walk up to input container to trigger layout
            var container: UIView? = self.superview
            while let view = container {
                view.layoutIfNeeded()
                container = view.superview
                if String(describing: type(of: view)).contains("InputSet") {
                    break
                }
            }
        }) { _ in
            // Layout complete - box frame is now accurate
            completion()
        }
    }
    
    private func removeZapAttachment() {
        removeZapAttachmentAnimated()
    }
    
    private func removeZapAttachmentAnimated() {
        UIView.animate(
            withDuration: 0.25,
            animations: {
                self.zapAttachmentBox.alpha = 0
                self.zapAttachmentBox.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }
        ) { _ in
            self.zapAttachmentBox.isHidden = true
            self.zapAttachmentBox.transform = .identity
            self.pendingZapAttachment = nil
            
            // Trigger height change
            self.invalidateIntrinsicContentSize()
            UIView.animate(withDuration: 0.25) {
                self.superview?.layoutIfNeeded()
            }
            self.updateActionButtonState()
        }
    }
    
    private func editZapAttachment() {
        guard let window = window,
              let targetPubkey = zapTargetPubkey,
              let currentAmount = pendingZapAttachment?.amount else { return }
        
        // Hide the box (modal will appear in its place)
        zapAttachmentBox.alpha = 0
        
        // FIX: Get the actual glass container frame for both source and target
        let glassFrame = zapAttachmentBox.glassContainerFrame(in: window)
        
        // Present modal FROM the glass container position (not full-width view)
        activeZapModal = MorphingZapModal.present(
            from: zapAttachmentBox,
            in: window,
            targetPubkey: targetPubkey,
            eventCoordinate: zapEventCoordinate,
            initialAmount: currentAmount,
            sourceFrame: glassFrame
        )
        
        // Use the same frame for dismiss animation target
        activeZapModal?.targetBoxFrame = glassFrame
        
        // Pass current keyboard height
        // Pass keyboard height — measure from the zap box top to screen bottom
        let boxFrame = zapAttachmentBox.convert(zapAttachmentBox.bounds, to: window)
        activeZapModal?.preExistingKeyboardHeight = max(0, UIScreen.main.bounds.height - boxFrame.origin.y + 4)
        
        // Sync box alpha with morph progress
        activeZapModal?.onMorphProgress = { [weak self] progress in
            self?.zapAttachmentBox.alpha = 1 - progress
        }
        
        // Handle new amount selection
        activeZapModal?.onAmountSelected = { [weak self] amount in
            self?.handleZapAmountSelected(amount)
        }
        
        // Handle dismiss without change
        activeZapModal?.onDismissed = { [weak self] in
            self?.zapAttachmentBox.alpha = 1
            self?.activeZapModal = nil
        }
    }
    
    // MARK: - Attachment Modal
    
    private func presentAttachmentModal() {
        guard let window = window else { return }
        
        // Hide the original button during modal presentation
        attachmentButton.alpha = 0
        
        // Present modal from button position
        activeModal = MorphingAttachmentModal.present(from: attachmentButton, in: window)
        
        // Wire up callbacks
        activeModal?.onCameraTapped = { [weak self] in
            self?.activeModal?.dismiss()
            self?.onAttachmentSelected?(.camera)
            self?.onAttachmentTapped?()
        }
        activeModal?.onPhotoLibraryTapped = { [weak self] in
            self?.activeModal?.dismiss()
            self?.onAttachmentSelected?(.photoLibrary)
            self?.onAttachmentTapped?()
        }
        activeModal?.onDocumentTapped = { [weak self] in
            self?.activeModal?.dismiss()
            self?.onAttachmentSelected?(.document)
            self?.onAttachmentTapped?()
        }
        activeModal?.onLocationTapped = { [weak self] in
            self?.activeModal?.dismiss()
            self?.onAttachmentSelected?(.location)
            self?.onAttachmentTapped?()
        }
        activeModal?.onContactTapped = { [weak self] in
            self?.activeModal?.dismiss()
            self?.onAttachmentSelected?(.contact)
            self?.onAttachmentTapped?()
        }
        activeModal?.onPollTapped = { [weak self] in
            self?.activeModal?.dismiss()
            self?.onAttachmentSelected?(.poll)
            self?.onAttachmentTapped?()
        }
        
        activeModal?.onDismissed = { [weak self] in
            // Ensure button is fully visible (should already be from onMorphProgress)
            self?.attachmentButton.alpha = 1
            self?.activeModal = nil
        }
        
        // Sync button alpha with morph progress
        // Button fades in as modal collapses (inverse of progress)
        activeModal?.onMorphProgress = { [weak self] progress in
            self?.attachmentButton.alpha = 1 - progress
        }
    }
    
    /// Dismiss the attachment modal if it's open
    func dismissAttachmentModal() {
        activeModal?.dismiss()
    }
    
    // MARK: - Public Methods
    
    func clearText() {
        textField.textView.attributedText = nil
        textField.text = ""
        updateActionButtonState()
    }
    
    func setText(_ text: String) {
        textField.text = text
        updateActionButtonState()
    }
    
    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textField.textView.becomeFirstResponder()
    }
    
    @discardableResult
    override func resignFirstResponder() -> Bool {
        return textField.textView.resignFirstResponder()
    }
    
    override var isFirstResponder: Bool {
        return textField.textView.isFirstResponder
    }
    
    // MARK: - View Hierarchy
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // Make container backgrounds transparent when added to view hierarchy
        // This removes the gray bar that iOS adds by default for inputAccessoryView
        DispatchQueue.main.async { [weak self] in
            self?.makeContainerTransparent()
        }
    }
    
    /// Walks up the view hierarchy and clears backgrounds
    private func makeContainerTransparent() {
        var currentView: UIView? = superview
        while let view = currentView {
            view.backgroundColor = .clear
            view.isOpaque = false
            currentView = view.superview
            
            // Stop at UIInputSetContainerView or similar system container
            let typeName = String(describing: type(of: view))
            if typeName.contains("InputSet") {
                break
            }
        }
    }
}

// MARK: - Preview Support

#if DEBUG
import SwiftUI

@available(iOS 17.0, *)
#Preview {
    struct PreviewContainer: UIViewRepresentable {
        func makeUIView(context: Context) -> TelegramChatInputBar {
            let bar = TelegramChatInputBar()
            bar.onSendMessage = { text in
                print("Send: \(text)")
            }
            return bar
        }
        
        func updateUIView(_ uiView: TelegramChatInputBar, context: Context) {}
    }
    
    return ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            PreviewContainer()
                .frame(height: 60)
        }
    }
}
#endif
