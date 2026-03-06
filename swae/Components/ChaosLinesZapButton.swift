//
//  ChaosLinesZapButton.swift
//  swae
//
//  Zap button with chaos lines Metal effect
//

import UIKit
import MetalKit

class ChaosLinesZapButton: UIButton {
    private var metalView: ChaosLinesMetalView?
    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let image = UIImage(systemName: "bolt.fill", withConfiguration: config)
        iv.image = image
        iv.tintColor = .white
        iv.contentMode = .center
        iv.isUserInteractionEnabled = false
        return iv
    }()
    
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
        layer.cornerRadius = 18
        clipsToBounds = true
        
        // Add Metal view as background
        if let device = MTLCreateSystemDefaultDevice() {
            let metalView = ChaosLinesMetalView(frame: bounds, device: device)
            metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            metalView.isUserInteractionEnabled = false
            addSubview(metalView)
            self.metalView = metalView
        }
        
        // Add icon on top
        iconImageView.frame = bounds
        iconImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(iconImageView)
        
        // Add shadow
        layer.shadowColor = UIColor.systemYellow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6
        layer.shadowOpacity = 0.4
        
        // Handle tap
        addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        if let touch = touches.first {
            let location = touch.location(in: self)
            let normalizedX = Float(location.x / bounds.width)
            let normalizedY = Float(location.y / bounds.height)
            
            // Trigger the lightning effect at touch location
            metalView?.triggerTap(at: SIMD2<Float>(normalizedX, normalizedY))
        }
    }
    
    @objc private func buttonTapped() {
        // This is called by UIButton's target-action
        // The actual effect is triggered in touchesBegan
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        metalView?.frame = bounds
        iconImageView.frame = bounds
    }
}
