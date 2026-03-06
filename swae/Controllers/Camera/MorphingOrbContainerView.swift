//
//  MorphingOrbContainerView.swift
//  swae
//
//  Full-screen container for the morphing Go Live orb
//  Manages the Metal view, controls overlay, and hit testing
//

import MetalKit
import UIKit

class MorphingOrbContainerView: UIView {
    
    // MARK: - Subviews
    
    private(set) var orbView: MorphingGoLiveOrbView!
    private(set) var controlsOverlay: ControlsOverlayView!
    private var dimOverlay: UIView!
    
    // MARK: - State
    
    private(set) var morphProgress: Float = 0.0
    private(set) var isExpanded: Bool = false
    
    // MARK: - Layout Constants
    
    private let controlBarHeight: CGFloat = 120
    private let orbDiameter: CGFloat = 70
    private let modalMaxWidth: CGFloat = 300
    private let modalHeight: CGFloat = 280
    private let modalHorizontalPadding: CGFloat = 32  // Minimum padding on each side
    
    // MARK: - Callbacks
    
    var onTap: (() -> Void)?
    var onExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onControlTapped: ((ModalControlType) -> Void)?
    var onStreamAction: (() -> Void)?
    var onStopStream: (() -> Void)?
    var isStreamConfigured: (() -> Bool)?
    var openSetup: (() -> Void)?
    
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
        clipsToBounds = false
        
