import UIKit

/// Glass circle button matching iOS 26 Camera style
/// Uses UIGlassEffect on iOS 26+ for the liquid glass look
class ControlButton: UIControl {
    
    // MARK: - Properties
    
    private var circleGlassContainer: GlassContainerView!
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    
    var isActive: Bool = false {
        didSet { updateActiveState() }
    }
    
    var isDisabled: Bool = false {
        didSet {
            alpha = isDisabled ? 0.4 : 1.0
            isUserInteractionEnabled = !isDisabled
        }
    }
    
    // MARK: - Constants
    
    private let circleSize: CGFloat = 70
    private let iconSize: CGFloat = 24
    
    // MARK: - Initialization
    
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
        
        // Circle background - use liquid glass!
        circleGlassContainer = GlassFactory.makeGlassView(cornerRadius: circleSize / 2)
        circleGlassContainer.translatesAutoresizingMaskIntoConstraints = false
        circleGlassContainer.isUserInteractionEnabled = false
        addSubview(circleGlassContainer)
        
        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        if let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)) {
            iconView.image = img.withRenderingMode(.alwaysTemplate)
        }
        circleGlassContainer.glassContentView.addSubview(iconView)
        
        // Label below circle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title.uppercased()
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            // Circle
            circleGlassContainer.topAnchor.constraint(equalTo: topAnchor),
            circleGlassContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleGlassContainer.widthAnchor.constraint(equalToConstant: circleSize),
            circleGlassContainer.heightAnchor.constraint(equalToConstant: circleSize),
            
            // Icon centered in circle
            iconView.centerXAnchor.constraint(equalTo: circleGlassContainer.glassContentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: circleGlassContainer.glassContentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            
            // Label below
            titleLabel.topAnchor.constraint(equalTo: circleGlassContainer.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        // Touch handlers
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchCancel, .touchUpInside, .touchUpOutside, .touchDragExit])
    }
    
    // MARK: - Active State (for LIVE button yellow ring)
    
    private func updateActiveState() {
        if isActive {
            circleGlassContainer.layer.cornerRadius = circleSize / 2
            circleGlassContainer.layer.borderWidth = 2.0
            circleGlassContainer.layer.borderColor = UIColor.systemYellow.cgColor
        } else {
            circleGlassContainer.layer.borderWidth = 0
            circleGlassContainer.layer.borderColor = nil
        }
    }
    
    // MARK: - Touch Feedback
    
    func setTitle(_ text: String) {
        titleLabel.text = text.uppercased()
    }
    
    func setIcon(_ symbolName: String) {
        if let img = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)) {
            iconView.image = img.withRenderingMode(.alwaysTemplate)
        }
    }
    
    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.circleGlassContainer.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            self.circleGlassContainer.alpha = 0.8
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    @objc private func touchUp() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.circleGlassContainer.transform = .identity
            self.circleGlassContainer.alpha = 1.0
        }
    }
}
