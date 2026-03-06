//
//  MorphingZapModal.swift
//  swae
//
//  Window-level morphing modal for zap amount selection
//  Morphs from the zap button position to a full-width modal
//  Uses the same animation pattern as MorphingAttachmentModal
//

import UIKit

/// Window-level modal that morphs from zap button to expanded amount selection
class MorphingZapModal: UIView {
    
    // MARK: - State
    
    enum State {
        case collapsed
        case expanded
        case animating(progress: CGFloat)
    }
    
    enum Mode {
        case quick
        case custom
        case noWallet
    }
    
    private(set) var currentState: State = .collapsed
    private var currentMode: Mode = .quick
    
    // MARK: - Layout Constants
    
    private let collapsedSize: CGFloat = 40
    private let collapsedCornerRadius: CGFloat = 20
    private var modalWidth: CGFloat { UIScreen.main.bounds.width - 32 }
    private let modalCornerRadius: CGFloat = 38
    
    // Header layout constants
    private let headerTopPadding: CGFloat = 20
    private let titleToAmountSpacing: CGFloat = 8
    private let amountToContentSpacing: CGFloat = 24      // For quick mode
    private let amountToContentSpacingCustom: CGFloat = 16 // For custom mode
    private let contentBottomPadding: CGFloat = 20
    private let contentHorizontalPadding: CGFloat = 16
    
    // MARK: - Computed Heights
    
    /// Header height: top padding + title (~24pt) + spacing + amount (~50pt) + spacing + sats (~24pt)
    private var headerHeight: CGFloat {
        return headerTopPadding + 24 + titleToAmountSpacing + 50 + 8 + 24
    }
    
    /// Quick mode total height - computed from content
    private var quickModeHeight: CGFloat {
        return headerHeight + amountToContentSpacing + quickAmountsView.requiredHeight + contentBottomPadding
    }
    
    /// Custom mode total height - computed from content
    private var customModeHeight: CGFloat {
        return headerHeight + amountToContentSpacingCustom + numberPadView.requiredHeight + contentBottomPadding
    }
    
    /// No-wallet mode height — bolt glow (64) + spacing (14) + headline (~24) + spacing (6) + subtitle (~36) + spacing (20) + button (~48)
    private let noWalletContentHeight: CGFloat = 230
    private var noWalletModeHeight: CGFloat {
        return headerTopPadding + noWalletContentHeight + contentBottomPadding
    }
    
    private var currentModalHeight: CGFloat {
        switch currentMode {
        case .quick: return quickModeHeight
        case .custom: return customModeHeight
        case .noWallet: return noWalletModeHeight
        }
    }
    
    // Positioning
    private var sourceFrame: CGRect = .zero
    private var screenBounds: CGRect { UIScreen.main.bounds }
    
    // Keyboard tracking
    private var currentKeyboardHeight: CGFloat = 0
    
    /// Set this before calling present() when the keyboard is already visible (e.g. chat input bar).
    /// The modal uses max(currentKeyboardHeight, preExistingKeyboardHeight) for positioning.
    var preExistingKeyboardHeight: CGFloat = 0
    
    private var effectiveKeyboardHeight: CGFloat {
        max(currentKeyboardHeight, preExistingKeyboardHeight)
    }
    
    /// Maximum height the modal can use between safe area top and keyboard top
    private var availableHeight: CGFloat {
        let safeTop = safeAreaInsets.top + 10
        let bottomLimit = screenBounds.height - effectiveKeyboardHeight - 6
        return max(200, bottomLimit - safeTop)
    }
    
    /// Caps the desired modal height to the available space
    private var cappedModalHeight: CGFloat {
        min(currentModalHeight, availableHeight)
    }
    
    // MARK: - Views
    
    private var morphingGlass: GlassContainerView!
    private let boltIcon = UIImageView()
    private let dimmingView = UIView()
    
    // Header views
    private let titleLabel = UILabel()
    private let amountLabel = AnimatedDigitLabel()
    private let satsLabel = UILabel()  // Separate "sats" label below amount
    
    // Content views
    private let contentScrollView = UIScrollView()
    private let quickAmountsView = ZapQuickAmountsView()
    private let numberPadView = ZapNumberPadView()
    
    // Sending overlay views
    private let sendingOverlay = UIView()
    private let sendingSpinner = UIActivityIndicatorView(style: .large)
    private let sendingStatusLabel = UILabel()
    private let sendingResultIcon = UIImageView()
    
    // No-wallet views
    private let noWalletContainer = UIView()
    
    // MARK: - Constraints
    
