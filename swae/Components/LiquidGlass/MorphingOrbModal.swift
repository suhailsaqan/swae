import UIKit

/// Main container that handles the morph animation between collapsed pill and expanded modal
/// Uses two-view crossfade approach for reliable animation on all iOS versions
class MorphingOrbModal: UIView {
    
    // MARK: - State
    
    enum State {
        case collapsed
        case expanded
        case dragging(progress: CGFloat)
    }
    
    private(set) var currentState: State = .collapsed
    
    // MARK: - Views
    
    // Collapsed state views
    private let collapsedContainer = UIView()
    private let modePill = ModePillView()
    private var galleryGlassContainer: GlassContainerView!
    private var flipGlassContainer: GlassContainerView!
    
    // Expanded state views
    private var expandedGlassContainer: GlassContainerView!
    private let expandedContent = ExpandedControlsModal()
    
    // Shared
    private let shutterButton = UIButton(type: .system)
    
    // MARK: - Animation
    
    private var morphAnimator: UIViewPropertyAnimator?
    private var panStartY: CGFloat = 0
    private let expandThreshold: CGFloat = 150
    
    // MARK: - Layout Constants
    
    private let modalWidth: CGFloat = UIScreen.main.bounds.width - 28
    private let modalHeight: CGFloat = 380
    private let modalCornerRadius: CGFloat = 38
    
    // MARK: - Callbacks
    
    var onModeChanged: ((Bool) -> Void)? // true = photo
    var onGalleryTapped: (() -> Void)?
    var onShutterTapped: (() -> Void)?
    
