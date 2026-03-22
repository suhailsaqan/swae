import UIKit

/// Inline stream detail view — shows balance, editable metadata, config, live stats inside the modal
/// Follows the same pattern as InlineSceneView
class InlineStreamDetailView: UIView {

    // MARK: - Data

    struct StreamDetailData {
        let streamName: String
        let isZapStream: Bool
        let protocolString: String
        let resolution: String
        let rate: Double
        let balance: Int?
        let isLive: Bool
        let uptime: String
        let bitrateMbps: String
        let bitrateColor: UIColor
        let viewerCount: String
        // Editable metadata
        let streamTitle: String
        let streamDescription: String
        let streamTags: String
        let isNSFW: Bool
        let isPublic: Bool
        let preferredProtocol: Int // 0 = RTMP, 1 = SRT
        // NWC auto-topup state
        let hasNwc: Bool
        let hasWallet: Bool
        let walletBalance: Int64?  // Coinos wallet balance in millisats, nil if not loaded
        // Video sub-page data
        let resolutionIndex: Int
        let availableResolutions: [String]
        let fpsIndex: Int
        let availableFps: [String]
        let isAdaptiveResolution: Bool
        let isLowLightBoostAvailable: Bool
        let isLowLightBoostEnabled: Bool
        // Audio sub-page data
        let audioBitrateKbps: Int
        // Hub page toggle data
        let isPortrait: Bool
        let isBackgroundStreaming: Bool
        let isAutoRecord: Bool
        let isLiveOrRecording: Bool
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onTopUpTapped: (() -> Void)?
    var onWalletReceiveTapped: (() -> Void)?
    var onStreamSettingsTapped: (() -> Void)?
    var onRefreshBalance: (() -> Void)?
    var onAutoTopupDisable: (() -> Void)?
    var onAutoTopupEnable: (() -> Void)?

    // Metadata edit callbacks
    var onTitleChanged: ((String) -> Void)?
    var onDescriptionChanged: ((String) -> Void)?
    var onTagsChanged: ((String) -> Void)?
    var onNSFWChanged: ((Bool) -> Void)?
    var onPublicChanged: ((Bool) -> Void)?
    var onProtocolChanged: ((Int) -> Void)?

    var onUpdateStreamTapped: (() -> Void)?

    // Navigation callbacks (hub → sub-pages)
    var onStreamDetailsTapped: (() -> Void)?
    var onVideoTapped: (() -> Void)?
    var onAudioTapped: (() -> Void)?

    // Inline toggle callbacks
    var onPortraitToggled: ((Bool) -> Void)?
    var onBackgroundStreamingToggled: ((Bool) -> Void)?
    var onAutoRecordToggled: ((Bool) -> Void)?

    // MARK: - State

    private var isZapStream = false
    private var currentIsLive = false
    private var currentHasNwc = false
    private var currentHasWallet = false
    private var currentWalletBalance: Int64?  // Coinos wallet balance in millisats

    // Skeleton loading state
    private var isShowingBalanceSkeleton = false
    private let balanceSkeleton = SkeletonView()
    private let runwaySkeleton = SkeletonView()
    private let runwayTextSkeleton = SkeletonView()
    private let rateSkeleton = SkeletonView()

    // MARK: - Balance Formatter

    private static let balanceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    // Balance section
    private let balanceSection = UIView()
    private let balanceIcon = UIImageView()
    private let balanceValueLabel = UILabel()
    private let runwayBar = UIProgressView()
    private let runwayLabel = UILabel()
    private let autoTopupIndicator = UIView()
    private let autoTopupIcon = UIImageView()
    private let autoTopupLabel = UILabel()
    private let topUpButton = UIButton(type: .system)
    private let enableAutoTopupButton = UIButton(type: .system)
    private let enableAutoTopupSpinner = UIActivityIndicatorView(style: .medium)
    private let balanceSpinner = UIActivityIndicatorView(style: .medium)
    private let refreshButton = UIButton(type: .system)

    // Editable metadata section
    private let metadataSection = UIView()
    private let titleField = UITextField()
    private let descriptionField = UITextField()
    private let tagsField = UITextField()
    private let nsfwToggle = UISwitch()
    private let publicToggle = UISwitch()
    private let protocolSegment = UISegmentedControl(items: ["RTMP", "SRT"])

    // Config rows
    private let streamTypeValueLabel = UILabel()
    private let resolutionValueLabel = UILabel()
    private let rateValueLabel = UILabel()

    // Live stats section
    private let liveStatsHeader = UILabel()
    private let uptimeValueLabel = UILabel()
    private let bitrateValueLabel = UILabel()
    private let viewerValueLabel = UILabel()

    // Bottom buttons
    private let buttonContainer = UIStackView()
    private let updateButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)

    // Balance section bottom stack (auto-topup indicator + buttons)
    private var balanceBottomStack: UIStackView!

    // MARK: - Init

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
        backgroundColor = .clear

        setupKeyboardObservers()

        // Back button
        backButton.translatesAutoresizingMaskIntoConstraints = false
        let backConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "STREAM INFO"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        // Stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        scrollView.addSubview(stack)

        // Bottom button container (horizontal stack)
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.axis = .horizontal
        buttonContainer.spacing = 10
        buttonContainer.distribution = .fillEqually
        addSubview(buttonContainer)

