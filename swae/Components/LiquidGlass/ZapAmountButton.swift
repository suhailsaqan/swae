//
//  ZapAmountButton.swift
//  swae
//
//  Individual amount button for the zap quick amounts grid
//

import UIKit

class ZapAmountButton: UIButton {
    
    let amount: Int64  // In sats
    
    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.05, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }
    
    init(amount: Int64) {
        self.amount = amount
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        // Format amount
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        
        setTitle(formatted, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        layer.cornerRadius = 12
        
        updateAppearance()
    }
    
    private func updateAppearance() {
        if isSelected {
            backgroundColor = .systemOrange
            setTitleColor(.white, for: .normal)  // White on orange is correct
        } else {
            backgroundColor = UIColor(white: 0.2, alpha: 0.5)
            setTitleColor(.label, for: .normal)  // Adapts to light/dark mode
        }
    }
}
