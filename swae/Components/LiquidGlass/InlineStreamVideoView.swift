import UIKit

/// Inline video settings sub-page — resolution + FPS pickers + adaptive resolution + low light boost
class InlineStreamVideoView: UIView {

    // MARK: - Callbacks

    var onResolutionSelected: ((Int) -> Void)?
    var onFpsSelected: ((Int) -> Void)?
    var onAdaptiveResolutionToggled: ((Bool) -> Void)?
    var onLowLightBoostToggled: ((Bool) -> Void)?
    var onBack: (() -> Void)?

    // MARK: - State

    private var resolutionButtons: [UIButton] = []
    private var fpsButtons: [UIButton] = []
    private var activeResolutionIndex: Int = 0
    private var activeFpsIndex: Int = 0
    private var isLocked: Bool = false

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let lockedLabel = UILabel()

    // Resolution
    private let resolutionHeader = UILabel()
    private let resolutionStack = UIStackView()

    // FPS
    private let fpsHeader = UILabel()
    private let fpsStack = UIStackView()

    // Adaptive resolution
    private let adaptiveRow = UIView()
    private let adaptiveToggle = UISwitch()
    private let adaptiveDescLabel = UILabel()

    // Low light boost
    private let llbRow = UIView()
    private let llbToggle = UISwitch()
    private let llbDescLabel = UILabel()

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
        titleLabel.text = "VIDEO"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),

            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        buildResolutionSection()
        buildFpsSection()
        buildAdaptiveSection()
        buildLLBSection()
        buildLockedLabel()
    }

    private func buildResolutionSection() {
        resolutionHeader.translatesAutoresizingMaskIntoConstraints = false
        resolutionHeader.text = "RESOLUTION"
        resolutionHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        resolutionHeader.textColor = UIColor(white: 1.0, alpha: 0.4)
        stack.addArrangedSubview(resolutionHeader)

        resolutionStack.translatesAutoresizingMaskIntoConstraints = false
        resolutionStack.axis = .vertical
        resolutionStack.spacing = 8
        resolutionStack.alignment = .fill
        stack.addArrangedSubview(resolutionStack)
    }

    private func buildFpsSection() {
        fpsHeader.translatesAutoresizingMaskIntoConstraints = false
        fpsHeader.text = "FRAME RATE"
        fpsHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        fpsHeader.textColor = UIColor(white: 1.0, alpha: 0.4)
        stack.addArrangedSubview(fpsHeader)

        fpsStack.translatesAutoresizingMaskIntoConstraints = false
        fpsStack.axis = .vertical
        fpsStack.spacing = 8
        fpsStack.alignment = .fill
        stack.addArrangedSubview(fpsStack)
    }

    private func buildAdaptiveSection() {
        adaptiveRow.translatesAutoresizingMaskIntoConstraints = false
        adaptiveRow.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = "Adaptive Resolution"
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.88)
        adaptiveRow.addSubview(lbl)

        adaptiveToggle.translatesAutoresizingMaskIntoConstraints = false
        adaptiveToggle.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        adaptiveToggle.onTintColor = .systemGreen
        adaptiveToggle.addTarget(self, action: #selector(adaptiveChanged), for: .valueChanged)
        adaptiveRow.addSubview(adaptiveToggle)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: adaptiveRow.leadingAnchor),
            lbl.centerYAnchor.constraint(equalTo: adaptiveRow.centerYAnchor),
            adaptiveToggle.trailingAnchor.constraint(equalTo: adaptiveRow.trailingAnchor),
            adaptiveToggle.centerYAnchor.constraint(equalTo: adaptiveRow.centerYAnchor),
        ])
        stack.addArrangedSubview(adaptiveRow)

        adaptiveDescLabel.translatesAutoresizingMaskIntoConstraints = false
        adaptiveDescLabel.text = "Auto-lowers resolution when bandwidth drops"
        adaptiveDescLabel.font = .systemFont(ofSize: 12, weight: .regular)
        adaptiveDescLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        adaptiveDescLabel.numberOfLines = 0
        stack.addArrangedSubview(adaptiveDescLabel)
    }

    private func buildLLBSection() {
        llbRow.translatesAutoresizingMaskIntoConstraints = false
        llbRow.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = "Low Light Boost"
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.88)
        llbRow.addSubview(lbl)

        llbToggle.translatesAutoresizingMaskIntoConstraints = false
        llbToggle.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        llbToggle.onTintColor = .systemYellow
        llbToggle.addTarget(self, action: #selector(llbChanged), for: .valueChanged)
        llbRow.addSubview(llbToggle)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: llbRow.leadingAnchor),
            lbl.centerYAnchor.constraint(equalTo: llbRow.centerYAnchor),
            llbToggle.trailingAnchor.constraint(equalTo: llbRow.trailingAnchor),
            llbToggle.centerYAnchor.constraint(equalTo: llbRow.centerYAnchor),
        ])
        stack.addArrangedSubview(llbRow)

        llbDescLabel.translatesAutoresizingMaskIntoConstraints = false
        llbDescLabel.text = "Auto-lowers FPS for brighter image in dark conditions"
        llbDescLabel.font = .systemFont(ofSize: 12, weight: .regular)
        llbDescLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        llbDescLabel.numberOfLines = 0
        stack.addArrangedSubview(llbDescLabel)
    }

    private func buildLockedLabel() {
        lockedLabel.translatesAutoresizingMaskIntoConstraints = false
        lockedLabel.text = "Cannot change while live"
        lockedLabel.font = .systemFont(ofSize: 12, weight: .medium)
        lockedLabel.textColor = UIColor(white: 1.0, alpha: 0.3)
        lockedLabel.textAlignment = .center
        lockedLabel.isHidden = true
        stack.addArrangedSubview(lockedLabel)
    }

    // MARK: - Public API

    func configure(
        resolutionOptions: [String],
        activeResolutionIndex: Int,
        fpsOptions: [String],
        activeFpsIndex: Int,
        isAdaptiveResolution: Bool,
        isLowLightBoostAvailable: Bool,
        isLowLightBoostEnabled: Bool,
        isLocked: Bool
    ) {
        self.activeResolutionIndex = activeResolutionIndex
        self.activeFpsIndex = activeFpsIndex
        self.isLocked = isLocked

        rebuildPills(in: resolutionStack, options: resolutionOptions, activeIndex: activeResolutionIndex, buttons: &resolutionButtons, action: #selector(resolutionTapped(_:)))
        rebuildPills(in: fpsStack, options: fpsOptions, activeIndex: activeFpsIndex, buttons: &fpsButtons, action: #selector(fpsTapped(_:)))

        adaptiveToggle.isOn = isAdaptiveResolution
        llbToggle.isOn = isLowLightBoostEnabled
        llbRow.isHidden = !isLowLightBoostAvailable
        llbDescLabel.isHidden = !isLowLightBoostAvailable

        lockedLabel.isHidden = !isLocked
        resolutionStack.isUserInteractionEnabled = !isLocked
        fpsStack.isUserInteractionEnabled = !isLocked
        adaptiveToggle.isEnabled = !isLocked
        llbToggle.isEnabled = !isLocked
        resolutionStack.alpha = isLocked ? 0.4 : 1.0
        fpsStack.alpha = isLocked ? 0.4 : 1.0
    }

    // MARK: - Pill Builder

    private let pillSize: CGFloat = 60
    private let pillHeight: CGFloat = 36
    private let pillsPerRow = 4

    private func rebuildPills(in container: UIStackView, options: [String], activeIndex: Int, buttons: inout [UIButton], action: Selector) {
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        var currentRow: UIStackView?
        for (i, option) in options.enumerated() {
            if i % pillsPerRow == 0 {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 8
                row.distribution = .fillEqually
                row.translatesAutoresizingMaskIntoConstraints = false
                row.heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
                container.addArrangedSubview(row)
                currentRow = row
            }

            let btn = UIButton(type: .system)
            btn.tag = i
            btn.setTitle(option, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.titleLabel?.adjustsFontSizeToFitWidth = false
            btn.layer.cornerRadius = pillHeight / 2
            btn.layer.cornerCurve = .continuous
            btn.clipsToBounds = true
            btn.addTarget(self, action: action, for: .touchUpInside)

            if i == activeIndex {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }

            currentRow?.addArrangedSubview(btn)
            buttons.append(btn)
        }

        // Pad the last row with invisible spacers so fillEqually keeps pills the same size
        if let lastRow = container.arrangedSubviews.last as? UIStackView {
            let remainder = options.count % pillsPerRow
            if remainder != 0 {
                for _ in 0 ..< (pillsPerRow - remainder) {
                    let spacer = UIView()
                    spacer.isHidden = false
                    spacer.backgroundColor = .clear
                    lastRow.addArrangedSubview(spacer)
                }
            }
        }
    }

    private func updatePillSelection(_ buttons: [UIButton], selectedIndex: Int) {
        for (i, btn) in buttons.enumerated() {
            if i == selectedIndex {
                btn.backgroundColor = .white
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
                btn.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
            }
        }
    }

    // MARK: - Actions

    @objc private func backTapped() { onBack?() }

    @objc private func resolutionTapped(_ sender: UIButton) {
        guard !isLocked else { return }
        activeResolutionIndex = sender.tag
        updatePillSelection(resolutionButtons, selectedIndex: sender.tag)
        onResolutionSelected?(sender.tag)
    }

    @objc private func fpsTapped(_ sender: UIButton) {
        guard !isLocked else { return }
        activeFpsIndex = sender.tag
        updatePillSelection(fpsButtons, selectedIndex: sender.tag)
        onFpsSelected?(sender.tag)
    }

    @objc private func adaptiveChanged() {
        onAdaptiveResolutionToggled?(adaptiveToggle.isOn)
    }

    @objc private func llbChanged() {
        onLowLightBoostToggled?(llbToggle.isOn)
    }
}
