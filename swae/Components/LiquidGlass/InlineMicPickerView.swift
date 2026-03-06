import UIKit

/// Inline mic picker — radio-button list of available mics
class InlineMicPickerView: UIView {

    // MARK: - Data

    struct MicItem {
        let id: String
        let name: String
        let isConnected: Bool
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onMicSelected: ((String) -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private var micButtons: [(id: String, button: UIButton)] = []
    private var selectedMicId: String = ""

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
        titleLabel.text = "MIC"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
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
    }

    // MARK: - Public

    func configure(mics: [MicItem], selectedId: String, title: String = "MIC") {
        titleLabel.text = title
        selectedMicId = selectedId
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        micButtons.removeAll()

        for mic in mics {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)

            let isSelected = mic.id == selectedId
            let circle = isSelected ? "largecircle.fill.circle" : "circle"
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: config), for: .normal)

            let title = mic.isConnected ? "  \(mic.name)" : "  \(mic.name) (disconnected)"
            button.setTitle(title, for: .normal)
            button.setTitleColor(mic.isConnected ? .white : UIColor(white: 1.0, alpha: 0.4), for: .normal)
            button.tintColor = isSelected ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isSelected ? UIColor(white: 1.0, alpha: 0.08) : .clear
            button.layer.cornerRadius = 8
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            button.isEnabled = mic.isConnected

            let micId = mic.id
            button.addAction(UIAction { [weak self] _ in
                self?.selectMic(micId)
            }, for: .touchUpInside)

            stack.addArrangedSubview(button)
            micButtons.append((id: mic.id, button: button))
        }
    }

    private func selectMic(_ id: String) {
        selectedMicId = id
        for (micId, button) in micButtons {
            let isSelected = micId == id
            let circle = isSelected ? "largecircle.fill.circle" : "circle"
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: config), for: .normal)
            button.tintColor = isSelected ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isSelected ? UIColor(white: 1.0, alpha: 0.08) : .clear
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onMicSelected?(id)
    }

    @objc private func backTapped() { onBack?() }
}