        // Yellow "Update" button (shown only when live)
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        updateButton.setTitle("Update", for: .normal)
        updateButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        updateButton.setTitleColor(.black, for: .normal)
        updateButton.backgroundColor = .systemYellow
        updateButton.layer.cornerRadius = 22
        updateButton.layer.cornerCurve = .continuous
        updateButton.addTarget(self, action: #selector(updateTapped), for: .touchUpInside)
        updateButton.isHidden = true
        buttonContainer.addArrangedSubview(updateButton)

        // Gray "Stream Settings" button
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        let gearConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: gearConfig), for: .normal)
        settingsButton.setTitle("  Stream Settings", for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.tintColor = .white
        settingsButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        settingsButton.layer.cornerRadius = 22
        settingsButton.layer.cornerCurve = .continuous
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        buttonContainer.addArrangedSubview(settingsButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            buttonContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: 44),
            buttonContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        buildBalanceSection()
        buildMetadataSection()
        buildConfigSection()
        buildNavigationSection()
        buildToggleSection()
        buildLiveStatsSection()
    }

    // MARK: - Build Sections

    private func buildBalanceSection() {
        balanceSection.translatesAutoresizingMaskIntoConstraints = false

        balanceIcon.translatesAutoresizingMaskIntoConstraints = false
        let boltConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        balanceIcon.image = UIImage(systemName: "bolt.fill", withConfiguration: boltConfig)
        balanceIcon.tintColor = .systemYellow
        balanceSection.addSubview(balanceIcon)

        balanceValueLabel.translatesAutoresizingMaskIntoConstraints = false
        balanceValueLabel.font = .systemFont(ofSize: 22, weight: .bold)
        balanceValueLabel.textColor = .white
        balanceSection.addSubview(balanceValueLabel)

        balanceSpinner.translatesAutoresizingMaskIntoConstraints = false
        balanceSpinner.color = .white
        balanceSpinner.hidesWhenStopped = true
        balanceSection.addSubview(balanceSpinner)

        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        let refreshConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        refreshButton.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: refreshConfig), for: .normal)
        refreshButton.tintColor = UIColor(white: 1.0, alpha: 0.5)
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        balanceSection.addSubview(refreshButton)

        runwayBar.translatesAutoresizingMaskIntoConstraints = false
        runwayBar.trackTintColor = UIColor(white: 1.0, alpha: 0.1)
        runwayBar.progressTintColor = .systemGreen
        balanceSection.addSubview(runwayBar)

        runwayLabel.translatesAutoresizingMaskIntoConstraints = false
        runwayLabel.font = .systemFont(ofSize: 12, weight: .regular)
        runwayLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        balanceSection.addSubview(runwayLabel)

        topUpButton.translatesAutoresizingMaskIntoConstraints = false
        let topUpBoltConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        topUpButton.setImage(UIImage(systemName: "bolt.fill", withConfiguration: topUpBoltConfig), for: .normal)
        topUpButton.setTitle("  Top Up Balance", for: .normal)
        topUpButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        topUpButton.setTitleColor(.white, for: .normal)
        topUpButton.tintColor = .systemYellow
        topUpButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
        topUpButton.layer.cornerRadius = 18
        topUpButton.addTarget(self, action: #selector(topUpTapped), for: .touchUpInside)

        // Auto-topup indicator (hidden by default)
        autoTopupIndicator.translatesAutoresizingMaskIntoConstraints = false
        autoTopupIndicator.isHidden = true

        autoTopupIcon.translatesAutoresizingMaskIntoConstraints = false
        let checkConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        autoTopupIcon.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: checkConfig)
        autoTopupIcon.tintColor = .systemGreen
        autoTopupIndicator.addSubview(autoTopupIcon)

        autoTopupLabel.translatesAutoresizingMaskIntoConstraints = false
        autoTopupLabel.text = "Auto-paying from your wallet"
        autoTopupLabel.font = .systemFont(ofSize: 12, weight: .medium)
        autoTopupLabel.textColor = .systemGreen
        autoTopupIndicator.addSubview(autoTopupLabel)

        let disableButton = UIButton(type: .system)
        disableButton.translatesAutoresizingMaskIntoConstraints = false
        disableButton.setTitle("Disable", for: .normal)
        disableButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        disableButton.setTitleColor(.systemRed, for: .normal)
        disableButton.addTarget(self, action: #selector(autoTopupDisableTapped), for: .touchUpInside)
        autoTopupIndicator.addSubview(disableButton)

        NSLayoutConstraint.activate([
            autoTopupIcon.leadingAnchor.constraint(equalTo: autoTopupIndicator.leadingAnchor),
            autoTopupIcon.centerYAnchor.constraint(equalTo: autoTopupIndicator.centerYAnchor),
            autoTopupLabel.leadingAnchor.constraint(equalTo: autoTopupIcon.trailingAnchor, constant: 4),
            autoTopupLabel.centerYAnchor.constraint(equalTo: autoTopupIndicator.centerYAnchor),
            disableButton.leadingAnchor.constraint(greaterThanOrEqualTo: autoTopupLabel.trailingAnchor, constant: 8),
            disableButton.trailingAnchor.constraint(equalTo: autoTopupIndicator.trailingAnchor),
            disableButton.centerYAnchor.constraint(equalTo: autoTopupIndicator.centerYAnchor),
            autoTopupIndicator.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Enable auto-topup button (hidden by default, shown when wallet connected but NWC not configured)
        enableAutoTopupButton.translatesAutoresizingMaskIntoConstraints = false
        enableAutoTopupButton.setTitle("Auto-Pay From Wallet", for: .normal)
        enableAutoTopupButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        enableAutoTopupButton.setTitleColor(.black, for: .normal)
        enableAutoTopupButton.tintColor = .black
        enableAutoTopupButton.backgroundColor = .systemGreen
        enableAutoTopupButton.layer.cornerRadius = 18
        enableAutoTopupButton.addTarget(self, action: #selector(enableAutoTopupTapped), for: .touchUpInside)
        enableAutoTopupButton.isHidden = true

        enableAutoTopupSpinner.translatesAutoresizingMaskIntoConstraints = false
        enableAutoTopupSpinner.color = UIColor.black
        enableAutoTopupSpinner.hidesWhenStopped = true
        enableAutoTopupButton.addSubview(enableAutoTopupSpinner)
        NSLayoutConstraint.activate([
            enableAutoTopupSpinner.centerXAnchor.constraint(equalTo: enableAutoTopupButton.centerXAnchor),
            enableAutoTopupSpinner.centerYAnchor.constraint(equalTo: enableAutoTopupButton.centerYAnchor),
        ])

        // Horizontal row for the two buttons (side by side, equal width)
        let buttonRow = UIStackView(arrangedSubviews: [enableAutoTopupButton, topUpButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fillEqually
        buttonRow.heightAnchor.constraint(equalToConstant: 36).isActive = true

        // Vertical stack: indicator on top, button row below
        let bottomStack = UIStackView(arrangedSubviews: [autoTopupIndicator, buttonRow])
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.axis = .vertical
        bottomStack.spacing = 8
        bottomStack.alignment = .fill
        balanceSection.addSubview(bottomStack)
        balanceBottomStack = bottomStack

        NSLayoutConstraint.activate([
            balanceIcon.leadingAnchor.constraint(equalTo: balanceSection.leadingAnchor, constant: 12),
            balanceIcon.topAnchor.constraint(equalTo: balanceSection.topAnchor, constant: 8),

            balanceValueLabel.leadingAnchor.constraint(equalTo: balanceIcon.trailingAnchor, constant: 6),
            balanceValueLabel.centerYAnchor.constraint(equalTo: balanceIcon.centerYAnchor),

            balanceSpinner.leadingAnchor.constraint(equalTo: balanceIcon.trailingAnchor, constant: 8),
            balanceSpinner.centerYAnchor.constraint(equalTo: balanceIcon.centerYAnchor),

            refreshButton.trailingAnchor.constraint(equalTo: balanceSection.trailingAnchor, constant: -12),
            refreshButton.centerYAnchor.constraint(equalTo: balanceIcon.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 32),
            refreshButton.heightAnchor.constraint(equalToConstant: 32),

            runwayBar.topAnchor.constraint(equalTo: balanceIcon.bottomAnchor, constant: 8),
            runwayBar.leadingAnchor.constraint(equalTo: balanceSection.leadingAnchor, constant: 12),
            runwayBar.trailingAnchor.constraint(equalTo: balanceSection.trailingAnchor, constant: -12),

            runwayLabel.topAnchor.constraint(equalTo: runwayBar.bottomAnchor, constant: 4),
            runwayLabel.leadingAnchor.constraint(equalTo: balanceSection.leadingAnchor, constant: 12),

            bottomStack.topAnchor.constraint(equalTo: runwayLabel.bottomAnchor, constant: 8),
            bottomStack.leadingAnchor.constraint(equalTo: balanceSection.leadingAnchor, constant: 12),
            bottomStack.trailingAnchor.constraint(equalTo: balanceSection.trailingAnchor, constant: -12),
            bottomStack.bottomAnchor.constraint(equalTo: balanceSection.bottomAnchor, constant: -4),
        ])

        // Skeleton overlays for loading state
        balanceSkeleton.translatesAutoresizingMaskIntoConstraints = false
        balanceSkeleton.layer.cornerRadius = 4
        balanceSkeleton.useDarkStyle()
        balanceSkeleton.isHidden = true
        balanceSection.addSubview(balanceSkeleton)

        runwaySkeleton.translatesAutoresizingMaskIntoConstraints = false
        runwaySkeleton.layer.cornerRadius = 2
        runwaySkeleton.useDarkStyle()
        runwaySkeleton.isHidden = true
        balanceSection.addSubview(runwaySkeleton)

        runwayTextSkeleton.translatesAutoresizingMaskIntoConstraints = false
        runwayTextSkeleton.layer.cornerRadius = 3
        runwayTextSkeleton.useDarkStyle()
        runwayTextSkeleton.isHidden = true
        balanceSection.addSubview(runwayTextSkeleton)

        NSLayoutConstraint.activate([
            balanceSkeleton.leadingAnchor.constraint(equalTo: balanceIcon.trailingAnchor, constant: 6),
            balanceSkeleton.centerYAnchor.constraint(equalTo: balanceIcon.centerYAnchor),
            balanceSkeleton.widthAnchor.constraint(equalToConstant: 120),
            balanceSkeleton.heightAnchor.constraint(equalToConstant: 20),

            runwaySkeleton.topAnchor.constraint(equalTo: balanceSkeleton.bottomAnchor, constant: 12),
            runwaySkeleton.leadingAnchor.constraint(equalTo: balanceSection.leadingAnchor, constant: 12),
            runwaySkeleton.trailingAnchor.constraint(equalTo: balanceSection.trailingAnchor, constant: -12),
            runwaySkeleton.heightAnchor.constraint(equalToConstant: 6),

            runwayTextSkeleton.topAnchor.constraint(equalTo: runwaySkeleton.bottomAnchor, constant: 10),
            runwayTextSkeleton.leadingAnchor.constraint(equalTo: balanceSection.leadingAnchor, constant: 12),
            runwayTextSkeleton.widthAnchor.constraint(equalToConstant: 130),
            runwayTextSkeleton.heightAnchor.constraint(equalToConstant: 14),
        ])

        stack.addArrangedSubview(balanceSection)
    }

    private func buildMetadataSection() {
        let sep = makeSeparator()
        sep.tag = 899
        stack.addArrangedSubview(sep)

        let header = makeSectionHeader("STREAM METADATA")
        header.tag = 900
        stack.addArrangedSubview(header)

        // Title field
        let titleRow = makeEditableRow(label: "Title", field: titleField, placeholder: "Stream title")
        titleRow.tag = 901
        titleField.addTarget(self, action: #selector(titleFieldChanged), for: .editingChanged)
        stack.addArrangedSubview(titleRow)

        // Description field
        let descRow = makeEditableRow(label: "Description", field: descriptionField, placeholder: "What are you streaming?")
        descRow.tag = 902
        descriptionField.addTarget(self, action: #selector(descriptionFieldChanged), for: .editingChanged)
        stack.addArrangedSubview(descRow)

        // Tags field
        let tagsRow = makeEditableRow(label: "Tags", field: tagsField, placeholder: "gaming, nostr, music")
        tagsRow.tag = 903
        tagsField.addTarget(self, action: #selector(tagsFieldChanged), for: .editingChanged)
        stack.addArrangedSubview(tagsRow)

        // NSFW toggle row
        let nsfwRow = makeToggleRow(label: "NSFW", toggle: nsfwToggle)
        nsfwRow.tag = 904
        nsfwToggle.addTarget(self, action: #selector(nsfwToggleChanged), for: .valueChanged)
        stack.addArrangedSubview(nsfwRow)

        // Public toggle row
        let publicRow = makeToggleRow(label: "Public Stream", toggle: publicToggle)
        publicRow.tag = 905
        publicToggle.addTarget(self, action: #selector(publicToggleChanged), for: .valueChanged)
        stack.addArrangedSubview(publicRow)

        // Protocol picker row
        let protoRow = makeSegmentRow(label: "Protocol", segment: protocolSegment)
        protoRow.tag = 906
        protocolSegment.selectedSegmentIndex = 0
        protocolSegment.addTarget(self, action: #selector(protocolChanged), for: .valueChanged)
        stack.addArrangedSubview(protoRow)
    }

    // MARK: - Navigation Rows (hub → sub-pages)

    private let streamDetailsNavRow = UIView()
    private let streamDetailsSubtitle = UILabel()
    private let videoNavRow = UIView()
    private let videoSubtitle = UILabel()
    private let audioNavRow = UIView()
    private let audioSubtitle = UILabel()

    private func buildNavigationSection() {
        let sep = makeSeparator()
        sep.tag = 950
        stack.addArrangedSubview(sep)

        // Stream Details row (Zap Stream only)
        buildNavRow(row: streamDetailsNavRow, title: "Stream Details", subtitle: streamDetailsSubtitle, subtitleText: "Title, description, tags...", tag: 951, action: #selector(streamDetailsTapped))
        stack.addArrangedSubview(streamDetailsNavRow)

        let sep2 = makeSeparator()
        sep2.tag = 952
        stack.addArrangedSubview(sep2)

        // Video row
        buildNavRow(row: videoNavRow, title: "Video", subtitle: videoSubtitle, subtitleText: "1080p · 30 FPS", tag: 953, action: #selector(videoNavTapped))
        stack.addArrangedSubview(videoNavRow)

        // Audio row
        buildNavRow(row: audioNavRow, title: "Audio", subtitle: audioSubtitle, subtitleText: "128 Kbps", tag: 954, action: #selector(audioNavTapped))
        stack.addArrangedSubview(audioNavRow)
    }

    private func buildNavRow(row: UIView, title: String, subtitle: UILabel, subtitleText: String, tag: Int, action: Selector) {
        row.translatesAutoresizingMaskIntoConstraints = false
        row.tag = tag
        row.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let titleLbl = UILabel()
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.text = title
        titleLbl.font = .systemFont(ofSize: 14, weight: .medium)
        titleLbl.textColor = UIColor(white: 1.0, alpha: 0.88)
        row.addSubview(titleLbl)

        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = subtitleText
        subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = UIColor(white: 1.0, alpha: 0.4)
        row.addSubview(subtitle)

        let chevConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: chevConfig))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = UIColor(white: 1.0, alpha: 0.3)
        row.addSubview(chevron)

        NSLayoutConstraint.activate([
            titleLbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            titleLbl.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            subtitle.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 2),
            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: action)
        row.addGestureRecognizer(tap)
        row.isUserInteractionEnabled = true
    }

    // MARK: - Inline Toggles

    private let portraitToggle = UISwitch()
    private let bgStreamToggle = UISwitch()
    private let autoRecordToggle = UISwitch()

    private func buildToggleSection() {
        let sep = makeSeparator()
        sep.tag = 960
        stack.addArrangedSubview(sep)

        let pRow = makeInlineToggleRow(label: "Portrait", toggle: portraitToggle, tag: 961)
        portraitToggle.addTarget(self, action: #selector(portraitChanged), for: .valueChanged)
        stack.addArrangedSubview(pRow)

        let bgRow = makeInlineToggleRow(label: "Background Streaming", toggle: bgStreamToggle, tag: 962)
        bgStreamToggle.addTarget(self, action: #selector(bgStreamChanged), for: .valueChanged)
        stack.addArrangedSubview(bgRow)

        let arRow = makeInlineToggleRow(label: "Auto-Record", toggle: autoRecordToggle, tag: 963)
        autoRecordToggle.addTarget(self, action: #selector(autoRecordChanged), for: .valueChanged)
        stack.addArrangedSubview(arRow)
    }

    private func makeInlineToggleRow(label: String, toggle: UISwitch, tag: Int) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.tag = tag
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = label
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.7)
        row.addSubview(lbl)

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        toggle.onTintColor = .systemGreen
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func buildConfigSection() {
        let sep = makeSeparator()
        sep.tag = 970
        stack.addArrangedSubview(sep)

        // Stream type row
        let streamRow = makeInfoRow(icon: "antenna.radiowaves.left.and.right", title: "Stream", valueLabel: streamTypeValueLabel)
        streamRow.tag = 971
        stack.addArrangedSubview(streamRow)

        // Rate row (Zap Stream only)
        let rRow = makeInfoRow(icon: "bitcoinsign.circle", title: "Rate", valueLabel: rateValueLabel)
        rRow.tag = 999
        stack.addArrangedSubview(rRow)

        // Rate skeleton overlay
        rateSkeleton.translatesAutoresizingMaskIntoConstraints = false
        rateSkeleton.layer.cornerRadius = 3
        rateSkeleton.useDarkStyle()
        rateSkeleton.isHidden = true
        rRow.addSubview(rateSkeleton)
        NSLayoutConstraint.activate([
            rateSkeleton.trailingAnchor.constraint(equalTo: rRow.trailingAnchor, constant: -12),
            rateSkeleton.centerYAnchor.constraint(equalTo: rRow.centerYAnchor),
            rateSkeleton.widthAnchor.constraint(equalToConstant: 80),
            rateSkeleton.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    private func buildLiveStatsSection() {
        let sep = makeSeparator()
        sep.tag = 998
        stack.addArrangedSubview(sep)

        let headerContainer = makeSectionHeader("LIVE STATS")
        headerContainer.tag = 997
        stack.addArrangedSubview(headerContainer)

        let uptimeRow = makeInfoRow(icon: "timer", title: "Uptime", valueLabel: uptimeValueLabel)
        uptimeRow.tag = 996
        uptimeValueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(uptimeRow)

        let bitrateRow = makeInfoRow(icon: "arrow.up", title: "Bitrate", valueLabel: bitrateValueLabel)
        bitrateRow.tag = 995
        bitrateValueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(bitrateRow)

        let viewerRow = makeInfoRow(icon: "eye", title: "Viewers", valueLabel: viewerValueLabel)
        viewerRow.tag = 994
        viewerValueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(viewerRow)
    }

    // MARK: - Public API

    func configure(data: StreamDetailData) {
        isZapStream = data.isZapStream
        currentIsLive = data.isLive
        currentHasNwc = data.hasNwc
        currentHasWallet = data.hasWallet
        currentWalletBalance = data.walletBalance

        // Balance section visibility
        balanceSection.isHidden = !data.isZapStream

        // Metadata section: always hidden on hub page (moved to streamMetadata sub-page)
        let metadataTags = [899, 900, 901, 902, 903, 904, 905, 906]
        for tag in metadataTags {
            stack.arrangedSubviews.first(where: { $0.tag == tag })?.isHidden = true
        }
        // Also hide the separator before metadata if not zap stream
        // (it's the first separator after balance)

        // Rate row visibility
        if let rateRow = stack.arrangedSubviews.first(where: { $0.tag == 999 }) {
            rateRow.isHidden = !data.isZapStream
        }

        // Live stats visibility
        let liveStatsTags = [998, 997, 996, 995, 994]
        for tag in liveStatsTags {
            stack.arrangedSubviews.first(where: { $0.tag == tag })?.isHidden = !data.isLive
        }

        // Balance
        updateBalanceDisplay(balance: data.balance, rate: data.rate)

        // NWC auto-topup state — hide during skeleton to prevent layout jump
        autoTopupIndicator.isHidden = !data.hasNwc || isShowingBalanceSkeleton
        enableAutoTopupButton.isHidden = data.hasNwc || !data.hasWallet || isShowingBalanceSkeleton
        if data.hasNwc {
            topUpButton.setTitle("Fund Wallet", for: .normal)
            topUpButton.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            topUpButton.tintColor = UIColor(white: 1.0, alpha: 0.5)
            topUpButton.setTitleColor(UIColor(white: 1.0, alpha: 0.5), for: .normal)
            topUpButton.setImage(nil, for: .normal)
        } else if data.hasWallet {
            topUpButton.setTitle("Top Up", for: .normal)
            topUpButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
            topUpButton.tintColor = .systemYellow
            topUpButton.setTitleColor(.white, for: .normal)
            topUpButton.setImage(nil, for: .normal)
        } else {
            topUpButton.setTitle("  Top Up Balance", for: .normal)
            topUpButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
            topUpButton.tintColor = .systemYellow
            topUpButton.setTitleColor(.white, for: .normal)
            let boltCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            topUpButton.setImage(UIImage(systemName: "bolt.fill", withConfiguration: boltCfg), for: .normal)
        }

        // Metadata fields
        titleField.text = data.streamTitle
        descriptionField.text = data.streamDescription
        tagsField.text = data.streamTags
        nsfwToggle.isOn = data.isNSFW
        publicToggle.isOn = data.isPublic
        protocolSegment.selectedSegmentIndex = data.preferredProtocol

        // Config — show Stream type + Rate between balance and nav rows
        // Hide config section separator and stream row for non-Zap streams
        let configTags = [970, 971, 999]
        for tag in configTags {
            stack.arrangedSubviews.first(where: { $0.tag == tag })?.isHidden = !data.isZapStream
        }
        streamTypeValueLabel.text = data.protocolString
        if data.isZapStream {
            if data.rate > 0 {
                rateValueLabel.text = "\(Int(data.rate)) sats/min"
                rateValueLabel.isHidden = false
                rateSkeleton.isHidden = true
                rateSkeleton.stopAnimating()
            } else {
                rateValueLabel.isHidden = true
                rateSkeleton.isHidden = false
                rateSkeleton.startAnimating(delay: 0.2)
            }
        }

        // Live stats
        uptimeValueLabel.text = data.uptime
        bitrateValueLabel.text = "\(data.bitrateMbps) Mbps"
        bitrateValueLabel.textColor = data.bitrateColor
        viewerValueLabel.text = data.viewerCount

        // Bottom buttons: show Update only when live on zap stream
        updateButton.isHidden = !(data.isZapStream && data.isLive)
        updateButton.setTitle("Update", for: .normal)

        // Navigation rows
        // Stream Details row: only for Zap Stream
        let navZapTags = [950, 951, 952]
        for tag in navZapTags {
            stack.arrangedSubviews.first(where: { $0.tag == tag })?.isHidden = !data.isZapStream
        }

        // Video subtitle
        var videoSub = "\(data.resolution) · \(data.availableFps.isEmpty ? "" : "\(data.availableFps[data.fpsIndex]) FPS")"
        if data.isAdaptiveResolution { videoSub += " · Adaptive" }
        videoSubtitle.text = videoSub

        // Audio subtitle
        audioSubtitle.text = "\(data.audioBitrateKbps) Kbps"

        // Inline toggles
        portraitToggle.isOn = data.isPortrait
        portraitToggle.isEnabled = !data.isLiveOrRecording
        bgStreamToggle.isOn = data.isBackgroundStreaming
        autoRecordToggle.isOn = data.isAutoRecord
    }

    /// Lightweight update called every ~1s from the subscription path.
    func updateLiveStats(
        uptime: String, bitrateMbps: String,
        bitrateColor: UIColor, viewerCount: String,
        balance: Int?, rate: Double
    ) {
        uptimeValueLabel.text = uptime
        bitrateValueLabel.text = "\(bitrateMbps) Mbps"
        bitrateValueLabel.textColor = bitrateColor
        viewerValueLabel.text = viewerCount

        if isZapStream {
            updateBalanceDisplay(balance: balance, rate: rate)
        }
    }

    // MARK: - Balance Skeleton

    private func showBalanceSkeleton() {
        guard !isShowingBalanceSkeleton else { return }
        isShowingBalanceSkeleton = true

        // Cancel any in-progress hide animation
        balanceSkeleton.layer.removeAllAnimations()
        runwaySkeleton.layer.removeAllAnimations()
        runwayTextSkeleton.layer.removeAllAnimations()

        // Hide real content — use alpha to keep layout anchors for the skeleton positioning
        balanceValueLabel.alpha = 0
        runwayBar.alpha = 0
        runwayLabel.alpha = 0
        // Collapse the bottom stack to remove the empty gap
        balanceBottomStack?.isHidden = true

        // Show and animate skeletons
        balanceSkeleton.alpha = 1
        runwaySkeleton.alpha = 1
        runwayTextSkeleton.alpha = 1
        balanceSkeleton.isHidden = false
        runwaySkeleton.isHidden = false
        runwayTextSkeleton.isHidden = false
        balanceSkeleton.startAnimating(delay: 0)
        runwaySkeleton.startAnimating(delay: 0.1)
        runwayTextSkeleton.startAnimating(delay: 0.15)
    }

    private func hideBalanceSkeleton() {
        guard isShowingBalanceSkeleton else { return }
        isShowingBalanceSkeleton = false

        // Restore real content visibility
        balanceValueLabel.alpha = 1
        runwayBar.alpha = 1
        runwayLabel.alpha = 1
        balanceBottomStack?.isHidden = false

        // Cross-fade skeleton out
        UIView.animate(withDuration: 0.25) {
            self.balanceSkeleton.alpha = 0
            self.runwaySkeleton.alpha = 0
            self.runwayTextSkeleton.alpha = 0
        } completion: { _ in
            self.balanceSkeleton.isHidden = true
            self.runwaySkeleton.isHidden = true
            self.runwayTextSkeleton.isHidden = true
            self.balanceSkeleton.stopAnimating()
            self.runwaySkeleton.stopAnimating()
            self.runwayTextSkeleton.stopAnimating()
            self.balanceSkeleton.alpha = 1
            self.runwaySkeleton.alpha = 1
            self.runwayTextSkeleton.alpha = 1
        }
    }

    // MARK: - Balance Display

    private func updateBalanceDisplay(balance: Int?, rate: Double) {
        // When auto top-up is active AND a local wallet is connected, show the wallet balance
        if currentHasNwc && currentHasWallet {
            balanceSpinner.stopAnimating()
            balanceIcon.tintColor = .systemGreen

            let walletSats = Int((currentWalletBalance ?? 0) / 1000)

            if currentWalletBalance == nil {
                // Wallet balance not loaded yet — show shimmer skeleton
                showBalanceSkeleton()
                return
            }
            hideBalanceSkeleton()

            if walletSats == 0 {
                // Wallet is empty — warn the user
                balanceIcon.tintColor = .systemOrange
                balanceValueLabel.text = "0 sats in wallet"
                balanceValueLabel.isHidden = false
                balanceValueLabel.alpha = 1.0
                runwayBar.isHidden = true
                runwayBar.trackTintColor = UIColor(white: 1.0, alpha: 0.1)
                runwayLabel.text = "Fund your wallet to stream"
                runwayLabel.isHidden = false
            } else {
                // Wallet has funds — show balance and runway
                let formatted = Self.balanceFormatter.string(from: NSNumber(value: walletSats)) ?? "\(walletSats)"
                balanceValueLabel.text = "\(formatted) sats in wallet"
                balanceValueLabel.isHidden = false
                balanceValueLabel.alpha = 1.0

                if rate > 0 {
                    let minutesLeft = Double(walletSats) / rate
                    let maxMinutes: Double = 600
                    runwayBar.isHidden = false
                    runwayBar.trackTintColor = UIColor(white: 1.0, alpha: 0.1)
                    runwayBar.progress = Float(min(minutesLeft / maxMinutes, 1.0))
                    runwayBar.progressTintColor = minutesLeft < 60 ? .systemRed : (minutesLeft < 120 ? .systemOrange : .systemGreen)

                    if minutesLeft >= 60 {
                        let hours = Int(minutesLeft / 60)
                        let mins = Int(minutesLeft.truncatingRemainder(dividingBy: 60))
                        runwayLabel.text = "~\(hours)h \(mins)m • \(Int(rate)) sats/min"
                    } else {
                        runwayLabel.text = "~\(Int(minutesLeft))m • \(Int(rate)) sats/min"
                    }
                } else {
                    runwayBar.isHidden = true
                    runwayLabel.text = ""
                }
            }
            runwayLabel.isHidden = false
            return
        }

        // Standard balance display when no auto top-up
        runwayBar.isHidden = false
        balanceIcon.tintColor = .systemYellow

        if let balance {
            hideBalanceSkeleton()
            balanceSpinner.stopAnimating()
            let formatted = Self.balanceFormatter.string(from: NSNumber(value: balance)) ?? "\(balance)"
            balanceValueLabel.text = "\(formatted) sats"
            balanceValueLabel.isHidden = false
            balanceValueLabel.alpha = 1.0
            runwayBar.trackTintColor = UIColor(white: 1.0, alpha: 0.1)

            if rate > 0 {
                let minutesLeft = Double(balance) / rate
                let maxMinutes: Double = 600
                runwayBar.progress = Float(min(minutesLeft / maxMinutes, 1.0))

                if minutesLeft >= 60 {
                    let hours = Int(minutesLeft / 60)
                    let mins = Int(minutesLeft.truncatingRemainder(dividingBy: 60))
                    runwayLabel.text = "~\(hours)h \(mins)m of streaming"
                } else {
                    runwayLabel.text = "~\(Int(minutesLeft))m of streaming"
                }

                if minutesLeft < 60 {
                    runwayBar.progressTintColor = .systemRed
                } else if minutesLeft < 120 {
                    runwayBar.progressTintColor = .systemOrange
                } else {
                    runwayBar.progressTintColor = .systemGreen
                }
            } else {
                runwayBar.progress = 0
                runwayLabel.text = ""
            }
        } else {
            // Balance not loaded yet — show shimmer skeleton
            showBalanceSkeleton()
        }
    }

    // MARK: - Row Builders

    private func makeInfoRow(icon: String, title: String, valueLabel: UILabel) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.image = UIImage(systemName: icon, withConfiguration: config)
        iconView.tintColor = UIColor(white: 1.0, alpha: 0.5)
        row.addSubview(iconView)

        let titleLbl = UILabel()
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.text = title
        titleLbl.font = .systemFont(ofSize: 14, weight: .medium)
        titleLbl.textColor = UIColor(white: 1.0, alpha: 0.7)
        row.addSubview(titleLbl)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .systemFont(ofSize: 14, weight: .regular)
        valueLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        valueLabel.textAlignment = .right
        row.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),

            titleLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLbl.trailingAnchor, constant: 8),
        ])

        return row
    }

    private func makeEditableRow(label: String, field: UITextField, placeholder: String) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = label
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.5)
        row.addSubview(lbl)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 14, weight: .regular)
        field.textColor = .white
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.25)]
        )
        field.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        field.layer.cornerRadius = 8
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.rightViewMode = .always
        field.returnKeyType = .done
        field.delegate = self
        row.addSubview(field)

        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),

            field.topAnchor.constraint(equalTo: lbl.bottomAnchor, constant: 4),
            field.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            field.heightAnchor.constraint(equalToConstant: 36),
            field.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
        ])

        return row
    }

    private func makeToggleRow(label: String, toggle: UISwitch) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = label
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.7)
        row.addSubview(lbl)

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        toggle.onTintColor = .systemGreen
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }

    private func makeSegmentRow(label: String, segment: UISegmentedControl) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = label
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.7)
        row.addSubview(lbl)

        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.selectedSegmentTintColor = UIColor(white: 1.0, alpha: 0.2)
        segment.setTitleTextAttributes([.foregroundColor: UIColor(white: 1.0, alpha: 0.5)], for: .normal)
        segment.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        row.addSubview(segment)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            segment.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            segment.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            segment.widthAnchor.constraint(equalToConstant: 120),
        ])

        return row
    }

    private func makeSeparator() -> UIView {
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    private func makeSectionHeader(_ text: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = text
        lbl.font = .systemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.4)
        container.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            lbl.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            lbl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        return container
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let kbFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let kbHeight = kbFrame.height
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25

        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = kbHeight
            self.scrollView.verticalScrollIndicatorInsets.bottom = kbHeight
        }

        // Scroll the active field into view
        if let activeField = [titleField, descriptionField, tagsField].first(where: { $0.isFirstResponder }) {
            let fieldRect = activeField.convert(activeField.bounds, to: scrollView)
            scrollView.scrollRectToVisible(fieldRect.insetBy(dx: 0, dy: -20), animated: true)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25

        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions

    @objc private func backTapped() { onBack?() }
    @objc private func topUpTapped() {
        if currentHasNwc {
            onWalletReceiveTapped?()
        } else {
            onTopUpTapped?()
        }
    }
    @objc private func settingsTapped() { onStreamSettingsTapped?() }

    @objc private func updateTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Brief flash to confirm
        let original = updateButton.backgroundColor
        UIView.animate(withDuration: 0.1, animations: {
            self.updateButton.backgroundColor = .white
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.updateButton.backgroundColor = original
            }
        }
        onUpdateStreamTapped?()
    }

    @objc private func autoTopupDisableTapped() {
        autoTopupLabel.text = "Disabling..."
        autoTopupLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        onAutoTopupDisable?()
    }

    @objc private func enableAutoTopupTapped() {
        enableAutoTopupButton.setTitle(nil, for: .normal)
        enableAutoTopupButton.isUserInteractionEnabled = false
        enableAutoTopupSpinner.startAnimating()
        onAutoTopupEnable?()
    }

    /// Call after enable/disable auto-topup completes to reset button state.
    func endAutoTopupLoading() {
        enableAutoTopupSpinner.stopAnimating()
        enableAutoTopupButton.setTitle("Auto-Pay From Wallet", for: .normal)
        enableAutoTopupButton.isUserInteractionEnabled = true
    }

    /// Update the auto-topup UI state without a full reconfigure.
    /// Call after enable/disable API calls succeed.
    func updateAutoTopupState(hasNwc: Bool, hasWallet: Bool) {
        currentHasNwc = hasNwc

        autoTopupIndicator.isHidden = !hasNwc
        enableAutoTopupButton.isHidden = hasNwc || !hasWallet

        // Reset loading state (stops spinner, restores button title)
        endAutoTopupLoading()

        // Reset disable label back to normal
        autoTopupLabel.text = "Auto-paying from your wallet"
        autoTopupLabel.textColor = .systemGreen

        // When auto top-up is active, hide the top-up button entirely
        // and show a small "Manage" style button instead
        if hasNwc {
            topUpButton.setTitle("Fund Wallet", for: .normal)
            topUpButton.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            topUpButton.tintColor = UIColor(white: 1.0, alpha: 0.5)
            topUpButton.setTitleColor(UIColor(white: 1.0, alpha: 0.5), for: .normal)
            topUpButton.setImage(nil, for: .normal)
        } else if hasWallet {
            topUpButton.setTitle("Top Up", for: .normal)
            topUpButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
            topUpButton.tintColor = .systemYellow
            topUpButton.setTitleColor(.white, for: .normal)
            topUpButton.setImage(nil, for: .normal)
        } else {
            topUpButton.setTitle("  Top Up Balance", for: .normal)
            topUpButton.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)
            topUpButton.tintColor = .systemYellow
            topUpButton.setTitleColor(.white, for: .normal)
            let boltCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            topUpButton.setImage(UIImage(systemName: "bolt.fill", withConfiguration: boltCfg), for: .normal)
        }
    }

    @objc private func refreshTapped() {
        UIView.animate(withDuration: 0.3) {
            self.refreshButton.transform = CGAffineTransform(rotationAngle: .pi)
        } completion: { _ in
            UIView.animate(withDuration: 0.3) {
                self.refreshButton.transform = .identity
            }
        }
        onRefreshBalance?()
    }

    @objc private func titleFieldChanged() { onTitleChanged?(titleField.text ?? "") }
    @objc private func descriptionFieldChanged() { onDescriptionChanged?(descriptionField.text ?? "") }
    @objc private func tagsFieldChanged() { onTagsChanged?(tagsField.text ?? "") }
    @objc private func nsfwToggleChanged() { onNSFWChanged?(nsfwToggle.isOn) }
    @objc private func publicToggleChanged() { onPublicChanged?(publicToggle.isOn) }
    @objc private func protocolChanged() { onProtocolChanged?(protocolSegment.selectedSegmentIndex) }

    // Navigation actions
    @objc private func streamDetailsTapped() { onStreamDetailsTapped?() }
    @objc private func videoNavTapped() { onVideoTapped?() }
    @objc private func audioNavTapped() { onAudioTapped?() }

    // Inline toggle actions
    @objc private func portraitChanged() { onPortraitToggled?(portraitToggle.isOn) }
    @objc private func bgStreamChanged() { onBackgroundStreamingToggled?(bgStreamToggle.isOn) }
    @objc private func autoRecordChanged() { onAutoRecordToggled?(autoRecordToggle.isOn) }
}

// MARK: - UITextFieldDelegate

extension InlineStreamDetailView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
