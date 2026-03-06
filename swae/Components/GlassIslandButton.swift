//
//  GlassIslandButton.swift
//  swae
//
//  Frosted glass navigation button that floats above the liquid pool
//

import UIKit

class GlassIslandButton: UIButton {
    
    // MARK: - Properties
    
    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let view = UIVisualEffectView(effect: blur)
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabelView: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    // Floating animation
    private var floatAnimator: UIViewPropertyAnimator?
    private var isFloating: Bool = false
    
    // Ripple callback
    var onTapWithPosition: ((CGPoint) -> Void)?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    convenience init(icon: String, title: String) {
        self.init(frame: .zero)
        configure(icon: icon, title: title)
    }
    
    // MARK: - Setup
    
    private func setup() {
        // Add blur background
        insertSubview(blurView, at: 0)
        
        // Add content stack
        addSubview(contentStack)
        contentStack.addArrangedSubview(iconImageView)
        contentStack.addArrangedSubview(titleLabelView)
        
        // Constraints
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),
        ])
        
        // Styling
        layer.cornerRadius = 14
        layer.masksToBounds = true
        
        // Subtle border
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        
        // Shadow for floating effect
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3
        layer.masksToBounds = false
        
        // Clip blur view
        blurView.layer.cornerRadius = 14
        blurView.clipsToBounds = true
    }
    
    // MARK: - Configuration
    
    func configure(icon: String, title: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        iconImageView.image = UIImage(systemName: icon, withConfiguration: config)
        titleLabelView.text = title
        
        // Accessibility
        accessibilityLabel = title
        accessibilityHint = "Double tap to open \(title)"
        accessibilityTraits = .button
    }
    
    // MARK: - Floating Animation
    
    func startFloating() {
        guard !isFloating else { return }
        isFloating = true
        
        // Subtle up/down bob
        animateFloat()
    }
    
    func stopFloating() {
        isFloating = false
        floatAnimator?.stopAnimation(true)
        
        UIView.animate(withDuration: 0.3) {
            self.transform = .identity
        }
    }
    
    private func animateFloat() {
        guard isFloating else { return }
        
        // Random slight offset for organic feel
        let yOffset = CGFloat.random(in: 2...4)
        let duration = Double.random(in: 2.0...2.5)
        
        floatAnimator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut) {
            self.transform = CGAffineTransform(translationX: 0, y: -yOffset)
        }
        
        floatAnimator?.addCompletion { [weak self] _ in
            guard let self = self, self.isFloating else { return }
            
            self.floatAnimator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut) {
                self.transform = .identity
            }
            
            self.floatAnimator?.addCompletion { [weak self] _ in
                self?.animateFloat()
            }
            
            self.floatAnimator?.startAnimation()
        }
        
        floatAnimator?.startAnimation()
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        // Press down effect - sink into liquid
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                .translatedBy(x: 0, y: 2)
            self.layer.shadowOffset = CGSize(width: 0, height: 2)
            self.layer.shadowOpacity = 0.2
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        // Get touch position for ripple
        if let touch = touches.first {
            let position = touch.location(in: superview)
            onTapWithPosition?(position)
        }
        
        // Spring back up
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            if self.isFloating {
                // Return to floating state
            } else {
                self.transform = .identity
            }
            self.layer.shadowOffset = CGSize(width: 0, height: 4)
            self.layer.shadowOpacity = 0.3
        }
        
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        UIView.animate(withDuration: 0.2) {
            self.transform = .identity
            self.layer.shadowOffset = CGSize(width: 0, height: 4)
            self.layer.shadowOpacity = 0.3
        }
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update shadow path for performance
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 14).cgPath
    }
}

// MARK: - SwiftUI Wrapper

import SwiftUI

struct GlassIslandButtonView: UIViewRepresentable {
    let icon: String
    let title: String
    let action: () -> Void
    
    func makeUIView(context: Context) -> GlassIslandButton {
        let button = GlassIslandButton(icon: icon, title: title)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.startFloating()
        return button
    }
    
    func updateUIView(_ uiView: GlassIslandButton, context: Context) {
        uiView.configure(icon: icon, title: title)
    }
}

// MARK: - Preview

#if DEBUG
struct GlassIslandButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            HStack(spacing: 12) {
                GlassIslandButtonView(icon: "dot.radiowaves.left.and.right", title: "Streams") {}
                    .frame(width: 100, height: 60)
                
                GlassIslandButtonView(icon: "square.grid.3x3.fill", title: "Widgets") {}
                    .frame(width: 100, height: 60)
                
                GlassIslandButtonView(icon: "gearshape.fill", title: "More") {}
                    .frame(width: 100, height: 60)
            }
            .padding()
        }
    }
}
#endif
