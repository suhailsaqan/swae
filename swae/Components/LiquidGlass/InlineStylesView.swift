import UIKit

/// Inline LUT/styles picker that replaces the button grid inside ExpandedControlsModal
class InlineStylesView: UIView {
    
    // MARK: - Callbacks
    
    var onLutSelected: ((Int) -> Void)?  // -1 = none
    var onBack: (() -> Void)?
    
    // MARK: - Views
    
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let flowContainer = UIView()
    private var flowHeightConstraint: NSLayoutConstraint?
    
    private var pillButtons: [UIButton] = []
    private var activeIndex: Int = -1
    
    private let pillHeight: CGFloat = 36
    private let pillSpacingH: CGFloat = 10
    private let pillSpacingV: CGFloat = 10
    
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
        titleLabel.text = "STYLES"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = UIColor(white: 1.0, alpha: 0.88)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        
        // Vertical scroll view for wrapping pills
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)
        
        // Flow container — pills are manually positioned inside
        flowContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(flowContainer)
        
        let heightC = flowContainer.heightAnchor.constraint(equalToConstant: 0)
        flowHeightConstraint = heightC
        
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
            backButton.heightAnchor.constraint(equalToConstant: 32),
            
            titleLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            scrollView.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            flowContainer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            flowContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            flowContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            flowContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            flowContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            heightC,
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPills()
    }
    
    // MARK: - Public
    
    func configure(lutNames: [String], activeIndex: Int) {
        self.activeIndex = activeIndex
        
        // Clear existing pills
        pillButtons.forEach { $0.removeFromSuperview() }
        pillButtons.removeAll()
        
        // "NONE" pill first
        let names = ["NONE"] + lutNames
        
        for (index, name) in names.enumerated() {
            let pill = makePill(title: name.uppercased(), tag: index - 1) // -1 = none, 0+ = lut index
            let isActive = (index == 0 && activeIndex == -1) || (index > 0 && index - 1 == activeIndex)
            stylePill(pill, active: isActive)
            flowContainer.addSubview(pill)
            pillButtons.append(pill)
        }
        
        // On first launch the entire parent chain may not have resolved layout yet.
        // Force the topmost ancestor to resolve so our flowContainer gets a real width.
        superview?.layoutIfNeeded()
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    // MARK: - Flow Layout
    
    private func layoutPills() {
        // Prefer flowContainer's resolved width; fall back to scrollView or self
        var containerWidth = flowContainer.bounds.width
        if containerWidth <= 0 { containerWidth = scrollView.bounds.width }
        if containerWidth <= 0 { containerWidth = bounds.width }
        guard containerWidth > 0, !pillButtons.isEmpty else { return }
        
        var x: CGFloat = 0
        var y: CGFloat = 0
        
        for pill in pillButtons {
            let size = pill.intrinsicContentSize
            let pillWidth = max(60, size.width)
            
            // Wrap to next line if this pill doesn't fit
            if x + pillWidth > containerWidth && x > 0 {
                x = 0
                y += pillHeight + pillSpacingV
            }
            
            pill.frame = CGRect(x: x, y: y, width: pillWidth, height: pillHeight)
            x += pillWidth + pillSpacingH
        }
        
        let totalHeight = y + pillHeight
        flowHeightConstraint?.constant = totalHeight
    }
    
    // MARK: - Pill Factory
    
    private func makePill(title: String, tag: Int) -> UIButton {
        let pill = UIButton(type: .system)
        pill.setTitle(title, for: .normal)
        pill.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        pill.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        pill.layer.cornerRadius = 18
        pill.clipsToBounds = true
        pill.tag = tag
        pill.addTarget(self, action: #selector(pillTapped(_:)), for: .touchUpInside)
        return pill
    }
    
    private func stylePill(_ pill: UIButton, active: Bool) {
        if active {
            pill.backgroundColor = .systemYellow
            pill.setTitleColor(.black, for: .normal)
        } else {
            pill.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
            pill.setTitleColor(.white, for: .normal)
        }
    }
    
    // MARK: - Actions
    
    @objc private func backTapped() { onBack?() }
    
    @objc private func pillTapped(_ sender: UIButton) {
        let lutIndex = sender.tag  // -1 = none, 0+ = lut index
        activeIndex = lutIndex
        
        // Update all pill styles
        for pill in pillButtons {
            let isActive = (pill.tag == -1 && lutIndex == -1) || (pill.tag == lutIndex && lutIndex != -1)
            stylePill(pill, active: isActive)
        }
        
        onLutSelected?(lutIndex)
    }
}
