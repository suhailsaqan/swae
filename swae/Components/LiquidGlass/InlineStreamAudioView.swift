import UIKit

/// Inline audio settings sub-page — audio bitrate picker
class InlineStreamAudioView: UIView {

    // MARK: - Callbacks

    var onBitrateSelected: ((Int) -> Void)?
    var onBack: (() -> Void)?

    // MARK: - State

    private var bitrateButtons: [UIButton] = []
    private var activeBitrateKbps: Int = 128
    private var isLocked: Bool = false
    private let presets = [64, 96, 128, 192, 256, 320]

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let headerLabel = UILabel()
    private let pillStack = UIStackView()
    private let pillRow2 = UIStackView()
    private let recommendLabel = UILabel()
    private let lockedLabel = UILabel()

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

        backButton.translatesAutoresizingMaskIntoConstraints = false
        let backConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "AUDIO"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        addSubview(titleLabel)

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.text = "BITRATE"
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        addSubview(headerLabel)

        // Row 1: first 3 presets
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillStack.axis = .horizontal
        pillStack.spacing = 8
        pillStack.distribution = .fillEqually
        addSubview(pillStack)

        // Row 2: last 3 presets
        pillRow2.translatesAutoresizingMaskIntoConstraints = false
        pillRow2.axis = .horizontal
        pillRow2.spacing = 8
        pillRow2.distribution = .fillEqually
        addSubview(pillRow2)

        recommendLabel.translatesAutoresizingMaskIntoConstraints = false
        recommendLabel.text = "128 Kbps or higher recommended"
        recommendLabel.font = .systemFont(ofSize: 12, weight: .regular)
        recommendLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        recommendLabel.textAlignment = .center
        addSubview(recommendLabel)

        lockedLabel.translatesAutoresizingMaskIntoConstraints = false
        lockedLabel.text = "Cannot change while live"
        lockedLabel.font = .systemFont(ofSize: 12, weight: .medium)
        lockedLabel.textColor = UIColor(white: 1.0, alpha: 0.3)
        lockedLabel.textAlignment = .center
        lockedLabel.isHidden = true
        addSubview(lockedLabel)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),

            headerLabel.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            pillStack.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            pillStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillStack.heightAnchor.constraint(equalToConstant: 36),

            pillRow2.topAnchor.constraint(equalTo: pillStack.bottomAnchor, constant: 8),
            pillRow2.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillRow2.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillRow2.heightAnchor.constraint(equalToConstant: 36),

            recommendLabel.topAnchor.constraint(equalTo: pillRow2.bottomAnchor, constant: 16),
            recommendLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            recommendLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            lockedLabel.topAnchor.constraint(equalTo: recommendLabel.bottomAnchor, constant: 12),
            lockedLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            lockedLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    // MARK: - Public API

    func configure(activeBitrateKbps: Int, isLocked: Bool) {
        self.activeBitrateKbps = activeBitrateKbps
        self.isLocked = isLocked

        pillStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pillRow2.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bitrateButtons.removeAll()

        for (i, kbps) in presets.enumerated() {
            let btn = UIButton(type: .system)
            btn.tag = kbps
            btn.setTitle("\(kbps)k", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.layer.cornerRadius = 18
            btn.layer.cornerCurve = .continuous
            btn.clipsToBounds = true
            btn.addTarget(self, action: #selector(bitrateTapped(_:)), for: .touchUpInside)

            if kbps == activeBitrateKbps {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }

            if i < 3 {
                pillStack.addArrangedSubview(btn)
            } else {
                pillRow2.addArrangedSubview(btn)
            }
            bitrateButtons.append(btn)
        }

        lockedLabel.isHidden = !isLocked
        pillStack.isUserInteractionEnabled = !isLocked
        pillRow2.isUserInteractionEnabled = !isLocked
        pillStack.alpha = isLocked ? 0.4 : 1.0
        pillRow2.alpha = isLocked ? 0.4 : 1.0
    }

    // MARK: - Actions

    @objc private func backTapped() { onBack?() }

    @objc private func bitrateTapped(_ sender: UIButton) {
        guard !isLocked else { return }
        activeBitrateKbps = sender.tag
        for btn in bitrateButtons {
            if btn.tag == sender.tag {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }
        }
        onBitrateSelected?(sender.tag)
    }
}