    private var glassWidthConstraint: NSLayoutConstraint!
    private var glassHeightConstraint: NSLayoutConstraint!
    private var glassCenterXConstraint: NSLayoutConstraint!
    private var glassCenterYConstraint: NSLayoutConstraint!
    
    // Reference to source button for position updates
    private weak var sourceButton: UIView?
    
    // MARK: - Zap Target
    
    let targetPubkey: String
    let eventCoordinate: String?
    var initialAmount: Int64?
    
    // MARK: - Amount State
    
    private var selectedAmount: Int64 = 0 {
        didSet {
            updateAmountDisplay()
        }
    }
    
    // MARK: - Target for morph-to-box animation
    
    var targetBoxFrame: CGRect?
    
    /// When true, the modal collapses to the source button's actual frame (pill shape)
    /// instead of the default 40×40 circle. The glass stays fully visible during collapse.
    var collapsesToSourceButton: Bool = false
    
    /// Custom title for the confirm button (defaults to "Add Zap")
    var confirmTitle: String? {
        didSet {
            if let title = confirmTitle {
                quickAmountsView.setConfirmTitle(title)
                numberPadView.setConfirmTitle(title)
            }
        }
    }
    
    // MARK: - Callbacks
    
    var onAmountSelected: ((Int64) -> Void)?
    var onDismissed: (() -> Void)?
    var onMorphProgress: ((CGFloat) -> Void)?
    
    /// Async send callback — when set, the modal shows loading/result states before dismissing.
    /// Return true for success, false for failure.
    var onSendZap: ((Int64) async -> Bool)?
    
    /// Called when the user taps "Set Up Wallet" in no-wallet mode.
    var onSetupWallet: (() -> Void)?
    
    /// When true, the modal shows a "wallet required" message instead of the amount picker.
    /// Must be set before calling present() for the animation to work correctly.
    var showNoWalletMode: Bool = false {
        didSet {
            guard showNoWalletMode else { return }
            switchToNoWalletMode()
        }
    }
    
    // MARK: - Initialization
    
    init(sourceFrame: CGRect, targetPubkey: String, eventCoordinate: String?, initialAmount: Int64? = nil) {
        self.sourceFrame = sourceFrame
        self.targetPubkey = targetPubkey
        self.eventCoordinate = eventCoordinate
        self.initialAmount = initialAmount
        super.init(frame: UIScreen.main.bounds)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setup() {
        frame = UIScreen.main.bounds
        backgroundColor = .clear
        
        setupDimmingView()
        setupMorphingGlass()
        setupCollapsedContent()
        setupHeader()
        setupContentScrollView()
        setupQuickAmounts()
        setupNumberPad()
        setupSendingOverlay()
        setupNoWalletView()
        setupGestures()
        
        // Start at collapsed state
        updateMorphProgress(0)
        currentState = .collapsed
        
        // Set initial scroll content size
        updateScrollContentSize()
        
        // Set initial amount display AFTER layout pass
        // Use layoutIfNeeded to ensure amountLabel has valid bounds before setting text
        layoutIfNeeded()
        amountLabel.setText("0", numericValue: 0, animated: false)
        
        // If editing, pre-select the amount
        if let initial = initialAmount, initial > 0 {
            selectedAmount = initial
            quickAmountsView.selectAmount(initial)
        }
        
        // Keyboard observation
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    
    private func setupDimmingView() {
        dimmingView.frame = bounds
        dimmingView.backgroundColor = UIColor.black
        dimmingView.alpha = 0
        addSubview(dimmingView)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmingTapped))
        dimmingView.addGestureRecognizer(tap)
    }
    
    private func setupMorphingGlass() {
        morphingGlass = GlassFactory.makeGlassView(cornerRadius: collapsedCornerRadius)
        morphingGlass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(morphingGlass)
        
        // Initial position at source button center
        let collapsedCenterX = sourceFrame.midX
        let collapsedCenterY = sourceFrame.midY
        
        glassWidthConstraint = morphingGlass.widthAnchor.constraint(equalToConstant: collapsedSize)
        glassHeightConstraint = morphingGlass.heightAnchor.constraint(equalToConstant: collapsedSize)
        glassCenterXConstraint = morphingGlass.centerXAnchor.constraint(equalTo: leadingAnchor, constant: collapsedCenterX)
        glassCenterYConstraint = morphingGlass.centerYAnchor.constraint(equalTo: topAnchor, constant: collapsedCenterY)
        
        NSLayoutConstraint.activate([
            glassWidthConstraint,
            glassHeightConstraint,
            glassCenterXConstraint,
            glassCenterYConstraint,
        ])
    }
    
