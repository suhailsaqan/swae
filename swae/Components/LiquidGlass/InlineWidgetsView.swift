import UIKit

/// UIView that delivers touches to subviews positioned outside its bounds.
/// Used for the swipe-to-reveal row content so action buttons (anchored just
/// past the trailing edge) can receive taps when the row slides left.
private class SwipeRowContentView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let hit = super.hitTest(point, with: event) {
            return hit
        }
        // Check subviews outside bounds (the actions view)
        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 && subview.isUserInteractionEnabled {
            let subPoint = subview.convert(point, from: self)
            if let hit = subview.hitTest(subPoint, with: event) {
                return hit
            }
        }
        return nil
    }
}

/// Inline widget list that replaces the button grid inside ExpandedControlsModal.
/// Shows all widgets in the current scene with toggle switches, plus an "Add Widget" button.
class InlineWidgetsView: UIView {

    // MARK: - Data Model

    struct WidgetItem {
        let id: UUID
        let name: String
        let type: SettingsWidgetType
        var enabled: Bool
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onWidgetToggled: ((UUID, Bool) -> Void)?
    var onWidgetTapped: ((UUID) -> Void)?
    var onWidgetRowTapped: ((UUID) -> Void)?
    var onWidgetDuplicate: ((UUID) -> Void)?
    var onWidgetDelete: ((UUID) -> Void)?
    var onAddTapped: (() -> Void)?
    var onSettingsTapped: (() -> Void)?

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let emptyLabel = UILabel()
    private let addButton = UIButton(type: .system)

    private var widgetRows: [WidgetRow] = []

    /// Tracks which row currently has swipe actions revealed (only one at a time).
    private weak var revealedRow: UIView?

    /// Widget ID to pulse the position badge for after configure.
    var pulseWidgetId: UUID?

    // MARK: - Row Data

    private struct WidgetRow {
        let id: UUID
        let name: String
        let toggle: UISwitch
        let container: UIView
        /// The visible row content (slides left to reveal actions).
        let contentView: UIView
        /// The action buttons container behind the row.
        let actionsView: UIView
        let positionBadge: UIView
        /// Pan gesture for swipe-to-reveal.
        let panGesture: UIPanGestureRecognizer
    }

    // MARK: - Constants

    private let rowHeight: CGFloat = 48
    private let actionButtonWidth: CGFloat = 56
    private let revealWidth: CGFloat = 112 // 2 buttons × 56
    private let fullSwipeThreshold: CGFloat = 150
    private static let hintShownKey = "widgetPositionHintShown"

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
        titleLabel.text = "WIDGETS"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        // Hint label (one-time)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "Tap the arrows to reposition a widget"
        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = UIColor(white: 1.0, alpha: 0.35)
        hintLabel.alpha = 0
        addSubview(hintLabel)

        // Settings gear button (top-right)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        let gearConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: gearConfig), for: .normal)
        settingsButton.tintColor = UIColor(white: 1.0, alpha: 0.6)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        addSubview(settingsButton)

        // Scroll view for widget list
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        // Content stack inside scroll view
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)

        // Empty state label
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No widgets yet.\nAdd one to get started."
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        // Add Widget button
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("  Add Widget", for: .normal)
        let plusConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        addButton.setImage(UIImage(systemName: "plus", withConfiguration: plusConfig), for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        addButton.setTitleColor(.white, for: .normal)
        addButton.tintColor = .white
        addButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        addButton.layer.cornerRadius = 22
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addSubview(addButton)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            settingsButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 32),
            settingsButton.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

            addButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            addButton.heightAnchor.constraint(equalToConstant: 44),
            addButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Public

