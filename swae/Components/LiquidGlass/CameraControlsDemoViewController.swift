import UIKit

// MARK: - Demo ViewController to preview MorphingOrbModal
class MorphingOrbModalDemoViewController: UIViewController {
    private let morphingModal = MorphingOrbModal()
    private var isLiveActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize layout swizzling
        initializeLayoutSwizzling()
        
        view.backgroundColor = .black

        // Gradient background to simulate camera preview
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0).cgColor,
            UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0).cgColor
        ]
        gradientLayer.frame = view.bounds
        view.layer.insertSublayer(gradientLayer, at: 0)

        // Add morphing modal
        view.addSubview(morphingModal)
        NSLayoutConstraint.activate([
            morphingModal.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            morphingModal.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            morphingModal.heightAnchor.constraint(equalToConstant: 500),
            morphingModal.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Wire up demo callbacks
        morphingModal.onShutterTapped = {
            print("Shutter tapped!")
        }
        
        morphingModal.onFlashTapped = {
            print("Flash tapped!")
        }
        
        morphingModal.onLiveTapped = { [weak self] in
            print("Live tapped!")
            // Toggle live state for demo
            self?.isLiveActive.toggle()
            self?.morphingModal.setLiveActive(self?.isLiveActive ?? false)
        }

        // Entry animation
        morphingModal.transform = CGAffineTransform(translationX: 0, y: 30)
        morphingModal.alpha = 0
        UIView.animate(withDuration: 0.45, delay: 0.1, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.9, options: [.curveEaseOut]) {
            self.morphingModal.transform = .identity
            self.morphingModal.alpha = 1.0
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update gradient frame
        if let gradientLayer = view.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = view.bounds
        }
    }
}

// Legacy alias
typealias LiquidGlassControlPanelDemoViewController = MorphingOrbModalDemoViewController