        // Dim overlay (behind Metal view, for tap-to-dismiss)
        dimOverlay = UIView()
        dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.0)
        dimOverlay.isUserInteractionEnabled = true
        dimOverlay.alpha = 0
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDimTap))
        dimOverlay.addGestureRecognizer(tapGesture)
        addSubview(dimOverlay)
        
        // Metal orb view (full screen for proper morphing)
        orbView = MorphingGoLiveOrbView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        orbView.clipsToBounds = false
        orbView.onTap = { [weak self] in self?.handleOrbTap() }
        orbView.onSwipeUp = { [weak self] in self?.expand() }
        orbView.onMorphProgress = { [weak self] progress in self?.updateMorphProgress(progress) }
        addSubview(orbView)
        
        // Controls overlay (positioned at modal center)
        controlsOverlay = ControlsOverlayView()
        controlsOverlay.alpha = 0
        controlsOverlay.isUserInteractionEnabled = true
        controlsOverlay.onControlTapped = { [weak self] type in self?.onControlTapped?(type) }
        addSubview(controlsOverlay)
        
        // Swipe down gesture on controls overlay to collapse
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        controlsOverlay.addGestureRecognizer(swipeDown)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        dimOverlay.frame = bounds
        orbView.frame = bounds
        
        // Calculate actual modal width (clamped to screen width minus padding)
        let maxAllowedWidth = bounds.width - (modalHorizontalPadding * 2)
        let actualModalWidth = min(modalMaxWidth, maxAllowedWidth)
        
        // Modal is positioned at the very bottom of the screen
        let modalTopY = bounds.height - modalHeight
        
        // Position controls overlay to align with modal
        let controlsWidth: CGFloat = min(280, actualModalWidth - 20)
        let controlsHeight: CGFloat = 200
        let controlsY = modalTopY + (modalHeight - controlsHeight) / 2 - 20  // Slightly above center of modal
        controlsOverlay.frame = CGRect(
            x: (bounds.width - controlsWidth) / 2,
            y: controlsY,
            width: controlsWidth,
            height: controlsHeight
        )
        
        // Update orb view layout with screen dimensions
        orbView.updateLayoutForScreen(
            screenSize: bounds.size,
            controlBarHeight: controlBarHeight,
            orbDiameter: orbDiameter,
            modalSize: CGSize(width: actualModalWidth, height: modalHeight)
        )
    }
    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Calculate actual modal width (same as layoutSubviews)
        let maxAllowedWidth = bounds.width - (modalHorizontalPadding * 2)
        let actualModalWidth = min(modalMaxWidth, maxAllowedWidth)
        
        // Modal position at very bottom of screen
        let modalTopY = bounds.height - modalHeight
        
        // When expanded, handle taps on controls, modal area, or dim overlay
        if isExpanded {
            // Check if tap is on controls overlay
            let controlsPoint = controlsOverlay.convert(point, from: self)
            if controlsOverlay.bounds.contains(controlsPoint) {
                if let controlHit = controlsOverlay.hitTest(controlsPoint, with: event) {
                    return controlHit
                }
            }
            
            // Check if tap is on the modal area (bottom of screen)
            let modalRect = CGRect(
                x: (bounds.width - actualModalWidth) / 2,
                y: modalTopY,
                width: actualModalWidth,
                height: modalHeight
            )
            if modalRect.contains(point) {
                return orbView
            }
            
            // Tap outside modal = dismiss via dim overlay
            return dimOverlay
        }
        
        // When collapsed, only the orb area responds to touches
        let orbRect = orbHitRect()
        if orbRect.contains(point) {
            return orbView
        }
        
        // Pass through to views below (camera, etc.)
        return nil
    }
    
    private func orbHitRect() -> CGRect {
        let orbCenterY = bounds.height - controlBarHeight / 2
        let hitSize: CGFloat = orbDiameter + 30  // Larger hit area for easier tapping
        return CGRect(
            x: (bounds.width - hitSize) / 2,
            y: orbCenterY - hitSize / 2,
            width: hitSize,
            height: hitSize
        )
    }
    
    // MARK: - Orb Tap Handling
    
    private func handleOrbTap() {
        if isExpanded {
            // Tap on modal center = Go Live action
            onTap?()
        } else {
            // Tap on collapsed orb = Go Live action
            onTap?()
        }
    }
    
    // MARK: - Expansion
    
    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        onExpand?()
        
        orbView.expand()
        dimOverlay.alpha = 1
        
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5) {
            self.dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        }
        
        // Fade in controls with slight delay
        UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseOut) {
            self.controlsOverlay.alpha = 1
        }
    }
    
    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        onCollapse?()
        
        orbView.collapse()
        
        UIView.animate(withDuration: 0.25, animations: {
            self.dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.0)
            self.controlsOverlay.alpha = 0
        }, completion: { _ in
            self.dimOverlay.alpha = 0
        })
    }
    
    @objc private func handleDimTap() {
        collapse()
    }
    
    @objc private func handleSwipeDown() {
        collapse()
    }
    
    private func updateMorphProgress(_ progress: Float) {
        morphProgress = progress
        
        // Update dim overlay alpha based on morph progress
        if progress > 0 {
            dimOverlay.alpha = 1
            dimOverlay.backgroundColor = UIColor.black.withAlphaComponent(CGFloat(progress) * 0.4)
            controlsOverlay.alpha = CGFloat(progress)
        }
    }

    
    // MARK: - Public API
    
    func triggerBirthAnimation() {
        orbView.triggerBirthAnimation()
    }
    
    func setLiveState(_ live: Bool) {
        orbView.setLiveState(live)
    }
    
    func startCountdown() {
        orbView.startCountdown()
    }
    
    func cancelCountdown() {
        orbView.cancelCountdown()
    }
    
    var goLiveState: MorphingGoLiveState {
        return orbView.goLiveState
    }
    
    // MARK: - Configure Callbacks
    
    func configureCallbacks(
        onStreamAction: @escaping () -> Void,
        onStopStream: @escaping () -> Void,
        isStreamConfigured: @escaping () -> Bool,
        openSetup: @escaping () -> Void
    ) {
        self.onStreamAction = onStreamAction
        self.onStopStream = onStopStream
        self.isStreamConfigured = isStreamConfigured
        self.openSetup = openSetup
        
        orbView.onStreamAction = onStreamAction
        orbView.onStopStream = onStopStream
        orbView.isStreamConfigured = isStreamConfigured
        orbView.openSetup = openSetup
    }
}
