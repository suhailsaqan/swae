import UIKit

/// Inline view for creating a new scene — text field for name + radio-button camera picker.
class InlineCreateSceneView: UIView, UITextFieldDelegate {

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onCreateScene: ((String, String) -> Void)? // (sceneName, selectedCameraId)
    var onFullConfig: (() -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let nameField = UITextField()
    private let sectionLabel = UILabel()
    private let pickerScrollView = UIScrollView()
    private let pickerStack = UIStackView()
    private let buttonRow = UIStackView()
    private let createButton = UIButton(type: .system)
    private let fullConfigButton = UIButton(type: .system)

    private var selectedCameraId: String = ""
    private var optionButtons: [(id: String, button: UIButton)] = []

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
        titleLabel.text = "NEW SCENE"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        // Name text field
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.font = .systemFont(ofSize: 16, weight: .regular)
        nameField.textColor = .white
        nameField.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        nameField.layer.cornerRadius = 12
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        nameField.leftViewMode = .always
        nameField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        nameField.rightViewMode = .always
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.autocorrectionType = .no
        nameField.autocapitalizationType = .sentences
        nameField.attributedPlaceholder = NSAttributedString(
            string: "Scene name",
            attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.3)]
        )
        addSubview(nameField)

        // Section label
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionLabel.text = "VIDEO SOURCE"
        sectionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        sectionLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        addSubview(sectionLabel)

        // Picker scroll view
        pickerScrollView.translatesAutoresizingMaskIntoConstraints = false
        pickerScrollView.showsVerticalScrollIndicator = false
        pickerScrollView.showsHorizontalScrollIndicator = false
        pickerScrollView.alwaysBounceVertical = true
        addSubview(pickerScrollView)

        pickerStack.translatesAutoresizingMaskIntoConstraints = false
        pickerStack.axis = .vertical
        pickerStack.spacing = 2
        pickerStack.alignment = .fill
        pickerScrollView.addSubview(pickerStack)

        // Button row
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually
        addSubview(buttonRow)

        // Create button (primary — yellow)
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.setTitle("Create", for: .normal)
        createButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        createButton.setTitleColor(.white, for: .normal)
        createButton.backgroundColor = .systemYellow.withAlphaComponent(0.8)
        createButton.layer.cornerRadius = 20
        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(createButton)

        // Full Config button (secondary — gray)
        fullConfigButton.translatesAutoresizingMaskIntoConstraints = false
        fullConfigButton.setTitle("Full Config →", for: .normal)
        fullConfigButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        fullConfigButton.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
        fullConfigButton.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        fullConfigButton.layer.cornerRadius = 20
        fullConfigButton.addTarget(self, action: #selector(fullConfigTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(fullConfigButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            nameField.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 16),
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 44),

            sectionLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 16),
            sectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),

            pickerScrollView.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 8),
            pickerScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pickerScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pickerScrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -12),

            pickerStack.topAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.topAnchor),
            pickerStack.leadingAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.leadingAnchor),
            pickerStack.trailingAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.trailingAnchor),
            pickerStack.bottomAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.bottomAnchor),
            pickerStack.widthAnchor.constraint(equalTo: pickerScrollView.frameLayoutGuide.widthAnchor),

            buttonRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            buttonRow.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    // MARK: - Public

    func configure(defaultName: String, cameras: [(id: String, name: String)], selectedCameraId: String) {
        nameField.text = defaultName
        self.selectedCameraId = selectedCameraId
        buildPickerOptions(cameras)
    }

    // MARK: - Picker

    private func buildPickerOptions(_ options: [(id: String, name: String)]) {
        pickerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        optionButtons.removeAll()

        for option in options {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)

            let isSelected = option.id == selectedCameraId
            let circle = isSelected ? "largecircle.fill.circle" : "circle"
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: config), for: .normal)
            button.setTitle("  \(option.name)", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.tintColor = isSelected ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isSelected ? UIColor(white: 1.0, alpha: 0.08) : .clear
            button.layer.cornerRadius = 8
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

            let optionId = option.id
            button.addAction(UIAction { [weak self] _ in
                self?.selectOption(optionId)
            }, for: .touchUpInside)

            pickerStack.addArrangedSubview(button)
            optionButtons.append((id: option.id, button: button))
        }
    }

    private func selectOption(_ id: String) {
        selectedCameraId = id
        for (optId, button) in optionButtons {
            let isSelected = optId == id
            let circle = isSelected ? "largecircle.fill.circle" : "circle"
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: config), for: .normal)
            button.tintColor = isSelected ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isSelected ? UIColor(white: 1.0, alpha: 0.08) : .clear
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Actions

    @objc private func backTapped() {
        nameField.resignFirstResponder()
        onBack?()
    }

    @objc private func createTapped() {
        nameField.resignFirstResponder()
        onCreateScene?(nameField.text ?? "", selectedCameraId)
    }

    @objc private func fullConfigTapped() {
        nameField.resignFirstResponder()
        onFullConfig?()
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        createTapped()
        return true
    }
}
