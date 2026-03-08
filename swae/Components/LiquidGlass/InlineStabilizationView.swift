import UIKit

/// Inline video stabilization picker — Off, Standard, Cinematic, Extended
class InlineStabilizationView: UIView {

    var onModeSelected: ((Int) -> Void)?
    var onBack: (() -> Void)?

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let pillStack = UIStackView()
    private var pillButtons: [UIButton] = []
    private var activeIndex: Int = 0

    private let modes = ["Off", "Standard", "Cinematic", "Extended"]

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
        titleLabel.text = "STABILIZATION"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillStack.axis = .horizontal
        pillStack.spacing = 8
        pillStack.distribution = .fillEqually
        addSubview(pillStack)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            pillStack.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 24),
            pillStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillStack.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func configure(activeIndex: Int) {
        self.activeIndex = activeIndex
        pillStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pillButtons.removeAll()

        for (i, mode) in modes.enumerated() {
            let btn = UIButton(type: .system)
            btn.tag = i
            btn.setTitle(mode, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.layer.cornerRadius = 18
            btn.layer.cornerCurve = .continuous
            btn.clipsToBounds = true
            btn.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)

            if i == activeIndex {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }
            pillStack.addArrangedSubview(btn)
            pillButtons.append(btn)
        }
    }

    @objc private func backTapped() { onBack?() }

    @objc private func modeTapped(_ sender: UIButton) {
        activeIndex = sender.tag
        for (i, btn) in pillButtons.enumerated() {
            if i == sender.tag {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }
        }
        onModeSelected?(sender.tag)
    }
}
