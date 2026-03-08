import UIKit

/// Minimal inline configuration view for widget types that need one critical field.
/// Used for Browser (URL), QR Code (message), and Camera (picker).
class InlineQuickConfigView: UIView, UITextFieldDelegate {

    // MARK: - Config Mode

    enum Mode {
        case textField(title: String, placeholder: String, keyboardType: UIKeyboardType, initialValue: String = "")
        case picker(title: String, options: [(id: String, name: String)], selectedId: String)
        /// Preset picker with icons. Each preset has (name, SF Symbol, value).
        /// A `nil` value means "Custom" — tapping it reveals a text field for freeform input.
        /// `selectedValue` pre-selects a matching preset, or selects "Custom" if no match.
        /// `showCustomField` controls whether the freeform text field is shown (default true).
        case presetPicker(title: String, presets: [(name: String, icon: String, value: String?)], selectedValue: String? = nil, showCustomField: Bool = true)
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onDone: ((String) -> Void)?  // Returns the entered text or selected option ID
    var onFullConfig: (() -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let textField = UITextField()
    private let pickerScrollView = UIScrollView()
    private let pickerStack = UIStackView()
    private let presetScrollView = UIScrollView()
    private let presetStack = UIStackView()
    private let customTextField = UITextField()
    private let doneButton = UIButton(type: .system)
    private let fullConfigButton = UIButton(type: .system)
    private let buttonRow = UIStackView()

    // Scroll view bottom constraints — switch based on mode/custom state
    private var pickerScrollBottom: NSLayoutConstraint!
    private var presetScrollBottom: NSLayoutConstraint!       // preset bottom → buttonRow top (no custom)
    private var presetScrollBottomCustom: NSLayoutConstraint! // preset bottom → customTextField top (custom visible)

    // Switchable top constraint for preset scroll view
    private var presetScrollTopBelowCustom: NSLayoutConstraint!  // below custom text field
    private var presetScrollTopBelowBack: NSLayoutConstraint!    // below back button (no custom field)

    private var mode: Mode?
    private var selectedOptionId: String = ""
    private var optionButtons: [(id: String, button: UIButton)] = []

    // Preset picker state
    private var presetButtons: [(value: String?, button: UIButton)] = []
    private var isCustomSelected = false

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
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        // Text field (hidden by default, shown for .textField mode)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 16, weight: .regular)
        textField.textColor = .white
        textField.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        textField.layer.cornerRadius = 12
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.rightViewMode = .always
        textField.returnKeyType = .done
        textField.delegate = self
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.isHidden = true
        
        addSubview(textField)

        // Picker scroll view + stack (hidden by default, shown for .picker mode)
        pickerScrollView.translatesAutoresizingMaskIntoConstraints = false
        pickerScrollView.showsVerticalScrollIndicator = false
        pickerScrollView.showsHorizontalScrollIndicator = false
        pickerScrollView.alwaysBounceVertical = false
        pickerScrollView.isHidden = true
        addSubview(pickerScrollView)

        pickerStack.translatesAutoresizingMaskIntoConstraints = false
        pickerStack.axis = .vertical
        pickerStack.spacing = 2
        pickerStack.alignment = .fill
        pickerScrollView.addSubview(pickerStack)

        // Preset scroll view + stack (hidden by default, shown for .presetPicker mode)
        presetScrollView.translatesAutoresizingMaskIntoConstraints = false
        presetScrollView.showsVerticalScrollIndicator = false
        presetScrollView.showsHorizontalScrollIndicator = false
        presetScrollView.alwaysBounceVertical = false
        presetScrollView.isHidden = true
        addSubview(presetScrollView)

        presetStack.translatesAutoresizingMaskIntoConstraints = false
        presetStack.axis = .vertical
        presetStack.spacing = 2
        presetStack.alignment = .fill
        presetScrollView.addSubview(presetStack)

        // Custom text field (hidden, shown when "Custom" preset is selected)
        customTextField.translatesAutoresizingMaskIntoConstraints = false
        customTextField.font = .systemFont(ofSize: 16, weight: .regular)
        customTextField.textColor = .white
        customTextField.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        customTextField.layer.cornerRadius = 12
        customTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        customTextField.leftViewMode = .always
        customTextField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        customTextField.rightViewMode = .always
        customTextField.returnKeyType = .done
        customTextField.delegate = self
        customTextField.autocorrectionType = .no
        customTextField.autocapitalizationType = .none
        customTextField.placeholder = "Custom format"
        customTextField.attributedPlaceholder = NSAttributedString(
            string: "Custom format",
            attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.3)]
        )
        customTextField.isHidden = true
        customTextField.addTarget(self, action: #selector(customTextFieldChanged), for: .editingChanged)
        addSubview(customTextField)

        // Button row
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually
        addSubview(buttonRow)

        // Done button
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = .systemYellow.withAlphaComponent(0.8)
        doneButton.layer.cornerRadius = 20
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(doneButton)

        // Full Config button
        fullConfigButton.translatesAutoresizingMaskIntoConstraints = false
        fullConfigButton.setTitle("Full Config →", for: .normal)
        fullConfigButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        fullConfigButton.setTitleColor(UIColor(white: 1.0, alpha: 0.7), for: .normal)
        fullConfigButton.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        fullConfigButton.layer.cornerRadius = 20
        fullConfigButton.addTarget(self, action: #selector(fullConfigTapped), for: .touchUpInside)
        buttonRow.addArrangedSubview(fullConfigButton)

        // Scroll view bottom constraints (mutually exclusive, switched per mode)
        pickerScrollBottom = pickerScrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -12)
        presetScrollBottom = presetScrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -12)
        // When custom text field is visible (always for presetPicker), preset scroll starts below it
        presetScrollBottomCustom = presetScrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -12)

        // Switchable top constraints for preset scroll view
        presetScrollTopBelowCustom = presetScrollView.topAnchor.constraint(equalTo: customTextField.bottomAnchor, constant: 12)
        presetScrollTopBelowBack = presetScrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12)

        // All start inactive; configure(mode:) activates the right ones
        pickerScrollBottom.isActive = false
        presetScrollBottom.isActive = false
        presetScrollBottomCustom.isActive = false
        presetScrollTopBelowCustom.isActive = false
        presetScrollTopBelowBack.isActive = false

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            // Text field (textField mode)
            textField.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 20),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.heightAnchor.constraint(equalToConstant: 44),

            // Picker scroll view (picker mode) — height is flexible, bounded by bottom constraint
            pickerScrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
            pickerScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pickerScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Picker stack fills the scroll view's content area
            pickerStack.topAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.topAnchor),
            pickerStack.leadingAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.leadingAnchor),
            pickerStack.trailingAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.trailingAnchor),
            pickerStack.bottomAnchor.constraint(equalTo: pickerScrollView.contentLayoutGuide.bottomAnchor),
            pickerStack.widthAnchor.constraint(equalTo: pickerScrollView.frameLayoutGuide.widthAnchor),

            // Custom text field (above preset scroll, always visible in presetPicker mode)
            customTextField.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
            customTextField.leadingAnchor.constraint(equalTo: leadingAnchor),
            customTextField.trailingAnchor.constraint(equalTo: trailingAnchor),
            customTextField.heightAnchor.constraint(equalToConstant: 44),

            // Preset scroll view (presetPicker mode) — top is switchable
            presetScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            presetScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            presetStack.topAnchor.constraint(equalTo: presetScrollView.contentLayoutGuide.topAnchor),
            presetStack.leadingAnchor.constraint(equalTo: presetScrollView.contentLayoutGuide.leadingAnchor),
            presetStack.trailingAnchor.constraint(equalTo: presetScrollView.contentLayoutGuide.trailingAnchor),
            presetStack.bottomAnchor.constraint(equalTo: presetScrollView.contentLayoutGuide.bottomAnchor),
            presetStack.widthAnchor.constraint(equalTo: presetScrollView.frameLayoutGuide.widthAnchor),

            // Button row pinned to bottom — always visible regardless of content above
            buttonRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            buttonRow.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    // MARK: - Public

    func configure(mode: Mode) {
        self.mode = mode
        isCustomSelected = false
        customTextField.text = ""
        customTextField.resignFirstResponder()

        // Deactivate all mode-specific bottom constraints
        deactivateAllScrollBottomConstraints()

        switch mode {
        case .textField(let title, let placeholder, let keyboardType, let initialValue):
            titleLabel.text = title.uppercased()
            textField.isHidden = false
            pickerScrollView.isHidden = true
            presetScrollView.isHidden = true
            customTextField.isHidden = true

            // No scroll bottom constraint needed — textField has fixed position

            textField.placeholder = placeholder
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.3)]
            )
            textField.keyboardType = keyboardType
            textField.text = initialValue
            // Auto-focus only when empty (new widget); pre-filled fields don't need immediate keyboard
            if initialValue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.textField.becomeFirstResponder()
                }
            }

        case .picker(let title, let options, let selectedId):
            titleLabel.text = title.uppercased()
            textField.isHidden = true
            pickerScrollView.isHidden = false
            presetScrollView.isHidden = true
            customTextField.isHidden = true

            pickerScrollBottom.isActive = true

            self.selectedOptionId = selectedId
            buildPickerOptions(options)
            // Enable bounce when content exceeds visible area
            updateScrollBounce(pickerScrollView, pickerStack)

        case .presetPicker(let title, let presets, let selectedValue, let showCustomField):
            titleLabel.text = title.uppercased()
            textField.isHidden = true
            pickerScrollView.isHidden = true
            presetScrollView.isHidden = false

            if showCustomField {
                // Show the text field at the top for custom input
                customTextField.isHidden = false
                customTextField.placeholder = "Custom format"
                customTextField.attributedPlaceholder = NSAttributedString(
                    string: "Custom format",
                    attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.3)]
                )
                presetScrollBottomCustom.isActive = true
                presetScrollTopBelowCustom.isActive = true
            } else {
                // No custom text field — preset scroll goes directly below back button
                customTextField.isHidden = true
                presetScrollBottom.isActive = true
                presetScrollTopBelowBack.isActive = true
            }

            if let selectedValue {
                if presets.contains(where: { $0.value == selectedValue }) {
                    // Matches a known preset — select it and fill the text field
                    self.selectedOptionId = selectedValue
                    customTextField.text = selectedValue
                } else {
                    // No match — treat as custom text
                    isCustomSelected = true
                    customTextField.text = selectedValue
                    self.selectedOptionId = selectedValue
                }
            } else {
                // Default to first non-nil preset
                if let first = presets.first(where: { $0.value != nil }) {
                    selectedOptionId = first.value!
                    customTextField.text = first.value!
                }
            }

            buildPresetOptions(presets)
            // Enable bounce when content exceeds visible area
            updateScrollBounce(presetScrollView, presetStack)
        }
    }

    private func deactivateAllScrollBottomConstraints() {
        pickerScrollBottom.isActive = false
        presetScrollBottom.isActive = false
        presetScrollBottomCustom.isActive = false
        presetScrollTopBelowCustom.isActive = false
        presetScrollTopBelowBack.isActive = false
    }

    /// Enable vertical bounce only when content is taller than the scroll view frame.
    private func updateScrollBounce(_ scrollView: UIScrollView, _ stack: UIStackView) {
        layoutIfNeeded()
        scrollView.alwaysBounceVertical = stack.frame.height > scrollView.frame.height
    }

    // MARK: - Preset Picker

    private func buildPresetOptions(_ presets: [(name: String, icon: String, value: String?)]) {
        presetStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        presetButtons.removeAll()

        for preset in presets {
            // Skip nil-value "Custom" entries — the always-visible text field replaces them
            guard let presetValue = preset.value else { continue }

            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)

            let isSelected = (presetValue == selectedOptionId) && !isCustomSelected

            let circle = isSelected ? "largecircle.fill.circle" : "circle"
            let symConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: symConfig), for: .normal)

            // Build title with icon prefix
            let iconAttachment = NSTextAttachment()
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            iconAttachment.image = UIImage(systemName: preset.icon, withConfiguration: iconConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            let iconString = NSAttributedString(attachment: iconAttachment)
            let titleString = NSMutableAttributedString(string: "  ")
            titleString.append(iconString)
            titleString.append(NSAttributedString(string: "  \(preset.name)",
                attributes: [.foregroundColor: UIColor.white,
                             .font: UIFont.systemFont(ofSize: 15, weight: .medium)]))
            button.setAttributedTitle(titleString, for: .normal)

            button.tintColor = isSelected ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isSelected ? UIColor(white: 1.0, alpha: 0.08) : .clear
            button.layer.cornerRadius = 8
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

            button.addAction(UIAction { [weak self] _ in
                self?.selectPreset(value: presetValue)
            }, for: .touchUpInside)

            presetStack.addArrangedSubview(button)
            presetButtons.append((value: presetValue, button: button))
        }
    }

    private func selectPreset(value: String?) {
        if let value {
            isCustomSelected = false
            selectedOptionId = value
            // Fill the always-visible text field with the preset value
            customTextField.text = value
        } else {
            isCustomSelected = true
            customTextField.text = ""
        }

        // Update visual state for all preset buttons
        for (presetValue, button) in presetButtons {
            let isSelected = !isCustomSelected && (presetValue == value)
            let circle = isSelected ? "largecircle.fill.circle" : "circle"
            let symConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: symConfig), for: .normal)
            button.tintColor = isSelected ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isSelected ? UIColor(white: 1.0, alpha: 0.08) : .clear
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func buildPickerOptions(_ options: [(id: String, name: String)]) {
        pickerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        optionButtons.removeAll()

        for option in options {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)

            let isSelected = option.id == selectedOptionId
            let circle = isSelected ? "largecircle.fill.circle" : "circle"
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: config), for: .normal)
            button.setTitle("  \(option.name)", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.tintColor = isSelected ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isSelected ? UIColor(white: 1.0, alpha: 0.08) : .clear
            button.layer.cornerRadius = 8
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

            button.addAction(UIAction { [weak self] _ in
                self?.selectOption(option.id)
            }, for: .touchUpInside)

            pickerStack.addArrangedSubview(button)
            optionButtons.append((id: option.id, button: button))
        }
    }

    private func selectOption(_ id: String) {
        selectedOptionId = id
        // Update visual state
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
        textField.resignFirstResponder()
        customTextField.resignFirstResponder()
        onBack?()
    }

    @objc private func doneTapped() {
        textField.resignFirstResponder()
        customTextField.resignFirstResponder()
        switch mode {
        case .textField:
            onDone?(textField.text ?? "")
        case .picker:
            onDone?(selectedOptionId)
        case .presetPicker(_, _, _, let showCustomField):
            if showCustomField {
                onDone?(customTextField.text ?? "")
            } else {
                onDone?(selectedOptionId)
            }
        case .none:
            break
        }
    }

    @objc private func fullConfigTapped() {
        textField.resignFirstResponder()
        customTextField.resignFirstResponder()
        onFullConfig?()
    }

    @objc private func customTextFieldChanged() {
        let text = customTextField.text ?? ""
        // Check if the typed text matches any preset
        var matchedPreset = false
        for (presetValue, button) in presetButtons {
            let isMatch = (presetValue == text)
            if isMatch {
                matchedPreset = true
                selectedOptionId = text
            }
            let circle = isMatch ? "largecircle.fill.circle" : "circle"
            let symConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            button.setImage(UIImage(systemName: circle, withConfiguration: symConfig), for: .normal)
            button.tintColor = isMatch ? .systemYellow : UIColor(white: 1.0, alpha: 0.5)
            button.backgroundColor = isMatch ? UIColor(white: 1.0, alpha: 0.08) : .clear
        }
        isCustomSelected = !matchedPreset
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        doneTapped()
        return true
    }
}
