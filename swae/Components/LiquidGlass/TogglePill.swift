import UIKit

/// Small glass pill for instant on/off toggles (Zone 1)
/// 44pt tall, ~50pt wide, icon only, active tint color
class TogglePill: UIControl {

    // MARK: - Properties

    private var glassContainer: GlassContainerView!
    private let iconView = UIImageView()
    private let tintOverlay = UIView()

    /// Color when active (yellow for flash/night, red for mute/record)
    var activeTintColor: UIColor = .systemYellow

    var isActive: Bool = false {
        didSet { updateActiveState() }
    }

    // MARK: - Constants

    private let pillHeight: CGFloat = 44
    private let pillWidth: CGFloat = 50
    private let cornerRadius: CGFloat = 22
    private let iconSize: CGFloat = 20

    // MARK: - Init

    init(symbolName: String, activeTint: UIColor = .systemYellow) {
        self.activeTintColor = activeTint
        super.init(frame: .zero)
        setup(symbol: symbolName)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(symbol: "questionmark")
    }

    // MARK: - Setup

    private func setup(symbol: String) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        glassContainer = GlassFactory.makeGlassView(cornerRadius: cornerRadius)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        glassContainer.isUserInteractionEnabled = false
        addSubview(glassContainer)

        // Tint overlay for active state
        tintOverlay.translatesAutoresizingMaskIntoConstraints = false
        tintOverlay.backgroundColor = .clear
        tintOverlay.layer.cornerRadius = cornerRadius
        tintOverlay.layer.cornerCurve = .continuous
        tintOverlay.isUserInteractionEnabled = false
        glassContainer.glassContentView.addSubview(tintOverlay)

        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        iconView.image = UIImage(systemName: symbol, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        glassContainer.glassContentView.addSubview(iconView)

        NSLayoutConstraint.activate([
            glassContainer.topAnchor.constraint(equalTo: topAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: pillWidth),
            heightAnchor.constraint(equalToConstant: pillHeight),

            tintOverlay.topAnchor.constraint(equalTo: glassContainer.glassContentView.topAnchor),
            tintOverlay.bottomAnchor.constraint(equalTo: glassContainer.glassContentView.bottomAnchor),
            tintOverlay.leadingAnchor.constraint(equalTo: glassContainer.glassContentView.leadingAnchor),
            tintOverlay.trailingAnchor.constraint(equalTo: glassContainer.glassContentView.trailingAnchor),

            iconView.centerXAnchor.constraint(equalTo: glassContainer.glassContentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: glassContainer.glassContentView.centerYAnchor),
        ])

        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchCancel, .touchUpInside, .touchUpOutside, .touchDragExit])
    }

    // MARK: - State

    private func updateActiveState() {
        UIView.animate(withDuration: 0.2) {
            self.tintOverlay.backgroundColor = self.isActive
                ? self.activeTintColor.withAlphaComponent(0.3)
                : .clear
            self.iconView.tintColor = self.isActive ? self.activeTintColor : .white
        }
    }

    func setIcon(_ symbolName: String) {
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
    }

    // MARK: - Touch Feedback

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.glassContainer.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.glassContainer.transform = .identity
        }
    }

    // MARK: - Accessibility

    override var accessibilityLabel: String? {
        get { super.accessibilityLabel }
        set { super.accessibilityLabel = newValue }
    }
}
