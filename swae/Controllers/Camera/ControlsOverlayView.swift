//
//  ControlsOverlayView.swift
//  swae
//
//  Overlay view showing control buttons when Go Live orb is expanded
//

import UIKit

// MARK: - Modal Control Type

enum ModalControlType {
    case widget
    case lut
    case mute
    case scene
    case obs
    case streams
}

// MARK: - ControlsOverlayView

class ControlsOverlayView: UIView {
    
    // MARK: - Properties
    
    private var controlButtons: [ControlOrbButton] = []
    
    private let controls: [(icon: String, title: String, type: ModalControlType)] = [
        ("square.grid.3x3", "Widget", .widget),
        ("camera.filters", "LUT", .lut),
        ("speaker.slash.fill", "Mute", .mute),
        ("photo.on.rectangle", "Scene", .scene),
        ("video.fill", "OBS", .obs),
        ("dot.radiowaves.left.and.right", "Streams", .streams),
    ]
    
    var onControlTapped: ((ModalControlType) -> Void)?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        
        for (index, control) in controls.enumerated() {
            let button = ControlOrbButton()
            button.configure(icon: control.icon, title: control.title)
            button.tag = index
            button.addTarget(self, action: #selector(controlTapped(_:)), for: .touchUpInside)
            addSubview(button)
            controlButtons.append(button)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutControls()
    }
    
    private func layoutControls() {
        let columns = 3
        let rows = 2
        let buttonSize: CGFloat = 70
        let horizontalSpacing: CGFloat = 20
        let verticalSpacing: CGFloat = 16
        
        let totalWidth = CGFloat(columns) * buttonSize + CGFloat(columns - 1) * horizontalSpacing
        let totalHeight = CGFloat(rows) * buttonSize + CGFloat(rows - 1) * verticalSpacing
        
        let startX = (bounds.width - totalWidth) / 2
        let startY = (bounds.height - totalHeight) / 2
        
        for (index, button) in controlButtons.enumerated() {
            let col = index % columns
            let row = index / columns
            
            let x = startX + CGFloat(col) * (buttonSize + horizontalSpacing)
            let y = startY + CGFloat(row) * (buttonSize + verticalSpacing)
            
            button.frame = CGRect(x: x, y: y, width: buttonSize, height: buttonSize)
        }
    }
    
    // MARK: - Animation
    
    func show(animated: Bool = true) {
        guard animated else {
            alpha = 1
            controlButtons.forEach { $0.alpha = 1 }
            return
        }
        
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }
        
        for (index, button) in controlButtons.enumerated() {
            let delay = 0.05 * Double(index)
            
            button.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                .translatedBy(x: 0, y: 20)
            button.alpha = 0
            
            UIView.animate(
                withDuration: 0.4,
                delay: delay,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0.5
            ) {
                button.alpha = 1
                button.transform = .identity
            }
        }
    }
    
    func hide(animated: Bool = true) {
        guard animated else {
            alpha = 0
            controlButtons.forEach { $0.alpha = 0 }
            return
        }
        
        for (index, button) in controlButtons.reversed().enumerated() {
            let delay = 0.03 * Double(index)
            
            UIView.animate(
                withDuration: 0.25,
                delay: delay,
                options: .curveEaseIn
            ) {
                button.alpha = 0
                button.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    .translatedBy(x: 0, y: 10)
            }
        }
        
        UIView.animate(withDuration: 0.2, delay: 0.15) {
            self.alpha = 0
        }
    }
    
    @objc private func controlTapped(_ sender: UIButton) {
        let control = controls[sender.tag]
        onControlTapped?(control.type)
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    func updateControlState(_ type: ModalControlType, isOn: Bool) {
        guard let index = controls.firstIndex(where: { $0.type == type }) else { return }
        controlButtons[index].setOn(isOn)
    }
}

// MARK: - ControlOrbButton

class ControlOrbButton: UIControl {
    
    // MARK: - Subviews
    
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let backgroundView = UIView()
    
    private var isOn: Bool = false
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Background
        backgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        backgroundView.layer.cornerRadius = 20
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)
        
        // Icon
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        addSubview(iconView)
        
        // Title
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .white.withAlphaComponent(0.8)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let iconSize: CGFloat = 24
        
        backgroundView.frame = CGRect(
            x: (bounds.width - 50) / 2,
            y: 0,
            width: 50,
            height: 50
        )
        
        iconView.frame = CGRect(
            x: (bounds.width - iconSize) / 2,
            y: (50 - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        
        titleLabel.frame = CGRect(
            x: 0,
            y: 50 + 4,
            width: bounds.width,
            height: 16
        )
    }
    
    // MARK: - Configuration
    
    func configure(icon: String, title: String) {
        iconView.image = UIImage(systemName: icon)
        titleLabel.text = title
    }
    
    func setOn(_ on: Bool) {
        isOn = on
        UIView.animate(withDuration: 0.2) {
            self.backgroundView.backgroundColor = on
                ? UIColor.white.withAlphaComponent(0.35)
                : UIColor.white.withAlphaComponent(0.15)
            self.iconView.tintColor = on ? .white : .white.withAlphaComponent(0.8)
        }
    }
    
    // MARK: - Touch Feedback
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.95, y: 0.95)
                    : .identity
                self.backgroundView.backgroundColor = self.isHighlighted
                    ? UIColor.white.withAlphaComponent(0.25)
                    : (self.isOn ? UIColor.white.withAlphaComponent(0.35) : UIColor.white.withAlphaComponent(0.15))
            }
        }
    }
}
