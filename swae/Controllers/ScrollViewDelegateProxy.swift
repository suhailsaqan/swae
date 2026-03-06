//
//  ScrollViewDelegateProxy.swift
//  swae
//
//  Proxy class that intercepts scroll view delegate calls to coordinate
//  scroll-to-navigation transitions in CameraContainerViewController.
//

import UIKit

/// Protocol for receiving scroll view events from the proxy.
/// Used by CameraContainerViewController to coordinate navigation with scroll behavior.
protocol ScrollViewDelegateProxyDelegate: AnyObject {
    /// Called when the scroll view scrolls.
    /// - Parameters:
    ///   - proxy: The proxy that sent the event
    ///   - scrollView: The scroll view that scrolled
    func scrollViewDelegateProxy(_ proxy: ScrollViewDelegateProxy, didScroll scrollView: UIScrollView)
    
    /// Called when the scroll view will begin dragging.
    /// - Parameters:
    ///   - proxy: The proxy that sent the event
    ///   - scrollView: The scroll view that will begin dragging
    func scrollViewDelegateProxy(_ proxy: ScrollViewDelegateProxy, willBeginDragging scrollView: UIScrollView)
    
    /// Called when the scroll view will end dragging.
    /// - Parameters:
    ///   - proxy: The proxy that sent the event
    ///   - scrollView: The scroll view that will end dragging
    ///   - velocity: The velocity of the drag
    ///   - targetContentOffset: The expected offset when scrolling decelerates to a stop
    func scrollViewDelegateProxy(
        _ proxy: ScrollViewDelegateProxy,
        willEndDragging scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    )
    
    /// Called when the scroll view did end dragging.
    /// - Parameters:
    ///   - proxy: The proxy that sent the event
    ///   - scrollView: The scroll view that ended dragging
    ///   - decelerate: Whether the scroll view will decelerate
    func scrollViewDelegateProxy(
        _ proxy: ScrollViewDelegateProxy,
        didEndDragging scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    )
    
    /// Called when the scroll view did end decelerating.
    /// - Parameters:
    ///   - proxy: The proxy that sent the event
    ///   - scrollView: The scroll view that ended decelerating
    func scrollViewDelegateProxy(_ proxy: ScrollViewDelegateProxy, didEndDecelerating scrollView: UIScrollView)
}

/// A proxy class that intercepts UIScrollViewDelegate calls to coordinate
/// scroll-to-navigation transitions without breaking existing scroll view functionality.
///
/// This class implements the delegate proxy pattern:
/// 1. Stores a weak reference to the original delegate
/// 2. Forwards all delegate calls to the original delegate
/// 3. Notifies the container of scroll events for navigation coordination
///
/// Requirements: 14.1, 14.4
class ScrollViewDelegateProxy: NSObject, UIScrollViewDelegate {
    
    // MARK: - Properties
    
    /// Weak reference to the original scroll view delegate.
    /// All delegate calls are forwarded to this delegate to preserve existing functionality.
    weak var originalDelegate: UIScrollViewDelegate?
    
    /// Weak reference to the container that receives scroll event notifications.
    weak var delegate: ScrollViewDelegateProxyDelegate?
    
    /// The scroll view this proxy is attached to.
    weak var scrollView: UIScrollView?
    
    /// Tracks whether the user is currently dragging the scroll view.
    private(set) var isDragging: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a new scroll view delegate proxy.
    /// - Parameters:
    ///   - scrollView: The scroll view to proxy
    ///   - delegate: The delegate to receive scroll event notifications
    init(scrollView: UIScrollView, delegate: ScrollViewDelegateProxyDelegate?) {
        self.scrollView = scrollView
        self.delegate = delegate
        self.originalDelegate = scrollView.delegate
        super.init()
        
        // Install ourselves as the delegate
        scrollView.delegate = self
    }
    
    /// Removes the proxy and restores the original delegate.
    func uninstall() {
        scrollView?.delegate = originalDelegate
        scrollView = nil
        originalDelegate = nil
        delegate = nil
    }
    
    // MARK: - UIScrollViewDelegate - Scroll Events
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Forward to original delegate
        originalDelegate?.scrollViewDidScroll?(scrollView)
        
        // Notify container
        delegate?.scrollViewDelegateProxy(self, didScroll: scrollView)
    }
    
    // MARK: - UIScrollViewDelegate - Drag Events
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isDragging = true
        
        // Forward to original delegate
        originalDelegate?.scrollViewWillBeginDragging?(scrollView)
        
        // Notify container
        delegate?.scrollViewDelegateProxy(self, willBeginDragging: scrollView)
    }
    
    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        // Forward to original delegate
        originalDelegate?.scrollViewWillEndDragging?(
            scrollView,
            withVelocity: velocity,
            targetContentOffset: targetContentOffset
        )
        
        // Notify container
        delegate?.scrollViewDelegateProxy(
            self,
            willEndDragging: scrollView,
            withVelocity: velocity,
            targetContentOffset: targetContentOffset
        )
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        isDragging = false
        
        // Forward to original delegate
        originalDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
        
        // Notify container
        delegate?.scrollViewDelegateProxy(self, didEndDragging: scrollView, willDecelerate: decelerate)
    }
    
    // MARK: - UIScrollViewDelegate - Deceleration Events
    
    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        // Forward to original delegate
        originalDelegate?.scrollViewWillBeginDecelerating?(scrollView)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Forward to original delegate
        originalDelegate?.scrollViewDidEndDecelerating?(scrollView)
        
        // Notify container
        delegate?.scrollViewDelegateProxy(self, didEndDecelerating: scrollView)
    }
    
    // MARK: - UIScrollViewDelegate - Scroll Animation Events
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // Forward to original delegate
        originalDelegate?.scrollViewDidEndScrollingAnimation?(scrollView)
    }
    
    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        // Forward to original delegate
        originalDelegate?.scrollViewDidScrollToTop?(scrollView)
    }
    
    // MARK: - UIScrollViewDelegate - Zoom Events
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return originalDelegate?.viewForZooming?(in: scrollView)
    }
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        originalDelegate?.scrollViewWillBeginZooming?(scrollView, with: view)
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        originalDelegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        originalDelegate?.scrollViewDidZoom?(scrollView)
    }
    
    // MARK: - UIScrollViewDelegate - Scroll Indicator Events
    
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        return originalDelegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
    }
    
    // MARK: - UIScrollViewDelegate - Content Inset Events
    
    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        originalDelegate?.scrollViewDidChangeAdjustedContentInset?(scrollView)
    }
}
