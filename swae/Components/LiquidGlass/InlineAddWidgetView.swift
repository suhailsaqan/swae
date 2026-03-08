import UIKit

/// Inline widget type picker grid that replaces the widget list inside ExpandedControlsModal.
/// Shows common widget types in a 3×3 grid. Tapping a type creates the widget instantly.
/// A horizontal "Templates" row at the top offers one-tap pre-configured widgets.
class InlineAddWidgetView: UIView {

    // MARK: - Template Definition

    struct WidgetTemplate {
        let name: String
        let icon: String
        let type: SettingsWidgetType
        /// Called after the SettingsWidget is created to pre-fill its config.
        let configure: (SettingsWidget) -> Void
        /// Optional custom position/size (percentages 0–100). Nil = use default centering.
        let position: (x: Double, y: Double, w: Double, h: Double)?
    }

    // MARK: - Callbacks

    var onBack: (() -> Void)?
    var onTypeSelected: ((SettingsWidgetType) -> Void)?
    /// Called when a template is tapped. The controller should create the widget using the template.
    var onTemplateSelected: ((WidgetTemplate) -> Void)?

    // MARK: - Types shown in the grid (most common first)

    private static let primaryTypes: [(type: SettingsWidgetType, label: String, icon: String)] = [
        (.text, "Text", "textformat"),
        (.browser, "Browser", "globe"),
        (.videoSource, "Camera", "video"),
        (.map, "Map", "map"),
        (.nostrChat, "Chat", "bubble.left.and.bubble.right"),
        (.qrCode, "QR", "qrcode"),
        (.snapshot, "Snapshot", "camera.aperture"),
        (.image, "Image", "photo"),
        (.scoreboard, "Score", "rectangle.split.2x1"),
    ]

    private static let moreTypes: [(type: SettingsWidgetType, label: String, icon: String)] = [
        (.alerts, "Alerts", "megaphone"),
        (.vTuber, "VTuber", "person.crop.circle"),
        (.pngTuber, "PNGTuber", "person.crop.circle.dashed"),
        (.scene, "Scene", "photo.on.rectangle"),
        (.crop, "Crop", "crop"),
    ]

    /// Built-in templates with pre-filled configuration.
    static let builtInTemplates: [WidgetTemplate] = [
        WidgetTemplate(
            name: "Timer",
            icon: "timer",
            type: .text,
            configure: { w in w.text.formatString = "⏳ {timer}" },
            position: (x: 80, y: 10, w: 18, h: 5)
        ),
        WidgetTemplate(
            name: "Stopwatch",
            icon: "stopwatch",
            type: .text,
            configure: { w in w.text.formatString = "⏱️ {stopwatch}" },
            position: (x: 80, y: 10, w: 18, h: 5)
        ),
        WidgetTemplate(
            name: "Clock",
            icon: "clock",
            type: .text,
            configure: { w in w.text.formatString = "🕑 {shortTime}" },
            position: (x: 82, y: 10, w: 16, h: 5)
        ),
        WidgetTemplate(
            name: "Camera PiP",
            icon: "pip",
            type: .videoSource,
            configure: { _ in },
            position: (x: 72, y: 72, w: 28, h: 28)
        ),
        WidgetTemplate(
            name: "Travel Info",
            icon: "location.fill",
            type: .text,
            configure: { w in w.text.formatString = "{countryFlag} {city}\n{speed} {altitude}" },
            position: (x: 2, y: 10, w: 30, h: 8)
        ),
        WidgetTemplate(
            name: "Map",
            icon: "map",
            type: .map,
            configure: { _ in },
            position: (x: 2, y: 74, w: 13, h: 23)
        ),
        WidgetTemplate(
            name: "Bitrate",
            icon: "speedometer",
            type: .text,
            configure: { w in w.text.formatString = "{bitrateAndTotal}" },
            position: (x: 70, y: 10, w: 28, h: 5)
        ),
        WidgetTemplate(
            name: "Live Chat",
            icon: "bubble.left.and.bubble.right",
            type: .nostrChat,
            configure: { _ in },
            position: (x: 2, y: 25, w: 25, h: 50)
        ),
    ]

    // MARK: - Views

    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let gridStack = UIStackView()
    private var isShowingMore = false