    func configure(widgets: [WidgetItem]) {
        // Close any revealed actions
        closeRevealedActions(animated: false)

        // Clear existing rows
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        widgetRows.removeAll()

        if widgets.isEmpty {
            emptyLabel.isHidden = false
            contentStack.addArrangedSubview(emptyLabel)
        } else {
            emptyLabel.isHidden = true
            emptyLabel.removeFromSuperview()
            for widget in widgets {
                let row = makeWidgetRow(widget)
                contentStack.addArrangedSubview(row)
            }
        }

        // Force layout
        superview?.layoutIfNeeded()
        setNeedsLayout()
        layoutIfNeeded()

        // Show one-time hint
        showHintIfNeeded()

        // Pulse position badge if requested
        if let pulseId = pulseWidgetId,
           let row = widgetRows.first(where: { $0.id == pulseId }) {
            pulseWidgetId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.pulsePositionBadge(row.positionBadge)
            }
        }
    }

    // MARK: - Hint

    private func showHintIfNeeded() {
        guard !widgetRows.isEmpty,
              !UserDefaults.standard.bool(forKey: Self.hintShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hintShownKey)

        hintLabel.alpha = 0
        UIView.animate(withDuration: 0.3) { self.hintLabel.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            UIView.animate(withDuration: 0.5) { self?.hintLabel.alpha = 0 }
        }
    }

    // MARK: - Row Factory

    private func makeWidgetRow(_ widget: WidgetItem) -> UIView {
        // Outer container clips the swipe actions
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.clipsToBounds = true

        // Content view (the visible row that slides left)
        let contentView = SwipeRowContentView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        container.addSubview(contentView)

        // Action buttons — child of contentView, positioned just off its right edge.
        // The container clips them so they're invisible at rest. When contentView
        // slides left via transform, the actions slide into the visible area.
        let actionsView = makeActionsView(widgetId: widget.id, widgetName: widget.name)
        actionsView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionsView)

        // Icon
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let symbolName = widgetImageForType(widget.type)
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: iconConfig)
        iconView.tintColor = UIColor(white: 1.0, alpha: 0.7)
        iconView.contentMode = .scaleAspectFit
        contentView.addSubview(iconView)

        // Name label
        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = widget.name
        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(nameLabel)

        // Position badge
        let badge = makePositionBadge()
        contentView.addSubview(badge)

        // Toggle switch
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.isOn = widget.enabled
        toggle.onTintColor = .systemYellow
        toggle.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        contentView.addSubview(toggle)

        // Separator
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: rowHeight),

            // Content fills the container (slides via transform)
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            // Actions sit just outside the content view's right edge
            actionsView.leadingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionsView.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            actionsView.widthAnchor.constraint(equalToConstant: revealWidth),

            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8),

            badge.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -6),
            badge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // Pan gesture for swipe-to-reveal
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleRowPan(_:)))
        pan.delegate = self
        contentView.addGestureRecognizer(pan)

        // Tap gesture on the row to enter positioning
        let rowTap = UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        contentView.addGestureRecognizer(rowTap)

        // Store reference
        let rowData = WidgetRow(
            id: widget.id,
            name: widget.name,
            toggle: toggle,
            container: container,
            contentView: contentView,
            actionsView: actionsView,
            positionBadge: badge,
            panGesture: pan
        )
        widgetRows.append(rowData)

        return container
    }

    // MARK: - Position Badge

    private func makePositionBadge() -> UIView {
        let badge = UIView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        badge.layer.cornerRadius = 10
        badge.isUserInteractionEnabled = true

        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        icon.image = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right", withConfiguration: config)
        icon.tintColor = UIColor(white: 1.0, alpha: 0.4)
        icon.contentMode = .scaleAspectFit
        badge.addSubview(icon)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 20),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(badgeTapped(_:)))
        badge.addGestureRecognizer(tap)

        return badge
    }

    private func pulsePositionBadge(_ badge: UIView) {
        let icon = badge.subviews.first as? UIImageView
        UIView.animate(withDuration: 0.15, animations: {
            badge.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            icon?.tintColor = .systemYellow
        }) { _ in
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
                badge.transform = .identity
                icon?.tintColor = UIColor(white: 1.0, alpha: 0.4)
            }
        }
    }

    // MARK: - Swipe Action Buttons

    private func makeActionsView(widgetId: UUID, widgetName: String) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let duplicateBtn = UIButton(type: .system)
        duplicateBtn.translatesAutoresizingMaskIntoConstraints = false
        let dupConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        duplicateBtn.setImage(UIImage(systemName: "square.on.square", withConfiguration: dupConfig), for: .normal)
        duplicateBtn.tintColor = .systemBlue
        duplicateBtn.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        duplicateBtn.addTarget(self, action: #selector(duplicateActionTapped(_:)), for: .touchUpInside)
        view.addSubview(duplicateBtn)

        let deleteBtn = UIButton(type: .system)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        let delConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        deleteBtn.setImage(UIImage(systemName: "trash", withConfiguration: delConfig), for: .normal)
        deleteBtn.tintColor = .systemRed
        deleteBtn.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        deleteBtn.addTarget(self, action: #selector(deleteActionTapped(_:)), for: .touchUpInside)
        view.addSubview(deleteBtn)

        NSLayoutConstraint.activate([
            duplicateBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            duplicateBtn.topAnchor.constraint(equalTo: view.topAnchor),
            duplicateBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            duplicateBtn.widthAnchor.constraint(equalToConstant: actionButtonWidth),

            deleteBtn.leadingAnchor.constraint(equalTo: duplicateBtn.trailingAnchor),
            deleteBtn.topAnchor.constraint(equalTo: view.topAnchor),
            deleteBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        return view
    }

    // MARK: - Delete Confirmation

    private func showDeleteConfirmation(for row: WidgetRow) {
        closeRevealedActions(animated: true)

        let contentView = row.contentView
        // Hide normal content
        for sub in contentView.subviews { sub.alpha = 0 }

        // Build confirmation overlay
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
        overlay.tag = 999 // for removal
        contentView.addSubview(overlay)

        let trashIcon = UIImageView()
        trashIcon.translatesAutoresizingMaskIntoConstraints = false
        let trashConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        trashIcon.image = UIImage(systemName: "trash", withConfiguration: trashConfig)
        trashIcon.tintColor = .systemRed
        overlay.addSubview(trashIcon)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Delete \"\(row.name)\"?"
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        overlay.addSubview(label)

        let cancelBtn = UIButton(type: .system)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        cancelBtn.setTitleColor(.white, for: .normal)
        cancelBtn.addTarget(self, action: #selector(confirmCancelTapped(_:)), for: .touchUpInside)
        overlay.addSubview(cancelBtn)

        let confirmBtn = UIButton(type: .system)
        confirmBtn.translatesAutoresizingMaskIntoConstraints = false
        confirmBtn.setTitle("Delete", for: .normal)
        confirmBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        confirmBtn.setTitleColor(.systemRed, for: .normal)
        confirmBtn.addTarget(self, action: #selector(confirmDeleteTapped(_:)), for: .touchUpInside)
        overlay.addSubview(confirmBtn)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            trashIcon.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 8),
            trashIcon.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: trashIcon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cancelBtn.leadingAnchor, constant: -4),

            confirmBtn.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -8),
            confirmBtn.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            cancelBtn.trailingAnchor.constraint(equalTo: confirmBtn.leadingAnchor, constant: -12),
            cancelBtn.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])

        overlay.alpha = 0
        UIView.animate(withDuration: 0.25) { overlay.alpha = 1 }

        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak overlay] in
            guard let overlay = overlay, overlay.superview != nil else { return }
            self?.dismissDeleteConfirmation(for: row)
        }
    }

    private func dismissDeleteConfirmation(for row: WidgetRow) {
        let contentView = row.contentView
        guard let overlay = contentView.viewWithTag(999) else { return }
        UIView.animate(withDuration: 0.2, animations: {
            overlay.alpha = 0
            for sub in contentView.subviews where sub !== overlay {
                sub.alpha = 1
            }
        }) { _ in
            overlay.removeFromSuperview()
        }
    }

    private func executeDelete(for row: WidgetRow) {
        let container = row.container

        // Animate row removal
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            container.alpha = 0
            container.frame.size.height = 0
            container.isHidden = true
        }) { [weak self] _ in
            container.removeFromSuperview()
            self?.widgetRows.removeAll(where: { $0.id == row.id })

            // Show empty state if needed
            if self?.widgetRows.isEmpty == true {
                if let emptyLabel = self?.emptyLabel {
                    emptyLabel.isHidden = false
                    emptyLabel.alpha = 0
                    self?.contentStack.addArrangedSubview(emptyLabel)
                    UIView.animate(withDuration: 0.3) { emptyLabel.alpha = 1 }
                }
            }
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onWidgetDelete?(row.id)
    }

    // MARK: - Swipe Reveal

    private func closeRevealedActions(animated: Bool) {
        guard let revealed = revealedRow,
              let row = widgetRows.first(where: { $0.container === revealed }) else {
            revealedRow = nil
            return
        }
        revealedRow = nil
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.5) {
                row.contentView.transform = .identity
            }
        } else {
            row.contentView.transform = .identity
        }
    }

    private func widgetImageForType(_ type: SettingsWidgetType) -> String {
        switch type {
        case .image: return "photo"
        case .videoEffect: return "camera.filters"
        case .browser: return "globe"
        case .text: return "textformat"
        case .crop: return "crop"
        case .map: return "map"
        case .scene: return "photo.on.rectangle"
        case .qrCode: return "qrcode"
        case .alerts: return "megaphone"
        case .videoSource: return "video"
        case .scoreboard: return "rectangle.split.2x1"
        case .vTuber: return "person.crop.circle"
        case .pngTuber: return "person.crop.circle.dashed"
        case .snapshot: return "camera.aperture"
        case .nostrChat: return "bubble.left.and.bubble.right"
        case .collabVideo: return "person.2.fill"
        }
    }

    // MARK: - Actions

    @objc private func backTapped() { onBack?() }
    @objc private func settingsTapped() { onSettingsTapped?() }
    @objc private func addTapped() { onAddTapped?() }

    @objc private func toggleChanged(_ sender: UISwitch) {
        guard let entry = widgetRows.first(where: { $0.toggle === sender }) else { return }
        onWidgetToggled?(entry.id, sender.isOn)
    }

    @objc private func rowTapped(_ gesture: UITapGestureRecognizer) {
        // If any row is revealed, close it instead
        if revealedRow != nil {
            closeRevealedActions(animated: true)
            return
        }
        guard let contentView = gesture.view,
              let entry = widgetRows.first(where: { $0.contentView === contentView }) else { return }
        // Don't fire if the tap was on the toggle or badge
        let location = gesture.location(in: contentView)
        if entry.toggle.frame.insetBy(dx: -10, dy: -10).contains(location) { return }
        if entry.positionBadge.frame.insetBy(dx: -5, dy: -5).contains(location) { return }
        onWidgetRowTapped?(entry.id)
    }

    @objc private func badgeTapped(_ gesture: UITapGestureRecognizer) {
        guard let badge = gesture.view,
              let contentView = badge.superview,
              let entry = widgetRows.first(where: { $0.contentView === contentView }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onWidgetTapped?(entry.id)
    }

    @objc private func duplicateActionTapped(_ sender: UIButton) {
        guard let actionsView = sender.superview,
              let entry = widgetRows.first(where: { $0.actionsView === actionsView }) else { return }
        closeRevealedActions(animated: true)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onWidgetDuplicate?(entry.id)
    }

    @objc private func deleteActionTapped(_ sender: UIButton) {
        guard let actionsView = sender.superview,
              let entry = widgetRows.first(where: { $0.actionsView === actionsView }) else { return }
        showDeleteConfirmation(for: entry)
    }

    @objc private func confirmCancelTapped(_ sender: UIButton) {
        guard let overlay = sender.superview,
              let contentView = overlay.superview,
              let entry = widgetRows.first(where: { $0.contentView === contentView }) else { return }
        dismissDeleteConfirmation(for: entry)
    }

    @objc private func confirmDeleteTapped(_ sender: UIButton) {
        guard let overlay = sender.superview,
              let contentView = overlay.superview,
              let entry = widgetRows.first(where: { $0.contentView === contentView }) else { return }
        executeDelete(for: entry)
    }

    // MARK: - Pan Gesture (Swipe to Reveal)

    @objc private func handleRowPan(_ gesture: UIPanGestureRecognizer) {
        guard let contentView = gesture.view,
              let entry = widgetRows.first(where: { $0.contentView === contentView }) else { return }

        let translation = gesture.translation(in: contentView)
        let velocity = gesture.velocity(in: contentView)

        switch gesture.state {
        case .began:
            // Close any other revealed row
            if revealedRow != nil && revealedRow !== entry.container {
                closeRevealedActions(animated: true)
            }

        case .changed:
            // Only allow left swipe (negative x)
            let currentX = contentView.transform.tx
            let newX = min(0, currentX + translation.x)
            // Rubber-band past the reveal width
            let clamped: CGFloat
            if newX < -revealWidth {
                clamped = -revealWidth + (newX + revealWidth) * 0.3
            } else {
                clamped = newX
            }
            contentView.transform = CGAffineTransform(translationX: clamped, y: 0)
            gesture.setTranslation(.zero, in: contentView)

        case .ended, .cancelled:
            let currentX = contentView.transform.tx

            // Full swipe → trigger delete
            if currentX < -fullSwipeThreshold && velocity.x < -200 {
                UIView.animate(withDuration: 0.2) {
                    contentView.transform = CGAffineTransform(translationX: -self.revealWidth, y: 0)
                }
                revealedRow = entry.container
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showDeleteConfirmation(for: entry)
                return
            }

            // Decide: reveal or close
            let shouldReveal = currentX < -revealWidth * 0.4 || velocity.x < -500
            if shouldReveal {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.8) {
                    contentView.transform = CGAffineTransform(translationX: -self.revealWidth, y: 0)
                }
                revealedRow = entry.container
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else {
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.5) {
                    contentView.transform = .identity
                }
                if revealedRow === entry.container { revealedRow = nil }
            }

        default:
            break
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension InlineWidgetsView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        // Only activate for horizontal movement (prevents stealing vertical scroll)
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Don't share with the parent scroll view
        return false
    }
}
