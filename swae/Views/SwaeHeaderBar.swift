//
//  SwaeHeaderBar.swift
//  swae
//
//  Instagram-style header bar with bare icon camera and search buttons (no glass)
//  Hides on scroll down, shows on scroll up, with subtle gradient shade when not over hero
//

import UIKit

final class SwaeHeaderBar: UIView {
    
    // MARK: - Search State
    enum SearchState {
        case collapsed
        case expanded
    }
    
    // MARK: - UI Components
    private let cameraButton = UIView()
    private let searchContainer = UIView()
    private let cameraIcon = UIImageView()
    private let searchIcon = UIImageView()
    private let searchTextField = UITextField()
    private let titleImageView = UIImageView()
    
    // Subtle gradient shade - shows when NOT over hero gradient for better button visibility
    private let shadeGradient = CAGradientLayer()
    
    // MARK: - Search State
    private(set) var searchState: SearchState = .collapsed
    
    // MARK: - Scroll State
    private var isHeaderHidden = false
    private var lastScrollOffset: CGFloat = 0
    private var accumulatedScrollDelta: CGFloat = 0
    private var lastScrollDirection: ScrollDirection = .none
    private var needsScrollResync = false
    
    /// When true, scroll-based hide/show is disabled (for search mode)
    var isScrollHideDisabled = false
    
    private enum ScrollDirection {
        case none, up, down
    }
    
    // Thresholds for hide/show behavior
    private let hideThreshold: CGFloat = 20   // Scroll down this much to start hiding
    private let showThreshold: CGFloat = 10   // Scroll up this much to start showing
    
    // MARK: - Callbacks
    var onCameraTapped: (() -> Void)?
    var onSearchActivated: (() -> Void)?
    var onSearchDeactivated: (() -> Void)?
    var onSearchTextChanged: ((String) -> Void)?
    
    // MARK: - Constants
    private let buttonSize: CGFloat = 36  // Compact size, not too big
    private let iconSize: CGFloat = 18    // Proportional icon size
    private let expandedCornerRadius: CGFloat = 12
    private let collapsedCornerRadius: CGFloat = 18
    
