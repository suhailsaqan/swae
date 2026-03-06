import UIKit

/// Compact info strip for Zone 3 — three states:
/// A) Not configured: yellow/orange setup CTA
/// B) Configured, not live: stream name + protocol pill + resolution + gear
/// C) Live: live dot + uptime + bitrate + stream name + viewers + resolution + gear
class StreamStatusBar: UIView {

    // MARK: - Callbacks

    var onSettingsGearTapped: ((_ sourceView: UIView) -> Void)?
    var onSetupStreamTapped: ((_ sourceView: UIView) -> Void)?
    var onInfoBarTapped: ((_ sourceView: UIView) -> Void)?

    // MARK: - State

    private(set) var isStreamConfigured: Bool = false
    private(set) var isLive: Bool = false

    /// Tracks state to avoid redundant layout animations
    private var previousState: (configured: Bool, live: Bool, zapStream: Bool)?

    // MARK: - Views

    // State A: Setup CTA
    private let setupContainer = UIView()
    private let setupGradient = CAGradientLayer()
    private let setupBoltIcon = UIImageView()
    private let setupTitleLabel = UILabel()
    private let setupSubtitleLabel = UILabel()
    private let setupChevron = UIImageView()

    // State B/C: Stream info container (tappable area)
    private let infoContainer = UIView()
    private let gearButton = UIButton(type: .system)

    // Row 1 elements (shared between B and C)
    private let row1Container = UIView()
    private let boltIcon = UIImageView()
    private let streamNameLabel = UILabel()
    private let protocolPill = UILabel()
    private let liveDot = UIView()
    private let liveLabel = UILabel()
    private let row1UptimeLabel = UILabel()
    private let row1BitrateLabel = UILabel()

    // Row 2 elements (State C only: stream name + viewers + resolution)
    private let row2Container = UIView()
    private let row2BoltIcon = UIImageView()
    private let row2StreamNameLabel = UILabel()
    private let row2ViewerLabel = UILabel()

    // MARK: - Constants

    private let barHeightStateA: CGFloat = 56
    private let barHeightStateB: CGFloat = 44
    private let barHeightStateC: CGFloat = 56
    private let cornerRadius: CGFloat = 16

    private var heightConstraint: NSLayoutConstraint!
    private var row1TopConstraint: NSLayoutConstraint!
    private var row1CenterYConstraint: NSLayoutConstraint!

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
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true

        heightConstraint = heightAnchor.constraint(equalToConstant: barHeightStateB)
        heightConstraint.isActive = true

