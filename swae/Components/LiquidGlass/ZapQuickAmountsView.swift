//
//  ZapQuickAmountsView.swift
//  swae
//
//  Grid of preset zap amounts plus custom button
//

import UIKit

class ZapQuickAmountsView: UIView {
    
    // MARK: - Layout Constants
    private let buttonHeight: CGFloat = 56
    private let buttonSpacing: CGFloat = 12
    private let gridToCustomSpacing: CGFloat = 16
    private let customButtonHeight: CGFloat = 44
    private let customToConfirmSpacing: CGFloat = 12
    private let confirmButtonHeight: CGFloat = 50
    
    // MARK: - Data
    private let presetAmounts: [Int64] = [21, 100, 500, 1000, 5000, 10000]
    
    // MARK: - Views
    private var amountButtons: [ZapAmountButton] = []
    private let customButton = UIButton()
    private let confirmButton = UIButton()
    private var grid: UIStackView!
    
    // MARK: - Callbacks
    var onAmountSelected: ((Int64) -> Void)?
    var onCustomTapped: (() -> Void)?
    var onConfirmTapped: (() -> Void)?
    
    // MARK: - State
    private var selectedIndex: Int? {
        didSet { updateSelection() }
    }
    
    // MARK: - Public: Required Height
    /// The exact height this view needs. Parent should use this to size the modal.
    var requiredHeight: CGFloat {
        let gridHeight = (buttonHeight * 2) + buttonSpacing  // 2 rows + 1 gap
        return gridHeight + gridToCustomSpacing + customButtonHeight + customToConfirmSpacing + confirmButtonHeight
    }
    
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
        translatesAutoresizingMaskIntoConstraints = false
        
        setupGrid()
        setupCustomButton()
        setupConfirmButton()
        setupConstraints()
    }

    
    private func setupGrid() {
        grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = buttonSpacing
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        
        for row in 0..<2 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = buttonSpacing
            rowStack.distribution = .fillEqually
            // Lower compression resistance so stack can shrink during morph animation
            rowStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            
            for col in 0..<3 {
                let index = row * 3 + col
                let amount = presetAmounts[index]
                let button = ZapAmountButton(amount: amount)
                button.tag = index
                button.addTarget(self, action: #selector(amountTapped(_:)), for: .touchUpInside)
                button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
                // Lower button compression resistance to avoid constraint conflicts during animation
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                amountButtons.append(button)
                rowStack.addArrangedSubview(button)
            }
            
            grid.addArrangedSubview(rowStack)
        }
    }
    
    private func setupCustomButton() {
        customButton.setTitle("Custom Amount", for: .normal)
        customButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        customButton.setTitleColor(.label, for: .normal)  // Adapts to light/dark mode
        customButton.backgroundColor = UIColor(white: 0.3, alpha: 0.5)
        customButton.layer.cornerRadius = 12
        customButton.translatesAutoresizingMaskIntoConstraints = false
        customButton.addTarget(self, action: #selector(customTapped), for: .touchUpInside)
        addSubview(customButton)
    }
    
    private func setupConfirmButton() {
        confirmButton.setTitle("Add Zap", for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .disabled)
        confirmButton.backgroundColor = UIColor(white: 0.3, alpha: 0.5)
        confirmButton.layer.cornerRadius = 16
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmButton.isEnabled = false
        addSubview(confirmButton)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Grid at top
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            // Custom button below grid
            customButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: gridToCustomSpacing),
            customButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            customButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            customButton.heightAnchor.constraint(equalToConstant: customButtonHeight),
            
            // Confirm button below custom
            confirmButton.topAnchor.constraint(equalTo: customButton.bottomAnchor, constant: customToConfirmSpacing),
            confirmButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            confirmButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            confirmButton.heightAnchor.constraint(equalToConstant: confirmButtonHeight),
            // NO BOTTOM CONSTRAINT - parent will size based on requiredHeight
        ])
    }

    
    // MARK: - Actions
    
    @objc private func amountTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        let amount = presetAmounts[sender.tag] * 1000  // Convert to millisats
        onAmountSelected?(amount)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    @objc private func customTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCustomTapped?()
    }
    
    @objc private func confirmTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onConfirmTapped?()
    }
    
    private func updateSelection() {
        for (index, button) in amountButtons.enumerated() {
            button.isSelected = (index == selectedIndex)
        }
    }
    
    // MARK: - Public Methods
    
    func setConfirmEnabled(_ enabled: Bool) {
        confirmButton.isEnabled = enabled
        UIView.animate(withDuration: 0.2) {
            self.confirmButton.backgroundColor = enabled ? .systemOrange : UIColor(white: 0.3, alpha: 0.5)
        }
    }

    func setConfirmTitle(_ title: String) {
        confirmButton.setTitle(title, for: .normal)
    }
    
    func clearSelection() {
        selectedIndex = nil
    }
    
    /// Pre-select an amount (for edit mode)
    func selectAmount(_ millisats: Int64) {
        let sats = millisats / 1000
        if let index = presetAmounts.firstIndex(of: sats) {
            selectedIndex = index
            setConfirmEnabled(true)
        }
    }
}