    private func setupCollapsedContent() {
        boltIcon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        boltIcon.image = UIImage(systemName: "bolt.fill", withConfiguration: config)
        boltIcon.tintColor = .systemOrange
        boltIcon.contentMode = .scaleAspectFit
        morphingGlass.glassContentView.addSubview(boltIcon)
        
        NSLayoutConstraint.activate([
            boltIcon.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            boltIcon.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor),
            boltIcon.widthAnchor.constraint(equalToConstant: 24),
            boltIcon.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
    
    private func setupHeader() {
        // Title
        titleLabel.text = "Send Zap"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alpha = 0
        morphingGlass.glassContentView.addSubview(titleLabel)
        
        // Amount display - animated digits only (no "sats")
        // Use rounded design to match ReceiveView's SwiftUI font
        amountLabel.font = .systemFont(ofSize: 36, weight: .bold, width: .standard)
        if let descriptor = UIFont.systemFont(ofSize: 36, weight: .bold).fontDescriptor.withDesign(.rounded) {
            amountLabel.font = UIFont(descriptor: descriptor, size: 36)
        }
        amountLabel.textColor = .systemOrange
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.alpha = 0
        morphingGlass.glassContentView.addSubview(amountLabel)
        
        // Sats label - static, below amount (matches ReceiveView style)
        satsLabel.text = "sats"
        satsLabel.font = .systemFont(ofSize: 20, weight: .medium)
        satsLabel.textColor = .gray
        satsLabel.textAlignment = .center
        satsLabel.translatesAutoresizingMaskIntoConstraints = false
        satsLabel.alpha = 0
        morphingGlass.glassContentView.addSubview(satsLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            
            amountLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            amountLabel.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            // Give amountLabel a fixed width so it has valid bounds for CATextLayer positioning
            amountLabel.widthAnchor.constraint(equalToConstant: 280),
            amountLabel.heightAnchor.constraint(equalToConstant: 50),
            
            // Sats label below amount with 8pt spacing
            satsLabel.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 8),
            satsLabel.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
        ])
    }
    
