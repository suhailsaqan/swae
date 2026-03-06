//
//  MorphingAttachmentModal.swift
//  swae
//
//  Window-level morphing modal for attachment options
//  Morphs from the attachment button position to a full-width modal
//  Uses the same animation pattern as MorphingGlassModal
//

import UIKit

/// Window-level modal that morphs from attachment button to expanded options
class MorphingAttachmentModal: UIView {
    
    // MARK: - State
    
    enum State {
        case collapsed
        case expanded
        case animating(progress: CGFloat)
    }
    
    private(set) var currentState: State = .collapsed
    
    // MARK: - Layout Constants
    
    // Collapsed (matches AttachmentButton)
    private let collapsedSize: CGFloat = 40
    private let collapsedCornerRadius: CGFloat = 20
    
    // Expanded modal dimensions
    private var modalWidth: CGFloat { UIScreen.main.bounds.width - 32 }
    private let modalHeight: CGFloat = 320
    private let modalCornerRadius: CGFloat = 38
    
    // Positioning
    private var sourceFrame: CGRect = .zero
    private var screenBounds: CGRect { UIScreen.main.bounds }
    
    // MARK: - Views
    
    private var morphingGlass: GlassContainerView!
    private let paperclipIcon = UIImageView()
    private let expandedContent = AttachmentOptionsView()
    private let dimmingView = UIView()
    
    // MARK: - Constraints
    
    private var glassWidthConstraint: NSLayoutConstraint!
    private var glassHeightConstraint: NSLayoutConstraint!
    private var glassCenterXConstraint: NSLayoutConstraint!
    private var glassCenterYConstraint: NSLayoutConstraint!
    
    // Reference to source button for position updates
    private weak var sourceButton: UIView?

    // MARK: - Callbacks
    
    var onCameraTapped: (() -> Void)?
    var onPhotoLibraryTapped: (() -> Void)?
    var onDocumentTapped: (() -> Void)?
    var onLocationTapped: (() -> Void)?
    var onContactTapped: (() -> Void)?
    var onPollTapped: (() -> Void)?
    var onDismissed: (() -> Void)?
    var onMorphProgress: ((CGFloat) -> Void)?  // Called during animation for button sync
    
    // MARK: - Initialization
    
    init(sourceFrame: CGRect) {
        self.sourceFrame = sourceFrame
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
        setupExpandedContent()
        setupGestures()
        
        // Start at collapsed state
        updateMorphProgress(0)
        currentState = .collapsed
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
        paperclipIcon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        paperclipIcon.image = UIImage(systemName: "paperclip", withConfiguration: config)
        paperclipIcon.tintColor = .white
        paperclipIcon.contentMode = .scaleAspectFit
        morphingGlass.glassContentView.addSubview(paperclipIcon)
        
        NSLayoutConstraint.activate([
            paperclipIcon.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            paperclipIcon.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor),
            paperclipIcon.widthAnchor.constraint(equalToConstant: 24),
            paperclipIcon.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
    
    private func setupExpandedContent() {
        expandedContent.translatesAutoresizingMaskIntoConstraints = false
        expandedContent.alpha = 0
        morphingGlass.glassContentView.addSubview(expandedContent)
        
        NSLayoutConstraint.activate([
            expandedContent.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor),
            expandedContent.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor),
            expandedContent.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor),
            expandedContent.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor),
        ])
        
        // Wire up callbacks
        expandedContent.onCameraTapped = { [weak self] in self?.onCameraTapped?() }
        expandedContent.onPhotoLibraryTapped = { [weak self] in self?.onPhotoLibraryTapped?() }
        expandedContent.onDocumentTapped = { [weak self] in self?.onDocumentTapped?() }
        expandedContent.onLocationTapped = { [weak self] in self?.onLocationTapped?() }
        expandedContent.onContactTapped = { [weak self] in self?.onContactTapped?() }
        expandedContent.onPollTapped = { [weak self] in self?.onPollTapped?() }
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

    // MARK: - Morph Animation
    
    private func updateMorphProgress(_ progress: CGFloat) {
        let p = max(0, min(1, progress))
        
        // === SIZE INTERPOLATION ===
        let width = collapsedSize + (modalWidth - collapsedSize) * p
        let height = collapsedSize + (modalHeight - collapsedSize) * p
        let cornerRadius = collapsedCornerRadius + (modalCornerRadius - collapsedCornerRadius) * p
        
        // === POSITION INTERPOLATION ===
        // Recalculate source frame if button reference available (handles keyboard changes)
        let currentSourceFrame: CGRect
        if let button = sourceButton, let window = self.window {
            currentSourceFrame = button.convert(button.bounds, to: window)
        } else {
            currentSourceFrame = sourceFrame
        }
        
        let collapsedCenterX = currentSourceFrame.midX
        let collapsedCenterY = currentSourceFrame.midY
        
        // Expanded: centered horizontally, positioned above input bar
        let expandedCenterX = screenBounds.width / 2
        
        // Calculate expanded Y position - above the source with gap
        // Clamp to stay within safe area
        let safeTop = safeAreaInsets.top + 20
        let idealExpandedCenterY = currentSourceFrame.minY - (modalHeight / 2) - 20
        let expandedCenterY = max(safeTop + modalHeight / 2, idealExpandedCenterY)
        
        // Interpolate position
        let centerX = collapsedCenterX + (expandedCenterX - collapsedCenterX) * p
        let centerY = collapsedCenterY + (expandedCenterY - collapsedCenterY) * p
        
        // === UPDATE CONSTRAINTS ===
        glassWidthConstraint.constant = width
        glassHeightConstraint.constant = height
        glassCenterXConstraint.constant = centerX
        glassCenterYConstraint.constant = centerY
        
        // Update corner radius (works because GlassContainerView has clipsToBounds = true)
        morphingGlass.layer.cornerRadius = cornerRadius
        
        // === CONTENT CROSSFADE ===
        // Paperclip fades out quickly (gone by 30% progress)
        paperclipIcon.alpha = max(0, 1 - (p * 3.33))
        
        // Expanded content fades in (starts at 30%)
        expandedContent.alpha = p > 0.3 ? (p - 0.3) / 0.7 : 0
        
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
            // Only respond to downward drags when expanded
            guard case .expanded = currentState else { return }
            
            // Positive translation = dragging down = collapsing
            let progress = max(0, 1 - (translation.y / 200))
            updateMorphProgress(progress)
            
        case .ended, .cancelled:
            guard case .animating = currentState else { return }
            
            // Collapse if dragged down enough or velocity is fast enough
            let progress = 1 - (translation.y / 200)
            let shouldCollapse = progress < 0.6 || velocity.y > 500
            completeMorph(expand: !shouldCollapse)
            
        default:
            break
        }
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
    
    /// Show the modal from a source button
    /// - Parameters:
    ///   - button: The button to morph from
    ///   - window: The window to present in
    /// - Returns: The presented modal
    @discardableResult
    static func present(from button: UIView, in window: UIWindow) -> MorphingAttachmentModal {
        let buttonFrame = button.convert(button.bounds, to: window)
        let modal = MorphingAttachmentModal(sourceFrame: buttonFrame)
        modal.sourceButton = button
        window.addSubview(modal)
        modal.present()
        return modal
    }
}