        setupSetupCTA()
        setupInfoBar()
    }

    private func setupSetupCTA() {
        setupContainer.translatesAutoresizingMaskIntoConstraints = false
        setupContainer.isHidden = true
        setupContainer.isUserInteractionEnabled = true
        addSubview(setupContainer)

        setupGradient.colors = [
            UIColor.systemYellow.withAlphaComponent(0.9).cgColor,
            UIColor.systemOrange.cgColor,
        ]
        setupGradient.startPoint = CGPoint(x: 0, y: 0.5)
        setupGradient.endPoint = CGPoint(x: 1, y: 0.5)
        setupGradient.cornerRadius = cornerRadius
        setupContainer.layer.insertSublayer(setupGradient, at: 0)

        setupBoltIcon.translatesAutoresizingMaskIntoConstraints = false
        let boltConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        setupBoltIcon.image = UIImage(systemName: "bolt.fill", withConfiguration: boltConfig)
        setupBoltIcon.tintColor = .white
        setupContainer.addSubview(setupBoltIcon)

        setupTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        setupTitleLabel.text = "Set Up Stream"
        setupTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        setupTitleLabel.textColor = .white
        setupContainer.addSubview(setupTitleLabel)

        setupSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        setupSubtitleLabel.text = "Stream to Nostr & earn zaps"
        setupSubtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        setupSubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        setupContainer.addSubview(setupSubtitleLabel)

        setupChevron.translatesAutoresizingMaskIntoConstraints = false
        let chevConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        setupChevron.image = UIImage(systemName: "chevron.right", withConfiguration: chevConfig)
        setupChevron.tintColor = UIColor.white.withAlphaComponent(0.7)
        setupContainer.addSubview(setupChevron)

        let tap = UITapGestureRecognizer(target: self, action: #selector(setupTapped))
        setupContainer.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            setupContainer.topAnchor.constraint(equalTo: topAnchor),
            setupContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            setupContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            setupContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            setupBoltIcon.leadingAnchor.constraint(equalTo: setupContainer.leadingAnchor, constant: 16),
            setupBoltIcon.topAnchor.constraint(equalTo: setupContainer.topAnchor, constant: 10),

            setupTitleLabel.leadingAnchor.constraint(equalTo: setupBoltIcon.trailingAnchor, constant: 8),
            setupTitleLabel.centerYAnchor.constraint(equalTo: setupBoltIcon.centerYAnchor),

            setupSubtitleLabel.leadingAnchor.constraint(equalTo: setupBoltIcon.leadingAnchor),
            setupSubtitleLabel.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: 2),

            setupChevron.trailingAnchor.constraint(equalTo: setupContainer.trailingAnchor, constant: -16),
            setupChevron.centerYAnchor.constraint(equalTo: setupContainer.centerYAnchor),
        ])
    }

    private func setupInfoBar() {
        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.isHidden = true
        infoContainer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.25)
        infoContainer.layer.cornerRadius = cornerRadius
        infoContainer.layer.cornerCurve = .continuous
        addSubview(infoContainer)

        let infoTap = UITapGestureRecognizer(target: self, action: #selector(infoBarTapped))
        infoContainer.addGestureRecognizer(infoTap)

        // Gear button — vertically centered in the bar
        gearButton.translatesAutoresizingMaskIntoConstraints = false
        let gearConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        gearButton.setImage(UIImage(systemName: "gearshape", withConfiguration: gearConfig), for: .normal)
        gearButton.tintColor = UIColor(white: 1.0, alpha: 0.7)
        gearButton.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        infoContainer.addSubview(gearButton)

        setupRow1()
        setupRow2()

        NSLayoutConstraint.activate([
            infoContainer.topAnchor.constraint(equalTo: topAnchor),
            infoContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            infoContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            infoContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            gearButton.trailingAnchor.constraint(equalTo: infoContainer.trailingAnchor, constant: -8),
            gearButton.centerYAnchor.constraint(equalTo: infoContainer.centerYAnchor),
            gearButton.widthAnchor.constraint(equalToConstant: 32),
            gearButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func setupRow1() {
        row1Container.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.addSubview(row1Container)

        // Live dot (8pt red circle)
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        liveDot.backgroundColor = .systemRed
        liveDot.layer.cornerRadius = 4
        liveDot.isHidden = true
        row1Container.addSubview(liveDot)

        liveLabel.translatesAutoresizingMaskIntoConstraints = false
        liveLabel.text = "LIVE"
        liveLabel.font = .systemFont(ofSize: 11, weight: .bold)
        liveLabel.textColor = .systemRed
        liveLabel.isHidden = true
        row1Container.addSubview(liveLabel)

        // Stream signal icon (State B)
        boltIcon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        boltIcon.image = UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config)
        boltIcon.tintColor = .systemYellow
        row1Container.addSubview(boltIcon)

        // Stream name (State B)
        streamNameLabel.translatesAutoresizingMaskIntoConstraints = false
        streamNameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        streamNameLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        streamNameLabel.lineBreakMode = .byTruncatingTail
        row1Container.addSubview(streamNameLabel)

        // Protocol pill (State B)
        protocolPill.translatesAutoresizingMaskIntoConstraints = false
        protocolPill.font = .systemFont(ofSize: 9, weight: .bold)
        protocolPill.textColor = UIColor(white: 1.0, alpha: 0.6)
        protocolPill.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        protocolPill.textAlignment = .center
        protocolPill.layer.cornerRadius = 4
        protocolPill.layer.cornerCurve = .continuous
        protocolPill.clipsToBounds = true
        row1Container.addSubview(protocolPill)

        // Uptime (State C row 1)
        row1UptimeLabel.translatesAutoresizingMaskIntoConstraints = false
        row1UptimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        row1UptimeLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        row1UptimeLabel.isHidden = true
        row1Container.addSubview(row1UptimeLabel)

        // Bitrate (State C row 1)
        row1BitrateLabel.translatesAutoresizingMaskIntoConstraints = false
        row1BitrateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        row1BitrateLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        row1BitrateLabel.isHidden = true
        row1Container.addSubview(row1BitrateLabel)

        row1TopConstraint = row1Container.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 8)
        row1CenterYConstraint = row1Container.centerYAnchor.constraint(equalTo: infoContainer.centerYAnchor)
        // Default to centered (State B); State C activates top constraint
        row1CenterYConstraint.isActive = true

        NSLayoutConstraint.activate([
            row1Container.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 12),
            row1Container.trailingAnchor.constraint(equalTo: gearButton.leadingAnchor, constant: -4),
            row1Container.heightAnchor.constraint(equalToConstant: 18),

            liveDot.leadingAnchor.constraint(equalTo: row1Container.leadingAnchor),
            liveDot.centerYAnchor.constraint(equalTo: row1Container.centerYAnchor),
            liveDot.widthAnchor.constraint(equalToConstant: 8),
            liveDot.heightAnchor.constraint(equalToConstant: 8),

            liveLabel.leadingAnchor.constraint(equalTo: liveDot.trailingAnchor, constant: 4),
            liveLabel.centerYAnchor.constraint(equalTo: row1Container.centerYAnchor),

            boltIcon.leadingAnchor.constraint(equalTo: row1Container.leadingAnchor),
            boltIcon.centerYAnchor.constraint(equalTo: row1Container.centerYAnchor),

            streamNameLabel.leadingAnchor.constraint(equalTo: boltIcon.trailingAnchor, constant: 4),
            streamNameLabel.centerYAnchor.constraint(equalTo: row1Container.centerYAnchor),
            streamNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: protocolPill.leadingAnchor, constant: -6),

            protocolPill.centerYAnchor.constraint(equalTo: row1Container.centerYAnchor),
            protocolPill.heightAnchor.constraint(equalToConstant: 16),
            protocolPill.trailingAnchor.constraint(equalTo: row1Container.trailingAnchor),

            row1UptimeLabel.leadingAnchor.constraint(equalTo: liveLabel.trailingAnchor, constant: 8),
            row1UptimeLabel.centerYAnchor.constraint(equalTo: row1Container.centerYAnchor),

            row1BitrateLabel.trailingAnchor.constraint(equalTo: row1Container.trailingAnchor),
            row1BitrateLabel.centerYAnchor.constraint(equalTo: row1Container.centerYAnchor),
        ])
    }

    private func setupRow2() {
        row2Container.translatesAutoresizingMaskIntoConstraints = false
        row2Container.isHidden = true
        infoContainer.addSubview(row2Container)

        // Stream signal icon for row 2 (State C stream name)
        row2BoltIcon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        row2BoltIcon.image = UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config)
        row2BoltIcon.tintColor = .systemYellow
        row2Container.addSubview(row2BoltIcon)

        // Stream name (State C row 2)
        row2StreamNameLabel.translatesAutoresizingMaskIntoConstraints = false
        row2StreamNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        row2StreamNameLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        row2StreamNameLabel.lineBreakMode = .byTruncatingTail
        row2Container.addSubview(row2StreamNameLabel)

        // Viewer count (State C)
        row2ViewerLabel.translatesAutoresizingMaskIntoConstraints = false
        row2ViewerLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        row2ViewerLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        row2ViewerLabel.textAlignment = .right
        row2Container.addSubview(row2ViewerLabel)

        NSLayoutConstraint.activate([
            row2Container.topAnchor.constraint(equalTo: row1Container.bottomAnchor, constant: 4),
            row2Container.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 12),
            row2Container.trailingAnchor.constraint(equalTo: gearButton.leadingAnchor, constant: -4),
            row2Container.heightAnchor.constraint(equalToConstant: 16),

            row2BoltIcon.leadingAnchor.constraint(equalTo: row2Container.leadingAnchor),
            row2BoltIcon.centerYAnchor.constraint(equalTo: row2Container.centerYAnchor),

            row2StreamNameLabel.leadingAnchor.constraint(equalTo: row2BoltIcon.trailingAnchor, constant: 3),
            row2StreamNameLabel.centerYAnchor.constraint(equalTo: row2Container.centerYAnchor),
            row2StreamNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: row2ViewerLabel.leadingAnchor, constant: -6),

            row2ViewerLabel.trailingAnchor.constraint(equalTo: row2Container.trailingAnchor),
            row2ViewerLabel.centerYAnchor.constraint(equalTo: row2Container.centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setupGradient.frame = setupContainer.bounds
    }

    // MARK: - Public API

    func configure(
        isStreamConfigured: Bool,
        isLive: Bool,
        streamName: String = "",
        resolution: String = "",
        isZapStream: Bool = false,
        uptime: String = "",
        bitrateMbps: String = "",
        bitrateColor: UIColor = .white,
        viewerCount: String = "",
        balance: Int? = nil,
        rate: Double = 0,
        protocolString: String = ""
    ) {
        self.isStreamConfigured = isStreamConfigured
        self.isLive = isLive

        let newState = (isStreamConfigured, isLive, isZapStream)
        let stateChanged = previousState == nil
            || previousState!.0 != newState.0
            || previousState!.1 != newState.1
            || previousState!.2 != newState.2
        previousState = newState

        if stateChanged {
            animateStateTransition(
                isStreamConfigured: isStreamConfigured,
                isLive: isLive,
                isZapStream: isZapStream
            )
        }

        updateLabels(
            streamName: streamName, resolution: resolution,
            isZapStream: isZapStream, uptime: uptime,
            bitrateMbps: bitrateMbps, bitrateColor: bitrateColor,
            viewerCount: viewerCount, protocolString: protocolString,
            isLive: isLive
        )
    }

    // MARK: - State Transition

    private func animateStateTransition(
        isStreamConfigured: Bool, isLive: Bool, isZapStream: Bool
    ) {
        if !isStreamConfigured {
            // State A
            setupContainer.isHidden = false
            infoContainer.isHidden = true
            heightConstraint.constant = barHeightStateA
            stopLiveDotPulse()
        } else if isLive {
            // State C: 2 rows
            setupContainer.isHidden = true
            infoContainer.isHidden = false

            // Row 1: live dot + LIVE + uptime ... bitrate
            liveDot.isHidden = false
            liveLabel.isHidden = false
            boltIcon.isHidden = true
            streamNameLabel.isHidden = true
            protocolPill.isHidden = true
            row1UptimeLabel.isHidden = false
            row1BitrateLabel.isHidden = false

            // Row 2: stream name + viewers
            row2Container.isHidden = false

            // Pin row1 to top for 2-row layout
            row1CenterYConstraint.isActive = false
            row1TopConstraint.isActive = true

            heightConstraint.constant = barHeightStateC
            startLiveDotPulse()
        } else {
            // State B: single row
            setupContainer.isHidden = true
            infoContainer.isHidden = false

            // Row 1: bolt + stream name + protocol pill
            liveDot.isHidden = true
            liveLabel.isHidden = true
            boltIcon.isHidden = false
            streamNameLabel.isHidden = false
            protocolPill.isHidden = false
            row1UptimeLabel.isHidden = true
            row1BitrateLabel.isHidden = true

            // Row 2: hidden
            row2Container.isHidden = true

            // Center row1 vertically for single-row layout
            row1TopConstraint.isActive = false
            row1CenterYConstraint.isActive = true

            heightConstraint.constant = barHeightStateB
            stopLiveDotPulse()
        }
    }

    // MARK: - Label Updates

    private func updateLabels(
        streamName: String, resolution: String,
        isZapStream: Bool, uptime: String,
        bitrateMbps: String, bitrateColor: UIColor,
        viewerCount: String, protocolString: String,
        isLive: Bool
    ) {
        if isLive {
            row1UptimeLabel.text = uptime
            row1BitrateLabel.text = "↑ \(bitrateMbps)"
            row1BitrateLabel.textColor = bitrateColor

            row2StreamNameLabel.text = streamName
            row2ViewerLabel.text = "👁 \(viewerCount)"
        } else {
            streamNameLabel.text = streamName
            protocolPill.text = "  \(protocolString)  "
        }
    }

    // MARK: - Live Dot Pulse

    private func startLiveDotPulse() {
        liveDot.layer.removeAnimation(forKey: "livePulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        liveDot.layer.add(pulse, forKey: "livePulse")
    }

    private func stopLiveDotPulse() {
        liveDot.layer.removeAnimation(forKey: "livePulse")
    }

    // MARK: - Actions

    @objc private func setupTapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.setupContainer.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.setupContainer.transform = .identity
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSetupStreamTapped?(setupContainer)
    }

    @objc private func gearTapped() {
        onSettingsGearTapped?(self)
    }

    @objc private func infoBarTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onInfoBarTapped?(infoContainer)
    }
}