    // MARK: - Constraints for Animation
    private var searchWidthConstraint: NSLayoutConstraint!
    private var searchIconCenterXConstraint: NSLayoutConstraint!
    private var searchIconLeadingConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update gradient frame - extend into safe area above the header bar
        // Get safe area from window for accurate value (view's safeAreaInsets may not be set yet)
        let safeAreaTop: CGFloat
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            safeAreaTop = window.safeAreaInsets.top
        } else {
            safeAreaTop = safeAreaInsets.top
        }
        
        // Extend gradient above bounds to cover entire top of screen
        shadeGradient.frame = CGRect(
            x: 0,
            y: -safeAreaTop,  // Extend above the header bar into safe area
            width: bounds.width,
            height: bounds.height + safeAreaTop  // Total height includes safe area
        )
    }
    
    private func setupUI() {
        backgroundColor = .clear  // CRITICAL: Allow grain gradient to show through
        clipsToBounds = false
        
        setupShadeGradient()
        setupCameraButton()
        setupTitleLabel()
        setupSearchBar()
        setupLayout()
    }
    
    private func setupShadeGradient() {
        // Subtle top-to-bottom gradient for better button visibility when scrolled
        // Starts with subtle dark at top, fades to transparent
        shadeGradient.colors = [
            UIColor.black.withAlphaComponent(0.3).cgColor,
            UIColor.black.withAlphaComponent(0.15).cgColor,
            UIColor.clear.cgColor
        ]
        shadeGradient.locations = [0.0, 0.5, 1.0]
        shadeGradient.startPoint = CGPoint(x: 0.5, y: 0)
        shadeGradient.endPoint = CGPoint(x: 0.5, y: 1)
        shadeGradient.opacity = 0  // Hidden by default (at top)
        layer.insertSublayer(shadeGradient, at: 0)
    }
    
    private func setupCameraButton() {
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.backgroundColor = .clear
        cameraButton.isUserInteractionEnabled = true
        addSubview(cameraButton)
        
        // Camera icon (outline, not filled)
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        cameraIcon.image = UIImage(systemName: "camera", withConfiguration: config)
        cameraIcon.tintColor = .white
        cameraIcon.contentMode = .scaleAspectFit
        cameraIcon.translatesAutoresizingMaskIntoConstraints = false
        cameraButton.addSubview(cameraIcon)
        
        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(cameraTapped))
        cameraButton.addGestureRecognizer(tap)
    }
    
    private func setupTitleLabel() {
        titleImageView.image = UIImage(named: "SwaeLogo")
        titleImageView.contentMode = .scaleAspectFit
        titleImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleImageView)
    }
    
    private func setupSearchBar() {
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.backgroundColor = .clear
        searchContainer.layer.cornerRadius = collapsedCornerRadius
        searchContainer.layer.cornerCurve = .continuous
        searchContainer.clipsToBounds = true
        searchContainer.isUserInteractionEnabled = true
        addSubview(searchContainer)
        
        // Search icon (magnifying glass)
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        searchIcon.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)
        searchIcon.tintColor = .white
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchIcon)
        
        // Text field (hidden when collapsed)
        searchTextField.placeholder = "Search"
        searchTextField.font = .systemFont(ofSize: 16, weight: .regular)
        searchTextField.textColor = .white
        searchTextField.tintColor = .white
        searchTextField.attributedPlaceholder = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: UIColor(white: 1.0, alpha: 0.5)]
        )
        searchTextField.returnKeyType = .search
        searchTextField.autocorrectionType = .no
        searchTextField.autocapitalizationType = .none
        searchTextField.delegate = self
        searchTextField.alpha = 0
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchTextField)
        
        // Add target for text changes
        searchTextField.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)
        
        // Tap gesture for collapsed state
        let tap = UITapGestureRecognizer(target: self, action: #selector(searchTapped))
        searchContainer.addGestureRecognizer(tap)
    }
    
    private func setupLayout() {
        // Create width constraint for animation
        searchWidthConstraint = searchContainer.widthAnchor.constraint(equalToConstant: buttonSize)
        
        // The search icon needs explicit size constraints because "magnifyingglass" has a larger
        // intrinsic size than the 36pt glass container, causing it to be clipped.
        // Use a size that fills the circle nicely (same visual weight as the camera icon).
        let searchIconSize: CGFloat = 24  // Leaves 6pt padding on each side of 36pt circle
        
        // Two constraints for the search icon horizontal position:
        // - centerX: active when collapsed (centers icon like camera button)
        // - leading: active when expanded (positions icon at left edge of pill)
        searchIconCenterXConstraint = searchIcon.centerXAnchor.constraint(
            equalTo: searchContainer.centerXAnchor
        )
        searchIconLeadingConstraint = searchIcon.leadingAnchor.constraint(
            equalTo: searchContainer.leadingAnchor,
            constant: 12
        )
        
        // Start in collapsed state: centerX active, leading inactive
        searchIconCenterXConstraint.isActive = true
        searchIconLeadingConstraint.isActive = false
        
        NSLayoutConstraint.activate([
            // Camera button - left aligned with padding
            cameraButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            cameraButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cameraButton.widthAnchor.constraint(equalToConstant: buttonSize),
            cameraButton.heightAnchor.constraint(equalToConstant: buttonSize),
            
            // Camera icon centered in button
            cameraIcon.centerXAnchor.constraint(equalTo: cameraButton.centerXAnchor),
            cameraIcon.centerYAnchor.constraint(equalTo: cameraButton.centerYAnchor),
            
            // Title image - centered with fixed height
            titleImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleImageView.heightAnchor.constraint(equalToConstant: 28),
            titleImageView.widthAnchor.constraint(equalToConstant: 112),
            
            // Search container - right aligned with padding
            searchContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            searchContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchWidthConstraint,
            searchContainer.heightAnchor.constraint(equalToConstant: buttonSize),
            
            // Search icon - constrained to fit within container, centered vertically
            searchIcon.widthAnchor.constraint(equalToConstant: searchIconSize),
            searchIcon.heightAnchor.constraint(equalToConstant: searchIconSize),
            searchIcon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            
            // Text field - to the right of icon
            searchTextField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchTextField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchTextField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
        ])
    }
    
    // MARK: - Search Actions
    
    @objc private func searchTapped() {
        if searchState == .collapsed {
            expandSearch(animated: true)
        }
    }
    
    @objc private func searchTextDidChange() {
        onSearchTextChanged?(searchTextField.text ?? "")
    }
    
    // MARK: - Search Expand/Collapse
    
    func expandSearch(animated: Bool) {
        guard searchState == .collapsed else { return }
        searchState = .expanded
        isScrollHideDisabled = true
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Notify immediately so overlay animation starts at the same time
        onSearchActivated?()
        
        // Calculate expanded width (screen width - camera button - spacing)
        let expandedWidth = bounds.width - 16 - buttonSize - 24 - 16 // leading + camera + spacing + trailing
        
        let xConfig = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        let xImage = UIImage(systemName: "xmark", withConfiguration: xConfig)
        
        let animations = {
            // Expand width
            self.searchWidthConstraint.constant = expandedWidth
            
            // Update corner radius
            self.searchContainer.layer.cornerRadius = self.expandedCornerRadius
            
            // Fade in pill background + border (darker glass feel)
            self.searchContainer.backgroundColor = UIColor(white: 0.0, alpha: 0.35)
            self.searchContainer.layer.borderWidth = 0.5
            self.searchContainer.layer.borderColor = UIColor(white: 1.0, alpha: 0.12).cgColor
            
            // Switch from centered to leading-aligned
            self.searchIconCenterXConstraint.isActive = false
            self.searchIconLeadingConstraint.isActive = true
            
            // Show text field
            self.searchTextField.alpha = 1
            
            // Fade out title
            self.titleImageView.alpha = 0
            
            self.layoutIfNeeded()
        }
        
        let completion: (Bool) -> Void = { _ in
            self.searchTextField.becomeFirstResponder()
        }
        
        if animated && !UIAccessibility.isReduceMotionEnabled {
            // Crossfade camera → xmark in sync with the spring animation
            UIView.transition(
                with: cameraIcon,
                duration: 0.3,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.cameraIcon.image = xImage
            }
            
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5,
                options: .allowUserInteraction,
                animations: animations,
                completion: completion
            )
        } else {
            cameraIcon.image = xImage
            animations()
            completion(true)
        }
    }
    
    func collapseSearch(animated: Bool) {
        guard searchState == .expanded else { return }
        searchState = .collapsed
        isScrollHideDisabled = false
        
        // Flag a resync so the next scroll event just captures the current
        // offset instead of computing a huge stale delta that hides the header
        needsScrollResync = true
        
        searchTextField.resignFirstResponder()
        searchTextField.text = ""
        onSearchTextChanged?("")
        
        // Notify immediately so overlay animation starts at the same time
        onSearchDeactivated?()
        
        let camConfig = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        let camImage = UIImage(systemName: "camera", withConfiguration: camConfig)
        
        let animations = {
            // Collapse width
            self.searchWidthConstraint.constant = self.buttonSize
            
            // Update corner radius
            self.searchContainer.layer.cornerRadius = self.collapsedCornerRadius
            
            // Fade out pill background + border
            self.searchContainer.backgroundColor = .clear
            self.searchContainer.layer.borderWidth = 0
            self.searchContainer.layer.borderColor = nil
            
            // Switch from leading-aligned back to centered
            self.searchIconLeadingConstraint.isActive = false
            self.searchIconCenterXConstraint.isActive = true
            
            // Hide text field
            self.searchTextField.alpha = 0
            
            // Show title
            self.titleImageView.alpha = 1
            
            self.layoutIfNeeded()
        }
        
        if animated && !UIAccessibility.isReduceMotionEnabled {
            // Crossfade xmark → camera in sync with the spring animation
            UIView.transition(
                with: cameraIcon,
                duration: 0.25,
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) {
                self.cameraIcon.image = camImage
            }
            
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.3,
                options: .allowUserInteraction,
                animations: animations
            )
        } else {
            cameraIcon.image = camImage
            animations()
        }
    }
    
    // MARK: - Actions
    
    @objc private func cameraTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        animateButtonPress(cameraButton)
        
        if searchState == .expanded {
            collapseSearch(animated: true)
        } else {
            onCameraTapped?()
        }
    }
    
    private func animateButtonPress(_ button: UIView) {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            button.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            button.alpha = 0.8
        } completion: { _ in
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                button.transform = .identity
                button.alpha = 1.0
            }
        }
    }
    
    // MARK: - Scroll Handling (Instagram-style hide/show)
    
    /// Call this from scrollViewDidScroll to update header visibility
    /// - Parameters:
    ///   - currentOffset: Current scroll offset (contentOffset.y + contentInset.top)
    ///   - isOverGradient: Whether the header bar is positioned over the hero gradient
    func updateForScroll(currentOffset: CGFloat, isOverGradient: Bool) {
        // Don't hide/show when search is active
        guard !isScrollHideDisabled else { return }
        
        // After search closes, resync to the current offset without acting on it
        // This prevents a huge stale delta from immediately hiding the header
        if needsScrollResync {
            needsScrollResync = false
            lastScrollOffset = currentOffset
            accumulatedScrollDelta = 0
            lastScrollDirection = .none
            updateShadeGradient(isOverGradient: isOverGradient)
            return
        }
        
        let delta = currentOffset - lastScrollOffset
        lastScrollOffset = currentOffset
        
        // Determine current scroll direction
        let currentDirection: ScrollDirection
        if delta > 0.5 {
            currentDirection = .down
        } else if delta < -0.5 {
            currentDirection = .up
        } else {
            currentDirection = .none
        }
        
        // Reset accumulated delta when direction changes (key fix for scroll up detection)
        if currentDirection != .none && currentDirection != lastScrollDirection {
            accumulatedScrollDelta = 0
            lastScrollDirection = currentDirection
        }
        
        // Update shade gradient - hide when over hero gradient, show when over content
        updateShadeGradient(isOverGradient: isOverGradient)
        
        // At very top (over gradient and near start) - always show header
        if isOverGradient && currentOffset <= 10 {
            if isHeaderHidden {
                showHeader(animated: true)
            }
            accumulatedScrollDelta = 0
            return
        }
        
        // Accumulate scroll delta
        accumulatedScrollDelta += delta
        
        // Scrolling down - hide header
        if delta > 0 && !isHeaderHidden {
            if accumulatedScrollDelta > hideThreshold {
                hideHeader(animated: true)
                accumulatedScrollDelta = 0
            }
        }
        // Scrolling up - show header
        else if delta < 0 && isHeaderHidden {
            if accumulatedScrollDelta < -showThreshold {
                showHeader(animated: true)
                accumulatedScrollDelta = 0
            }
        }
    }
    
    /// Reset scroll tracking (call when view appears)
    func resetScrollState() {
        lastScrollOffset = 0
        accumulatedScrollDelta = 0
        lastScrollDirection = .none
        if isHeaderHidden {
            showHeader(animated: false)
        }
    }
    
    private func updateShadeGradient(isOverGradient: Bool) {
        // Hide shade when over gradient (grain gradient provides colorful background)
        // Show shade when over content (need visibility help over varying content)
        let targetOpacity: Float = isOverGradient ? 0 : 1
        
        if shadeGradient.opacity != targetOpacity {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            shadeGradient.opacity = targetOpacity
            CATransaction.commit()
        }
    }
    
    private func hideHeader(animated: Bool) {
        guard !isHeaderHidden else { return }
        isHeaderHidden = true
        
        let duration = animated ? 0.25 : 0
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            self.transform = CGAffineTransform(translationX: 0, y: -self.bounds.height - 10)
            self.alpha = 0
        }
    }
    
    private func showHeader(animated: Bool) {
        guard isHeaderHidden else { return }
        isHeaderHidden = false
        
        let duration = animated ? 0.25 : 0
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            self.transform = .identity
            self.alpha = 1
        }
    }
}


// MARK: - UITextFieldDelegate
extension SwaeHeaderBar: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Dismiss keyboard on return key
        textField.resignFirstResponder()
        return true
    }
}
