import SwiftUI
import UIKit

// MARK: - MorphingOrbModalWrapper
// SwiftUI wrapper for MorphingOrbModal (UIKit) to use in MainView

struct MorphingOrbModalWrapper: UIViewRepresentable {
    
    // Callbacks
    var onModeChanged: ((Bool) -> Void)?
    var onGalleryTapped: (() -> Void)?
    var onShutterTapped: (() -> Void)?
    var onFlashTapped: (() -> Void)?
    var onLiveTapped: (() -> Void)?
    var onTimerTapped: (() -> Void)?
    var onExposureTapped: (() -> Void)?
    var onStylesTapped: (() -> Void)?
    var onAspectTapped: (() -> Void)?
    var onNightModeTapped: (() -> Void)?
    
    func makeUIView(context: Context) -> UIView {
        // Initialize layout swizzling
        initializeLayoutSwizzling()
        
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = false
        
        let modal = MorphingOrbModal()
        modal.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(modal)
        
        // Wire up callbacks
        modal.onModeChanged = onModeChanged
        modal.onGalleryTapped = onGalleryTapped
        modal.onShutterTapped = onShutterTapped
        modal.onFlashTapped = onFlashTapped
        modal.onLiveTapped = onLiveTapped
        modal.onTimerTapped = onTimerTapped
        modal.onExposureTapped = onExposureTapped
        modal.onStylesTapped = onStylesTapped
        modal.onAspectTapped = onAspectTapped
        modal.onNightModeTapped = onNightModeTapped
        
        NSLayoutConstraint.activate([
            modal.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            modal.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            modal.topAnchor.constraint(equalTo: containerView.topAnchor),
            modal.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Entry animation
        modal.transform = CGAffineTransform(translationX: 0, y: 30)
        modal.alpha = 0
        UIView.animate(withDuration: 0.45, delay: 0.1, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.9, options: [.curveEaseOut]) {
            modal.transform = .identity
            modal.alpha = 1.0
        }
        
        context.coordinator.modal = modal
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update callbacks if they changed
        context.coordinator.modal?.onModeChanged = onModeChanged
        context.coordinator.modal?.onGalleryTapped = onGalleryTapped
        context.coordinator.modal?.onShutterTapped = onShutterTapped
        context.coordinator.modal?.onFlashTapped = onFlashTapped
        context.coordinator.modal?.onLiveTapped = onLiveTapped
        context.coordinator.modal?.onTimerTapped = onTimerTapped
        context.coordinator.modal?.onExposureTapped = onExposureTapped
        context.coordinator.modal?.onStylesTapped = onStylesTapped
        context.coordinator.modal?.onAspectTapped = onAspectTapped
        context.coordinator.modal?.onNightModeTapped = onNightModeTapped
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var modal: MorphingOrbModal?
    }
}

// MARK: - Legacy Alias
// Keep old name for backward compatibility during transition
typealias LiquidGlassControlPanelWrapper = MorphingOrbModalWrapper

// MARK: - Preview

#if DEBUG
struct MorphingOrbModalWrapper_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Simulated camera preview
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                MorphingOrbModalWrapper()
                    .frame(height: 500)
            }
        }
    }
}
#endif
