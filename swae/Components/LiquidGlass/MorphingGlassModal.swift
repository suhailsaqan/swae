import UIKit

/// iOS 26 Camera-style morphing glass modal
/// The glass selector over PHOTO morphs into the full expanded modal
class MorphingGlassModal: UIView {
    
    // MARK: - State
    
    enum State {
        case collapsed
        case expanded
        case dragging(progress: CGFloat)
    }
    
    private(set) var currentState: State = .collapsed
    
    // MARK: - Layout Constants
    
    // Collapsed pill dimensions
    private let pillWidth: CGFloat = 220
    private let pillHeight: CGFloat = 53
    private let pillCornerRadius: CGFloat = 26
    
    // Bottom safe area padding (clearance from home indicator)
    // Increased from 25 to 35 for easier tapping without hitting home indicator
    private let bottomPadding: CGFloat = 35
    
    // Expanded modal dimensions
    private var modalWidth: CGFloat { UIScreen.main.bounds.width - 28 }
    private let buttonGridHeight: CGFloat = 282
    private let maxModalHeight: CGFloat = 560
    private var currentExpandedHeight: CGFloat = 282
    private let modalCornerRadius: CGFloat = 44
    
    // Button sizes
    private let sideButtonSize: CGFloat = 50
    
    // Keyboard tracking
    private var currentKeyboardHeight: CGFloat = 0
    
    // Landscape support
    var isLandscape: Bool = false {
        didSet {
            guard isLandscape != oldValue else { return }
            // Stop any in-progress morph animation to prevent conflicts
            morphAnimator?.stopAnimation(true)
            morphAnimator = nil
            // Snap to collapsed immediately (no animation) to avoid race with reconfigure
            if isExpanded {
                updateMorphProgress(0)
                currentState = .collapsed
                onModalStateChanged?(false)
            }
            reconfigureForOrientation()
        }
    }
    private let trailingPadding: CGFloat = 35
    
    /// When true, the control bar is on the leading (left) side in landscape.
    /// The glass expands rightward instead of leftward.
    var controlBarOnLeading: Bool = false {
        didSet {
            guard controlBarOnLeading != oldValue, isLandscape else { return }
            // Control bar side changed while in landscape — rebuild constraints
            morphAnimator?.stopAnimation(true)
            morphAnimator = nil
            if isExpanded {
                updateMorphProgress(0)
                currentState = .collapsed
                onModalStateChanged?(false)
            }
            reconfigureForOrientation()
        }
    }
    
    // Landscape constraint references (swapped from portrait)
    private var glassTrailingConstraint: NSLayoutConstraint?
    private var glassLeadingConstraint: NSLayoutConstraint?
    private var glassCenterYConstraint: NSLayoutConstraint?
    private var glassCenterXConstraint: NSLayoutConstraint?
    
    // Side button landscape constraints
    private var settingsPortraitConstraints: [NSLayoutConstraint] = []
    private var settingsLandscapeConstraints: [NSLayoutConstraint] = []
    private var flipPortraitConstraints: [NSLayoutConstraint] = []
    private var flipLandscapeConstraints: [NSLayoutConstraint] = []
    private var glassPortraitConstraints: [NSLayoutConstraint] = []
    private var glassLandscapeConstraints: [NSLayoutConstraint] = []
    
    // Scene scroll view portrait/landscape constraints
    private var sceneScrollPortraitConstraints: [NSLayoutConstraint] = []
    private var sceneScrollLandscapeConstraints: [NSLayoutConstraint] = []
    
    // Grab handle portrait/landscape constraints
    private var grabHandlePortraitConstraints: [NSLayoutConstraint] = []
    private var grabHandleLandscapeConstraints: [NSLayoutConstraint] = []
    
    // MARK: - Views
    
    // The morphing glass - this is the KEY element that transforms
    private var morphingGlass: GlassContainerView!
    
    // Scene selector (horizontal scroll) - replaces VIDEO/PHOTO labels
    private let sceneScrollView = UIScrollView()
    private let sceneStackView = UIStackView()
    private var sceneLabels: [UILabel] = []
    private var addSceneButtonContainer: UIView?
    private var selectedSceneIndex: Int = 0

    // Onboarding CTA label (shown when stream not configured)
    private let setupCTALabel = UILabel()
    
    // Side buttons (settings, Go Live) - these stay in place
    private(set) var settingsGlass: GlassContainerView!
    private(set) var flipGlass: GlassContainerView!
    
    // Grab handle bar (hint to swipe up)
    private let grabHandle = UIView()
    
    // Expanded content (fades in during morph)
    private let expandedScrollView = UIScrollView()
    private let expandedContent = ExpandedControlsModal()
    
    // MARK: - Animation
    
    private var morphAnimator: UIViewPropertyAnimator?
    private let expandThreshold: CGFloat = 120
    
    // Gesture state
    private enum GestureDirection {
        case unknown
        case horizontal  // Scene scrolling
        case vertical    // Modal morphing
    }
    private var gestureDirection: GestureDirection = .unknown
    private var gestureStartPoint: CGPoint = .zero
    private let directionLockThreshold: CGFloat = 10 // Pixels before locking direction
    private var gestureStartProgress: CGFloat = 0 // Progress when gesture began (0 = collapsed, 1 = expanded)
    
    // Constraints that change during morph
    private var glassWidthConstraint: NSLayoutConstraint!
    private var glassHeightConstraint: NSLayoutConstraint!
    private var glassBottomConstraint: NSLayoutConstraint!
    
    // Live countdown state
    private var countdownTimer: Timer?
    private var countdownRemaining: Int = 0
    private var isCountingDown: Bool = false
    private var countdownLabel: UILabel?
    private var countdownRingLayer: CAShapeLayer?
    private var isCurrentlyLive: Bool = false
    private var loadingSpinner: UIActivityIndicatorView?
    
    // MARK: - Callbacks
    
    var onSceneSelected: ((Int) -> Void)? // Called when user selects a scene by index
    var onSettingsTapped: ((_ sourceView: UIView) -> Void)?
    var onModalStateChanged: ((Bool) -> Void)? // true = expanded
    
