import UIKit

/// Inline resolution picker that replaces the button grid inside ExpandedControlsModal
class InlineQualityView: UIView {
    
    // MARK: - Callbacks
    
    var onResolutionSelected: ((Int) -> Void)?
    var onBack: (() -> Void)?
    
    // MARK: - Views
    
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let pillStack = UIStackView()
    private let lockedLabel = UILabel()
    
    private var pillButtons: [UIButton] = []
    private var activeIndex: Int = 0
    private var isLocked: Bool = false
    
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
        titleLabel.text = "QUALITY"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        addSubview(titleLabel)
        
        // Pill grid (2×2, centered)
        pillStack.translatesAutoresizingMaskIntoConstraints = false
        pillStack.axis = .vertical
        pillStack.spacing = 10
        pillStack.alignment = .center
        addSubview(pillStack)
        
        // Locked label (shown when live/recording)
        lockedLabel.translatesAutoresizingMaskIntoConstraints = false
        lockedLabel.text = "Cannot change while live"
        lockedLabel.font = .systemFont(ofSize: 12, weight: .medium)
        lockedLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        lockedLabel.textAlignment = .center
        lockedLabel.isHidden = true
        addSubview(lockedLabel)
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),
            
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            
            pillStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            lockedLabel.topAnchor.constraint(equalTo: pillStack.bottomAnchor, constant: 12),
            lockedLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
    
    // MARK: - Public
    
    func configure(options: [String], activeIndex: Int, isLocked: Bool) {
        self.activeIndex = activeIndex
        self.isLocked = isLocked
        lockedLabel.isHidden = !isLocked
        
        // Clear existing
        pillButtons.forEach { $0.removeFromSuperview() }
        pillButtons.removeAll()
        pillStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Build pills into rows of 2
        let pillsPerRow = 2
        var currentRow: UIStackView?
        
        for (index, name) in options.enumerated() {
            if index % pillsPerRow == 0 {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 12
                row.alignment = .center
                pillStack.addArrangedSubview(row)
                currentRow = row
            }
            let pill = makePill(title: name, tag: index)
            stylePill(pill, active: index == activeIndex, locked: isLocked)
            currentRow?.addArrangedSubview(pill)
            pillButtons.append(pill)
        }
    }
    
    // MARK: - Pill Factory
    
    private func makePill(title: String, tag: Int) -> UIButton {
        let pill = UIButton(type: .system)
        pill.setTitle(title, for: .normal)
        pill.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        pill.layer.cornerRadius = 18
        pill.tag = tag
        pill.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        pill.addTarget(self, action: #selector(pillTapped(_:)), for: .touchUpInside)
        
        pill.heightAnchor.constraint(equalToConstant: 36).isActive = true
        pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        
        return pill
    }
    
    private func stylePill(_ pill: UIButton, active: Bool, locked: Bool) {
        if locked {
            pill.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            pill.setTitleColor(UIColor(white: 1.0, alpha: 0.3), for: .normal)
            pill.isUserInteractionEnabled = false
        } else if active {
            pill.backgroundColor = .systemYellow
            pill.setTitleColor(.black, for: .normal)
            pill.isUserInteractionEnabled = true
        } else {
            pill.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
            pill.setTitleColor(.white, for: .normal)
            pill.isUserInteractionEnabled = true
        }
    }
    
    // MARK: - Actions
    
    @objc private func backTapped() { onBack?() }
    
    @objc private func pillTapped(_ sender: UIButton) {
        guard !isLocked else { return }
        let index = sender.tag
        guard index != activeIndex else { return }
        
        activeIndex = index
        for pill in pillButtons {
            stylePill(pill, active: pill.tag == index, locked: false)
        }
        
        onResolutionSelected?(index)
    }
}
