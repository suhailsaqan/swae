import UIKit

/// Native UIKit focus indicator that shows a yellow square at the tap-to-focus location.
/// Matches the legacy SwiftUI `StreamOverlayTapGridView` appearance (70pt yellow rounded rect).
class FocusIndicatorView: UIView {
    private let squareLayer = CAShapeLayer()
    private let sideLength: CGFloat = 70

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isHidden = true

        squareLayer.fillColor = UIColor.clear.cgColor
        squareLayer.strokeColor = UIColor.yellow.cgColor
        squareLayer.lineWidth = 1.5
        layer.addSublayer(squareLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the focus indicator at the given normalized point (0...1) within the container.
    func show(at normalizedPoint: CGPoint, in containerSize: CGSize) {
        let centerX = containerSize.width * normalizedPoint.x
        let centerY = containerSize.height * normalizedPoint.y
        let rect = CGRect(
            x: centerX - sideLength / 2,
            y: centerY - sideLength / 2,
            width: sideLength,
            height: sideLength
        )
        squareLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 2).cgPath

        isHidden = false
        alpha = 1
        transform = CGAffineTransform(scaleX: 1.2, y: 1.2)

        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut) {
            self.transform = .identity
        }

        // Cancel any pending fade-out and schedule a new one
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(fadeOut), object: nil)
        perform(#selector(fadeOut), with: nil, afterDelay: 1.5)
    }

    @objc private func fadeOut() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
        }
    }

    func hide() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self, selector: #selector(fadeOut), object: nil)
        isHidden = true
        alpha = 0
    }
}
