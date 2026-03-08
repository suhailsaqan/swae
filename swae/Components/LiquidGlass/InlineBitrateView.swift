import UIKit

/// Inline bitrate picker — shows bitrate presets as pills
class InlineBitrateView: UIView {

    var onBitrateSelected: ((UInt32) -> Void)?
    var onBack: (() -> Void)?

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let containerStack = UIStackView()
    private var pillButtons: [UIButton] = []
    private var activeBitrate: UInt32 = 5_000_000
    private var isLocked: Bool = false
    private let lockedLabel = UILabel()

    struct BitrateOption {
        let bitrate: UInt32
        let label: String
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear

        backButton.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: cfg), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "BITRATE"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.axis = .vertical
        containerStack.spacing = 8
        containerStack.alignment = .fill
        addSubview(containerStack)

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
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            containerStack.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 16),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            lockedLabel.topAnchor.constraint(equalTo: containerStack.bottomAnchor, constant: 12),
            lockedLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            lockedLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func configure(options: [BitrateOption], activeBitrate: UInt32, isLocked: Bool) {
        self.activeBitrate = activeBitrate
        self.isLocked = isLocked

        containerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pillButtons.removeAll()

        let pillsPerRow = 4
        var currentRow: UIStackView?

        for (i, opt) in options.enumerated() {
            if i % pillsPerRow == 0 {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 8
                row.distribution = .fillEqually
                row.translatesAutoresizingMaskIntoConstraints = false
                row.heightAnchor.constraint(equalToConstant: 36).isActive = true
                containerStack.addArrangedSubview(row)
                currentRow = row
            }

            let btn = UIButton(type: .system)
            btn.tag = Int(opt.bitrate)
            btn.setTitle(opt.label, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            btn.layer.cornerRadius = 18
            btn.layer.cornerCurve = .continuous
            btn.clipsToBounds = true
            btn.addTarget(self, action: #selector(bitrateTapped(_:)), for: .touchUpInside)

            if opt.bitrate == activeBitrate {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }

            currentRow?.addArrangedSubview(btn)
            pillButtons.append(btn)
        }

        // Pad last row
        if let lastRow = containerStack.arrangedSubviews.last as? UIStackView {
            let remainder = options.count % pillsPerRow
            if remainder != 0 {
                for _ in 0 ..< (pillsPerRow - remainder) {
                    let spacer = UIView()
                    spacer.backgroundColor = .clear
                    lastRow.addArrangedSubview(spacer)
                }
            }
        }

        lockedLabel.isHidden = !isLocked
        containerStack.isUserInteractionEnabled = !isLocked
        containerStack.alpha = isLocked ? 0.4 : 1.0
    }

    @objc private func backTapped() { onBack?() }

    @objc private func bitrateTapped(_ sender: UIButton) {
        guard !isLocked else { return }
        activeBitrate = UInt32(sender.tag)
        for btn in pillButtons {
            if btn.tag == sender.tag {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }
        }
        onBitrateSelected?(UInt32(sender.tag))
    }
}
