//
//  ZapNumberPadView.swift
//  swae
//
//  Custom number pad for entering zap amounts
//

import UIKit

class ZapNumberPadView: UIView {
    
    // MARK: - Layout Constants
    private let backButtonHeight: CGFloat = 44
    private let backButtonToGridSpacing: CGFloat = 8
    private let gridRowHeight: CGFloat = 52  // Increased from ~49 for better touch targets
    private let gridRowSpacing: CGFloat = 8
    private let gridToConfirmSpacing: CGFloat = 16
    private let confirmButtonHeight: CGFloat = 50
    
    // MARK: - Callbacks
    var onDigitTapped: ((Int) -> Void)?
    var onBackspaceTapped: (() -> Void)?
    var onConfirmTapped: (() -> Void)?
    var onBackTapped: (() -> Void)?
    
    // MARK: - Views
    private let confirmButton = UIButton()
    private let backButton = UIButton()
    private var digitButtons: [UIButton] = []
    private var grid: UIStackView!
    
    // MARK: - Public: Required Height
    /// The exact height this view needs. Parent should use this to size the modal.
    var requiredHeight: CGFloat {
        let gridHeight = (gridRowHeight * 4) + (gridRowSpacing * 3)
        return backButtonHeight + backButtonToGridSpacing + gridHeight + gridToConfirmSpacing + confirmButtonHeight
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
        
        setupBackButton()
        setupGrid()
        setupConfirmButton()
        setupConstraints()
    }

    
    private func setupBackButton() {
        backButton.setImage(
            UIImage(systemName: "chevron.left",
                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)),
            for: .normal
        )
        backButton.tintColor = .white
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        addSubview(backButton)
    }
    
    private func setupGrid() {
        grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = gridRowSpacing
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        
        let buttons = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"]
        ]
        
        for row in buttons {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = gridRowSpacing
            rowStack.distribution = .fillEqually
            // Lower compression resistance so stack can shrink during morph animation
            rowStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            
            for label in row {
                let button = createNumberButton(label)
                // Lower button compression resistance to avoid constraint conflicts during animation
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                digitButtons.append(button)
                rowStack.addArrangedSubview(button)
            }
            
            grid.addArrangedSubview(rowStack)
        }
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
        // Calculate grid height from row heights
        let gridHeight = (gridRowHeight * 4) + (gridRowSpacing * 3)
        
        NSLayoutConstraint.activate([
            // Back button - top left
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: backButtonHeight),
            
            // Grid - below back button
            grid.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: backButtonToGridSpacing),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.heightAnchor.constraint(equalToConstant: gridHeight),
            
            // Confirm button - below grid
            confirmButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: gridToConfirmSpacing),
            confirmButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            confirmButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            confirmButton.heightAnchor.constraint(equalToConstant: confirmButtonHeight),
            // NO BOTTOM CONSTRAINT - parent will size based on requiredHeight
        ])
    }

    
    private func createNumberButton(_ label: String) -> UIButton {
        let button = UIButton()
        
        if label == "⌫" {
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            button.setImage(UIImage(systemName: "delete.left", withConfiguration: config), for: .normal)
            button.tintColor = .white
            button.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        } else {
            button.setTitle(label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28, weight: .medium)
            button.setTitleColor(.white, for: .normal)
        }
        
        button.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
        button.layer.cornerRadius = 12
        
        if label.isEmpty {
            button.isUserInteractionEnabled = false
            button.backgroundColor = .clear
        } else if let digit = Int(label) {
            button.tag = digit
            button.addTarget(self, action: #selector(digitTapped(_:)), for: .touchUpInside)
        }
        
        // Add press animation
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        return button
    }
    
    // MARK: - Actions
    
    @objc private func buttonTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.05, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            sender.backgroundColor = UIColor(white: 0.3, alpha: 0.7)
        }
    }
    
    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            sender.transform = .identity
            sender.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
        }
    }
    
    @objc private func digitTapped(_ sender: UIButton) {
        onDigitTapped?(sender.tag)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    @objc private func backspaceTapped() {
        onBackspaceTapped?()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    @objc private func confirmTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onConfirmTapped?()
    }
    
    @objc private func backTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onBackTapped?()
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
}
