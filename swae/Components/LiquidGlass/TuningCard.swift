import UIKit

/// Rectangular glass card for tuning controls (Zone 2)
/// ~85×70pt, icon + title + dynamic subtitle, yellow top border when active
class TuningCard: UIControl {

    // MARK: - Properties

    private var glassContainer: GlassContainerView!
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let activeBorder = UIView()

    var isActive: Bool = false {
        didSet { updateActiveState() }
    }

    // MARK: - Constants

    private let cardWidth: CGFloat = 85
    private let cardHeight: CGFloat = 70
    private let cornerRadius: CGFloat = 16

    // MARK: - Init

    init(symbolName: String, title: String) {
        super.init(frame: .zero)
        setup(symbol: symbolName, title: title)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(symbol: "questionmark", title: "")
    }

    // MARK: - Setup

    private func setup(symbol: String, title: String) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        glassContainer = GlassFactory.makeGlassView(cornerRadius: cornerRadius)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        glassContainer.isUserInteractionEnabled = false
        addSubview(glassContainer)

        // Active top border (yellow, 2pt)
        activeBorder.translatesAutoresizingMaskIntoConstraints = false
        activeBorder.backgroundColor = .systemYellow
        activeBorder.layer.cornerRadius = 1
        activeBorder.alpha = 0
        glassContainer.glassContentView.addSubview(activeBorder)

        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconView.image = UIImage(systemName: symbol, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        glassContainer.glassContentView.addSubview(iconView)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title.uppercased()
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        glassContainer.glassContentView.addSubview(titleLabel)

        // Subtitle (dynamic value)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10, weight: .regular)
        subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        subtitleLabel.textAlignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingTail
        glassContainer.glassContentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            glassContainer.topAnchor.constraint(equalTo: topAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: cardWidth),
            heightAnchor.constraint(equalToConstant: cardHeight),

            activeBorder.topAnchor.constraint(equalTo: glassContainer.glassContentView.topAnchor, constant: 4),
            activeBorder.centerXAnchor.constraint(equalTo: glassContainer.glassContentView.centerXAnchor),
            activeBorder.widthAnchor.constraint(equalToConstant: 30),
            activeBorder.heightAnchor.constraint(equalToConstant: 2),

            iconView.topAnchor.constraint(equalTo: glassContainer.glassContentView.topAnchor, constant: 10),
            iconView.centerXAnchor.constraint(equalTo: glassContainer.glassContentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: glassContainer.glassContentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: glassContainer.glassContentView.trailingAnchor, constant: -4),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: glassContainer.glassContentView.leadingAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: glassContainer.glassContentView.trailingAnchor, constant: -4),
        ])

        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchCancel, .touchUpInside, .touchUpOutside, .touchDragExit])
    }

    // MARK: - Public

    func configure(subtitle: String, isActive: Bool) {
        subtitleLabel.text = subtitle
        self.isActive = isActive
    }

    // MARK: - State

    private func updateActiveState() {
        UIView.animate(withDuration: 0.2) {
            self.activeBorder.alpha = self.isActive ? 1 : 0
        }
    }

    // MARK: - Touch Feedback

    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.glassContainer.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func touchUp() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.glassContainer.transform = .identity
        }
    }
}