    // Templates row
    private let templatesSectionLabel = UILabel()
    private let templatesScroll = UIScrollView()
    private let templatesStack = UIStackView()
    private let typesSectionLabel = UILabel()

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
        titleLabel.text = "ADD WIDGET"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)

        // Outer scroll view (holds templates + type grid)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        // Content stack inside outer scroll (vertical: templates section → types section)
        let contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)

        // --- Templates section ---
        templatesSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        templatesSectionLabel.text = "TEMPLATES"
        templatesSectionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        templatesSectionLabel.textColor = UIColor(white: 1.0, alpha: 0.45)
        contentStack.addArrangedSubview(templatesSectionLabel)

        templatesScroll.translatesAutoresizingMaskIntoConstraints = false
        templatesScroll.showsHorizontalScrollIndicator = false
        templatesScroll.showsVerticalScrollIndicator = false
        templatesScroll.alwaysBounceHorizontal = true
        contentStack.addArrangedSubview(templatesScroll)
        templatesScroll.heightAnchor.constraint(equalToConstant: 72).isActive = true

        templatesStack.translatesAutoresizingMaskIntoConstraints = false
        templatesStack.axis = .horizontal
        templatesStack.spacing = 10
        templatesStack.alignment = .fill
        templatesScroll.addSubview(templatesStack)

        NSLayoutConstraint.activate([
            templatesStack.topAnchor.constraint(equalTo: templatesScroll.contentLayoutGuide.topAnchor),
            templatesStack.leadingAnchor.constraint(equalTo: templatesScroll.contentLayoutGuide.leadingAnchor),
            templatesStack.trailingAnchor.constraint(equalTo: templatesScroll.contentLayoutGuide.trailingAnchor),
            templatesStack.bottomAnchor.constraint(equalTo: templatesScroll.contentLayoutGuide.bottomAnchor),
            templatesStack.heightAnchor.constraint(equalTo: templatesScroll.frameLayoutGuide.heightAnchor),
        ])

        buildTemplateChips()

        // --- Types section ---
        typesSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        typesSectionLabel.text = "CUSTOM"
        typesSectionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        typesSectionLabel.textColor = UIColor(white: 1.0, alpha: 0.45)
        contentStack.addArrangedSubview(typesSectionLabel)

        // Grid stack (vertical, holds rows)
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        gridStack.axis = .vertical
        gridStack.spacing = 12
        gridStack.alignment = .fill
        contentStack.addArrangedSubview(gridStack)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
        ])

        buildGrid()
    }

    private func buildTemplateChips() {
        templatesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for template in Self.builtInTemplates {
            let chip = makeTemplateChip(template)
            templatesStack.addArrangedSubview(chip)
        }
    }

    private func makeTemplateChip(_ template: WidgetTemplate) -> UIView {
        let chip = TemplateChipView(template: template) { [weak self] t in
            self?.onTemplateSelected?(t)
        }
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        chip.layer.cornerRadius = 12

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        iconView.image = UIImage(systemName: template.icon, withConfiguration: config)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        chip.addSubview(iconView)

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = template.name
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        chip.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 72),

            iconView.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: chip.centerYAnchor, constant: -10),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -2),
        ])

        return chip
    }

    private func buildGrid() {
        gridStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Build rows of 3 from primary types + "More..." button
        var items: [(label: String, icon: String, action: () -> Void)] = Self.primaryTypes.map { item in
            return (label: item.label, icon: item.icon, action: { [weak self] in
                self?.onTypeSelected?(item.type)
            } as () -> Void)
        }

        if !isShowingMore {
            // Add "More..." button as the 9th item
            items.append((label: "More", icon: "ellipsis", action: { [weak self] in
                self?.isShowingMore = true
                self?.buildGrid()
            } as () -> Void))
        } else {
            // Add all the extra types
            for item in Self.moreTypes {
                items.append((label: item.label, icon: item.icon, action: { [weak self] in
                    self?.onTypeSelected?(item.type)
                } as () -> Void))
            }
        }

        // Chunk into rows of 3
        var index = 0
        while index < items.count {
            let end = min(index + 3, items.count)
            let rowItems = Array(items[index..<end])
            let row = makeRow(rowItems)
            gridStack.addArrangedSubview(row)
            index += 3
        }
    }

    private func makeRow(_ items: [(label: String, icon: String, action: () -> Void)]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually

        for item in items {
            let cell = makeTypeCell(label: item.label, icon: item.icon, action: item.action)
            row.addArrangedSubview(cell)
        }

        // Pad with empty views if fewer than 3
        for _ in items.count..<3 {
            let spacer = UIView()
            row.addArrangedSubview(spacer)
        }

        row.heightAnchor.constraint(equalToConstant: 80).isActive = true
        return row
    }

    private func makeTypeCell(label: String, icon: String, action: @escaping () -> Void) -> UIView {
        let cell = TypeCellView(action: action)
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        cell.layer.cornerRadius = 14

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        iconView.image = UIImage(systemName: icon, withConfiguration: config)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        cell.addSubview(iconView)

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = label
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        nameLabel.textAlignment = .center
        cell.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: -10),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameLabel.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cell.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
        ])

        return cell
    }

    // MARK: - Actions

    @objc private func backTapped() { onBack?() }
}

// MARK: - TypeCellView

/// Tappable cell that stores an action closure
private class TypeCellView: UIView {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        // Brief highlight
        UIView.animate(withDuration: 0.1, animations: {
            self.alpha = 0.5
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.alpha = 1.0
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action()
    }
}

// MARK: - TemplateChipView

/// Tappable chip for a widget template.
private class TemplateChipView: UIView {
    private let template: InlineAddWidgetView.WidgetTemplate
    private let action: (InlineAddWidgetView.WidgetTemplate) -> Void

    init(template: InlineAddWidgetView.WidgetTemplate, action: @escaping (InlineAddWidgetView.WidgetTemplate) -> Void) {
        self.template = template
        self.action = action
        super.init(frame: .zero)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.alpha = 0.5
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.alpha = 1.0
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action(template)
    }
}