    private func setupContentScrollView() {
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.showsVerticalScrollIndicator = false
        contentScrollView.alwaysBounceVertical = false
        contentScrollView.isScrollEnabled = false // enabled only when content is constrained
        contentScrollView.alpha = 0
        morphingGlass.glassContentView.addSubview(contentScrollView)
        
        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(equalTo: satsLabel.bottomAnchor),
            contentScrollView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor),
        ])
    }
    
    /// Updates the scroll view's content size based on the current mode
    private func updateScrollContentSize() {
        let contentHeight: CGFloat
        if currentMode == .quick {
            contentHeight = amountToContentSpacing + quickAmountsView.requiredHeight + contentBottomPadding
        } else {
            contentHeight = amountToContentSpacingCustom + numberPadView.requiredHeight + contentBottomPadding
        }
        contentScrollView.contentSize = CGSize(width: 0, height: contentHeight)
    }

    private func setupQuickAmounts() {
        quickAmountsView.translatesAutoresizingMaskIntoConstraints = false
        quickAmountsView.alpha = 0
        contentScrollView.addSubview(quickAmountsView)
        
        quickAmountsView.onAmountSelected = { [weak self] amount in
            self?.selectedAmount = amount
        }
        
        quickAmountsView.onCustomTapped = { [weak self] in
            self?.switchToCustomMode()
        }
        
        quickAmountsView.onConfirmTapped = { [weak self] in
            guard let self = self, self.selectedAmount > 0 else { return }
            self.confirmAmount()
        }
        
        NSLayoutConstraint.activate([
            quickAmountsView.topAnchor.constraint(equalTo: contentScrollView.topAnchor, constant: amountToContentSpacing),
            quickAmountsView.leadingAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.leadingAnchor, constant: contentHorizontalPadding),
            quickAmountsView.trailingAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.trailingAnchor, constant: -contentHorizontalPadding),
            quickAmountsView.heightAnchor.constraint(equalToConstant: quickAmountsView.requiredHeight),
        ])
    }
    
    private func setupNumberPad() {
        numberPadView.translatesAutoresizingMaskIntoConstraints = false
        numberPadView.alpha = 0
        numberPadView.isHidden = true
        contentScrollView.addSubview(numberPadView)
        
        numberPadView.onDigitTapped = { [weak self] digit in
            self?.appendDigit(digit)
        }
        
        numberPadView.onBackspaceTapped = { [weak self] in
            self?.removeLastDigit()
        }
        
        numberPadView.onConfirmTapped = { [weak self] in
            guard let self = self, self.selectedAmount > 0 else { return }
            self.confirmAmount()
        }
        
        numberPadView.onBackTapped = { [weak self] in
            self?.switchToQuickMode()
        }
        
        NSLayoutConstraint.activate([
            numberPadView.topAnchor.constraint(equalTo: contentScrollView.topAnchor, constant: amountToContentSpacingCustom),
            numberPadView.leadingAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.leadingAnchor, constant: contentHorizontalPadding),
            numberPadView.trailingAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.trailingAnchor, constant: -contentHorizontalPadding),
            numberPadView.heightAnchor.constraint(equalToConstant: numberPadView.requiredHeight),
        ])
    }
    
    private func setupSendingOverlay() {
        sendingOverlay.translatesAutoresizingMaskIntoConstraints = false
        sendingOverlay.alpha = 0
        sendingOverlay.isHidden = true
        contentScrollView.addSubview(sendingOverlay)
        
        sendingSpinner.color = .systemOrange
        sendingSpinner.translatesAutoresizingMaskIntoConstraints = false
        sendingOverlay.addSubview(sendingSpinner)
        
        sendingResultIcon.contentMode = .scaleAspectFit
        sendingResultIcon.translatesAutoresizingMaskIntoConstraints = false
        sendingResultIcon.alpha = 0
        sendingOverlay.addSubview(sendingResultIcon)
        
        sendingStatusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        sendingStatusLabel.textColor = .label  // Adapts to light/dark mode
        sendingStatusLabel.textAlignment = .center
        sendingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        sendingOverlay.addSubview(sendingStatusLabel)
        
        NSLayoutConstraint.activate([
            sendingOverlay.topAnchor.constraint(equalTo: contentScrollView.topAnchor, constant: amountToContentSpacing),
            sendingOverlay.leadingAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.leadingAnchor, constant: contentHorizontalPadding),
            sendingOverlay.trailingAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.trailingAnchor, constant: -contentHorizontalPadding),
            sendingOverlay.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),
            
            sendingSpinner.centerXAnchor.constraint(equalTo: sendingOverlay.centerXAnchor),
            sendingSpinner.centerYAnchor.constraint(equalTo: sendingOverlay.centerYAnchor, constant: -16),
            
            sendingResultIcon.centerXAnchor.constraint(equalTo: sendingOverlay.centerXAnchor),
            sendingResultIcon.centerYAnchor.constraint(equalTo: sendingSpinner.centerYAnchor),
            sendingResultIcon.widthAnchor.constraint(equalToConstant: 40),
            sendingResultIcon.heightAnchor.constraint(equalToConstant: 40),
            
            sendingStatusLabel.topAnchor.constraint(equalTo: sendingSpinner.bottomAnchor, constant: 12),
            sendingStatusLabel.centerXAnchor.constraint(equalTo: sendingOverlay.centerXAnchor),
        ])
    }
    
    private func setupGestures() {
        // Swipe down to dismiss
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        morphingGlass.addGestureRecognizer(swipeDown)
        
        // Pan gesture for interactive dismiss
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        morphingGlass.addGestureRecognizer(pan)
    }
    
    // MARK: - No Wallet Mode
    
    private func setupNoWalletView() {
        noWalletContainer.translatesAutoresizingMaskIntoConstraints = false
        noWalletContainer.alpha = 0
        noWalletContainer.isUserInteractionEnabled = true
        morphingGlass.glassContentView.addSubview(noWalletContainer)
        
        // Bolt icon with orange glow
        let boltContainer = UIView()
        boltContainer.translatesAutoresizingMaskIntoConstraints = false
        noWalletContainer.addSubview(boltContainer)
        
        // Glow layer behind the bolt
        let glowView = UIView()
        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.15)
        glowView.layer.cornerRadius = 32
        boltContainer.addSubview(glowView)
        
        let boltImage = UIImageView()
        boltImage.translatesAutoresizingMaskIntoConstraints = false
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
        boltImage.image = UIImage(systemName: "bolt.fill", withConfiguration: iconConfig)
        boltImage.tintColor = .systemOrange
        boltImage.contentMode = .scaleAspectFit
        boltContainer.addSubview(boltImage)
        
        // Headline
        let headlineLabel = UILabel()
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false
        headlineLabel.text = "Support with Zaps ⚡"
        headlineLabel.font = .systemFont(ofSize: 20, weight: .bold)
        headlineLabel.textColor = .white
        headlineLabel.textAlignment = .center
        noWalletContainer.addSubview(headlineLabel)
        
        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Connect a Lightning wallet to send instant Bitcoin tips to your favorite creators."
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        noWalletContainer.addSubview(subtitleLabel)
        
        // CTA button — gradient orange with bolt icon
        let ctaButton = UIButton(type: .system)
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        
        var config = UIButton.Configuration.filled()
        config.title = "Connect Wallet"
        config.image = UIImage(systemName: "bolt.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        config.imagePadding = 6
        config.imagePlacement = .leading
        config.baseForegroundColor = .white
        config.baseBackgroundColor = .systemOrange
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        ctaButton.configuration = config
        ctaButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        ctaButton.addTarget(self, action: #selector(setupWalletTapped), for: .touchUpInside)
        noWalletContainer.addSubview(ctaButton)
        
        NSLayoutConstraint.activate([
            noWalletContainer.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor, constant: headerTopPadding),
            noWalletContainer.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: contentHorizontalPadding),
            noWalletContainer.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor, constant: -contentHorizontalPadding),
            noWalletContainer.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor, constant: -contentBottomPadding),
            
            // Bolt glow circle
            boltContainer.topAnchor.constraint(equalTo: noWalletContainer.topAnchor, constant: 16),
            boltContainer.centerXAnchor.constraint(equalTo: noWalletContainer.centerXAnchor),
            boltContainer.widthAnchor.constraint(equalToConstant: 64),
            boltContainer.heightAnchor.constraint(equalToConstant: 64),
            
            glowView.centerXAnchor.constraint(equalTo: boltContainer.centerXAnchor),
            glowView.centerYAnchor.constraint(equalTo: boltContainer.centerYAnchor),
            glowView.widthAnchor.constraint(equalToConstant: 64),
            glowView.heightAnchor.constraint(equalToConstant: 64),
            
            boltImage.centerXAnchor.constraint(equalTo: boltContainer.centerXAnchor),
            boltImage.centerYAnchor.constraint(equalTo: boltContainer.centerYAnchor),
            
            // Headline
            headlineLabel.topAnchor.constraint(equalTo: boltContainer.bottomAnchor, constant: 14),
            headlineLabel.leadingAnchor.constraint(equalTo: noWalletContainer.leadingAnchor, constant: 8),
            headlineLabel.trailingAnchor.constraint(equalTo: noWalletContainer.trailingAnchor, constant: -8),
            
            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: noWalletContainer.leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(equalTo: noWalletContainer.trailingAnchor, constant: -12),
            
            // CTA button
            ctaButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            ctaButton.centerXAnchor.constraint(equalTo: noWalletContainer.centerXAnchor),
            ctaButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }
    
    @objc private func setupWalletTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
        // Fire callback after dismiss animation starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.onSetupWallet?()
        }
    }
    
    private func switchToNoWalletMode() {
        currentMode = .noWallet
        
        // Hide normal content and disable interaction so noWalletContainer receives touches
        titleLabel.isHidden = true
        amountLabel.isHidden = true
        satsLabel.isHidden = true
        contentScrollView.isHidden = true
        
        // Bring no-wallet container to front
        morphingGlass.glassContentView.bringSubviewToFront(noWalletContainer)
    }

    
    // MARK: - Mode Switching
    
    private func switchToCustomMode() {
        currentMode = .custom
        selectedAmount = 0
        quickAmountsView.clearSelection()
        
        // Calculate target height and position with keyboard-aware capping
        let desiredHeight = customModeHeight
        let cappedHeight = min(desiredHeight, availableHeight)
        let targetCenterY = calculateExpandedCenterY(for: cappedHeight)
        
        // Phase 1: Fade out quick amounts
        UIView.animate(withDuration: 0.15, animations: {
            self.quickAmountsView.alpha = 0
        }) { _ in
            self.quickAmountsView.isHidden = true
            self.numberPadView.isHidden = false
            self.numberPadView.alpha = 0
            self.contentScrollView.isScrollEnabled = cappedHeight < desiredHeight
            self.contentScrollView.contentOffset = .zero
            self.updateScrollContentSize()
            
            // Phase 2: Resize and reposition modal, fade in number pad
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0,
                options: [],
                animations: {
                    self.glassHeightConstraint.constant = cappedHeight
                    self.glassCenterYConstraint.constant = targetCenterY
                    self.numberPadView.alpha = 1
                    self.layoutIfNeeded()
                }
            )
        }
    }
    
    private func switchToQuickMode() {
        currentMode = .quick
        selectedAmount = 0
        
        // Calculate target height and position with keyboard-aware capping
        let desiredHeight = quickModeHeight
        let cappedHeight = min(desiredHeight, availableHeight)
        let targetCenterY = calculateExpandedCenterY(for: cappedHeight)
        
        // Phase 1: Fade out number pad
        UIView.animate(withDuration: 0.15, animations: {
            self.numberPadView.alpha = 0
        }) { _ in
            self.numberPadView.isHidden = true
            self.quickAmountsView.isHidden = false
            self.quickAmountsView.alpha = 0
            self.quickAmountsView.clearSelection()
            self.contentScrollView.isScrollEnabled = cappedHeight < desiredHeight
            self.contentScrollView.contentOffset = .zero
            self.updateScrollContentSize()
            
            // Phase 2: Resize and reposition modal, fade in quick amounts
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0,
                options: [],
                animations: {
                    self.glassHeightConstraint.constant = cappedHeight
                    self.glassCenterYConstraint.constant = targetCenterY
                    self.quickAmountsView.alpha = 1
                    self.layoutIfNeeded()
                }
            )
        }
    }
    
    /// Calculate the Y center position for the expanded modal at a given height
    private func calculateExpandedCenterY(for height: CGFloat) -> CGFloat {
        let collapsedFrame: CGRect
        if let targetFrame = targetBoxFrame {
            collapsedFrame = targetFrame
        } else if let button = sourceButton, let window = self.window {
            collapsedFrame = button.convert(button.bounds, to: window)
        } else {
            collapsedFrame = sourceFrame
        }
        
        let isConstrained = height < currentModalHeight
        
        // Use tighter padding when constrained by keyboard
        let topPad: CGFloat = isConstrained ? 10 : 20
        let bottomPad: CGFloat = isConstrained ? 6 : 10
        
        let safeTop = safeAreaInsets.top + topPad
        let bottomLimit = screenBounds.height - effectiveKeyboardHeight - bottomPad
        
        let idealCenterY = collapsedFrame.minY - (height / 2) - 20
        let minCenterY = safeTop + height / 2
        let maxCenterY = bottomLimit - height / 2
        
        return min(max(minCenterY, idealCenterY), maxCenterY)
    }
    
    // MARK: - Amount Handling
    
    private func updateAmountDisplay() {
        let sats = selectedAmount / 1000
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: sats)) ?? "\(sats)"
        
        // Animate just the number (satsLabel is static below)
        amountLabel.setText(formatted, numericValue: sats, animated: true)
        
        // Update confirm button state
        let enabled = selectedAmount > 0
        quickAmountsView.setConfirmEnabled(enabled)
        numberPadView.setConfirmEnabled(enabled)
    }
    
    private func appendDigit(_ digit: Int) {
        let currentSats = selectedAmount / 1000
        let newSats = currentSats * 10 + Int64(digit)
        // Cap at 1 billion sats (10 BTC)
        if newSats <= 1_000_000_000 {
            selectedAmount = newSats * 1000
        }
    }
    
    private func removeLastDigit() {
        let currentSats = selectedAmount / 1000
        let newSats = currentSats / 10
        selectedAmount = newSats * 1000
    }
    
    private func confirmAmount() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        if let onSendZap = onSendZap {
            // Async send mode — show loading, send, show result, then dismiss
            showSendingState()
            Task {
                let success = await onSendZap(selectedAmount)
                await MainActor.run {
                    self.showResultState(success: success)
                }
            }
        } else {
            // Default mode — just fire callback (chat input bar flow)
            onAmountSelected?(selectedAmount)
        }
    }
    
    // MARK: - Sending States
    
    private func showSendingState() {
        // Disable gestures during send
        morphingGlass.gestureRecognizers?.forEach { $0.isEnabled = false }
        
        sendingOverlay.isHidden = false
        sendingSpinner.startAnimating()
        sendingResultIcon.alpha = 0
        sendingStatusLabel.text = "Sending..."
        
        UIView.animate(withDuration: 0.25) {
            self.quickAmountsView.alpha = 0
            self.numberPadView.alpha = 0
            self.sendingOverlay.alpha = 1
        }
    }
    
    private func showResultState(success: Bool) {
        sendingSpinner.stopAnimating()
        
        let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        if success {
            sendingResultIcon.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
            sendingResultIcon.tintColor = .systemGreen
            sendingStatusLabel.text = "Sent!"
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        } else {
            sendingResultIcon.image = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
            sendingResultIcon.tintColor = .systemRed
            sendingStatusLabel.text = "Failed"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        
        UIView.animate(withDuration: 0.2) {
            self.sendingSpinner.alpha = 0
            self.sendingResultIcon.alpha = 1
        }
        
        // Auto-dismiss after a brief pause
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.8 : 1.5)) { [weak self] in
            self?.dismiss()
        }
    }
    
    // MARK: - Morph Animation
    
    private func updateMorphProgress(_ progress: CGFloat) {
        let p = max(0, min(1, progress))
        
        // === DETERMINE COLLAPSED STATE ===
        // If we have a targetBoxFrame (editing mode), collapse to the pill
        // Otherwise, collapse to the source button
        let collapsedFrame: CGRect
        let collapsedWidth: CGFloat
        let collapsedHeight: CGFloat
        let collapsedCorner: CGFloat
        
        if let targetFrame = targetBoxFrame {
            // Editing mode: collapse to pill position/size
            collapsedFrame = targetFrame
            collapsedWidth = targetFrame.width
            collapsedHeight = targetFrame.height
            collapsedCorner = 18  // Pill corner radius
        } else if collapsesToSourceButton, let button = sourceButton, let window = self.window {
            // Pill mode: collapse to source button's actual frame
            collapsedFrame = button.convert(button.bounds, to: window)
            collapsedWidth = collapsedFrame.width
            collapsedHeight = collapsedFrame.height
            collapsedCorner = 18  // Pill corner radius
        } else {
            // Normal mode: collapse to button position/size
            if let button = sourceButton, let window = self.window {
                collapsedFrame = button.convert(button.bounds, to: window)
            } else {
                collapsedFrame = sourceFrame
            }
            collapsedWidth = collapsedSize  // 40
            collapsedHeight = collapsedSize  // 40
            collapsedCorner = collapsedCornerRadius  // 20
        }
        
        // === SIZE INTERPOLATION ===
        let desiredHeight = currentModalHeight
        let cappedHeight = min(desiredHeight, availableHeight)
        let width = collapsedWidth + (modalWidth - collapsedWidth) * p
        let height = collapsedHeight + (cappedHeight - collapsedHeight) * p
        let cornerRadius = collapsedCorner + (modalCornerRadius - collapsedCorner) * p
        
        // Enable scrolling only when content is constrained
        contentScrollView.isScrollEnabled = cappedHeight < desiredHeight
        
        // === POSITION INTERPOLATION ===
        let collapsedCenterX = collapsedFrame.midX
        let collapsedCenterY = collapsedFrame.midY
        
        // Expanded: centered horizontally, positioned above input bar
        let expandedCenterX = screenBounds.width / 2
        
        // Calculate expanded Y position using capped height
        let expandedCenterY = calculateExpandedCenterY(for: cappedHeight)
        
        // Interpolate position
        let centerX = collapsedCenterX + (expandedCenterX - collapsedCenterX) * p
        let centerY = collapsedCenterY + (expandedCenterY - collapsedCenterY) * p
        
        // === UPDATE CONSTRAINTS ===
        glassWidthConstraint.constant = width
        glassHeightConstraint.constant = height
        glassCenterXConstraint.constant = centerX
        glassCenterYConstraint.constant = centerY
        
        morphingGlass.layer.cornerRadius = cornerRadius
        
        // === CONTENT CROSSFADE ===
        if targetBoxFrame != nil {
            // Edit mode: collapsing to pill
            // Keep bolt icon hidden - the pill will be revealed via onMorphProgress
            boltIcon.alpha = 0
            // Fade out the entire glass container as we collapse
            // At p=1 (expanded): glass alpha = 1
            // At p=0.3: glass alpha = 0 (hidden before we reach pill)
            morphingGlass.alpha = min(1, p / 0.3)
        } else if collapsesToSourceButton {
            // Pill mode: collapse to source button shape
            // Fade out the glass in the final 15% of collapse so it vanishes
            // right as it reaches the button (the real button fades in via onMorphProgress)
            boltIcon.alpha = 0
            morphingGlass.alpha = min(1, p / 0.15)
        } else {
            // Normal mode: collapsing to button
            // Bolt icon fades in as we collapse (mimics button icon)
            boltIcon.alpha = max(0, 1 - (p * 3.33))
            morphingGlass.alpha = 1
        }
        
        // Expanded content fades in (starts at 30%)
        let contentAlpha = p > 0.3 ? (p - 0.3) / 0.7 : 0
        
        if currentMode == .noWallet {
            // No-wallet mode: only show the no-wallet container
            titleLabel.alpha = 0
            amountLabel.alpha = 0
            satsLabel.alpha = 0
            contentScrollView.alpha = 0
            noWalletContainer.alpha = contentAlpha
        } else {
            titleLabel.alpha = contentAlpha
            amountLabel.alpha = contentAlpha
            satsLabel.alpha = contentAlpha
            contentScrollView.alpha = contentAlpha
            noWalletContainer.alpha = 0
            
            if currentMode == .quick {
                quickAmountsView.alpha = contentAlpha
            } else {
                numberPadView.alpha = contentAlpha
            }
        }
        
        // Dimming background
        dimmingView.alpha = p * 0.4
        
        layoutIfNeeded()
        
        // Notify parent of progress for button sync
        onMorphProgress?(p)
        
        currentState = .animating(progress: p)
    }
    
    private func completeMorph(expand: Bool) {
        let targetProgress: CGFloat = expand ? 1 : 0
        
        let animator = UIViewPropertyAnimator(
            duration: 0.5,
            dampingRatio: 0.85
        ) { [weak self] in
            self?.updateMorphProgress(targetProgress)
        }
        
        animator.addCompletion { [weak self] _ in
            guard let self = self else { return }
            self.currentState = expand ? .expanded : .collapsed
            
            if !expand {
                self.removeFromSuperview()
                self.onDismissed?()
            }
        }
        
        animator.startAnimation()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    
    // MARK: - Special Dismiss (to attachment box)
    
    func dismissToAttachmentBox(completion: @escaping () -> Void) {
        guard let targetFrame = targetBoxFrame else {
            // Fallback: just dismiss normally
            dismiss()
            completion()
            return
        }
        
        // Animate modal glass to EXACT box position
        let animator = UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.85) {
            // Size: match box exactly
            self.glassWidthConstraint.constant = targetFrame.width
            self.glassHeightConstraint.constant = targetFrame.height
            
            // Position: match box exactly
            self.glassCenterXConstraint.constant = targetFrame.midX
            self.glassCenterYConstraint.constant = targetFrame.midY
            
            // Corner radius: match box (18pt)
            self.morphingGlass.layer.cornerRadius = 18
            
            // Fade out modal content (but NOT the glass itself)
            self.titleLabel.alpha = 0
            self.amountLabel.alpha = 0
            self.satsLabel.alpha = 0
            self.quickAmountsView.alpha = 0
            self.numberPadView.alpha = 0
            self.dimmingView.alpha = 0
            self.boltIcon.alpha = 0
            
            self.layoutIfNeeded()
        }
        
        animator.addCompletion { [weak self] _ in
            // Signal parent to reveal the box
            completion()
            // Remove modal - the box is now visible in its place
            self?.removeFromSuperview()
        }
        
        animator.startAnimation()
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func dimmingTapped() {
        dismiss()
    }
    
    @objc private func handleSwipeDown() {
        dismiss()
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .changed:
            guard case .expanded = currentState else { return }
            
            // Positive translation = dragging down = collapsing
            let progress = max(0, 1 - (translation.y / 200))
            updateMorphProgress(progress)
            
        case .ended, .cancelled:
            guard case .animating = currentState else { return }
            
            let progress = 1 - (translation.y / 200)
            let shouldCollapse = progress < 0.6 || velocity.y > 500
            completeMorph(expand: !shouldCollapse)
            
        default:
            break
        }
    }
    
    // MARK: - Keyboard Handling
    
    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let newHeight = max(0, screenBounds.height - endFrame.origin.y)
        currentKeyboardHeight = newHeight
        
        // If expanded, reposition and resize to stay within available space
        guard isExpanded else { return }
        let desiredHeight = currentModalHeight
        let cappedHeight = min(desiredHeight, availableHeight)
        let targetCenterY = calculateExpandedCenterY(for: cappedHeight)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curveRaw << 16),
            animations: {
                self.glassHeightConstraint.constant = cappedHeight
                self.glassCenterYConstraint.constant = targetCenterY
                self.contentScrollView.isScrollEnabled = cappedHeight < desiredHeight
                self.layoutIfNeeded()
            }
        )
    }

    // MARK: - Public API
    
    var isExpanded: Bool {
        if case .expanded = currentState { return true }
        return false
    }
    
    func present() {
        completeMorph(expand: true)
    }
    
    func dismiss() {
        // Recalculate source frame before dismissing
        if let button = sourceButton, let window = self.window {
            sourceFrame = button.convert(button.bounds, to: window)
        }
        completeMorph(expand: false)
    }
    
    // MARK: - Convenience Presentation
    
    @discardableResult
    static func present(
        from button: UIView,
        in window: UIWindow,
        targetPubkey: String,
        eventCoordinate: String?,
        initialAmount: Int64? = nil,
        sourceFrame: CGRect? = nil,
        noWallet: Bool = false
    ) -> MorphingZapModal {
        let frame = sourceFrame ?? button.convert(button.bounds, to: window)
        let modal = MorphingZapModal(
            sourceFrame: frame,
            targetPubkey: targetPubkey,
            eventCoordinate: eventCoordinate,
            initialAmount: initialAmount
        )
        modal.sourceButton = button
        if noWallet {
            modal.showNoWalletMode = true
        }
        window.addSubview(modal)
        modal.present()
        return modal
    }
}
