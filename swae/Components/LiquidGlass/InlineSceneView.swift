import UIKit

/// Inline scene configuration view — shows current scene's key settings
class InlineSceneView: UIView, UITextFieldDelegate {

    // MARK: - Data

    struct SceneData {
        let name: String
        let cameraName: String
        let micOverrideEnabled: Bool
        let micName: String
        let widgets: [(id: UUID, name: String, type: String, enabled: Bool)]
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onCameraTapped: (() -> Void)?
    var onMicTapped: (() -> Void)?
    var onWidgetToggled: ((UUID, Bool) -> Void)?
    var onAddWidgetTapped: (() -> Void)?
    var onAddSceneTapped: (() -> Void)?
    var onSceneRenamed: ((String) -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let renameField = UITextField()
    private var isRenaming = false
    private var currentName = ""
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let addSceneButton = UIButton(type: .system)

    // Dynamic scroll top constraints (swap when rename field is shown/hidden)
    private var scrollTopToTitle: NSLayoutConstraint!
    private var scrollTopToRenameField: NSLayoutConstraint!

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
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(titleTapped)))
        addSubview(titleLabel)

        renameField.translatesAutoresizingMaskIntoConstraints = false
        renameField.font = .systemFont(ofSize: 16, weight: .regular)
        renameField.textColor = .white
        renameField.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        renameField.layer.cornerRadius = 12
        renameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        renameField.leftViewMode = .always
        renameField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        renameField.rightViewMode = .always
        renameField.returnKeyType = .done
        renameField.delegate = self
        renameField.autocorrectionType = .no
        renameField.autocapitalizationType = .sentences
        renameField.attributedPlaceholder = NSAttributedString(
            string: "Scene name",
            attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.3)]
        )
        renameField.alpha = 0
        addSubview(renameField)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .fill
        scrollView.addSubview(stack)

        // Sticky bottom "+ Add Scene" button (same style as InlineWidgetsView.addButton)
        addSceneButton.translatesAutoresizingMaskIntoConstraints = false
        addSceneButton.setTitle("  Add Scene", for: .normal)
        let plusConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        addSceneButton.setImage(UIImage(systemName: "plus", withConfiguration: plusConfig), for: .normal)
        addSceneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        addSceneButton.setTitleColor(.white, for: .normal)
        addSceneButton.tintColor = .white
        addSceneButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        addSceneButton.layer.cornerRadius = 22
        addSceneButton.addTarget(self, action: #selector(addSceneTapped), for: .touchUpInside)
        addSubview(addSceneButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            renameField.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            renameField.leadingAnchor.constraint(equalTo: leadingAnchor),
            renameField.trailingAnchor.constraint(equalTo: trailingAnchor),
            renameField.heightAnchor.constraint(equalToConstant: 44),
        ])

        // scrollView top depends on rename state — start anchored to backButton
        scrollTopToTitle = scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12)
        scrollTopToRenameField = scrollView.topAnchor.constraint(equalTo: renameField.bottomAnchor, constant: 8)
        scrollTopToTitle.isActive = true

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addSceneButton.topAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            addSceneButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            addSceneButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            addSceneButton.heightAnchor.constraint(equalToConstant: 44),
            addSceneButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Public

    func configure(data: SceneData) {
        currentName = data.name
        titleLabel.text = "\(data.name.uppercased())"
        hideRenameField(animated: false)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Camera row (tappable)
        addTappableRow(icon: "camera", title: "Camera", value: data.cameraName) { [weak self] in
            self?.onCameraTapped?()
        }

        // Mic row (tappable)
        let micValue = data.micOverrideEnabled ? data.micName : "Default"
        addTappableRow(icon: "music.mic", title: "Mic", value: micValue) { [weak self] in
            self?.onMicTapped?()
        }

        // Separator
        let sep = makeSeparator()
        stack.addArrangedSubview(sep)

        // Section header
        let header = UILabel()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.text = "WIDGETS IN THIS SCENE"
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = UIColor(white: 1.0, alpha: 0.4)
        let headerContainer = UIView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 12),
            header.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 8),
            header.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -4),
        ])
        stack.addArrangedSubview(headerContainer)

        // Widget rows
        for widget in data.widgets {
            addWidgetRow(widget)
        }

        // Add widget button
        let addButton = UIButton(type: .system)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("  + Add Widget", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        addButton.setTitleColor(.systemYellow, for: .normal)
        addButton.contentHorizontalAlignment = .center
        addButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        addButton.addTarget(self, action: #selector(addWidgetTapped), for: .touchUpInside)
        stack.addArrangedSubview(addButton)
    }

    // MARK: - Row Builders

    private func addTappableRow(icon: String, title: String, value: String, action: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.backgroundColor = .clear
        button.layer.cornerRadius = 8

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.image = UIImage(systemName: icon, withConfiguration: config)
        iconView.tintColor = UIColor(white: 1.0, alpha: 0.6)
        iconView.isUserInteractionEnabled = false
        button.addSubview(iconView)

        let titleLbl = UILabel()
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.text = title
        titleLbl.font = .systemFont(ofSize: 14, weight: .medium)
        titleLbl.textColor = .white
        titleLbl.isUserInteractionEnabled = false
        button.addSubview(titleLbl)

        let valueLbl = UILabel()
        valueLbl.translatesAutoresizingMaskIntoConstraints = false
        valueLbl.text = value
        valueLbl.font = .systemFont(ofSize: 14, weight: .regular)
        valueLbl.textColor = UIColor(white: 1.0, alpha: 0.5)
        valueLbl.textAlignment = .right
        valueLbl.isUserInteractionEnabled = false
        button.addSubview(valueLbl)

        let chevron = UIImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevron.image = UIImage(systemName: "chevron.right", withConfiguration: chevronConfig)
        chevron.tintColor = UIColor(white: 1.0, alpha: 0.3)
        chevron.isUserInteractionEnabled = false
        button.addSubview(chevron)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            titleLbl.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLbl.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            valueLbl.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            valueLbl.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            valueLbl.leadingAnchor.constraint(greaterThanOrEqualTo: titleLbl.trailingAnchor, constant: 8),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    private func addWidgetRow(_ widget: (id: UUID, name: String, type: String, enabled: Bool)) {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.isOn = widget.enabled
        toggle.onTintColor = .systemYellow
        toggle.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        let widgetId = widget.id
        toggle.addAction(UIAction { [weak self] action in
            let sw = action.sender as! UISwitch
            self?.onWidgetToggled?(widgetId, sw.isOn)
        }, for: .valueChanged)
        row.addSubview(toggle)

        let nameLbl = UILabel()
        nameLbl.translatesAutoresizingMaskIntoConstraints = false
        nameLbl.text = widget.name
        nameLbl.font = .systemFont(ofSize: 14, weight: .medium)
        nameLbl.textColor = widget.enabled ? .white : UIColor(white: 1.0, alpha: 0.4)
        row.addSubview(nameLbl)

        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameLbl.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 4),
            nameLbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameLbl.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12),
        ])

        stack.addArrangedSubview(row)
    }

    private func makeSeparator() -> UIView {
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    // MARK: - Actions

    @objc private func backTapped() {
        commitRenameIfNeeded()
        onBack?()
    }
    @objc private func addWidgetTapped() { onAddWidgetTapped?() }
    @objc private func addSceneTapped() { onAddSceneTapped?() }

    // MARK: - Inline Rename

    @objc private func titleTapped() {
        showRenameField()
    }

    private func showRenameField() {
        guard !isRenaming else { return }
        isRenaming = true
        renameField.text = currentName

        scrollTopToTitle.isActive = false
        scrollTopToRenameField.isActive = true

        UIView.animate(withDuration: 0.25) {
            self.renameField.alpha = 1
            self.layoutIfNeeded()
        } completion: { _ in
            self.renameField.becomeFirstResponder()
        }
    }

    private func hideRenameField(animated: Bool) {
        isRenaming = false
        renameField.resignFirstResponder()

        scrollTopToRenameField.isActive = false
        scrollTopToTitle.isActive = true

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.renameField.alpha = 0
                self.layoutIfNeeded()
            }
        } else {
            renameField.alpha = 0
        }
    }

    private func commitRenameIfNeeded() {
        guard isRenaming else { return }
        let newName = (renameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != currentName {
            currentName = newName
            titleLabel.text = "\(newName.uppercased())"
            onSceneRenamed?(newName)
        }
        hideRenameField(animated: true)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commitRenameIfNeeded()
        return true
    }
}