    // Forward button callbacks
    var onFlashTapped: (() -> Void)? {
        didSet { expandedContent.onFlashTapped = onFlashTapped }
    }
    var onLiveTapped: (() -> Void)?
    var onTimerTapped: (() -> Void)? {
        get { expandedContent.onRecordTapped }
        set { expandedContent.onRecordTapped = newValue }
    }
    var onExposureTapped: (() -> Void)? {
        get { expandedContent.onExposureTapped }
        set { expandedContent.onExposureTapped = newValue }
    }
    var onStylesTapped: (() -> Void)? {
        get { expandedContent.onStylesTapped }
        set { expandedContent.onStylesTapped = newValue }
    }
    var onAspectTapped: (() -> Void)? {
        get { expandedContent.onQualityTapped }
        set { expandedContent.onQualityTapped = newValue }
    }
    var onNightModeTapped: (() -> Void)? {
        get { expandedContent.onNightModeTapped }
        set { expandedContent.onNightModeTapped = newValue }
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Setup
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = false
        
        setupCollapsedState()
        setupExpandedState()
        setupShutterButton()
        setupGestures()
        
        // Start collapsed
        setExpanded(false, animated: false)
    }

    
    private func setupCollapsedState() {
        collapsedContainer.translatesAutoresizingMaskIntoConstraints = false
        collapsedContainer.backgroundColor = .clear
        addSubview(collapsedContainer)
        
        // Gallery button (left) - liquid glass
        galleryGlassContainer = GlassFactory.makeGlassView(cornerRadius: 25)
        galleryGlassContainer.translatesAutoresizingMaskIntoConstraints = false
        collapsedContainer.addSubview(galleryGlassContainer)
        
        let galleryIcon = UIImageView()
        galleryIcon.translatesAutoresizingMaskIntoConstraints = false
        galleryIcon.image = UIImage(systemName: "photo", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        galleryIcon.tintColor = .white
        galleryIcon.contentMode = .scaleAspectFit
        galleryGlassContainer.glassContentView.addSubview(galleryIcon)
        
        let galleryTap = UITapGestureRecognizer(target: self, action: #selector(galleryTapped))
        galleryGlassContainer.addGestureRecognizer(galleryTap)
        
        // Mode pill (center)
        modePill.onModeChanged = { [weak self] isPhoto in
            self?.onModeChanged?(isPhoto)
        }
        collapsedContainer.addSubview(modePill)
        
        // Flash button (right) - liquid glass
        flipGlassContainer = GlassFactory.makeGlassView(cornerRadius: 25)
        flipGlassContainer.translatesAutoresizingMaskIntoConstraints = false
        collapsedContainer.addSubview(flipGlassContainer)
        
        let flashIcon = UIImageView()
        flashIcon.translatesAutoresizingMaskIntoConstraints = false
        flashIcon.image = UIImage(systemName: "flashlight.on.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        flashIcon.tintColor = .white
        flashIcon.contentMode = .scaleAspectFit
        flipGlassContainer.glassContentView.addSubview(flashIcon)
        
        let flashTap = UITapGestureRecognizer(target: self, action: #selector(flashButtonTapped))
        flipGlassContainer.addGestureRecognizer(flashTap)
        
        NSLayoutConstraint.activate([
            collapsedContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            collapsedContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            collapsedContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -30),
            collapsedContainer.heightAnchor.constraint(equalToConstant: 50),
            
            // Gallery glass button
            galleryGlassContainer.leadingAnchor.constraint(equalTo: collapsedContainer.leadingAnchor, constant: 30),
            galleryGlassContainer.centerYAnchor.constraint(equalTo: collapsedContainer.centerYAnchor),
            galleryGlassContainer.widthAnchor.constraint(equalToConstant: 50),
            galleryGlassContainer.heightAnchor.constraint(equalToConstant: 50),
            
            galleryIcon.centerXAnchor.constraint(equalTo: galleryGlassContainer.glassContentView.centerXAnchor),
            galleryIcon.centerYAnchor.constraint(equalTo: galleryGlassContainer.glassContentView.centerYAnchor),
            
            // Mode pill
            modePill.centerXAnchor.constraint(equalTo: collapsedContainer.centerXAnchor),
            modePill.centerYAnchor.constraint(equalTo: collapsedContainer.centerYAnchor),
            
            // Flash glass button
            flipGlassContainer.trailingAnchor.constraint(equalTo: collapsedContainer.trailingAnchor, constant: -30),
            flipGlassContainer.centerYAnchor.constraint(equalTo: collapsedContainer.centerYAnchor),
            flipGlassContainer.widthAnchor.constraint(equalToConstant: 50),
            flipGlassContainer.heightAnchor.constraint(equalToConstant: 50),
            
            flashIcon.centerXAnchor.constraint(equalTo: flipGlassContainer.glassContentView.centerXAnchor),
            flashIcon.centerYAnchor.constraint(equalTo: flipGlassContainer.glassContentView.centerYAnchor),
        ])
    }
    
    private func setupExpandedState() {
        // Glass container for expanded modal
        expandedGlassContainer = GlassFactory.makeGlassView(cornerRadius: modalCornerRadius)
        expandedGlassContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(expandedGlassContainer)
        
        // Add content to glass container
        expandedGlassContainer.glassContentView.addSubview(expandedContent)
        
        NSLayoutConstraint.activate([
            // Glass container
            expandedGlassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            expandedGlassContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            expandedGlassContainer.widthAnchor.constraint(equalToConstant: modalWidth),
            expandedGlassContainer.heightAnchor.constraint(equalToConstant: modalHeight),
            
            // Content fills glass container
            expandedContent.topAnchor.constraint(equalTo: expandedGlassContainer.glassContentView.topAnchor),
            expandedContent.leadingAnchor.constraint(equalTo: expandedGlassContainer.glassContentView.leadingAnchor),
            expandedContent.trailingAnchor.constraint(equalTo: expandedGlassContainer.glassContentView.trailingAnchor),
            expandedContent.bottomAnchor.constraint(equalTo: expandedGlassContainer.glassContentView.bottomAnchor),
        ])
    }
    
    private func setupShutterButton() {
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 35
        shutterButton.layer.borderWidth = 4
        shutterButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.3).cgColor
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        addSubview(shutterButton)
        
        // Inner circle
        let innerCircle = UIView()
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.backgroundColor = .white
        innerCircle.layer.cornerRadius = 28
        innerCircle.isUserInteractionEnabled = false
        shutterButton.addSubview(innerCircle)
        
        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: collapsedContainer.topAnchor, constant: -20),
            shutterButton.widthAnchor.constraint(equalToConstant: 70),
            shutterButton.heightAnchor.constraint(equalToConstant: 70),
            
            innerCircle.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 56),
            innerCircle.heightAnchor.constraint(equalToConstant: 56),
        ])
    }
    
    private var panGesture: UIPanGestureRecognizer!
    
    private func setupGestures() {
        // Pan gesture on pill to expand - this should be exclusive
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        modePill.addGestureRecognizer(panGesture)
        
        // Also add pan gesture to the whole collapsed container area for easier activation
        let containerPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        containerPanGesture.delegate = self
        collapsedContainer.addGestureRecognizer(containerPanGesture)
        
        // Tap outside to collapse
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)
        
        // Swipe down on modal to collapse
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        expandedGlassContainer.addGestureRecognizer(swipeDown)
        
        // Pan down on modal to collapse (more responsive than swipe)
        let modalPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleModalPan(_:)))
        modalPanGesture.delegate = self
        expandedGlassContainer.addGestureRecognizer(modalPanGesture)
    }

    
    // MARK: - Gesture Handlers
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .began:
            panStartY = 0
            morphAnimator?.stopAnimation(true)
            
        case .changed:
            // Calculate progress (0 = collapsed, 1 = expanded)
            // Negative translation = dragging up = expanding
            let rawProgress = -translation.y / expandThreshold
            let progress = applyRubberBand(rawProgress)
            
            updateMorphProgress(progress)
            currentState = .dragging(progress: progress)
            
        case .ended, .cancelled:
            // Determine final state based on progress and velocity
            let progress: CGFloat
            if case .dragging(let p) = currentState {
                progress = p
            } else {
                progress = 0
            }
            
            // Expand if dragged past 40% or velocity is fast enough upward
            let shouldExpand = progress > 0.4 || velocity.y < -500
            completeMorph(expand: shouldExpand)
            
        default:
            break
        }
    }
    
    @objc private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        
        // Only collapse if tapping outside the expanded modal
        if case .expanded = currentState {
            if !expandedGlassContainer.frame.contains(location) {
                setExpanded(false, animated: true)
            }
        }
    }
    
    @objc private func handleSwipeDown() {
        setExpanded(false, animated: true)
    }
    
    @objc private func handleModalPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        switch gesture.state {
        case .began:
            morphAnimator?.stopAnimation(true)
            
        case .changed:
            // Only respond to downward drags when expanded
            if case .expanded = currentState {
                // Positive translation = dragging down = collapsing
                let rawProgress = 1 - (translation.y / expandThreshold)
                let progress = max(0, min(1, rawProgress))
                updateMorphProgress(progress)
            }
            
        case .ended, .cancelled:
            if case .expanded = currentState {
                // Collapse if dragged down enough or velocity is fast enough downward
                let progress = 1 - (translation.y / expandThreshold)
                let shouldCollapse = progress < 0.6 || velocity.y > 500
                completeMorph(expand: !shouldCollapse)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Rubber Band Effect
    
    private func applyRubberBand(_ progress: CGFloat) -> CGFloat {
        if progress < 0 {
            // Dragging down when collapsed - resist
            let factor: CGFloat = 0.3
            return progress * factor
        } else if progress > 1 {
            // Over-dragging up when expanded - resist
            let overshoot = progress - 1
            let factor: CGFloat = 0.3
            return 1 + overshoot * factor
        }
        return progress
    }
    
    // MARK: - Morph Animation
    
    private func updateMorphProgress(_ progress: CGFloat) {
        let clampedProgress = max(0, min(1, progress))
        
        // Crossfade between collapsed and expanded
        collapsedContainer.alpha = 1 - clampedProgress
        expandedGlassContainer.alpha = clampedProgress
        
        // Scale effect on expanded modal
        let scale = 0.85 + (0.15 * clampedProgress)
        expandedGlassContainer.transform = CGAffineTransform(scaleX: scale, y: scale)
        
        // Move shutter button up as modal expands
        let shutterOffset = clampedProgress * (modalHeight - 100)
        shutterButton.transform = CGAffineTransform(translationX: 0, y: -shutterOffset)
        
        // Fade content in expanded modal
        expandedContent.alpha = clampedProgress > 0.5 ? (clampedProgress - 0.5) * 2 : 0
    }
    
    private func completeMorph(expand: Bool) {
        let targetProgress: CGFloat = expand ? 1 : 0
        
        morphAnimator = UIViewPropertyAnimator(
            duration: 0.5,
            dampingRatio: 0.85
        ) { [weak self] in
            self?.updateMorphProgress(targetProgress)
        }
        
        morphAnimator?.addCompletion { [weak self] _ in
            self?.currentState = expand ? .expanded : .collapsed
        }
        
        morphAnimator?.startAnimation()
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    // MARK: - Public API
    
    func setExpanded(_ expanded: Bool, animated: Bool) {
        if animated {
            completeMorph(expand: expanded)
        } else {
            updateMorphProgress(expanded ? 1 : 0)
            currentState = expanded ? .expanded : .collapsed
        }
    }
    
    func setLiveActive(_ active: Bool) {
        // Live button was moved to side button in MorphingGlassModal;
        // MorphingOrbModal keeps a no-op for API compatibility.
    }
    
    // MARK: - Button Actions
    
    @objc private func galleryTapped() {
        onGalleryTapped?()
    }
    
    @objc private func flashButtonTapped() {
        onFlashTapped?()
    }
    
    @objc private func shutterTapped() {
        // Animate shutter press
        UIView.animate(withDuration: 0.1, animations: {
            self.shutterButton.transform = self.shutterButton.transform.scaledBy(x: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                // Restore to current transform (may include translation)
                if case .expanded = self.currentState {
                    let shutterOffset = self.modalHeight - 100
                    self.shutterButton.transform = CGAffineTransform(translationX: 0, y: -shutterOffset)
                } else {
                    self.shutterButton.transform = .identity
                }
            }
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onShutterTapped?()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MorphingOrbModal: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only receive background taps when expanded
        if gestureRecognizer is UITapGestureRecognizer {
            if case .expanded = currentState {
                return true
            }
            return false
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't allow our pan gestures to work simultaneously with other pan/scroll gestures
        if gestureRecognizer is UIPanGestureRecognizer {
            // Block other pan gestures and scroll views from interfering
            if otherGestureRecognizer is UIPanGestureRecognizer || 
               otherGestureRecognizer.view is UIScrollView {
                return false
            }
        }
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Our pan gestures should take priority over other gestures
        if gestureRecognizer is UIPanGestureRecognizer {
            return true
        }
        return false
    }
}
