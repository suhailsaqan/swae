import UIKit

// MARK: - GlassContainerView
/// A wrapper view that provides a consistent interface for adding content
/// to both UIGlassEffect (iOS 26+) and fallback blur views.
class GlassContainerView: UIView {
    private(set) var effectView: UIVisualEffectView!
    
    /// The view where you should add your content subviews
    var glassContentView: UIView {
        return effectView.contentView
    }
    
    @available(iOS 26.0, *)
    init(glassCornerRadius: CGFloat) {
        super.init(frame: .zero)
        setupGlassEffect(cornerRadius: glassCornerRadius)
    }
    
    init(fallbackCornerRadius: CGFloat) {
        super.init(frame: .zero)
        setupFallbackEffect(cornerRadius: fallbackCornerRadius)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @available(iOS 26.0, *)
    private func setupGlassEffect(cornerRadius: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        
        // Create UIGlassEffect using the class method with style
        // Available styles may include .regular, .clear, etc.
        let glassEffect = UIGlassEffect()
        
        // Enable interactive behavior for the glass effect
        glassEffect.isInteractive = true
        
        effectView = UIVisualEffectView(effect: glassEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.backgroundColor = .clear
        
        // Apply corner radius
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func setupFallbackEffect(cornerRadius: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        
        // Fallback: Use adaptive blur effect that works in both light and dark mode
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        
        effectView = UIVisualEffectView(effect: blurEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Tint overlay for depth (adapts to light/dark mode)
        let tint = UIView()
        tint.backgroundColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(white: 0.1, alpha: 0.3)
            } else {
                return UIColor(white: 0.5, alpha: 0.08)
            }
        }
        tint.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
            tint.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            tint.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor)
        ])
        
        // Subtle border (adapts to light/dark mode)
        effectView.layer.borderWidth = 0.5
        effectView.layer.borderColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(white: 1.0, alpha: 0.15)
            } else {
                return UIColor(white: 0.0, alpha: 0.08)
            }
        }.cgColor
        
        // Inner shadow for depth
        let innerShadow = CAShapeLayer()
        innerShadow.fillRule = .evenOdd
        innerShadow.shadowColor = UIColor(white: 0, alpha: 0.4).cgColor
        innerShadow.shadowOffset = CGSize(width: 0, height: 2)
        innerShadow.shadowRadius = 8
        innerShadow.shadowOpacity = 1.0
        layer.addSublayer(innerShadow)
        
        layoutSubviewsHandler = { [weak self] in
            guard let self = self else { return }
            let bigger = UIBezierPath(roundedRect: self.bounds.insetBy(dx: -50, dy: -50), cornerRadius: cornerRadius + 50)
            let inner = UIBezierPath(roundedRect: self.bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius)
            bigger.append(inner.reversing())
            innerShadow.path = bigger.cgPath
            innerShadow.frame = self.bounds
        }
    }
}

// MARK: - Corner Radius Animation Support
extension GlassContainerView {
    /// Updates the corner radius for animation
    /// Must update both container and internal effectView for proper rendering
    func updateCornerRadius(_ radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        effectView.layer.cornerRadius = radius
        effectView.layer.cornerCurve = .continuous
    }
    
    /// Removes border and inner shadow styling (for full-screen overlays)
    /// Call this after creating a glass view that should have no visible edges
    func removeEdgeStyling() {
        // Remove border
        effectView.layer.borderWidth = 0
        effectView.layer.borderColor = nil
        
        // Remove inner shadow sublayer (added in fallback mode)
        layer.sublayers?.forEach { sublayer in
            if sublayer is CAShapeLayer {
                sublayer.removeFromSuperlayer()
            }
        }
        
        // Clear the layoutSubviewsHandler that updates inner shadow
        layoutSubviewsHandler = nil
    }
}

// MARK: - GlassFactory
/// Returns a GlassContainerView that renders the Liquid Glass material on iOS 26+
/// and an app-store-safe fallback on earlier OS versions.
/// Usage: add your content to the returned view's `glassContentView` property.
enum GlassFactory {
    /// Create a glass container view with the requested corner radius.
    static func makeGlassView(cornerRadius: CGFloat) -> GlassContainerView {
        if #available(iOS 26.0, *) {
            return GlassContainerView(glassCornerRadius: cornerRadius)
        } else {
            return GlassContainerView(fallbackCornerRadius: cornerRadius)
        }
    }
}
