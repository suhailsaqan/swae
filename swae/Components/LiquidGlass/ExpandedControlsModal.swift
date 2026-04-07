import UIKit

/// The expanded modal content with four-zone layout and inline sub-views
/// Zone 1: Toggle Strip (flash, mute, night, record)
/// Zone 2: Tuning Cards (styles, exposure, mic, quality)
/// Zone 3: Stream Status Bar
/// Zone 4: Action Buttons (Widgets, Scene)
class ExpandedControlsModal: UIView {

    // MARK: - Inline Content Type

    enum InlineContentType {
        case exposure
        case styles
        case quality
        case stabilization
        case bitrate
        case widgets
        case addWidget
        case quickConfig
        case micPicker
        case scene
        case sceneCameraPicker
        case sceneMicPicker
        case createScene
        case streamDetail
        case streamMetadata
        case streamVideo
        case streamAudio
        case collabInvite
        case collabCall
        case collabIncoming
    }

    // MARK: - Properties

    /// Tracks which inline content is currently showing, nil = zone layout
    private(set) var currentInlineContent: InlineContentType?

    // Zone 1: Toggle Strip
    private let toggleScrollView = UIScrollView()
    private let toggleStrip = UIStackView()
    private(set) var flashPill: TogglePill!
    private(set) var mutePill: TogglePill!
    private(set) var nightModePill: TogglePill!
    private(set) var portraitPill: TogglePill!
    private(set) var recordPill: TogglePill!
    private(set) var collabPill: TogglePill!

    // Zone 2: Tuning Cards
    private let cardScrollView = UIScrollView()
    private let cardStack = UIStackView()
    private(set) var stabilizationCard: TuningCard!
    private(set) var bitrateCard: TuningCard!
    private(set) var micCard: TuningCard!
    private(set) var qualityCard: TuningCard!

    // Zone 3: Status Bar
    private(set) var statusBar = StreamStatusBar()

    // Zone 4: Action Buttons
    private let buttonRow = UIStackView()
    private let widgetsButton = UIButton(type: .system)
    private let sceneButton = UIButton(type: .system)

    // Main zone container (hidden when inline content shows)
    private let zoneContainer = UIStackView()

    // Home indicator
    private let homeIndicator = UIView()

    // Inline views (lazily created)
    private var exposureView: InlineExposureView?
    private var stylesView: InlineStylesView?
    private var qualityView: InlineQualityView?
    private var stabilizationView: InlineStabilizationView?
    private var bitrateView: InlineBitrateView?
    private var widgetsView: InlineWidgetsView?
    private var addWidgetView: InlineAddWidgetView?
    private var quickConfigView: InlineQuickConfigView?
    private var micPickerView: InlineMicPickerView?
    private var sceneView: InlineSceneView?
    private var sceneCameraPickerView: InlineMicPickerView?
    private var sceneMicPickerView: InlineMicPickerView?
    private var createSceneView: InlineCreateSceneView?
    private var streamDetailView: InlineStreamDetailView?
    private var streamMetadataView: InlineStreamMetadataView?
    private var streamVideoView: InlineStreamVideoView?
    private var streamAudioView: InlineStreamAudioView?
    private var collabInviteView: InlineCollabInviteView?
    private var collabCallView: InlineCollabCallView?
    private var collabIncomingView: InlineCollabIncomingView?

    // MARK: - Callbacks — button taps

    var onFlashTapped: (() -> Void)?
    var onMuteTapped: (() -> Void)?
    var onRecordTapped: (() -> Void)?
    var onCollabTapped: (() -> Void)?
    var onPortraitTapped: (() -> Void)?
    var onExposureTapped: (() -> Void)?
    var onStylesTapped: (() -> Void)?
    var onQualityTapped: (() -> Void)?
    var onStabilizationTapped: (() -> Void)?
    var onBitrateTapped: (() -> Void)?
    var onStabilizationModeChanged: ((Int) -> Void)?
    var onBitrateChanged: ((UInt32) -> Void)?
    var onNightModeTapped: (() -> Void)?
    var onWidgetsTapped: (() -> Void)?
    var onMicCardTapped: (() -> Void)?
    var onSceneButtonTapped: (() -> Void)?

    /// Called when the zone layout becomes visible again (after returning from an inline view).
    var onButtonGridShown: (() -> Void)?

    /// Called immediately when navigating back to zone layout (before crossfade animation).
    var onWillShowButtonGrid: (() -> Void)?

    /// Called immediately when navigating to an inline view (before crossfade animation).
    var onWillShowInlineContent: ((InlineContentType) -> Void)?

    // Callbacks — inline view actions (set by CameraViewController)
    var onExposureChanged: ((Float) -> Void)?
    var onExposureReset: (() -> Void)?
    var onLutSelected: ((Int) -> Void)?
    var onResolutionSelected: ((Int) -> Void)?
    var onWidgetToggled: ((UUID, Bool) -> Void)?
    var onWidgetAddTapped: (() -> Void)?
    var onWidgetTapped: ((UUID) -> Void)?
    var onWidgetRowTapped: ((UUID) -> Void)?
    var onWidgetDuplicate: ((UUID) -> Void)?
    var onWidgetDelete: ((UUID) -> Void)?
    var onWidgetSettingsTapped: (() -> Void)?
    var onWidgetTypeSelected: ((SettingsWidgetType) -> Void)?
    var onTemplateSelected: ((InlineAddWidgetView.WidgetTemplate) -> Void)?
    var onQuickConfigDone: ((String) -> Void)?
    var onQuickConfigFullSettings: (() -> Void)?
    var onMicSelected: ((String) -> Void)?
    var onSceneWidgetToggled: ((UUID, Bool) -> Void)?
    var onSceneAddWidgetTapped: (() -> Void)?
    var onSceneCameraTapped: (() -> Void)?
    var onSceneCameraSelected: ((String) -> Void)?
    var onSceneMicTapped: (() -> Void)?
    var onSceneMicSelected: ((String) -> Void)?
    var onSceneAddSceneTapped: (() -> Void)?
    var onSceneRenamed: ((String) -> Void)?
    var onCreateScene: ((String, String) -> Void)?  // (name, cameraId)
    var onCreateSceneFullConfig: (() -> Void)?

