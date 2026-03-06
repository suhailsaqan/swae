import UIKit

/// Inline view for in-call collab controls — mute, widgets, skip-PiP, end call.
/// Shown inside the MorphingGlassModal during an active collab call.
class InlineCollabCallView: UIView {

    enum DisplayState {
        case waiting
        case connecting
        case connected
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onMuteTapped: (() -> Void)?
    var onWidgetsTapped: (() -> Void)?
    var onSkipPipTapped: (() -> Void)?
    var onEndCall: (() -> Void)?
    var onVolumeChanged: ((Float) -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let controlStack = UIStackView()
    private let muteButton = UIButton(type: .system)
    private let widgetsButton = UIButton(type: .system)
    private let skipPipButton = UIButton(type: .system)
    private let endCallButton = UIButton(type: .system)
    private let volumeContainer = UIView()
    private let volumeIcon = UIImageView()
    private let volumeSlider = UISlider()
    private let volumeLabel = UILabel()

    private var currentState: DisplayState = .waiting

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

        // Back button
        backButton.translatesAutoresizingMaskIntoConstraints = false
        let backConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "COLLAB"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        addSubview(titleLabel)

        // Status dot (green when connected)
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.backgroundColor = .systemGreen
        statusDot.layer.cornerRadius = 4
        statusDot.isHidden = true
        addSubview(statusDot)

        // Status label
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        statusLabel.textAlignment = .center
        addSubview(statusLabel)

        // Spinner
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        addSubview(spinner)

        // Control buttons
        configureControlButton(muteButton, symbol: "mic.fill", tint: .white, bg: UIColor(white: 1.0, alpha: 0.2))
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)

        configureControlButton(widgetsButton, symbol: "rectangle.on.rectangle.fill", tint: .white, bg: UIColor.systemBlue.withAlphaComponent(0.8))
        widgetsButton.addTarget(self, action: #selector(widgetsTapped), for: .touchUpInside)

        configureControlButton(skipPipButton, symbol: "rectangle.on.rectangle.slash", tint: .white, bg: UIColor.systemOrange.withAlphaComponent(0.8))
        skipPipButton.addTarget(self, action: #selector(skipPipTapped), for: .touchUpInside)

        configureControlButton(endCallButton, symbol: "phone.down.fill", tint: .white, bg: .systemRed)
        endCallButton.addTarget(self, action: #selector(endCallTapped), for: .touchUpInside)

        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.axis = .horizontal
        controlStack.spacing = 16
        controlStack.alignment = .center
        controlStack.distribution = .equalCentering
        controlStack.addArrangedSubview(muteButton)
        controlStack.addArrangedSubview(widgetsButton)
        controlStack.addArrangedSubview(skipPipButton)
        controlStack.addArrangedSubview(endCallButton)
        addSubview(controlStack)

        // Volume slider container
        volumeContainer.translatesAutoresizingMaskIntoConstraints = false
        volumeContainer.isHidden = true
        addSubview(volumeContainer)

        let speakerConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        volumeIcon.image = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: speakerConfig)
        volumeIcon.tintColor = UIColor(white: 1.0, alpha: 0.7)
        volumeIcon.translatesAutoresizingMaskIntoConstraints = false
        volumeContainer.addSubview(volumeIcon)

        volumeSlider.minimumValue = 0.0
        volumeSlider.maximumValue = 2.0
        volumeSlider.value = 1.0
        volumeSlider.minimumTrackTintColor = .systemBlue
        volumeSlider.maximumTrackTintColor = UIColor(white: 1.0, alpha: 0.2)
        volumeSlider.translatesAutoresizingMaskIntoConstraints = false
        volumeSlider.addTarget(self, action: #selector(volumeSliderChanged), for: .valueChanged)
        volumeContainer.addSubview(volumeSlider)

        volumeLabel.text = "100%"
        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        volumeLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        volumeLabel.textAlignment = .right
        volumeLabel.translatesAutoresizingMaskIntoConstraints = false
        volumeContainer.addSubview(volumeLabel)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),

            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            statusDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            statusDot.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),

            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 20),

            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),

            controlStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            controlStack.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),

            volumeContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            volumeContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            volumeContainer.topAnchor.constraint(equalTo: controlStack.bottomAnchor, constant: 16),

            volumeIcon.leadingAnchor.constraint(equalTo: volumeContainer.leadingAnchor),
            volumeIcon.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeIcon.widthAnchor.constraint(equalToConstant: 20),

            volumeSlider.leadingAnchor.constraint(equalTo: volumeIcon.trailingAnchor, constant: 8),
            volumeSlider.trailingAnchor.constraint(equalTo: volumeLabel.leadingAnchor, constant: -8),
            volumeSlider.topAnchor.constraint(equalTo: volumeContainer.topAnchor),
            volumeSlider.bottomAnchor.constraint(equalTo: volumeContainer.bottomAnchor),

            volumeLabel.trailingAnchor.constraint(equalTo: volumeContainer.trailingAnchor),
            volumeLabel.centerYAnchor.constraint(equalTo: volumeSlider.centerYAnchor),
            volumeLabel.widthAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func configureControlButton(_ button: UIButton, symbol: String, tint: UIColor, bg: UIColor) {
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.tintColor = tint
        button.backgroundColor = bg
        button.layer.cornerRadius = 22
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    // MARK: - Public

    func configure(state: DisplayState, isMuted: Bool, sendWidgets: Bool, skipPip: Bool, guestVolume: Float = 1.0) {
        currentState = state

        switch state {
        case .waiting:
            spinner.startAnimating()
            statusLabel.text = "Waiting for guest..."
            controlStack.isHidden = false
            muteButton.isHidden = true
            widgetsButton.isHidden = true
            skipPipButton.isHidden = true
            endCallButton.isHidden = false
            statusDot.isHidden = true
            volumeContainer.isHidden = true
        case .connecting:
            spinner.startAnimating()
            statusLabel.text = "Connecting..."
            controlStack.isHidden = false
            muteButton.isHidden = true
            widgetsButton.isHidden = true
            skipPipButton.isHidden = true
            endCallButton.isHidden = false
            statusDot.isHidden = true
            volumeContainer.isHidden = true
        case .connected:
            spinner.stopAnimating()
            statusLabel.text = "Connected"
            controlStack.isHidden = false
            muteButton.isHidden = false
            widgetsButton.isHidden = false
            endCallButton.isHidden = false
            statusDot.isHidden = false
            volumeContainer.isHidden = false
        }

        // Update button states
        let muteConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        muteButton.setImage(UIImage(systemName: isMuted ? "mic.slash.fill" : "mic.fill", withConfiguration: muteConfig), for: .normal)
        muteButton.backgroundColor = isMuted ? UIColor.systemRed.withAlphaComponent(0.8) : UIColor(white: 1.0, alpha: 0.2)

        widgetsButton.backgroundColor = sendWidgets ? UIColor.systemBlue.withAlphaComponent(0.8) : UIColor(white: 1.0, alpha: 0.2)
        let widgetSymbol = sendWidgets ? "rectangle.on.rectangle.fill" : "rectangle"
        widgetsButton.setImage(UIImage(systemName: widgetSymbol, withConfiguration: muteConfig), for: .normal)

        skipPipButton.isHidden = !sendWidgets
        skipPipButton.backgroundColor = skipPip ? UIColor.systemOrange.withAlphaComponent(0.8) : UIColor(white: 1.0, alpha: 0.2)

        // Update volume slider
        volumeSlider.value = guestVolume
        volumeLabel.text = "\(Int(guestVolume * 100))%"
    }

    // MARK: - Actions

    @objc private func backTapped() { onBack?() }
    @objc private func muteTapped() { onMuteTapped?() }
    @objc private func widgetsTapped() { onWidgetsTapped?() }
    @objc private func skipPipTapped() { onSkipPipTapped?() }
    @objc private func endCallTapped() { onEndCall?() }
    @objc private func volumeSliderChanged() {
        let value = volumeSlider.value
        volumeLabel.text = "\(Int(value * 100))%"
        onVolumeChanged?(value)
    }
}
