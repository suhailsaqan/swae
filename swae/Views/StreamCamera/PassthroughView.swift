import UIKit

/// A UIView that passes through touches when no subview claims them.
/// Used for overlay containers that should be transparent to touch
/// except where interactive content exists (e.g. status icon taps, interactive chat).
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        // If hitTest resolved to self (no subview claimed it), return nil
        // to let the touch pass through to views behind us
        return hitView == self ? nil : hitView
    }
}