    var onLiveTapped: (() -> Void)?
    var isStreamConfigured: (() -> Bool)?
    var onOpenSetup: (() -> Void)?
    var onPreStreamReview: (() -> Void)?
    var onForcePreStreamReview: (() -> Void)?
    var onFlashTapped: (() -> Void)? {
        get { expandedContent.onFlashTapped }
        set { expandedContent.onFlashTapped = newValue }
    }
    var onRecordTapped: (() -> Void)? {
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
    var onQualityTapped: (() -> Void)? {
        get { expandedContent.onQualityTapped }
        set { expandedContent.onQualityTapped = newValue }
    }
    var onNightModeTapped: (() -> Void)? {
        get { expandedContent.onNightModeTapped }
        set { expandedContent.onNightModeTapped = newValue }
    }
    var onPortraitTapped: (() -> Void)? {
        get { expandedContent.onPortraitTapped }
        set { expandedContent.onPortraitTapped = newValue }
    }
    
    var onWidgetsTapped: (() -> Void)? {
        get { expandedContent.onWidgetsTapped }
        set { expandedContent.onWidgetsTapped = newValue }
    }
    
    var onWidgetTypeSelected: ((SettingsWidgetType) -> Void)? {
        get { expandedContent.onWidgetTypeSelected }
        set { expandedContent.onWidgetTypeSelected = newValue }
    }
    
    var onTemplateSelected: ((InlineAddWidgetView.WidgetTemplate) -> Void)? {
        get { expandedContent.onTemplateSelected }
        set { expandedContent.onTemplateSelected = newValue }
    }
    
    var onQuickConfigDone: ((String) -> Void)? {
        get { expandedContent.onQuickConfigDone }
        set { expandedContent.onQuickConfigDone = newValue }
    }
    
    var onQuickConfigFullSettings: (() -> Void)? {
        get { expandedContent.onQuickConfigFullSettings }
        set { expandedContent.onQuickConfigFullSettings = newValue }
    }
    
    var onWidgetTapped: ((UUID) -> Void)? {
        get { expandedContent.onWidgetTapped }
        set { expandedContent.onWidgetTapped = newValue }
    }
    
    var onWidgetRowTapped: ((UUID) -> Void)? {
        get { expandedContent.onWidgetRowTapped }
        set { expandedContent.onWidgetRowTapped = newValue }
    }
    
    var onWidgetDuplicate: ((UUID) -> Void)? {
        get { expandedContent.onWidgetDuplicate }
        set { expandedContent.onWidgetDuplicate = newValue }
    }
    
    var onWidgetDelete: ((UUID) -> Void)? {
        get { expandedContent.onWidgetDelete }
        set { expandedContent.onWidgetDelete = newValue }
    }

    var onMuteTapped: (() -> Void)? {
        get { expandedContent.onMuteTapped }
        set { expandedContent.onMuteTapped = newValue }
    }

    var onCollabTapped: (() -> Void)? {
        get { expandedContent.onCollabTapped }
        set { expandedContent.onCollabTapped = newValue }
    }

    var onCollabInvite: ((String) -> Void)? {
        get { expandedContent.onCollabInvite }
        set { expandedContent.onCollabInvite = newValue }
    }

    var onCollabAccept: (() -> Void)? {
        get { expandedContent.onCollabAccept }
        set { expandedContent.onCollabAccept = newValue }
    }

    var onCollabDecline: (() -> Void)? {
        get { expandedContent.onCollabDecline }
        set { expandedContent.onCollabDecline = newValue }
    }

    var onCollabEndCall: (() -> Void)? {
        get { expandedContent.onCollabEndCall }
        set { expandedContent.onCollabEndCall = newValue }
    }

    var onCollabMuteTapped: (() -> Void)? {
        get { expandedContent.onCollabMuteTapped }
        set { expandedContent.onCollabMuteTapped = newValue }
    }

    var onCollabWidgetsTapped: (() -> Void)? {
        get { expandedContent.onCollabWidgetsTapped }
        set { expandedContent.onCollabWidgetsTapped = newValue }
    }

    var onCollabSkipPipTapped: (() -> Void)? {
        get { expandedContent.onCollabSkipPipTapped }
        set { expandedContent.onCollabSkipPipTapped = newValue }
    }

    var onCollabVolumeChanged: ((Float) -> Void)? {
        get { expandedContent.onCollabVolumeChanged }
        set { expandedContent.onCollabVolumeChanged = newValue }
    }

    var onInfoBarTapped: ((_ sourceView: UIView) -> Void)? {
        get { expandedContent.statusBar.onInfoBarTapped }
        set { expandedContent.statusBar.onInfoBarTapped = newValue }
    }

    var onSettingsGearTapped: ((_ sourceView: UIView) -> Void)? {
        get { expandedContent.statusBar.onSettingsGearTapped }
        set { expandedContent.statusBar.onSettingsGearTapped = newValue }
    }

    var onSetupStreamTapped: ((_ sourceView: UIView) -> Void)? {
        get { expandedContent.statusBar.onSetupStreamTapped }
        set { expandedContent.statusBar.onSetupStreamTapped = newValue }
    }

    var onMicCardTapped: (() -> Void)? {
        get { expandedContent.onMicCardTapped }
        set { expandedContent.onMicCardTapped = newValue }
    }

    var onMicSelected: ((String) -> Void)? {
        get { expandedContent.onMicSelected }
        set { expandedContent.onMicSelected = newValue }
    }

    var onSceneButtonTapped: (() -> Void)? {
        get { expandedContent.onSceneButtonTapped }
        set { expandedContent.onSceneButtonTapped = newValue }
    }

    var onSceneWidgetToggled: ((UUID, Bool) -> Void)? {
        get { expandedContent.onSceneWidgetToggled }
        set { expandedContent.onSceneWidgetToggled = newValue }
    }

    var onSceneAddWidgetTapped: (() -> Void)? {
        get { expandedContent.onSceneAddWidgetTapped }
        set { expandedContent.onSceneAddWidgetTapped = newValue }
    }

    var onSceneCameraTapped: (() -> Void)? {
        get { expandedContent.onSceneCameraTapped }
        set { expandedContent.onSceneCameraTapped = newValue }
    }

    var onSceneCameraSelected: ((String) -> Void)? {
        get { expandedContent.onSceneCameraSelected }
        set { expandedContent.onSceneCameraSelected = newValue }
    }

    var onSceneMicTapped: (() -> Void)? {
        get { expandedContent.onSceneMicTapped }
        set { expandedContent.onSceneMicTapped = newValue }
    }

    var onSceneMicSelected: ((String) -> Void)? {
        get { expandedContent.onSceneMicSelected }
        set { expandedContent.onSceneMicSelected = newValue }
    }

    var onSceneAddSceneTapped: (() -> Void)? {
        get { expandedContent.onSceneAddSceneTapped }
        set { expandedContent.onSceneAddSceneTapped = newValue }
    }

    var onSceneRenamed: ((String) -> Void)? {
        get { expandedContent.onSceneRenamed }
        set { expandedContent.onSceneRenamed = newValue }
    }

    var onCreateScene: ((String, String) -> Void)? {
        get { expandedContent.onCreateScene }
        set { expandedContent.onCreateScene = newValue }
    }

    var onCreateSceneFullConfig: (() -> Void)? {
        get { expandedContent.onCreateSceneFullConfig }
        set { expandedContent.onCreateSceneFullConfig = newValue }
    }

    var onStreamDetailTopUp: (() -> Void)? {
        get { expandedContent.onStreamDetailTopUp }
        set { expandedContent.onStreamDetailTopUp = newValue }
    }

    var onStreamDetailSettings: (() -> Void)? {
        get { expandedContent.onStreamDetailSettings }
        set { expandedContent.onStreamDetailSettings = newValue }
    }

    var onStreamDetailRefreshBalance: (() -> Void)? {
        get { expandedContent.onStreamDetailRefreshBalance }
        set { expandedContent.onStreamDetailRefreshBalance = newValue }
    }

    var onStreamDetailUpdateStream: (() -> Void)? {
        get { expandedContent.onStreamDetailUpdateStream }
        set { expandedContent.onStreamDetailUpdateStream = newValue }
    }

    var onStreamDetailAutoTopupDisable: (() -> Void)? {
        get { expandedContent.onStreamDetailAutoTopupDisable }
        set { expandedContent.onStreamDetailAutoTopupDisable = newValue }
    }

    var onStreamDetailAutoTopupEnable: (() -> Void)? {
        get { expandedContent.onStreamDetailAutoTopupEnable }
        set { expandedContent.onStreamDetailAutoTopupEnable = newValue }
    }

    var onStreamDetailTitleChanged: ((String) -> Void)? {
        get { expandedContent.onStreamDetailTitleChanged }
        set { expandedContent.onStreamDetailTitleChanged = newValue }
    }

    var onStreamDetailDescriptionChanged: ((String) -> Void)? {
        get { expandedContent.onStreamDetailDescriptionChanged }
        set { expandedContent.onStreamDetailDescriptionChanged = newValue }
    }

    var onStreamDetailTagsChanged: ((String) -> Void)? {
        get { expandedContent.onStreamDetailTagsChanged }
        set { expandedContent.onStreamDetailTagsChanged = newValue }
    }

    var onStreamDetailNSFWChanged: ((Bool) -> Void)? {
        get { expandedContent.onStreamDetailNSFWChanged }
        set { expandedContent.onStreamDetailNSFWChanged = newValue }
    }

    var onStreamDetailPublicChanged: ((Bool) -> Void)? {
        get { expandedContent.onStreamDetailPublicChanged }
        set { expandedContent.onStreamDetailPublicChanged = newValue }
    }

    var onStreamDetailProtocolChanged: ((Int) -> Void)? {
        get { expandedContent.onStreamDetailProtocolChanged }
        set { expandedContent.onStreamDetailProtocolChanged = newValue }
    }

    var onStreamDetailResolutionChanged: ((Int) -> Void)? {
        get { expandedContent.onStreamDetailResolutionChanged }
        set { expandedContent.onStreamDetailResolutionChanged = newValue }
    }

    var onStreamDetailFpsChanged: ((Int) -> Void)? {
        get { expandedContent.onStreamDetailFpsChanged }
        set { expandedContent.onStreamDetailFpsChanged = newValue }
    }

    var onStreamDetailAudioBitrateChanged: ((Int) -> Void)? {
        get { expandedContent.onStreamDetailAudioBitrateChanged }
        set { expandedContent.onStreamDetailAudioBitrateChanged = newValue }
    }

    var onStreamDetailAdaptiveResolutionChanged: ((Bool) -> Void)? {
        get { expandedContent.onStreamDetailAdaptiveResolutionChanged }
        set { expandedContent.onStreamDetailAdaptiveResolutionChanged = newValue }
    }

    var onStreamDetailLowLightBoostChanged: ((Bool) -> Void)? {
        get { expandedContent.onStreamDetailLowLightBoostChanged }
        set { expandedContent.onStreamDetailLowLightBoostChanged = newValue }
    }

    var onStreamDetailPortraitToggled: ((Bool) -> Void)? {
        get { expandedContent.onStreamDetailPortraitToggled }
        set { expandedContent.onStreamDetailPortraitToggled = newValue }
    }

    var onStreamDetailBackgroundStreamingChanged: ((Bool) -> Void)? {
        get { expandedContent.onStreamDetailBackgroundStreamingChanged }
        set { expandedContent.onStreamDetailBackgroundStreamingChanged = newValue }
    }

    var onStreamDetailAutoRecordChanged: ((Bool) -> Void)? {
        get { expandedContent.onStreamDetailAutoRecordChanged }
        set { expandedContent.onStreamDetailAutoRecordChanged = newValue }
    }

    /// Fires at the START of expand animation (before buttons are visible)
    var onExpandStarted: (() -> Void)?
    
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
        overrideUserInterfaceStyle = .dark
        
        setupSideButtons()
        setupMorphingGlass() // Modal on top
        setupSceneSelector()
        setupGrabHandle()
        setupExpandedContent()
        setupGestures()
        
        // Ensure grab handle is visible above other content
        morphingGlass.glassContentView.bringSubviewToFront(grabHandle)
        
        // Start collapsed
        setCollapsedState(animated: false)
        
        // Show onboarding CTA if stream not yet configured
        updateOnboardingState()
        
        // Keyboard observation
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Landscape Reconfiguration
    
    private func reconfigureForOrientation() {
        // Deactivate all orientation-specific constraints
        NSLayoutConstraint.deactivate(settingsPortraitConstraints)
        NSLayoutConstraint.deactivate(flipPortraitConstraints)
        NSLayoutConstraint.deactivate(glassPortraitConstraints)
        NSLayoutConstraint.deactivate(sceneScrollPortraitConstraints)
        NSLayoutConstraint.deactivate(grabHandlePortraitConstraints)
        NSLayoutConstraint.deactivate(settingsLandscapeConstraints)
        NSLayoutConstraint.deactivate(flipLandscapeConstraints)
        NSLayoutConstraint.deactivate(glassLandscapeConstraints)
        NSLayoutConstraint.deactivate(sceneScrollLandscapeConstraints)
        NSLayoutConstraint.deactivate(grabHandleLandscapeConstraints)
        
        if isLandscape {
            // Swap pill dimensions: horizontal pill → vertical pill
            glassWidthConstraint.constant = pillHeight  // 53
            glassHeightConstraint.constant = pillWidth   // 220
            
            // Build landscape constraints based on which side the control bar is on.
            // When controlBarOnLeading, the glass anchors to leadingAnchor and expands rightward.
            // When on trailing (default), it anchors to trailingAnchor and expands leftward.
            if controlBarOnLeading {
                glassLandscapeConstraints = [glassCenterYConstraint!, glassLeadingConstraint!]
                settingsLandscapeConstraints = [
                    settingsGlass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: trailingPadding),
                    settingsGlass.topAnchor.constraint(equalTo: topAnchor, constant: 24),
                ]
                flipLandscapeConstraints = [
                    flipGlass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: trailingPadding),
                    flipGlass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
                ]
                grabHandleLandscapeConstraints = [
                    grabHandle.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor, constant: -5),
                    grabHandle.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor),
                    grabHandle.widthAnchor.constraint(equalToConstant: 5),
                    grabHandle.heightAnchor.constraint(equalToConstant: 36),
                ]
                sceneScrollLandscapeConstraints = [
                    sceneScrollView.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor),
                    sceneScrollView.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor),
                    sceneScrollView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: 4),
                    sceneScrollView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor, constant: -4),
                    sceneStackView.widthAnchor.constraint(equalTo: sceneScrollView.frameLayoutGuide.widthAnchor),
                ]
            } else {
                glassLandscapeConstraints = [glassCenterYConstraint!, glassTrailingConstraint!]
                settingsLandscapeConstraints = [
                    settingsGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingPadding),
                    settingsGlass.topAnchor.constraint(equalTo: topAnchor, constant: 24),
                ]
                flipLandscapeConstraints = [
                    flipGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingPadding),
                    flipGlass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
                ]
                grabHandleLandscapeConstraints = [
                    grabHandle.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: 5),
                    grabHandle.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor),
                    grabHandle.widthAnchor.constraint(equalToConstant: 5),
                    grabHandle.heightAnchor.constraint(equalToConstant: 36),
                ]
                sceneScrollLandscapeConstraints = [
                    sceneScrollView.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor),
                    sceneScrollView.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor),
                    sceneScrollView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: 4),
                    sceneScrollView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor, constant: -4),
                    sceneStackView.widthAnchor.constraint(equalTo: sceneScrollView.frameLayoutGuide.widthAnchor),
                ]
            }
            
            NSLayoutConstraint.activate(settingsLandscapeConstraints)
            NSLayoutConstraint.activate(flipLandscapeConstraints)
            NSLayoutConstraint.activate(glassLandscapeConstraints)
            NSLayoutConstraint.activate(sceneScrollLandscapeConstraints)
            NSLayoutConstraint.activate(grabHandleLandscapeConstraints)
            
            // Scene selector: horizontal → vertical
            sceneStackView.axis = .vertical
            sceneStackView.alignment = .fill
            sceneScrollView.showsVerticalScrollIndicator = false
        } else {
            // Restore pill dimensions
            glassWidthConstraint.constant = pillWidth   // 220
            glassHeightConstraint.constant = pillHeight  // 53
            
            NSLayoutConstraint.activate(settingsPortraitConstraints)
            NSLayoutConstraint.activate(flipPortraitConstraints)
            NSLayoutConstraint.activate(glassPortraitConstraints)
            NSLayoutConstraint.activate(sceneScrollPortraitConstraints)
            NSLayoutConstraint.activate(grabHandlePortraitConstraints)
            
            // Scene selector: vertical → horizontal
            sceneStackView.axis = .horizontal
            sceneStackView.alignment = .center
        }
        
        // Recreate scene labels from scratch for the new orientation.
        // This avoids accumulated constraint issues from switching orientations.
        let scenes = sceneLabels.map { $0.text ?? "" }
        if !scenes.isEmpty {
            setScenes(scenes, selectedIndex: selectedSceneIndex)
        }
        
        UIView.animate(withDuration: 0.3) {
            self.layoutIfNeeded()
        }
    }
    
    private func updateSceneLabelSizes() {
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let pillLandscapeWidth = pillHeight - 8
        let maxLabelWidth: CGFloat = 80
        
        for label in sceneLabels {
            // Fully remove old size constraints
            let widthC = label.constraints.filter { $0.firstAttribute == .width }
            let heightC = label.constraints.filter { $0.firstAttribute == .height }
            widthC.forEach { label.removeConstraint($0) }
            heightC.forEach { label.removeConstraint($0) }
            
            // Same font in both orientations
            label.font = font
            label.adjustsFontSizeToFitWidth = false
            label.lineBreakMode = .byClipping
            
            if isLandscape {
                label.heightAnchor.constraint(equalToConstant: 44).isActive = true
                
                let textWidth = ((label.text ?? "") as NSString).size(withAttributes: [.font: font]).width
                let availableWidth = pillLandscapeWidth
                
                if textWidth > availableWidth {
                    // Text overflows — left-align and fade out the right edge
                    label.textAlignment = .left
                    let gradientLayer = CAGradientLayer()
                    gradientLayer.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
                    gradientLayer.locations = [0.0, 0.7, 1.0]
                    gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
                    gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
                    gradientLayer.frame = CGRect(x: 0, y: 0, width: pillLandscapeWidth, height: 44)
                    label.layer.mask = gradientLayer
                } else {
                    // Text fits — center it, no mask
                    label.textAlignment = .center
                    label.layer.mask = nil
                }
            } else {
                label.textAlignment = .center
                label.layer.mask = nil
                let textWidth = ((label.text ?? "") as NSString).size(withAttributes: [.font: font]).width
                let minWidth = pillWidth / CGFloat(min(sceneLabels.count, 3))
                let labelWidth = min(max(textWidth + 24, minWidth), maxLabelWidth)
                label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
                
                if textWidth + 24 > maxLabelWidth {
                    let gradientLayer = CAGradientLayer()
                    gradientLayer.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
                    gradientLayer.locations = [0.0, 0.7, 1.0]
                    gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
                    gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
                    gradientLayer.frame = CGRect(x: 0, y: 0, width: labelWidth, height: 30)
                    label.layer.mask = gradientLayer
                }
            }
        }
        
        // Size the add scene "+" button
        if let plusContainer = addSceneButtonContainer {
            let widthC = plusContainer.constraints.filter { $0.firstAttribute == .width && $0.firstItem === plusContainer }
            let heightC = plusContainer.constraints.filter { $0.firstAttribute == .height && $0.firstItem === plusContainer }
            widthC.forEach { plusContainer.removeConstraint($0) }
            heightC.forEach { plusContainer.removeConstraint($0) }
            
            let size: CGFloat = 26
            plusContainer.widthAnchor.constraint(equalToConstant: size).isActive = true
            plusContainer.heightAnchor.constraint(equalToConstant: size).isActive = true
            plusContainer.layer.cornerRadius = size / 2
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.scrollToSelectedScene(animated: false)
        }
    }

    
    private func setupSideButtons() {
        // Settings button (left) - liquid glass circle
        settingsGlass = GlassFactory.makeGlassView(cornerRadius: sideButtonSize / 2)
        settingsGlass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsGlass)
        
        let settingsIcon = UIImageView()
        settingsIcon.translatesAutoresizingMaskIntoConstraints = false
        settingsIcon.image = UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        settingsIcon.tintColor = .white
        settingsIcon.contentMode = .scaleAspectFit
        settingsGlass.glassContentView.addSubview(settingsIcon)
        
        let settingsTap = UITapGestureRecognizer(target: self, action: #selector(settingsTapped))
        settingsGlass.addGestureRecognizer(settingsTap)
        
        // Live button (right) - liquid glass circle
        flipGlass = GlassFactory.makeGlassView(cornerRadius: sideButtonSize / 2)
        flipGlass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(flipGlass)
        
        let liveIcon = UIImageView()
        liveIcon.translatesAutoresizingMaskIntoConstraints = false
        liveIcon.image = UIImage(systemName: "record.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium))
        liveIcon.tintColor = .white
        liveIcon.contentMode = .scaleAspectFit
        liveIcon.tag = 100 // Tag for finding later to update tint
        flipGlass.glassContentView.addSubview(liveIcon)
        
        let liveTap = UITapGestureRecognizer(target: self, action: #selector(liveButtonTapped))
        flipGlass.addGestureRecognizer(liveTap)

        let liveLongPress = UILongPressGestureRecognizer(target: self, action: #selector(liveButtonLongPressed(_:)))
        liveLongPress.minimumPressDuration = 0.5
        flipGlass.addGestureRecognizer(liveLongPress)
        
        NSLayoutConstraint.activate([
            settingsIcon.centerXAnchor.constraint(equalTo: settingsGlass.glassContentView.centerXAnchor),
            settingsIcon.centerYAnchor.constraint(equalTo: settingsGlass.glassContentView.centerYAnchor),
            
            liveIcon.centerXAnchor.constraint(equalTo: flipGlass.glassContentView.centerXAnchor),
            liveIcon.centerYAnchor.constraint(equalTo: flipGlass.glassContentView.centerYAnchor),
            
            settingsGlass.widthAnchor.constraint(equalToConstant: sideButtonSize),
            settingsGlass.heightAnchor.constraint(equalToConstant: sideButtonSize),
            flipGlass.widthAnchor.constraint(equalToConstant: sideButtonSize),
            flipGlass.heightAnchor.constraint(equalToConstant: sideButtonSize),
        ])
        
        // Portrait: settings left-bottom, flip right-bottom
        settingsPortraitConstraints = [
            settingsGlass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            settingsGlass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomPadding),
        ]
        flipPortraitConstraints = [
            flipGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            flipGlass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomPadding),
        ]
        
        // Landscape: settings top-right, flip bottom-right
        settingsLandscapeConstraints = [
            settingsGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingPadding),
            settingsGlass.topAnchor.constraint(equalTo: topAnchor, constant: 24),
        ]
        flipLandscapeConstraints = [
            flipGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingPadding),
            flipGlass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ]
        
        NSLayoutConstraint.activate(settingsPortraitConstraints)
        NSLayoutConstraint.activate(flipPortraitConstraints)
    }
    
    private func setupMorphingGlass() {
        // THE morphing glass element - starts as selector, grows to modal
        morphingGlass = GlassFactory.makeGlassView(cornerRadius: pillCornerRadius)
        morphingGlass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(morphingGlass)
        
        // Create constraints that we'll animate
        glassWidthConstraint = morphingGlass.widthAnchor.constraint(equalToConstant: pillWidth)
        glassHeightConstraint = morphingGlass.heightAnchor.constraint(equalToConstant: pillHeight)
        glassBottomConstraint = morphingGlass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomPadding)
        glassCenterXConstraint = morphingGlass.centerXAnchor.constraint(equalTo: centerXAnchor)
        
        // Portrait glass constraints
        glassPortraitConstraints = [
            glassCenterXConstraint!,
            glassBottomConstraint,
        ]
        
        // Landscape glass constraints (created but not activated — chosen dynamically based on controlBarOnLeading)
        glassCenterYConstraint = morphingGlass.centerYAnchor.constraint(equalTo: centerYAnchor)
        glassTrailingConstraint = morphingGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingPadding)
        glassLeadingConstraint = morphingGlass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: trailingPadding)
        // Default landscape constraints (trailing side) — rebuilt in reconfigureForOrientation
        glassLandscapeConstraints = [
            glassCenterYConstraint!,
            glassTrailingConstraint!,
        ]
        
        NSLayoutConstraint.activate([
            glassWidthConstraint,
            glassHeightConstraint,
        ])
        NSLayoutConstraint.activate(glassPortraitConstraints)
    }
    
    private func setupSceneSelector() {
        // Scroll view for scenes
        sceneScrollView.translatesAutoresizingMaskIntoConstraints = false
        sceneScrollView.showsHorizontalScrollIndicator = false
        sceneScrollView.showsVerticalScrollIndicator = false
        sceneScrollView.clipsToBounds = true
        sceneScrollView.decelerationRate = .fast
        sceneScrollView.delegate = self
        sceneScrollView.delaysContentTouches = false
        sceneScrollView.canCancelContentTouches = true
        morphingGlass.glassContentView.addSubview(sceneScrollView)
        
        // Stack view to hold scene labels
        sceneStackView.translatesAutoresizingMaskIntoConstraints = false
        sceneStackView.axis = .horizontal
        sceneStackView.alignment = .center
        sceneStackView.distribution = .fill
        sceneStackView.spacing = 0
        sceneScrollView.addSubview(sceneStackView)

        // Onboarding CTA label (hidden by default)
        setupCTALabel.translatesAutoresizingMaskIntoConstraints = false
        setupCTALabel.text = "Tap to Set Up Stream"
        setupCTALabel.font = .systemFont(ofSize: 14, weight: .semibold)
        setupCTALabel.textColor = .systemYellow
        setupCTALabel.textAlignment = .center
        setupCTALabel.isUserInteractionEnabled = true
        setupCTALabel.isHidden = true
        morphingGlass.glassContentView.addSubview(setupCTALabel)

        let ctaTap = UITapGestureRecognizer(target: self, action: #selector(setupCTATapped))
        setupCTALabel.addGestureRecognizer(ctaTap)
        
        // Always-active constraints: stack view pinned to scroll view content guide
        NSLayoutConstraint.activate([
            sceneStackView.leadingAnchor.constraint(equalTo: sceneScrollView.contentLayoutGuide.leadingAnchor),
            sceneStackView.trailingAnchor.constraint(equalTo: sceneScrollView.contentLayoutGuide.trailingAnchor),
            sceneStackView.topAnchor.constraint(equalTo: sceneScrollView.contentLayoutGuide.topAnchor),
            sceneStackView.bottomAnchor.constraint(equalTo: sceneScrollView.contentLayoutGuide.bottomAnchor),

            // CTA label centered in pill
            setupCTALabel.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            setupCTALabel.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor),
        ])
        
        // Portrait: scroll view fills pill width, fixed height, horizontal scrolling
        sceneScrollPortraitConstraints = [
            sceneScrollView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor),
            sceneScrollView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor),
            sceneScrollView.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor),
            sceneScrollView.heightAnchor.constraint(equalToConstant: pillHeight),
            // Cross-axis: stack view height = scroll view frame height (horizontal scroll)
            sceneStackView.heightAnchor.constraint(equalTo: sceneScrollView.frameLayoutGuide.heightAnchor),
        ]
        
        // Landscape: scroll view fills pill height, narrower width with padding, vertical scrolling
        sceneScrollLandscapeConstraints = [
            sceneScrollView.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor),
            sceneScrollView.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor),
            sceneScrollView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: 4),
            sceneScrollView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor, constant: -4),
            // Cross-axis: stack view width = scroll view frame width (vertical scroll)
            sceneStackView.widthAnchor.constraint(equalTo: sceneScrollView.frameLayoutGuide.widthAnchor),
        ]
        
        // Activate portrait by default
        NSLayoutConstraint.activate(sceneScrollPortraitConstraints)
    }
    
    /// Update scenes displayed in the pill
    /// - Parameters:
    ///   - scenes: Array of scene names to display
    ///   - selectedIndex: Currently selected scene index
    func setScenes(_ scenes: [String], selectedIndex: Int) {
        // Clear existing labels and add button
        sceneLabels.forEach { $0.removeFromSuperview() }
        sceneLabels.removeAll()
        addSceneButtonContainer?.removeFromSuperview()
        addSceneButtonContainer = nil
        
        // Create labels for each scene
        for (index, sceneName) in scenes.enumerated() {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = sceneName.uppercased()
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textAlignment = .center
            label.isUserInteractionEnabled = true
            label.lineBreakMode = .byClipping
            
            // Highlight selected scene
            if index == selectedIndex {
                label.textColor = .systemYellow
            } else {
                label.textColor = UIColor(white: 1.0, alpha: 0.6)
            }
            
            // Add tap gesture
            let tap = UITapGestureRecognizer(target: self, action: #selector(sceneLabelTapped(_:)))
            label.addGestureRecognizer(tap)
            label.tag = index
            
            sceneStackView.addArrangedSubview(label)
            sceneLabels.append(label)
        }
        
        // Add "+" button at the end with circular background
        // Use UILabel + UITapGestureRecognizer (same pattern as scene labels)
        // to ensure taps are recognized inside the scroll view
        let plusLabel = UILabel()
        plusLabel.translatesAutoresizingMaskIntoConstraints = false
        plusLabel.text = "+"
        plusLabel.font = .systemFont(ofSize: 20, weight: .medium)
        plusLabel.textAlignment = .center
        plusLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        // Nudge text up slightly for optical centering in the circle
        let attrStr = NSAttributedString(string: "+", attributes: [
            .font: UIFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: UIColor(white: 1.0, alpha: 0.6),
            .baselineOffset: 3
        ])
        plusLabel.attributedText = attrStr
        plusLabel.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        plusLabel.layer.cornerRadius = 12
        plusLabel.clipsToBounds = true
        plusLabel.isUserInteractionEnabled = true
        
        let plusTap = UITapGestureRecognizer(target: self, action: #selector(addSceneButtonTapped))
        plusLabel.addGestureRecognizer(plusTap)
        
        sceneStackView.addArrangedSubview(plusLabel)
        
        // Add trailing spacer for right padding (matches left padding of first scene)
        let trailingSpacer = UIView()
        trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
        trailingSpacer.widthAnchor.constraint(equalToConstant: 8).isActive = true
        sceneStackView.addArrangedSubview(trailingSpacer)
        
        addSceneButtonContainer = plusLabel
        
        // Apply correct size constraints for current orientation
        updateSceneLabelSizes()
        
        selectedSceneIndex = selectedIndex
        
        // Scroll to selected scene after layout
        DispatchQueue.main.async { [weak self] in
            self?.scrollToSelectedScene(animated: false)
        }

        // Refresh onboarding CTA visibility now that scenes are set
        updateOnboardingState()
    }

    /// Update the collapsed pill to show onboarding CTA or scene labels
    func updateOnboardingState() {
        let configured = isStreamConfigured?() ?? true
        setupCTALabel.isHidden = configured
        sceneScrollView.isHidden = !configured
    }
    
    private func scrollToSelectedScene(animated: Bool) {
        guard selectedSceneIndex < sceneLabels.count else { return }
        let label = sceneLabels[selectedSceneIndex]
        
        if isLandscape {
            // Vertical scrolling in landscape
            let labelCenter = label.frame.midY
            let scrollViewHeight = sceneScrollView.bounds.height
            let maxOffset = max(0, sceneScrollView.contentSize.height - scrollViewHeight)
            let targetOffset = max(0, min(labelCenter - scrollViewHeight / 2, maxOffset))
            sceneScrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: animated)
        } else {
            // Horizontal scrolling in portrait
            let labelCenter = label.frame.midX
            let scrollViewWidth = sceneScrollView.bounds.width
            let maxOffset = max(0, sceneScrollView.contentSize.width - scrollViewWidth)
            let targetOffset = max(0, min(labelCenter - scrollViewWidth / 2, maxOffset))
            sceneScrollView.setContentOffset(CGPoint(x: targetOffset, y: 0), animated: animated)
        }
    }
    
    @objc private func sceneLabelTapped(_ gesture: UITapGestureRecognizer) {
        guard let label = gesture.view as? UILabel else { return }
        let index = label.tag
        
        // If tapping the already-selected scene, expand the modal
        if index == selectedSceneIndex {
            setExpanded(true, animated: true)
            return
        }
        
        // Update selection
        selectScene(at: index, animated: true)
        
        // Notify callback
        onSceneSelected?(index)
    }
    
    @objc private func addSceneButtonTapped() {
        if !isExpanded {
            completeMorph(expand: true)
            morphAnimator?.addCompletion { [weak self] _ in
                // Show button grid first (so back button has somewhere to go),
                // then immediately navigate to create scene
                self?.showButtonGrid()
                self?.onSceneAddSceneTapped?()
            }
        } else {
            onSceneAddSceneTapped?()
        }
    }
    
    /// Select a scene programmatically
    func selectScene(at index: Int, animated: Bool) {
        guard index >= 0, index < sceneLabels.count else { return }
        
        // Update colors
        for (i, label) in sceneLabels.enumerated() {
            if i == index {
                label.textColor = .systemYellow
            } else {
                label.textColor = UIColor(white: 1.0, alpha: 0.6)
            }
        }
        
        selectedSceneIndex = index
        scrollToSelectedScene(animated: animated)
    }
    
    private func setupGrabHandle() {
        grabHandle.translatesAutoresizingMaskIntoConstraints = false
        grabHandle.backgroundColor = UIColor(white: 1.0, alpha: 0.6)
        grabHandle.layer.cornerRadius = 2.5
        grabHandle.isUserInteractionEnabled = false
        morphingGlass.glassContentView.addSubview(grabHandle)
        
        // Portrait: horizontal bar at top center
        grabHandlePortraitConstraints = [
            grabHandle.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor, constant: 5),
            grabHandle.centerXAnchor.constraint(equalTo: morphingGlass.glassContentView.centerXAnchor),
            grabHandle.widthAnchor.constraint(equalToConstant: 36),
            grabHandle.heightAnchor.constraint(equalToConstant: 5),
        ]
        
        // Landscape: vertical bar at leading center
        grabHandleLandscapeConstraints = [
            grabHandle.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: 5),
            grabHandle.centerYAnchor.constraint(equalTo: morphingGlass.glassContentView.centerYAnchor),
            grabHandle.widthAnchor.constraint(equalToConstant: 5),
            grabHandle.heightAnchor.constraint(equalToConstant: 36),
        ]
        
        NSLayoutConstraint.activate(grabHandlePortraitConstraints)
    }
    
    private func setupExpandedContent() {
        // Scroll view wraps expanded content so inline views can scroll if they exceed modal height
        expandedScrollView.translatesAutoresizingMaskIntoConstraints = false
        expandedScrollView.alpha = 0 // Hidden initially
        expandedScrollView.showsVerticalScrollIndicator = false
        expandedScrollView.showsHorizontalScrollIndicator = false
        expandedScrollView.alwaysBounceVertical = false
        morphingGlass.glassContentView.addSubview(expandedScrollView)
        
        // Add expanded content inside the scroll view
        expandedContent.translatesAutoresizingMaskIntoConstraints = false
        expandedScrollView.addSubview(expandedContent)
        
        // Wire height adaptation callbacks so internal navigation
        // (e.g. inline back buttons) triggers the correct height animation
        expandedContent.onWillShowButtonGrid = { [weak self] in
            self?.animateToHeight(for: nil)
        }
        expandedContent.onWillShowInlineContent = { [weak self] type in
            self?.animateToHeight(for: type)
        }
        
        NSLayoutConstraint.activate([
            // Scroll view fills the glass with 5pt minimum edge clearance
            expandedScrollView.topAnchor.constraint(equalTo: morphingGlass.glassContentView.topAnchor, constant: 10),
            expandedScrollView.leadingAnchor.constraint(equalTo: morphingGlass.glassContentView.leadingAnchor, constant: 10),
            expandedScrollView.trailingAnchor.constraint(equalTo: morphingGlass.glassContentView.trailingAnchor, constant: -10),
            expandedScrollView.bottomAnchor.constraint(equalTo: morphingGlass.glassContentView.bottomAnchor, constant: -10),
            
            // Content pinned to scroll view's content layout guide
            expandedContent.topAnchor.constraint(equalTo: expandedScrollView.contentLayoutGuide.topAnchor),
            expandedContent.leadingAnchor.constraint(equalTo: expandedScrollView.contentLayoutGuide.leadingAnchor),
            expandedContent.trailingAnchor.constraint(equalTo: expandedScrollView.contentLayoutGuide.trailingAnchor),
            expandedContent.bottomAnchor.constraint(equalTo: expandedScrollView.contentLayoutGuide.bottomAnchor),
            
            // Width matches scroll view frame (vertical-only scrolling)
            expandedContent.widthAnchor.constraint(equalTo: expandedScrollView.frameLayoutGuide.widthAnchor),
            
            // Height matches scroll view frame so inline views fill the visible area.
            // Without this, the content height is driven by the button grid (~280pt)
            // and inline views get cramped regardless of the glass height.
            // Individual inline views have their own internal scroll views for overflow.
            expandedContent.heightAnchor.constraint(equalTo: expandedScrollView.frameLayoutGuide.heightAnchor),
        ])
    }
    
    private func setupGestures() {
        // Pan gesture on the morphing glass for vertical morphing
        // This gesture will determine direction and either handle vertical or let scroll view handle horizontal
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        panGesture.delaysTouchesBegan = false
        morphingGlass.addGestureRecognizer(panGesture)
    }

    
    // MARK: - Gesture Handlers
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)
        
        // In landscape, morphing is horizontal (left=expand, right=collapse)
        // In portrait, morphing is vertical (up=expand, down=collapse)
        let morphAxis: GestureDirection = isLandscape ? .horizontal : .vertical
        
        switch gesture.state {
        case .began:
            gestureStartPoint = gesture.location(in: self)
            gestureDirection = .unknown
            morphAnimator?.stopAnimation(true)
            
            switch currentState {
            case .collapsed:
                gestureStartProgress = 0
            case .expanded:
                gestureStartProgress = 1
            case .dragging(let p):
                gestureStartProgress = p
            }
            
        case .changed:
            if gestureDirection == .unknown {
                let absX = abs(translation.x)
                let absY = abs(translation.y)
                
                if absX > directionLockThreshold || absY > directionLockThreshold {
                    if isLandscape {
                        // Landscape: horizontal = morphing, vertical = scene scroll
                        if absX > absY {
                            gestureDirection = .horizontal
                        } else {
                            gestureDirection = .vertical
                            gesture.isEnabled = false
                            gesture.isEnabled = true
                            return
                        }
                    } else {
                        // Portrait: vertical = morphing, horizontal = scene scroll
                        if absY > absX {
                            gestureDirection = .vertical
                        } else {
                            gestureDirection = .horizontal
                            gesture.isEnabled = false
                            gesture.isEnabled = true
                            return
                        }
                    }
                }
            }
            
            guard gestureDirection == morphAxis else { return }
            
            // Calculate drag delta based on orientation
            let dragDelta: CGFloat
            if isLandscape {
                // When control bar is on leading (left), expand rightward (positive x)
                // When control bar is on trailing (right), expand leftward (negative x)
                let xSign: CGFloat = controlBarOnLeading ? 1 : -1
                dragDelta = xSign * translation.x / expandThreshold
            } else {
                dragDelta = -translation.y / expandThreshold  // Up = expand (negative y)
            }
            let rawProgress = gestureStartProgress + dragDelta
            let progress = applyRubberBand(rawProgress)
            updateMorphProgress(progress)
            
        case .ended, .cancelled:
            let direction = gestureDirection
            gestureDirection = .unknown
            
            guard direction == morphAxis else { return }
            
            let dragDelta: CGFloat
            let vel: CGFloat
            if isLandscape {
                let xSign: CGFloat = controlBarOnLeading ? 1 : -1
                dragDelta = xSign * translation.x / expandThreshold
                vel = xSign * velocity.x
            } else {
                dragDelta = -translation.y / expandThreshold
                vel = -velocity.y
            }
            let rawProgress = gestureStartProgress + dragDelta
            let progress = min(1, max(0, rawProgress))
            
            if vel > 500 {
                completeMorph(expand: true)
            } else if vel < -500 {
                completeMorph(expand: false)
            } else {
                completeMorph(expand: progress > 0.5)
            }
            
        default:
            break
        }
    }
    
    @objc private func settingsTapped() {
        onSettingsTapped?(settingsGlass)
    }

    @objc private func setupCTATapped() {
        setExpanded(true, animated: true)
    }

    @objc private func liveButtonTapped() {
        if isCountingDown {
            cancelCountdown()
            return
        }
        
        // If already live, stop immediately (no countdown to end stream)
        if isCurrentlyLive {
            onLiveTapped?()
            return
        }
        
        // If no stream is configured, open the setup wizard instead of counting down
        if isStreamConfigured?() != true {
            onOpenSetup?()
            return
        }
        
        // Show pre-stream review sheet if callback is set
        if let onPreStreamReview {
            onPreStreamReview()
        } else {
            startCountdown()
        }
    }

    /// Long-press always opens the pre-stream review sheet, even when "skip review" is on.
    @objc private func liveButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard !isCountingDown, !isCurrentlyLive else { return }
        guard isStreamConfigured?() == true else { return }

        if let onForcePreStreamReview {
            onForcePreStreamReview()
        } else if let onPreStreamReview {
            onPreStreamReview()
        }
    }
    
    // MARK: - Loading Spinner (balance check)

    /// Shows a red-tinted spinner in the go-live button while fetching balance.
    func showLoadingSpinner() {
        guard loadingSpinner == nil else { return }

        // Hide the antenna icon
        if let icon = flipGlass.glassContentView.viewWithTag(100) {
            icon.alpha = 0
        }

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .systemRed
        spinner.translatesAutoresizingMaskIntoConstraints = false
        flipGlass.glassContentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: flipGlass.glassContentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: flipGlass.glassContentView.centerYAnchor),
        ])
        spinner.startAnimating()
        loadingSpinner = spinner

        flipGlass.glassContentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
        flipGlass.isUserInteractionEnabled = false
    }

    /// Removes the spinner and restores the go-live button.
    func hideLoadingSpinner() {
        loadingSpinner?.stopAnimating()
        loadingSpinner?.removeFromSuperview()
        loadingSpinner = nil

        if let icon = flipGlass.glassContentView.viewWithTag(100) {
            icon.alpha = 1
        }
        flipGlass.glassContentView.backgroundColor = .clear
        flipGlass.isUserInteractionEnabled = true
    }

    // MARK: - Live Countdown
    
    func startCountdown() {
        // Clean up spinner if transitioning from loading state
        hideLoadingSpinner()

        isCountingDown = true
        countdownRemaining = 3
        
        // Hide the antenna icon
        if let icon = flipGlass.glassContentView.viewWithTag(100) {
            icon.alpha = 0
        }
        
        // Create countdown number label
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.text = "3"
        label.tag = 101
        flipGlass.glassContentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: flipGlass.glassContentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: flipGlass.glassContentView.centerYAnchor),
        ])
        countdownLabel = label
        
        // Create circular progress ring
        let ringLayer = CAShapeLayer()
        let center = CGPoint(x: sideButtonSize / 2, y: sideButtonSize / 2)
        let radius = (sideButtonSize / 2) - 3
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true)
        ringLayer.path = path.cgPath
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = UIColor.systemRed.cgColor
        ringLayer.lineWidth = 3
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 1.0 // Model value = final state
        flipGlass.glassContentView.layer.addSublayer(ringLayer)
        countdownRingLayer = ringLayer
        
        // Single continuous animation from 0→1 over the full 3 seconds
        let ringAnim = CABasicAnimation(keyPath: "strokeEnd")
        ringAnim.fromValue = 0
        ringAnim.toValue = 1
        ringAnim.duration = 3.0
        ringAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        countdownRingLayer?.add(ringAnim, forKey: "countdownRing")
        
        // Tint the button background
        flipGlass.glassContentView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.15)
        
        // Pop the first number
        animateCountdownLabel()
        
        // Start timer for remaining ticks
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.countdownTick()
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func countdownTick() {
        countdownRemaining -= 1
        
        if countdownRemaining <= 0 {
            // Countdown complete — go live
            countdownTimer?.invalidate()
            countdownTimer = nil
            isCountingDown = false
            cleanupCountdownViews()
            onLiveTapped?()
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        
        // Update label with pop
        animateCountdownLabel()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func animateCountdownLabel() {
        countdownLabel?.text = "\(countdownRemaining)"
        
        // Pop scale animation on the label
        countdownLabel?.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            self.countdownLabel?.transform = .identity
        }
    }
    
    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountingDown = false
        countdownRemaining = 0
        
        cleanupCountdownViews()
        
        // Restore normal appearance
        if let icon = flipGlass.glassContentView.viewWithTag(100) {
            UIView.animate(withDuration: 0.2) {
                icon.alpha = 1
            }
        }
        flipGlass.glassContentView.backgroundColor = .clear
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func cleanupCountdownViews() {
        countdownLabel?.removeFromSuperview()
        countdownLabel = nil
        countdownRingLayer?.removeAllAnimations()
        countdownRingLayer?.removeFromSuperlayer()
        countdownRingLayer = nil
        
        // Restore the icon and clear countdown background tint
        if let icon = flipGlass.glassContentView.viewWithTag(100) {
            icon.alpha = 1
        }
        flipGlass.glassContentView.backgroundColor = .clear
    }
    
    // MARK: - Rubber Band
    
    private func applyRubberBand(_ progress: CGFloat) -> CGFloat {
        if progress < 0 {
            return progress * 0.3
        } else if progress > 1 {
            return 1 + (progress - 1) * 0.3
        }
        return progress
    }
    
    // MARK: - Morph Animation
    
    private func updateMorphProgress(_ progress: CGFloat) {
        let p = max(0, min(1, progress))
        
        if isLandscape {
            updateMorphProgressLandscape(p)
        } else {
            updateMorphProgressPortrait(p)
        }
        
        // Common fade logic
        let selectorAlpha = max(0, 1 - (p * 10))
        sceneScrollView.alpha = selectorAlpha
        setupCTALabel.alpha = selectorAlpha
        let expandedAlpha = p > 0.2 ? (p - 0.2) / 0.8 : 0.0
        expandedScrollView.alpha = expandedAlpha
        expandedScrollView.isHidden = expandedAlpha < 0.01
        settingsGlass.alpha = 1 - p
        flipGlass.alpha = 1 - p
        grabHandle.alpha = (1 - p) * 0.3
        
        layoutIfNeeded()
        
        // Keep the selected scene centered
        if selectedSceneIndex < sceneLabels.count {
            let label = sceneLabels[selectedSceneIndex]
            if isLandscape {
                let labelCenter = label.frame.midY
                let scrollViewHeight = sceneScrollView.bounds.height
                let maxOffset = max(0, sceneScrollView.contentSize.height - scrollViewHeight)
                let targetOffset = max(0, min(labelCenter - scrollViewHeight / 2, maxOffset))
                sceneScrollView.contentOffset = CGPoint(x: 0, y: targetOffset)
            } else {
                let labelCenter = label.frame.midX
                let scrollViewWidth = sceneScrollView.bounds.width
                let maxOffset = max(0, sceneScrollView.contentSize.width - scrollViewWidth)
                let targetOffset = max(0, min(labelCenter - scrollViewWidth / 2, maxOffset))
                sceneScrollView.contentOffset = CGPoint(x: targetOffset, y: 0)
            }
        }
        
        currentState = .dragging(progress: p)
    }
    
    private func updateMorphProgressPortrait(_ p: CGFloat) {
        let width = pillWidth + (modalWidth - pillWidth) * p
        let height = pillHeight + (currentExpandedHeight - pillHeight) * p
        let cornerRadius = pillCornerRadius + (modalCornerRadius - pillCornerRadius) * p
        
        glassWidthConstraint.constant = width
        glassHeightConstraint.constant = height
        glassBottomConstraint.constant = -bottomPadding
        morphingGlass.layer.cornerRadius = cornerRadius
    }
    
    private func updateMorphProgressLandscape(_ p: CGFloat) {
        // In landscape, pill is vertical (53w × 220h). Expands toward the camera preview.
        let collapsedWidth: CGFloat = pillHeight   // 53 (pill is rotated)
        let collapsedHeight: CGFloat = pillWidth   // 220
        let expandedWidth = UIScreen.main.bounds.height - 28  // Use screen height (landscape)
        let expandedHeight = currentExpandedHeight
        
        let width = collapsedWidth + (expandedWidth - collapsedWidth) * p
        let height = collapsedHeight + (expandedHeight - collapsedHeight) * p
        let cornerRadius = pillCornerRadius + (modalCornerRadius - pillCornerRadius) * p
        
        glassWidthConstraint.constant = width
        glassHeightConstraint.constant = height
        if controlBarOnLeading {
            glassLeadingConstraint?.constant = trailingPadding
        } else {
            glassTrailingConstraint?.constant = -trailingPadding
        }
        morphingGlass.layer.cornerRadius = cornerRadius
    }
    
    private func completeMorph(expand: Bool) {
        if expand { onExpandStarted?() }
        
        let targetProgress: CGFloat = expand ? 1 : 0
        
        // If collapsing while showing inline content, snap back to button grid first
        if !expand && expandedContent.currentInlineContent != nil {
            expandedContent.showButtonGrid()
        }
        
        // Dismiss keyboard and reset height when collapsing
        if !expand {
            endEditing(true)
            currentKeyboardHeight = 0
            currentExpandedHeight = buttonGridHeight
        }
        
        // When expanding with inline content already queued (e.g. returning from
        // widget editing), use the correct target height so the modal doesn't
        // expand to the shorter button-grid height first.
        if expand, let inlineType = expandedContent.currentInlineContent {
            currentExpandedHeight = targetHeight(for: inlineType)
        }
        
        morphAnimator = UIViewPropertyAnimator(
            duration: 0.5,
            dampingRatio: 0.85
        ) { [weak self] in
            self?.updateMorphProgress(targetProgress)
        }
        
        morphAnimator?.addCompletion { [weak self] _ in
            guard let self else { return }
            self.currentState = expand ? .expanded : .collapsed
            // When fully expanded with no inline content, ensure height is at
            // button grid default (inline views will animate to their own height
            // when shown). If inline content is already active, keep its height.
            if expand && self.expandedContent.currentInlineContent == nil {
                self.currentExpandedHeight = self.buttonGridHeight
            }
            self.onModalStateChanged?(expand)
        }
        
        morphAnimator?.startAnimation()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func setCollapsedState(animated: Bool) {
        if animated {
            completeMorph(expand: false)
        } else {
            updateMorphProgress(0)
            currentState = .collapsed
        }
    }
    
    // MARK: - Public API
    
    var isExpanded: Bool {
        if case .expanded = currentState {
            return true
        }
        return false
    }
    
    func dismiss() {
        if isExpanded {
            setExpanded(false, animated: true)
        }
    }
    
    func setExpanded(_ expanded: Bool, animated: Bool) {
        if animated {
            completeMorph(expand: expanded)
        } else {
            updateMorphProgress(expanded ? 1 : 0)
            currentState = expanded ? .expanded : .collapsed
        }
    }
    
    func setLiveActive(_ active: Bool) {
        isCurrentlyLive = active
        
        // If going live while countdown is running, clean it up
        if active && isCountingDown {
            countdownTimer?.invalidate()
            countdownTimer = nil
            isCountingDown = false
            cleanupCountdownViews()
        }
        
        // Update the side button appearance
        if let icon = flipGlass.glassContentView.viewWithTag(100) as? UIImageView {
            icon.tintColor = active ? .systemRed : .white
            icon.alpha = isCountingDown ? 0 : 1
        }
        
        if active {
            startBreathingAnimation()
        } else {
            stopBreathingAnimation()
        }
    }
    
    // MARK: - Breathing Animation
    
    private static let breathingKey = "liveBreathing"
    
    private func startBreathingAnimation() {
        guard let icon = flipGlass.glassContentView.viewWithTag(100) else { return }
        icon.layer.removeAnimation(forKey: Self.breathingKey)
        
        let group = CAAnimationGroup()
        group.duration = 1.6
        group.repeatCount = .infinity
        group.autoreverses = true
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.3
        
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.5
        
        group.animations = [scale, opacity]
        icon.layer.add(group, forKey: Self.breathingKey)
    }
    
    private func stopBreathingAnimation() {
        flipGlass.glassContentView.viewWithTag(100)?.layer.removeAnimation(forKey: Self.breathingKey)
    }
    
    // MARK: - Forwarded to ExpandedControlsModal
    
    func updateAllStates(
        flash: Bool, live: Bool, mute: Bool, record: Bool,
        exposure: Bool, styles: Bool, nightMode: Bool,
        qualityTitle: String, isLiveOrRecording: Bool,
        isStreamConfigured: Bool, streamName: String,
        resolution: String, isZapStream: Bool,
        uptime: String, bitrateMbps: String,
        bitrateColor: UIColor, viewerCount: String,
        currentLutName: String?, exposureBias: Float,
        currentMicName: String,
        balance: Int? = nil, rate: Double = 0,
        protocolString: String = "",
        stabilizationMode: String = "Off",
        bitrateTitle: String = "5 Mbps"
    ) {
        // Update side live button
        setLiveActive(live)
        // Update onboarding state
        updateOnboardingState()
        // Forward all states to expanded content
        expandedContent.updateAllStates(
            flash: flash, mute: mute, record: record,
            exposure: exposure, styles: styles, nightMode: nightMode,
            qualityTitle: qualityTitle, isLiveOrRecording: isLiveOrRecording,
            isStreamConfigured: isStreamConfigured, isLive: live,
            streamName: streamName, resolution: resolution,
            isZapStream: isZapStream,
            uptime: uptime, bitrateMbps: bitrateMbps,
            bitrateColor: bitrateColor, viewerCount: viewerCount,
            currentLutName: currentLutName, exposureBias: exposureBias,
            currentMicName: currentMicName,
            balance: balance, rate: rate,
            protocolString: protocolString,
            stabilizationMode: stabilizationMode,
            bitrateTitle: bitrateTitle
        )
    }
    
    func showInlineContent(_ type: ExpandedControlsModal.InlineContentType) {
        expandedContent.showInlineContent(type)
        animateToHeight(for: type)
    }
    
    func showButtonGrid() {
        expandedContent.showButtonGrid()
        animateToHeight(for: nil)
    }

    /// Lightweight Zone 3-only update. Bypasses full updateAllStates chain.
    /// Safe to call every second — only updates status bar labels and inline detail view.
    func updateStatusBar(
        isStreamConfigured: Bool, isLive: Bool, streamName: String,
        resolution: String, isZapStream: Bool, uptime: String,
        bitrateMbps: String, bitrateColor: UIColor, viewerCount: String,
        balance: Int?, rate: Double, protocolString: String
    ) {
        expandedContent.statusBar.configure(
            isStreamConfigured: isStreamConfigured, isLive: isLive,
            streamName: streamName, resolution: resolution,
            isZapStream: isZapStream, uptime: uptime,
            bitrateMbps: bitrateMbps, bitrateColor: bitrateColor,
            viewerCount: viewerCount, balance: balance,
            rate: rate, protocolString: protocolString
        )
        // Also update inline detail view if it's currently showing
        expandedContent.updateStreamDetailLiveStats(
            uptime: uptime, bitrateMbps: bitrateMbps,
            bitrateColor: bitrateColor, viewerCount: viewerCount,
            balance: balance, rate: rate
        )
    }
    
    // MARK: - Keyboard Handling
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard case .expanded = currentState else { return }
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        
        currentKeyboardHeight = frame.height
        animateToKeyboardAdaptedHeight(notification: notification)
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        currentKeyboardHeight = 0
        animateToKeyboardAdaptedHeight(notification: notification)
    }
    
    /// Animates the glass height using the keyboard's own animation curve and duration
    /// so the resize stays perfectly in sync with the keyboard slide.
    private func animateToKeyboardAdaptedHeight(notification: Notification) {
        guard case .expanded = currentState else { return }
        let targetH = targetHeight(for: expandedContent.currentInlineContent)
        guard glassHeightConstraint.constant != targetH else { return }
        
        currentExpandedHeight = targetH
        
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.3
        let curveRaw = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curveRaw << 16),
            animations: {
                self.glassHeightConstraint.constant = targetH
                self.layoutIfNeeded()
            }
        )
    }
    
    // MARK: - Adaptive Height
    
    private func targetHeight(for type: ExpandedControlsModal.InlineContentType?) -> CGFloat {
        let base: CGFloat
        switch type {
        case .none:        base = buttonGridHeight
        case .exposure:    base = buttonGridHeight
        case .quality:     base = buttonGridHeight
        case .stabilization: base = buttonGridHeight
        case .bitrate:     base = 380
        case .styles:      base = 420
        case .widgets:     base = 440
        case .addWidget:   base = maxModalHeight
        case .quickConfig: base = maxModalHeight
        case .micPicker:   base = buttonGridHeight
        case .scene:       base = 440
        case .sceneCameraPicker: base = maxModalHeight
        case .sceneMicPicker:    base = buttonGridHeight
        case .createScene:       base = maxModalHeight
        case .streamDetail:      base = 540
        case .streamMetadata:    base = maxModalHeight
        case .streamVideo:       base = 440
        case .streamAudio:       base = 340
        case .collabInvite:      base = maxModalHeight
        case .collabCall:        base = 290
        case .collabIncoming:    base = 200
        }
        
        // In landscape, the glass is centered vertically. Cap the height so it
        // doesn't extend beyond the screen edges. Leave 20pt margin top and bottom.
        if isLandscape {
            let screenHeight = UIScreen.main.bounds.height
            let maxLandscapeHeight = screenHeight - 40
            return min(base, maxLandscapeHeight)
        }
        
        // When the keyboard is up, grow the modal so content sits above it.
        // The modal is anchored at bottomPadding from the screen bottom, so
        // it needs to be tall enough that the content (title + field + buttons ≈ 160pt)
        // clears the keyboard. We add the keyboard height to the content height
        // plus some breathing room, rather than adding it to the full base height.
        if currentKeyboardHeight > 0, type == .quickConfig {
            let contentHeight: CGFloat = 160 // title bar + text field + buttons + spacing
            let screenHeight = UIScreen.main.bounds.height
            let maxAvailable = screenHeight - bottomPadding - 20
            return min(currentKeyboardHeight + contentHeight, maxAvailable)
        }

        if currentKeyboardHeight > 0, type == .streamDetail {
            let screenHeight = UIScreen.main.bounds.height
            let maxAvailable = screenHeight - bottomPadding - 20
            // Don't grow by the full keyboard height — just nudge up enough
            // so the field is visible. The scroll view handles the rest.
            let nudge = currentKeyboardHeight * 0.45
            return min(base + nudge, maxAvailable)
        }
        
        return base
    }
    
    private func animateToHeight(for contentType: ExpandedControlsModal.InlineContentType?) {
        // Only resize when the modal is fully expanded. During collapse, the morph
        // animator handles height. If collapsed, the glass is at pill size and should
        // stay there — resizing while collapsed causes the glass to jump to expanded
        // height with no content visible (empty rectangle bug).
        if case .expanded = currentState {} else { return }
        
        let targetH = targetHeight(for: contentType)
        guard glassHeightConstraint.constant != targetH else { return }
        
        currentExpandedHeight = targetH
        
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.3,
            options: .allowUserInteraction
        ) {
            self.glassHeightConstraint.constant = targetH
            self.layoutIfNeeded()
        }
    }
    
    /// Direct access to expanded content for setting data providers
    var expandedControls: ExpandedControlsModal {
        return expandedContent
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Default hitTest handles points inside our bounds
        if let hit = super.hitTest(point, with: event) {
            return hit
        }
        
        // For points outside bounds (the expanded morphingGlass extends above),
        // check subviews anyway so button taps reach the ControlButtons.
        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 && subview.isUserInteractionEnabled {
            let subPoint = subview.convert(point, from: self)
            if let hit = subview.hitTest(subPoint, with: event) {
                return hit
            }
        }
        
        return nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MorphingGlassModal: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous recognition during direction detection phase
        // Once we've locked to vertical, we own it exclusively
        if gestureRecognizer is UIPanGestureRecognizer {
            // If we're handling vertical morphing, don't share
            if gestureDirection == .vertical {
                return false
            }
            // When expanded with inline content, don't share with scroll view pan gestures
            if isExpanded, expandedContent.currentInlineContent != nil,
               otherGestureRecognizer.view is UIScrollView {
                return false
            }
            // During detection or horizontal, allow simultaneous
            return true
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't require scroll view to fail - we'll determine direction ourselves
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Parent navigation gestures should wait for us to determine direction
        // This prevents the camera container's vertical pan from stealing our gesture
        if gestureRecognizer is UIPanGestureRecognizer {
            // If the other gesture is from a parent view controller, require us to fail first
            if let otherView = otherGestureRecognizer.view,
               !otherView.isDescendant(of: self) {
                return true
            }
        }
        return false
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        
        // Check if touch is on the morphing glass
        let location = pan.location(in: self)
        guard morphingGlass.frame.contains(location) else { return false }
        
        // When expanded with inline content showing, only allow pan from the
        // grab handle region at the top of the modal. This prevents the modal's
        // pan gesture from stealing vertical scrolls inside inline scroll views.
        if isExpanded, expandedContent.currentInlineContent != nil {
            let locationInGlass = pan.location(in: morphingGlass)
            let grabHandleRegionHeight: CGFloat = 40
            if locationInGlass.y > grabHandleRegionHeight {
                return false
            }
        }
        
        return true
    }
}

// MARK: - UIScrollViewDelegate

extension MorphingGlassModal: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // updateSelectedSceneFromScrollPosition()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // if !decelerate {
        //     updateSelectedSceneFromScrollPosition()
        // }
    }
    
    /// Finds the scene label closest to center and selects it
    // private func updateSelectedSceneFromScrollPosition() {
    //     guard !sceneLabels.isEmpty else { return }
    //
    //     let scrollCenter = sceneScrollView.contentOffset.x + sceneScrollView.bounds.width / 2
    //
    //     var closestIndex = 0
    //     var closestDistance: CGFloat = .greatestFiniteMagnitude
    //
    //     for (index, label) in sceneLabels.enumerated() {
    //         let labelCenter = label.frame.midX
    //         let distance = abs(labelCenter - scrollCenter)
    //         if distance < closestDistance {
    //             closestDistance = distance
    //             closestIndex = index
    //         }
    //     }
    //
    //     // Only update if different from current selection
    //     if closestIndex != selectedSceneIndex {
    //         selectScene(at: closestIndex, animated: true)
    //         onSceneSelected?(closestIndex)
    //     }
    // }
}
