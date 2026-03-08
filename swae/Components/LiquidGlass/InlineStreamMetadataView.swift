import UIKit

/// Inline stream metadata editing sub-page — title, description, tags, NSFW, public, protocol
class InlineStreamMetadataView: UIView {

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onTitleChanged: ((String) -> Void)?
    var onDescriptionChanged: ((String) -> Void)?
    var onTagsChanged: ((String) -> Void)?
    var onNSFWChanged: ((Bool) -> Void)?
    var onPublicChanged: ((Bool) -> Void)?
    var onProtocolChanged: ((Int) -> Void)?
    var onUpdateTapped: (() -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let titleField = UITextField()
    private let descriptionField = UITextField()
    private let tagsField = UITextField()
    private let nsfwToggle = UISwitch()
    private let publicToggle = UISwitch()
    private let protocolSegment = UISegmentedControl(items: ["RTMP", "SRT"])
    private let updateButton = UIButton(type: .system)

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
        setupKeyboardObservers()

        backButton.translatesAutoresizingMaskIntoConstraints = false
        let backConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        backButton.tintColor = .white
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "STREAM DETAILS"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .fill
        scrollView.addSubview(stack)

        updateButton.translatesAutoresizingMaskIntoConstraints = false
        updateButton.setTitle("Update", for: .normal)
        updateButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        updateButton.setTitleColor(.black, for: .normal)
        updateButton.backgroundColor = .systemYellow
        updateButton.layer.cornerRadius = 22
        updateButton.layer.cornerCurve = .continuous
        updateButton.addTarget(self, action: #selector(updateTapped), for: .touchUpInside)
        updateButton.isHidden = true
        addSubview(updateButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: updateButton.topAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            updateButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            updateButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            updateButton.heightAnchor.constraint(equalToConstant: 44),
            updateButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        buildFields()
    }

    private func buildFields() {
        stack.addArrangedSubview(makeEditableRow(label: "Title", field: titleField, placeholder: "Stream title"))
        titleField.addTarget(self, action: #selector(titleChanged), for: .editingChanged)

        stack.addArrangedSubview(makeEditableRow(label: "Description", field: descriptionField, placeholder: "What are you streaming?"))
        descriptionField.addTarget(self, action: #selector(descChanged), for: .editingChanged)

        stack.addArrangedSubview(makeEditableRow(label: "Tags", field: tagsField, placeholder: "gaming, nostr, music"))
        tagsField.addTarget(self, action: #selector(tagsChanged), for: .editingChanged)

        let nsfwRow = makeToggleRow(label: "NSFW", toggle: nsfwToggle)
        nsfwToggle.addTarget(self, action: #selector(nsfwChanged), for: .valueChanged)
        stack.addArrangedSubview(nsfwRow)

        let publicRow = makeToggleRow(label: "Public Stream", toggle: publicToggle)
        publicToggle.addTarget(self, action: #selector(publicChanged), for: .valueChanged)
        stack.addArrangedSubview(publicRow)

        let protoRow = makeSegmentRow(label: "Protocol", segment: protocolSegment)
        protocolSegment.addTarget(self, action: #selector(protocolChanged), for: .valueChanged)
        stack.addArrangedSubview(protoRow)
    }

    // MARK: - Public API

    func configure(title: String, description: String, tags: String, isNSFW: Bool, isPublic: Bool, preferredProtocol: Int, isLive: Bool) {
        titleField.text = title
        descriptionField.text = description
        tagsField.text = tags
        nsfwToggle.isOn = isNSFW
        publicToggle.isOn = isPublic
        protocolSegment.selectedSegmentIndex = preferredProtocol
        // Always show the Update button so the user explicitly confirms changes
        updateButton.isHidden = false
        updateButton.setTitle(isLive ? "Update" : "Save", for: .normal)
    }

    // MARK: - Row Builders

    private func makeEditableRow(label: String, field: UITextField, placeholder: String) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = label
        lbl.font = .systemFont(ofSize: 13, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.5)
        row.addSubview(lbl)

        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 14, weight: .regular)
        field.textColor = .white
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.25)])
        field.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        field.layer.cornerRadius = 8
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.rightViewMode = .always
        field.returnKeyType = .done
        field.delegate = self
        row.addSubview(field)

        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: row.topAnchor, constant: 4),
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            field.topAnchor.constraint(equalTo: lbl.bottomAnchor, constant: 4),
            field.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            field.heightAnchor.constraint(equalToConstant: 36),
            field.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
        ])
        return row
    }

    private func makeToggleRow(label: String, toggle: UISwitch) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = label
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.7)
        row.addSubview(lbl)

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        toggle.onTintColor = .systemGreen
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func makeSegmentRow(label: String, segment: UISegmentedControl) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.text = label
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = UIColor(white: 1.0, alpha: 0.7)
        row.addSubview(lbl)

        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.selectedSegmentTintColor = UIColor(white: 1.0, alpha: 0.2)
        segment.setTitleTextAttributes([.foregroundColor: UIColor(white: 1.0, alpha: 0.5)], for: .normal)
        segment.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        row.addSubview(segment)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            lbl.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            segment.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            segment.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            segment.widthAnchor.constraint(equalToConstant: 120),
        ])
        return row
    }

    // MARK: - Keyboard

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(kbShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(kbHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func kbShow(_ n: Notification) {
        guard let kbFrame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let dur = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        UIView.animate(withDuration: dur) {
            self.scrollView.contentInset.bottom = kbFrame.height
            self.scrollView.verticalScrollIndicatorInsets.bottom = kbFrame.height
        }
        if let active = [titleField, descriptionField, tagsField].first(where: { $0.isFirstResponder }) {
            let rect = active.convert(active.bounds, to: scrollView)
            scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -20), animated: true)
        }
    }

    @objc private func kbHide(_ n: Notification) {
        let dur = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        UIView.animate(withDuration: dur) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Actions

    @objc private func backTapped() { onBack?() }

    // Field change handlers are no-ops — edits stay local in the text fields
    // until the user taps Save/Update.
    @objc private func titleChanged() {}
    @objc private func descChanged() {}
    @objc private func tagsChanged() {}
    @objc private func nsfwChanged() {}
    @objc private func publicChanged() {}
    @objc private func protocolChanged() {}

    @objc private func updateTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Commit all field values to the model at once
        onTitleChanged?(titleField.text ?? "")
        onDescriptionChanged?(descriptionField.text ?? "")
        onTagsChanged?(tagsField.text ?? "")
        onNSFWChanged?(nsfwToggle.isOn)
        onPublicChanged?(publicToggle.isOn)
        onProtocolChanged?(protocolSegment.selectedSegmentIndex)

        // Push to server if live
        onUpdateTapped?()

        // Flash confirmation then navigate back
        let original = updateButton.backgroundColor
        UIView.animate(withDuration: 0.1, animations: { self.updateButton.backgroundColor = .white }) { _ in
            UIView.animate(withDuration: 0.2, animations: { self.updateButton.backgroundColor = original }) { _ in
                self.onBack?()
            }
        }
    }
}

extension InlineStreamMetadataView: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