    // Stream detail callbacks (forwarded to InlineStreamDetailView)
    var onStreamDetailTopUp: (() -> Void)?
    var onStreamDetailWalletReceive: (() -> Void)?
    var onStreamDetailSettings: (() -> Void)?
    var onStreamDetailRefreshBalance: (() -> Void)?
    var onStreamDetailUpdateStream: (() -> Void)?
    var onStreamDetailAutoTopupDisable: (() -> Void)?
    var onStreamDetailAutoTopupEnable: (() -> Void)?
    var onStreamDetailTitleChanged: ((String) -> Void)?
    var onStreamDetailDescriptionChanged: ((String) -> Void)?
    var onStreamDetailTagsChanged: ((String) -> Void)?
    var onStreamDetailNSFWChanged: ((Bool) -> Void)?
    var onStreamDetailPublicChanged: ((Bool) -> Void)?
    var onStreamDetailProtocolChanged: ((Int) -> Void)?

    // Stream detail sub-page navigation
    var onStreamDetailStreamDetailsTapped: (() -> Void)?
    var onStreamDetailVideoTapped: (() -> Void)?
    var onStreamDetailAudioTapped: (() -> Void)?
    var onStreamDetailWillShow: (() -> Void)?

    // Stream detail new settings callbacks
    var onStreamDetailResolutionChanged: ((Int) -> Void)?
    var onStreamDetailFpsChanged: ((Int) -> Void)?
    var onStreamDetailBitrateChanged: ((Int) -> Void)?
    var onStreamDetailAudioBitrateChanged: ((Int) -> Void)?
    var onStreamDetailAdaptiveResolutionChanged: ((Bool) -> Void)?
    var onStreamDetailLowLightBoostChanged: ((Bool) -> Void)?
    var onStreamDetailPortraitToggled: ((Bool) -> Void)?
    var onStreamDetailBackgroundStreamingChanged: ((Bool) -> Void)?
    var onStreamDetailAutoRecordChanged: ((Bool) -> Void)?

    // Collab callbacks
    var onCollabInvite: ((String) -> Void)?
    var onCollabAccept: (() -> Void)?
    var onCollabDecline: (() -> Void)?
    var onCollabEndCall: (() -> Void)?
    var onCollabMuteTapped: (() -> Void)?
    var onCollabWidgetsTapped: (() -> Void)?
    var onCollabSkipPipTapped: (() -> Void)?
    var onCollabVolumeChanged: ((Float) -> Void)?

    // Pending quick config mode
    private var pendingQuickConfigMode: InlineQuickConfigView.Mode?

    // Data providers
    var lutNames: [String] = []
    var activeLutIndex: Int = -1
    var resolutionOptions: [String] = []
    var activeResolutionIndex: Int = 0
    var isLiveOrRecording: Bool = false
    var currentExposureBias: Float = 0.0
    var pendingWidgetItems: [InlineWidgetsView.WidgetItem] = []
    var pendingMicItems: [InlineMicPickerView.MicItem] = []
    var pendingSelectedMicId: String = ""
    var pendingSceneData: InlineSceneView.SceneData?
    var pendingSceneCameraItems: [InlineMicPickerView.MicItem] = []
    var pendingSelectedSceneCameraId: String = ""
    var pendingSceneMicItems: [InlineMicPickerView.MicItem] = []
    var pendingSelectedSceneMicId: String = ""
    var pendingCreateSceneDefaultName: String = ""
    var pendingCreateSceneCameras: [(id: String, name: String)] = []
    var pendingCreateSceneSelectedCameraId: String = ""
    var pendingStreamDetailData: InlineStreamDetailView.StreamDetailData?
    var pendingStabilizationIndex: Int = 0
    var pendingBitrateOptions: [InlineBitrateView.BitrateOption] = []
    var pendingActiveBitrate: UInt32 = 5_000_000
    var pendingBitrateLocked: Bool = false

    // Collab pending data
    var pendingCollabFollows: [InlineCollabInviteView.FollowItem] = []
    var pendingCollabCallData: (state: InlineCollabCallView.DisplayState, isMuted: Bool, sendWidgets: Bool, skipPip: Bool, guestVolume: Float)?
    var pendingCollabIncomingTitle: String?
    weak var pendingCollabAppState: AppState?

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

        // Tap anywhere outside a text field to dismiss the keyboard
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissTap.cancelsTouchesInView = false
        addGestureRecognizer(dismissTap)

        // Home indicator at top
        homeIndicator.translatesAutoresizingMaskIntoConstraints = false
        homeIndicator.backgroundColor = UIColor(white: 1.0, alpha: 0.3)
        homeIndicator.layer.cornerRadius = 2.5
        addSubview(homeIndicator)

        // Main zone container
        zoneContainer.translatesAutoresizingMaskIntoConstraints = false
        zoneContainer.axis = .vertical
        zoneContainer.spacing = 12
        zoneContainer.alignment = .fill
        addSubview(zoneContainer)

