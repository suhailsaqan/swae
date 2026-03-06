import UIKit

// MARK: - UIView layout hook convenience
// Small utility to attach a layout handler to a UIView
private var layoutHandlerKey = "layoutHandlerKey"
extension UIView {
    typealias LayoutHandler = () -> Void
    var layoutSubviewsHandler: LayoutHandler? {
        get { return objc_getAssociatedObject(self, &layoutHandlerKey) as? LayoutHandler }
        set { objc_setAssociatedObject(self, &layoutHandlerKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
    // Swizzle layoutSubviews once to call handler if present
    static func swizzleLayoutIfNeeded() {
        struct Once { static var done = false }
        guard !Once.done else { return }
        Once.done = true
        let cls = UIView.self
        let orig = #selector(UIView.layoutSubviews)
        let new = #selector(UIView._lg_layoutSubviews)
        let origMethod = class_getInstanceMethod(cls, orig)!
        let newMethod = class_getInstanceMethod(cls, new)!
        method_exchangeImplementations(origMethod, newMethod)
    }
    @objc func _lg_layoutSubviews() {
        // calls original implementation due to swizzling
        self._lg_layoutSubviews()
        self.layoutSubviewsHandler?()
    }
}

// Initialize swizzling at load time
private let _swizzleOnce: Void = {
    UIView.swizzleLayoutIfNeeded()
}()

func initializeLayoutSwizzling() {
    _ = _swizzleOnce
}
