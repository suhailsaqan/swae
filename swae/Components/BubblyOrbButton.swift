//
//  BubblyOrbButton.swift
//  swae
//
//  Bubbly orb button for camera tab (temporary replacement for particle ring)
//

import UIKit

// Button that contains bubbly orb and forwards touches
class CameraButtonWithBubblyOrb: UIButton {
    private let orbView: BubblyOrbView
    
    override init(frame: CGRect) {
        orbView = BubblyOrbView(frame: .zero, device: nil)
        super.init(frame: frame)
        setup()
    }
    
    convenience init() {
        self.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        orbView = BubblyOrbView(frame: .zero, device: nil)
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        
        orbView.translatesAutoresizingMaskIntoConstraints = false
        orbView.isUserInteractionEnabled = false
        orbView.clipsToBounds = false
        addSubview(orbView)
        
        // Make the view much larger than the orb so deformation has room to extend
        // The orb itself will be smaller (controlled by shader), but the canvas is big
        NSLayoutConstraint.activate([
            orbView.centerXAnchor.constraint(equalTo: centerXAnchor),
            orbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            orbView.widthAnchor.constraint(equalToConstant: 120),
            orbView.heightAnchor.constraint(equalToConstant: 120)
        ])
    }
    
    // Forward touches to orb view for deformation effect
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesBegan(touches, with: event)
        sendActions(for: .touchDown)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesEnded(touches, with: event)
        
        if let touch = touches.first {
            let location = touch.location(in: self)
            if bounds.contains(location) {
                sendActions(for: .touchUpInside)
            } else {
                sendActions(for: .touchUpOutside)
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbView.touchesCancelled(touches, with: event)
        sendActions(for: .touchCancel)
    }
    
    /// Trigger the birth animation (call after splash screen disappears)
    func triggerBirthAnimation() {
        orbView.triggerBirthAnimation()
    }
}