        setupToggleStrip()
        setupTuningCards()
        setupStatusBar()
        setupActionButtons()

        zoneContainer.addArrangedSubview(toggleScrollView)
        zoneContainer.addArrangedSubview(cardScrollView)
        zoneContainer.addArrangedSubview(statusBar)
        zoneContainer.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            homeIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            homeIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            homeIndicator.widthAnchor.constraint(equalToConstant: 36),
            homeIndicator.heightAnchor.constraint(equalToConstant: 5),

            zoneContainer.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            zoneContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            zoneContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            zoneContainer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])
    }

    private func setupToggleStrip() {
        flashPill = TogglePill(symbolName: "bolt.fill", activeTint: .systemYellow)
        mutePill = TogglePill(symbolName: "mic.slash", activeTint: .systemRed)
        nightModePill = TogglePill(symbolName: "moon.fill", activeTint: .systemYellow)
        portraitPill = TogglePill(symbolName: "rectangle.portrait.rotate", activeTint: .systemBlue)
        recordPill = TogglePill(symbolName: "record.circle", activeTint: .systemRed)
        collabPill = TogglePill(symbolName: "person.2.fill", activeTint: .systemGreen)

        flashPill.accessibilityLabel = "Flash"
        mutePill.accessibilityLabel = "Mute"
        nightModePill.accessibilityLabel = "Night Mode"
        portraitPill.accessibilityLabel = "Portrait"
        recordPill.accessibilityLabel = "Record"
        collabPill.accessibilityLabel = "Invite Guest"

        flashPill.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        mutePill.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        nightModePill.addTarget(self, action: #selector(nightModeTapped), for: .touchUpInside)
        portraitPill.addTarget(self, action: #selector(portraitTapped), for: .touchUpInside)
        recordPill.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
        collabPill.addTarget(self, action: #selector(collabTapped), for: .touchUpInside)

        toggleStrip.axis = .horizontal
        toggleStrip.spacing = 12
        toggleStrip.alignment = .center
        toggleStrip.distribution = .equalCentering
        toggleStrip.translatesAutoresizingMaskIntoConstraints = false

        toggleStrip.addArrangedSubview(flashPill)
        toggleStrip.addArrangedSubview(mutePill)
        toggleStrip.addArrangedSubview(nightModePill)
        toggleStrip.addArrangedSubview(portraitPill)
        toggleStrip.addArrangedSubview(recordPill)
        toggleStrip.addArrangedSubview(collabPill)

        toggleScrollView.translatesAutoresizingMaskIntoConstraints = false
        toggleScrollView.showsHorizontalScrollIndicator = false
        toggleScrollView.showsVerticalScrollIndicator = false
        toggleScrollView.clipsToBounds = false
        toggleScrollView.addSubview(toggleStrip)

        NSLayoutConstraint.activate([
            toggleScrollView.heightAnchor.constraint(equalToConstant: 44),
            toggleStrip.topAnchor.constraint(equalTo: toggleScrollView.contentLayoutGuide.topAnchor),
            toggleStrip.leadingAnchor.constraint(equalTo: toggleScrollView.contentLayoutGuide.leadingAnchor),
            toggleStrip.trailingAnchor.constraint(equalTo: toggleScrollView.contentLayoutGuide.trailingAnchor),
            toggleStrip.bottomAnchor.constraint(equalTo: toggleScrollView.contentLayoutGuide.bottomAnchor),
            toggleStrip.heightAnchor.constraint(equalTo: toggleScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    private func setupTuningCards() {
        stabilizationCard = TuningCard(symbolName: "gyroscope", title: "Stabilize")
        bitrateCard = TuningCard(symbolName: "speedometer", title: "Bitrate")
        micCard = TuningCard(symbolName: "music.mic", title: "Mic")
        qualityCard = TuningCard(symbolName: "aspectratio", title: "Quality")

        stabilizationCard.addTarget(self, action: #selector(stabilizationTapped), for: .touchUpInside)
        bitrateCard.addTarget(self, action: #selector(bitrateTapped), for: .touchUpInside)
        micCard.addTarget(self, action: #selector(micCardTapped), for: .touchUpInside)
        qualityCard.addTarget(self, action: #selector(qualityTapped), for: .touchUpInside)

        cardStack.axis = .horizontal
        cardStack.spacing = 10
        cardStack.alignment = .center
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        cardStack.addArrangedSubview(stabilizationCard)
        cardStack.addArrangedSubview(bitrateCard)
        cardStack.addArrangedSubview(micCard)
        cardStack.addArrangedSubview(qualityCard)

        cardScrollView.translatesAutoresizingMaskIntoConstraints = false
        cardScrollView.showsHorizontalScrollIndicator = false
        cardScrollView.showsVerticalScrollIndicator = false
        cardScrollView.clipsToBounds = false
        cardScrollView.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardScrollView.heightAnchor.constraint(equalToConstant: 70),
            cardStack.topAnchor.constraint(equalTo: cardScrollView.contentLayoutGuide.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: cardScrollView.contentLayoutGuide.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: cardScrollView.contentLayoutGuide.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: cardScrollView.contentLayoutGuide.bottomAnchor),
            cardStack.heightAnchor.constraint(equalTo: cardScrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    private func setupStatusBar() {
        statusBar.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupActionButtons() {
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually

        // Widgets button (primary — yellow)
        widgetsButton.translatesAutoresizingMaskIntoConstraints = false
        let widgetConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let widgetIcon = UIImage(systemName: "rectangle.3.group", withConfiguration: widgetConfig)
        widgetsButton.setImage(widgetIcon, for: .normal)
        widgetsButton.setTitle(" Widgets", for: .normal)
        widgetsButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        widgetsButton.setTitleColor(.white, for: .normal)
        widgetsButton.tintColor = .white
        widgetsButton.backgroundColor = .systemYellow.withAlphaComponent(0.8)
        widgetsButton.layer.cornerCurve = .continuous
        widgetsButton.clipsToBounds = true
        widgetsButton.addTarget(self, action: #selector(widgetsTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(widgetsButton)

        // Scene button (secondary — gray)
        sceneButton.translatesAutoresizingMaskIntoConstraints = false
        let sceneConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let sceneIcon = UIImage(systemName: "photo.on.rectangle", withConfiguration: sceneConfig)
        sceneButton.setImage(sceneIcon, for: .normal)
        sceneButton.setTitle(" Scene", for: .normal)
        sceneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        sceneButton.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
        sceneButton.tintColor = UIColor(white: 1.0, alpha: 0.7)
        sceneButton.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        sceneButton.layer.cornerCurve = .continuous
        sceneButton.clipsToBounds = true
        sceneButton.addTarget(self, action: #selector(sceneButtonTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(sceneButton)

        buttonRow.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        widgetsButton.layer.cornerRadius = widgetsButton.bounds.height / 2
        sceneButton.layer.cornerRadius = sceneButton.bounds.height / 2
    }

    // MARK: - Actions

    @objc private func flashTapped() { onFlashTapped?() }
    @objc private func muteTapped() { onMuteTapped?() }
    @objc private func recordTapped() { onRecordTapped?() }
    @objc private func collabTapped() { onCollabTapped?() }
    @objc private func portraitTapped() { onPortraitTapped?() }
    @objc private func exposureTapped() { onExposureTapped?() }
    @objc private func stylesTapped() { onStylesTapped?() }
    @objc private func qualityTapped() { onQualityTapped?() }
    @objc private func stabilizationTapped() { onStabilizationTapped?() }
    @objc private func bitrateTapped() { onBitrateTapped?() }
    @objc private func nightModeTapped() { onNightModeTapped?() }
    @objc private func widgetsTapped() { onWidgetsTapped?() }
    @objc private func micCardTapped() { onMicCardTapped?() }
    @objc private func sceneButtonTapped() { onSceneButtonTapped?() }
    @objc private func dismissKeyboard() { endEditing(true) }

    // MARK: - State Updates

    func updateAllStates(
        flash: Bool, mute: Bool, record: Bool,
        exposure: Bool, styles: Bool, nightMode: Bool,
        qualityTitle: String, isLiveOrRecording: Bool,
        isStreamConfigured: Bool, isLive: Bool,
        streamName: String, resolution: String,
        isZapStream: Bool,
        uptime: String, bitrateMbps: String,
        bitrateColor: UIColor, viewerCount: String,
        currentLutName: String?, exposureBias: Float,
        currentMicName: String,
        balance: Int? = nil, rate: Double = 0,
        protocolString: String = "",
        stabilizationMode: String = "Off",
        bitrateTitle: String = "5 Mbps"
    ) {
        // Zone 1: Toggle pills
        flashPill.isActive = flash
        mutePill.isActive = mute
        recordPill.isActive = record
        recordPill.setIcon(record ? "stop.circle.fill" : "record.circle")
        nightModePill.isActive = nightMode

        // Zone 2: Tuning cards
        stabilizationCard.configure(subtitle: stabilizationMode, isActive: stabilizationMode != "Off")
        bitrateCard.configure(subtitle: bitrateTitle, isActive: false)
        micCard.configure(subtitle: currentMicName, isActive: false)
        qualityCard.configure(subtitle: qualityTitle, isActive: false)

        // Zone 3: Status bar
        statusBar.configure(
            isStreamConfigured: isStreamConfigured,
            isLive: isLive,
            streamName: streamName,
            resolution: resolution,
            isZapStream: isZapStream,
            uptime: uptime,
            bitrateMbps: bitrateMbps,
            bitrateColor: bitrateColor,
            viewerCount: viewerCount,
            balance: balance,
            rate: rate,
            protocolString: protocolString
        )

        // Quality card disabled when live/recording
        qualityCard.isUserInteractionEnabled = !isLiveOrRecording
        qualityCard.alpha = isLiveOrRecording ? 0.4 : 1.0
        self.isLiveOrRecording = isLiveOrRecording

        // Collab pill: always visible (call works without being live)
        collabPill.isHidden = false
    }

    // MARK: - Inline Content Swapping

    func showInlineContent(_ type: InlineContentType) {
        // Dismiss keyboard when leaving quick config
        if currentInlineContent == .quickConfig && type != .quickConfig {
            quickConfigView?.endEditing(true)
        }

        currentInlineContent = type
        onWillShowInlineContent?(type)

        let inlineView: UIView
        switch type {
        case .exposure:
            if exposureView == nil {
                let ev = InlineExposureView()
                ev.translatesAutoresizingMaskIntoConstraints = false
                ev.onValueChanged = { [weak self] value in self?.onExposureChanged?(value) }
                ev.onReset = { [weak self] in self?.onExposureReset?() }
                ev.onBack = { [weak self] in self?.showButtonGrid() }
                addSubview(ev)
                pinInlineView(ev)
                exposureView = ev
            }
            exposureView?.setValue(currentExposureBias)
            inlineView = exposureView!

        case .styles:
            if stylesView == nil {
                let sv = InlineStylesView()
                sv.translatesAutoresizingMaskIntoConstraints = false
                sv.onLutSelected = { [weak self] index in self?.onLutSelected?(index) }
                sv.onBack = { [weak self] in self?.showButtonGrid() }
                addSubview(sv)
                pinInlineView(sv)
                stylesView = sv
            }
            stylesView?.configure(lutNames: lutNames, activeIndex: activeLutIndex)
            inlineView = stylesView!

        case .quality:
            if qualityView == nil {
                let qv = InlineQualityView()
                qv.translatesAutoresizingMaskIntoConstraints = false
                qv.onResolutionSelected = { [weak self] index in self?.onResolutionSelected?(index) }
                qv.onBack = { [weak self] in self?.showButtonGrid() }
                addSubview(qv)
                pinInlineView(qv)
                qualityView = qv
            }
            qualityView?.configure(
                options: resolutionOptions,
                activeIndex: activeResolutionIndex,
                isLocked: isLiveOrRecording
            )
            inlineView = qualityView!

        case .stabilization:
            if stabilizationView == nil {
                let sv = InlineStabilizationView()
                sv.translatesAutoresizingMaskIntoConstraints = false
                sv.onModeSelected = { [weak self] index in self?.onStabilizationModeChanged?(index) }
                sv.onBack = { [weak self] in self?.showButtonGrid() }
                addSubview(sv)
                pinInlineView(sv)
                stabilizationView = sv
            }
            stabilizationView?.configure(activeIndex: pendingStabilizationIndex)
            inlineView = stabilizationView!

        case .bitrate:
            if bitrateView == nil {
                let bv = InlineBitrateView()
                bv.translatesAutoresizingMaskIntoConstraints = false
                bv.onBitrateSelected = { [weak self] bitrate in self?.onBitrateChanged?(bitrate) }
                bv.onBack = { [weak self] in self?.showButtonGrid() }
                addSubview(bv)
                pinInlineView(bv)
                bitrateView = bv
            }
            bitrateView?.configure(
                options: pendingBitrateOptions,
                activeBitrate: pendingActiveBitrate,
                isLocked: pendingBitrateLocked
            )
            inlineView = bitrateView!

        case .widgets:
            if widgetsView == nil {
                let wv = InlineWidgetsView()
                wv.translatesAutoresizingMaskIntoConstraints = false
                wv.onBack = { [weak self] in self?.showButtonGrid() }
                wv.onWidgetToggled = { [weak self] id, enabled in self?.onWidgetToggled?(id, enabled) }
                wv.onWidgetTapped = { [weak self] id in self?.onWidgetTapped?(id) }
                wv.onWidgetRowTapped = { [weak self] id in self?.onWidgetRowTapped?(id) }
                wv.onWidgetDuplicate = { [weak self] id in self?.onWidgetDuplicate?(id) }
                wv.onWidgetDelete = { [weak self] id in self?.onWidgetDelete?(id) }
                wv.onAddTapped = { [weak self] in self?.onWidgetAddTapped?() }
                wv.onSettingsTapped = { [weak self] in self?.onWidgetSettingsTapped?() }
                addSubview(wv)
                pinInlineView(wv)
                widgetsView = wv
            }
            widgetsView?.configure(widgets: pendingWidgetItems)
            inlineView = widgetsView!

        case .addWidget:
            if addWidgetView == nil {
                let aw = InlineAddWidgetView()
                aw.translatesAutoresizingMaskIntoConstraints = false
                aw.onBack = { [weak self] in self?.showInlineContent(.widgets) }
                aw.onTypeSelected = { [weak self] type in self?.onWidgetTypeSelected?(type) }
                aw.onTemplateSelected = { [weak self] template in self?.onTemplateSelected?(template) }
                addSubview(aw)
                pinInlineView(aw)
                addWidgetView = aw
            }
            inlineView = addWidgetView!

        case .quickConfig:
            if quickConfigView == nil {
                let qc = InlineQuickConfigView()
                qc.translatesAutoresizingMaskIntoConstraints = false
                qc.onBack = { [weak self] in self?.showInlineContent(.widgets) }
                qc.onDone = { [weak self] value in self?.onQuickConfigDone?(value) }
                qc.onFullConfig = { [weak self] in self?.onQuickConfigFullSettings?() }
                addSubview(qc)
                pinInlineView(qc)
                quickConfigView = qc
            }
            if let mode = pendingQuickConfigMode {
                quickConfigView?.configure(mode: mode)
            }
            inlineView = quickConfigView!

        case .micPicker:
            if micPickerView == nil {
                let mp = InlineMicPickerView()
                mp.translatesAutoresizingMaskIntoConstraints = false
                mp.onBack = { [weak self] in self?.showButtonGrid() }
                mp.onMicSelected = { [weak self] id in self?.onMicSelected?(id) }
                addSubview(mp)
                pinInlineView(mp)
                micPickerView = mp
            }
            micPickerView?.configure(mics: pendingMicItems, selectedId: pendingSelectedMicId)
            inlineView = micPickerView!

        case .scene:
            if sceneView == nil {
                let sv = InlineSceneView()
                sv.translatesAutoresizingMaskIntoConstraints = false
                sv.onBack = { [weak self] in self?.showButtonGrid() }
                sv.onWidgetToggled = { [weak self] id, enabled in self?.onSceneWidgetToggled?(id, enabled) }
                sv.onAddWidgetTapped = { [weak self] in self?.onSceneAddWidgetTapped?() }
                sv.onCameraTapped = { [weak self] in self?.onSceneCameraTapped?() }
                sv.onMicTapped = { [weak self] in self?.onSceneMicTapped?() }
                sv.onAddSceneTapped = { [weak self] in self?.onSceneAddSceneTapped?() }
                sv.onSceneRenamed = { [weak self] name in self?.onSceneRenamed?(name) }
                addSubview(sv)
                pinInlineView(sv)
                sceneView = sv
            }
            if let data = pendingSceneData {
                sceneView?.configure(data: data)
            }
            inlineView = sceneView!

        case .sceneCameraPicker:
            if sceneCameraPickerView == nil {
                let cp = InlineMicPickerView()
                cp.translatesAutoresizingMaskIntoConstraints = false
                cp.onBack = { [weak self] in self?.showInlineContent(.scene) }
                cp.onMicSelected = { [weak self] id in self?.onSceneCameraSelected?(id) }
                addSubview(cp)
                pinInlineView(cp)
                sceneCameraPickerView = cp
            }
            sceneCameraPickerView?.configure(
                mics: pendingSceneCameraItems,
                selectedId: pendingSelectedSceneCameraId,
                title: "CAMERA"
            )
            inlineView = sceneCameraPickerView!

        case .sceneMicPicker:
            if sceneMicPickerView == nil {
                let mp = InlineMicPickerView()
                mp.translatesAutoresizingMaskIntoConstraints = false
                mp.onBack = { [weak self] in self?.showInlineContent(.scene) }
                mp.onMicSelected = { [weak self] id in self?.onSceneMicSelected?(id) }
                addSubview(mp)
                pinInlineView(mp)
                sceneMicPickerView = mp
            }
            sceneMicPickerView?.configure(
                mics: pendingSceneMicItems,
                selectedId: pendingSelectedSceneMicId
            )
            inlineView = sceneMicPickerView!

        case .createScene:
            if createSceneView == nil {
                let csv = InlineCreateSceneView()
                csv.translatesAutoresizingMaskIntoConstraints = false
                csv.onBack = { [weak self] in self?.showInlineContent(.scene) }
                csv.onCreateScene = { [weak self] name, cameraId in self?.onCreateScene?(name, cameraId) }
                csv.onFullConfig = { [weak self] in self?.onCreateSceneFullConfig?() }
                addSubview(csv)
                pinInlineView(csv)
                createSceneView = csv
            }
            createSceneView?.configure(
                defaultName: pendingCreateSceneDefaultName,
                cameras: pendingCreateSceneCameras,
                selectedCameraId: pendingCreateSceneSelectedCameraId
            )
            inlineView = createSceneView!

        case .streamDetail:
            onStreamDetailWillShow?()  // refresh pendingStreamDetailData before configuring
            if streamDetailView == nil {
                let sv = InlineStreamDetailView()
                sv.translatesAutoresizingMaskIntoConstraints = false
                sv.onBack = { [weak self] in self?.showButtonGrid() }
                sv.onTopUpTapped = { [weak self] in self?.onStreamDetailTopUp?() }
                sv.onWalletReceiveTapped = { [weak self] in self?.onStreamDetailWalletReceive?() }
                sv.onStreamSettingsTapped = { [weak self] in self?.onStreamDetailSettings?() }
                sv.onRefreshBalance = { [weak self] in self?.onStreamDetailRefreshBalance?() }
                sv.onUpdateStreamTapped = { [weak self] in self?.onStreamDetailUpdateStream?() }
                sv.onAutoTopupDisable = { [weak self] in self?.onStreamDetailAutoTopupDisable?() }
                sv.onAutoTopupEnable = { [weak self] in self?.onStreamDetailAutoTopupEnable?() }
                sv.onTitleChanged = { [weak self] v in self?.onStreamDetailTitleChanged?(v) }
                sv.onDescriptionChanged = { [weak self] v in self?.onStreamDetailDescriptionChanged?(v) }
                sv.onTagsChanged = { [weak self] v in self?.onStreamDetailTagsChanged?(v) }
                sv.onNSFWChanged = { [weak self] v in self?.onStreamDetailNSFWChanged?(v) }
                sv.onPublicChanged = { [weak self] v in self?.onStreamDetailPublicChanged?(v) }
                sv.onProtocolChanged = { [weak self] v in self?.onStreamDetailProtocolChanged?(v) }
                sv.onStreamDetailsTapped = { [weak self] in self?.onStreamDetailStreamDetailsTapped?() }
                sv.onVideoTapped = { [weak self] in self?.onStreamDetailVideoTapped?() }
                sv.onAudioTapped = { [weak self] in self?.onStreamDetailAudioTapped?() }
                sv.onPortraitToggled = { [weak self] v in self?.onStreamDetailPortraitToggled?(v) }
                sv.onBackgroundStreamingToggled = { [weak self] v in self?.onStreamDetailBackgroundStreamingChanged?(v) }
                sv.onAutoRecordToggled = { [weak self] v in self?.onStreamDetailAutoRecordChanged?(v) }
                addSubview(sv)
                pinInlineView(sv)
                streamDetailView = sv
            }
            if let data = pendingStreamDetailData {
                streamDetailView?.configure(data: data)
            }
            inlineView = streamDetailView!

        case .streamMetadata:
            if streamMetadataView == nil {
                let mv = InlineStreamMetadataView()
                mv.translatesAutoresizingMaskIntoConstraints = false
                mv.onBack = { [weak self] in self?.showInlineContent(.streamDetail) }
                mv.onTitleChanged = { [weak self] v in self?.onStreamDetailTitleChanged?(v) }
                mv.onDescriptionChanged = { [weak self] v in self?.onStreamDetailDescriptionChanged?(v) }
                mv.onTagsChanged = { [weak self] v in self?.onStreamDetailTagsChanged?(v) }
                mv.onNSFWChanged = { [weak self] v in self?.onStreamDetailNSFWChanged?(v) }
                mv.onPublicChanged = { [weak self] v in self?.onStreamDetailPublicChanged?(v) }
                mv.onProtocolChanged = { [weak self] v in self?.onStreamDetailProtocolChanged?(v) }
                mv.onUpdateTapped = { [weak self] in self?.onStreamDetailUpdateStream?() }
                addSubview(mv)
                pinInlineView(mv)
                streamMetadataView = mv
            }
            if let data = pendingStreamDetailData {
                streamMetadataView?.configure(
                    title: data.streamTitle,
                    description: data.streamDescription,
                    tags: data.streamTags,
                    isNSFW: data.isNSFW,
                    isPublic: data.isPublic,
                    preferredProtocol: data.preferredProtocol,
                    isLive: data.isLive
                )
            }
            inlineView = streamMetadataView!

        case .streamVideo:
            if streamVideoView == nil {
                let vv = InlineStreamVideoView()
                vv.translatesAutoresizingMaskIntoConstraints = false
                vv.onBack = { [weak self] in self?.showInlineContent(.streamDetail) }
                vv.onResolutionSelected = { [weak self] i in self?.onStreamDetailResolutionChanged?(i) }
                vv.onFpsSelected = { [weak self] i in self?.onStreamDetailFpsChanged?(i) }
                vv.onBitrateSelected = { [weak self] i in self?.onStreamDetailBitrateChanged?(i) }
                vv.onAdaptiveResolutionToggled = { [weak self] v in self?.onStreamDetailAdaptiveResolutionChanged?(v) }
                vv.onLowLightBoostToggled = { [weak self] v in self?.onStreamDetailLowLightBoostChanged?(v) }
                addSubview(vv)
                pinInlineView(vv)
                streamVideoView = vv
            }
            if let data = pendingStreamDetailData {
                streamVideoView?.configure(
                    resolutionOptions: data.availableResolutions,
                    activeResolutionIndex: data.resolutionIndex,
                    fpsOptions: data.availableFps,
                    activeFpsIndex: data.fpsIndex,
                    bitrateOptions: data.availableBitrates,
                    activeBitrateIndex: data.bitrateIndex,
                    isAdaptiveResolution: data.isAdaptiveResolution,
                    isLowLightBoostAvailable: data.isLowLightBoostAvailable,
                    isLowLightBoostEnabled: data.isLowLightBoostEnabled,
                    isLocked: data.isLiveOrRecording
                )
            }
            inlineView = streamVideoView!

        case .streamAudio:
            if streamAudioView == nil {
                let av = InlineStreamAudioView()
                av.translatesAutoresizingMaskIntoConstraints = false
                av.onBack = { [weak self] in self?.showInlineContent(.streamDetail) }
                av.onBitrateSelected = { [weak self] kbps in self?.onStreamDetailAudioBitrateChanged?(kbps) }
                addSubview(av)
                pinInlineView(av)
                streamAudioView = av
            }
            if let data = pendingStreamDetailData {
                streamAudioView?.configure(
                    activeBitrateKbps: data.audioBitrateKbps,
                    isLocked: data.isLive
                )
            }
            inlineView = streamAudioView!

        case .collabInvite:
            if collabInviteView == nil {
                let cv = InlineCollabInviteView()
                cv.translatesAutoresizingMaskIntoConstraints = false
                cv.onBack = { [weak self] in self?.showButtonGrid() }
                cv.onInvite = { [weak self] pubkey in self?.onCollabInvite?(pubkey) }
                addSubview(cv)
                pinInlineView(cv)
                collabInviteView = cv
            }
            // Fix 4: activate the subscription each time the view becomes visible.
            // This re-binds the metadataEvents observer that was cancelled in showButtonGrid().
            if let appState = pendingCollabAppState {
                collabInviteView?.activate(appState: appState)
            }
            if !pendingCollabFollows.isEmpty {
                collabInviteView?.configure(follows: pendingCollabFollows)
            }
            inlineView = collabInviteView!

        case .collabCall:
            if collabCallView == nil {
                let cv = InlineCollabCallView()
                cv.translatesAutoresizingMaskIntoConstraints = false
                cv.onBack = { [weak self] in self?.showButtonGrid() }
                cv.onMuteTapped = { [weak self] in self?.onCollabMuteTapped?() }
                cv.onWidgetsTapped = { [weak self] in self?.onCollabWidgetsTapped?() }
                cv.onSkipPipTapped = { [weak self] in self?.onCollabSkipPipTapped?() }
                cv.onVolumeChanged = { [weak self] volume in self?.onCollabVolumeChanged?(volume) }
                cv.onEndCall = { [weak self] in self?.onCollabEndCall?() }
                addSubview(cv)
                pinInlineView(cv)
                collabCallView = cv
            }
            if let data = pendingCollabCallData {
                collabCallView?.configure(
                    state: data.state,
                    isMuted: data.isMuted,
                    sendWidgets: data.sendWidgets,
                    skipPip: data.skipPip,
                    guestVolume: data.guestVolume
                )
            }
            inlineView = collabCallView!

        case .collabIncoming:
            if collabIncomingView == nil {
                let cv = InlineCollabIncomingView()
                cv.translatesAutoresizingMaskIntoConstraints = false
                cv.onAccept = { [weak self] in self?.onCollabAccept?() }
                cv.onDecline = { [weak self] in self?.onCollabDecline?() }
                addSubview(cv)
                pinInlineView(cv)
                collabIncomingView = cv
            }
            if let title = pendingCollabIncomingTitle {
                collabIncomingView?.configure(streamTitle: title)
            }
            inlineView = collabIncomingView!
        }

        // Crossfade: hide zone container, show inline view
        inlineView.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.zoneContainer.alpha = 0
            // Hide all inline views except the target
            for view in [self.exposureView, self.stylesView, self.qualityView,
                         self.stabilizationView, self.bitrateView,
                         self.widgetsView, self.addWidgetView, self.quickConfigView,
                         self.micPickerView, self.sceneView,
                         self.sceneCameraPickerView, self.sceneMicPickerView,
                         self.createSceneView, self.streamDetailView,
                         self.streamMetadataView, self.streamVideoView,
                         self.streamAudioView,
                         self.collabInviteView, self.collabCallView,
                         self.collabIncomingView] as [UIView?] {
                if let v = view, v !== inlineView {
                    v.alpha = 0
                }
            }
            inlineView.alpha = 1
        }
    }

    /// Hide or show the top home indicator bar (hidden in landscape where the side grab handle is used instead)
    func setHomeIndicatorHidden(_ hidden: Bool) {
        homeIndicator.isHidden = hidden
    }

    func showButtonGrid() {
        quickConfigView?.endEditing(true)
        collabInviteView?.endEditing(true)
        // Fix 4: cancel the metadataEvents subscription when the invite view is hidden
        collabInviteView?.deactivate()
        currentInlineContent = nil
        onWillShowButtonGrid?()
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            self.zoneContainer.alpha = 1
            self.exposureView?.alpha = 0
            self.stylesView?.alpha = 0
            self.qualityView?.alpha = 0
            self.stabilizationView?.alpha = 0
            self.bitrateView?.alpha = 0
            self.widgetsView?.alpha = 0
            self.addWidgetView?.alpha = 0
            self.quickConfigView?.alpha = 0
            self.micPickerView?.alpha = 0
            self.sceneView?.alpha = 0
            self.sceneCameraPickerView?.alpha = 0
            self.sceneMicPickerView?.alpha = 0
            self.createSceneView?.alpha = 0
            self.streamDetailView?.alpha = 0
            self.streamMetadataView?.alpha = 0
            self.streamVideoView?.alpha = 0
            self.streamAudioView?.alpha = 0
            self.collabInviteView?.alpha = 0
            self.collabCallView?.alpha = 0
            self.collabIncomingView?.alpha = 0
        } completion: { _ in
            self.onButtonGridShown?()
        }
    }

    private func pinInlineView(_ view: UIView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Widget Data

    func configureWidgets(_ widgets: [InlineWidgetsView.WidgetItem]) {
        pendingWidgetItems = widgets
        widgetsView?.configure(widgets: widgets)
    }

    var pulseWidgetId: UUID? {
        get { widgetsView?.pulseWidgetId }
        set { widgetsView?.pulseWidgetId = newValue }
    }

    func configureQuickConfig(mode: InlineQuickConfigView.Mode) {
        pendingQuickConfigMode = mode
        quickConfigView?.configure(mode: mode)
    }

    /// Lightweight update for the stream detail view's live stats.
    /// Called from the 1s subscription path — only updates if the view is showing.
    func updateStreamDetailLiveStats(
        uptime: String, bitrateMbps: String,
        bitrateColor: UIColor, viewerCount: String,
        balance: Int?, rate: Double
    ) {
        guard currentInlineContent == .streamDetail else { return }
        streamDetailView?.updateLiveStats(
            uptime: uptime, bitrateMbps: bitrateMbps,
            bitrateColor: bitrateColor, viewerCount: viewerCount,
            balance: balance, rate: rate
        )
    }

    func endStreamDetailAutoTopupLoading() {
        streamDetailView?.endAutoTopupLoading()
    }

    func updateStreamDetailAutoTopupState(hasNwc: Bool, hasWallet: Bool, balance: Int? = nil, rate: Double? = nil, walletBalance: Int64? = nil) {
        streamDetailView?.updateAutoTopupState(hasNwc: hasNwc, hasWallet: hasWallet, balance: balance, rate: rate, walletBalance: walletBalance)
    }

    /// Reconfigures the stream detail view with fresh data (e.g., after balance refresh).
    func reconfigureStreamDetail(data: InlineStreamDetailView.StreamDetailData) {
        pendingStreamDetailData = data
        streamDetailView?.configure(data: data)
    }

    // MARK: - Collab Data

    func configureCollabInvite(follows: [InlineCollabInviteView.FollowItem]) {
        pendingCollabFollows = follows
        collabInviteView?.configure(follows: follows)
    }

    func bindCollabInviteAppState(_ appState: AppState) {
        pendingCollabAppState = appState
        collabInviteView?.bindAppState(appState)
    }

    func configureCollabCall(
        state: InlineCollabCallView.DisplayState,
        isMuted: Bool,
        sendWidgets: Bool,
        skipPip: Bool,
        guestVolume: Float = 1.0
    ) {
        pendingCollabCallData = (state: state, isMuted: isMuted, sendWidgets: sendWidgets, skipPip: skipPip, guestVolume: guestVolume)
        collabCallView?.configure(state: state, isMuted: isMuted, sendWidgets: sendWidgets, skipPip: skipPip, guestVolume: guestVolume)
    }

    func configureCollabIncoming(streamTitle: String) {
        pendingCollabIncomingTitle = streamTitle
        collabIncomingView?.configure(streamTitle: streamTitle)
    }
}
