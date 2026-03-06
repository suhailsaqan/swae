//
//  OnboardingViewController.swift
//  swae
//
//  Feature carousel with Metal particle animation for onboarding
//

import SwiftUI
import UIKit

protocol OnboardingViewControllerDelegate: AnyObject {
    func onboardingDidComplete()
    func onboardingDidSkip()
}

struct OnboardingFeatureItem {
    let icon: String
    let title: String
    let description: String
    let color: UIColor
}

final class OnboardingViewController: UIViewController {
    
    // MARK: - Dependencies
    private let appState: AppState
    weak var delegate: OnboardingViewControllerDelegate?
    
    // MARK: - Features
    private let features: [OnboardingFeatureItem] = [
        OnboardingFeatureItem(
            icon: "video.fill",
            title: "Go Live Instantly",
            description: "Stream to your audience with built-in tools and real-time engagement",
            color: .accentPurple
        ),
        OnboardingFeatureItem(
            icon: "play.circle.fill",
            title: "Watch Live Streams",
            description: "Discover and watch live content from creators worldwide on a decentralized platform",
            color: .systemPurple
        ),
        OnboardingFeatureItem(
            icon: "bolt.fill",
            title: "Support with Zaps",
            description: "Send instant Bitcoin tips to creators you love using Lightning Network",
            color: .systemOrange
        ),
        OnboardingFeatureItem(
            icon: "lock.shield.fill",
            title: "Own Your Identity",
            description: "Your account, your keys, your data. Built on Nostr for true ownership",
            color: .systemGreen
        )
    ]
    
    private var currentFeatureIndex: Int = 0 {
        didSet { updateFeature(from: oldValue) }
    }
    
    // MARK: - UI Components
    private let logoLabel = UILabel()
    private let taglineLabel = UILabel()
    
    // Content container for vertical centering
    private let contentContainer = UIView()
    
    // Metal particle view (embedded SwiftUI)
    private var metalHostingController: UIHostingController<MetalParticleWrapper>?
    private let particleContainer = UIView()
    
    // Feature content
    private let featureTitleLabel = UILabel()
    private let featureDescriptionLabel = UILabel()
    private let pageIndicator = OnboardingPageIndicator()
    
    // Buttons
    private let actionButton = OnboardingActionButton()
    private let signInButton = UIButton(type: .system)
    private let guestButton = UIButton(type: .system)
    
    // MARK: - Initialization
    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        updateFeature(from: 0)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // After a presented SwiftUI sheet is dismissed (programmatically or by swipe),
        // check if sign-in/create-profile completed.
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            delegate?.onboardingDidComplete()
        }
    }
    
    // MARK: - Setup UI
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        setupLogo()
        setupButtons()
        setupContentContainer()
        setupParticleView()
        setupFeatureContent()
        setupPageIndicator()
    }
    
    private func setupLogo() {
        // Logo
        logoLabel.text = "Swae"
        logoLabel.font = .systemFont(ofSize: 48, weight: .bold)
        logoLabel.textAlignment = .center
        logoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Gradient text
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [UIColor.cyan.cgColor, UIColor.accentPurple.cgColor, UIColor.systemPurple.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.frame = CGRect(x: 0, y: 0, width: 200, height: 70)
        
        let renderer = UIGraphicsImageRenderer(size: gradientLayer.frame.size)
        let gradientImage = renderer.image { ctx in
            gradientLayer.render(in: ctx.cgContext)
        }
        logoLabel.textColor = UIColor(patternImage: gradientImage)
        
        view.addSubview(logoLabel)
        
        // Tagline
        taglineLabel.text = "Live streaming on Nostr"
        taglineLabel.font = .systemFont(ofSize: 15)
        taglineLabel.textColor = .secondaryLabel
        taglineLabel.textAlignment = .center
        taglineLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(taglineLabel)
        
        NSLayoutConstraint.activate([
            logoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            logoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            taglineLabel.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 4),
            taglineLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
    
    private func setupContentContainer() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: taglineLabel.bottomAnchor, constant: 8),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -16),
        ])
    }
    
    private func setupParticleView() {
        particleContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(particleContainer)
        
        // Embed SwiftUI Metal view
        let metalView = MetalParticleWrapper(
            config: .onboarding,
            initialIcon: features[0].icon,
            initialColor: features[0].color
        )
        let hostingController = UIHostingController(rootView: metalView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        addChild(hostingController)
        particleContainer.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        metalHostingController = hostingController
        
        NSLayoutConstraint.activate([
            particleContainer.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            particleContainer.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor, constant: -60),
            particleContainer.widthAnchor.constraint(equalToConstant: 200),
            particleContainer.heightAnchor.constraint(equalToConstant: 200),
            
            hostingController.view.topAnchor.constraint(equalTo: particleContainer.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: particleContainer.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: particleContainer.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: particleContainer.bottomAnchor),
        ])
    }
    
    private func setupFeatureContent() {
        // Title
        featureTitleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        featureTitleLabel.textColor = .label
        featureTitleLabel.textAlignment = .center
        featureTitleLabel.numberOfLines = 0
        featureTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(featureTitleLabel)
        
        // Description
        featureDescriptionLabel.font = .systemFont(ofSize: 15)
        featureDescriptionLabel.textColor = .secondaryLabel
        featureDescriptionLabel.textAlignment = .center
        featureDescriptionLabel.numberOfLines = 0
        featureDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(featureDescriptionLabel)
        
        // Set initial text so it has content on first display
        let feature = features[0]
        featureTitleLabel.text = feature.title
        featureDescriptionLabel.text = feature.description
        
        NSLayoutConstraint.activate([
            featureTitleLabel.topAnchor.constraint(equalTo: particleContainer.bottomAnchor, constant: 16),
            featureTitleLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 32),
            featureTitleLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -32),
            
            featureDescriptionLabel.topAnchor.constraint(equalTo: featureTitleLabel.bottomAnchor, constant: 8),
            featureDescriptionLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 32),
            featureDescriptionLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -32),
        ])
    }
    
    private func setupPageIndicator() {
        pageIndicator.numberOfPages = features.count
        pageIndicator.currentPage = 0
        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(pageIndicator)
        
        NSLayoutConstraint.activate([
            pageIndicator.topAnchor.constraint(equalTo: featureDescriptionLabel.bottomAnchor, constant: 16),
            pageIndicator.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
        ])
    }
    
    private func setupButtons() {
        // Action button
        actionButton.setTitle("Next")
        actionButton.accentColor = features[0].color
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        view.addSubview(actionButton)
        
        // Sign in button
        signInButton.setTitle("Already have an account? Sign In", for: .normal)
        signInButton.titleLabel?.font = .systemFont(ofSize: 15)
        signInButton.setTitleColor(.secondaryLabel, for: .normal)
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        view.addSubview(signInButton)
        
        // Guest button
        guestButton.setTitle("Browse as Guest", for: .normal)
        guestButton.titleLabel?.font = .systemFont(ofSize: 13)
        guestButton.setTitleColor(.tertiaryLabel, for: .normal)
        guestButton.translatesAutoresizingMaskIntoConstraints = false
        guestButton.addTarget(self, action: #selector(guestTapped), for: .touchUpInside)
        view.addSubview(guestButton)
        
        NSLayoutConstraint.activate([
            // Buttons anchored to bottom
            guestButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            guestButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guestButton.heightAnchor.constraint(equalToConstant: 36),
            
            signInButton.bottomAnchor.constraint(equalTo: guestButton.topAnchor, constant: -8),
            signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signInButton.heightAnchor.constraint(equalToConstant: 36),
            
            actionButton.bottomAnchor.constraint(equalTo: signInButton.topAnchor, constant: -16),
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }
    
    private func setupGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)
        
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)
    }
    
    // MARK: - Feature Updates
    private func updateFeature(from oldIndex: Int) {
        let feature = features[currentFeatureIndex]
        let isForward = currentFeatureIndex > oldIndex
        
        // Update page indicator
        pageIndicator.currentPage = currentFeatureIndex
        pageIndicator.activeColor = feature.color
        
        // Update button
        let isLastFeature = currentFeatureIndex == features.count - 1
        actionButton.setTitle(isLastFeature ? "Get Started" : "Next")
        
        UIView.animate(withDuration: 0.3) {
            self.actionButton.accentColor = feature.color
        }
        
        // Animate text transition
        let offset: CGFloat = isForward ? 50 : -50
        
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
            self.featureTitleLabel.alpha = 0
            self.featureTitleLabel.transform = CGAffineTransform(translationX: -offset, y: 0)
            self.featureDescriptionLabel.alpha = 0
            self.featureDescriptionLabel.transform = CGAffineTransform(translationX: -offset, y: 0)
        } completion: { _ in
            self.featureTitleLabel.text = feature.title
            self.featureDescriptionLabel.text = feature.description
            self.featureTitleLabel.transform = CGAffineTransform(translationX: offset, y: 0)
            self.featureDescriptionLabel.transform = CGAffineTransform(translationX: offset, y: 0)
            
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.featureTitleLabel.alpha = 1
                self.featureTitleLabel.transform = .identity
                self.featureDescriptionLabel.alpha = 1
                self.featureDescriptionLabel.transform = .identity
            }
        }
        
        // Update Metal particle view
        updateParticleView(icon: feature.icon, color: feature.color)
    }
    
    private func updateParticleView(icon: String, color: UIColor) {
        // Post notification to update the SwiftUI view
        NotificationCenter.default.post(
            name: .onboardingFeatureChanged,
            object: nil,
            userInfo: ["icon": icon, "color": color]
        )
    }
    
    // MARK: - Actions
    @objc private func actionButtonTapped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if currentFeatureIndex < features.count - 1 {
            currentFeatureIndex += 1
        } else {
            showCreateProfile()
        }
    }
    
    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.direction == .left && currentFeatureIndex < features.count - 1 {
            currentFeatureIndex += 1
        } else if gesture.direction == .right && currentFeatureIndex > 0 {
            currentFeatureIndex -= 1
        }
    }
    
    @objc private func signInTapped() {
        let signInView = NavigationStack { SignInView() }
            .environmentObject(appState)
        let hostingController = UIHostingController(rootView: signInView)
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        hostingController.presentationController?.delegate = self
        present(hostingController, animated: true)
    }
    
    @objc private func guestTapped() {
        delegate?.onboardingDidSkip()
    }
    
    private func showCreateProfile() {
        let createView = NavigationStack {
            CreateProfileView(appState: appState)
        }
        .environmentObject(appState)
        let hostingController = UIHostingController(rootView: createView)
        hostingController.modalPresentationStyle = .pageSheet
        hostingController.presentationController?.delegate = self
        present(hostingController, animated: true)
    }
}

// MARK: - Onboarding Completion Observation
// The SwiftUI SignInView and CreateProfileView set hasCompletedOnboarding via @AppStorage.
// We observe that to trigger the delegate callback.
extension OnboardingViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        checkOnboardingCompletion()
    }

    private func checkOnboardingCompletion() {
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            delegate?.onboardingDidComplete()
        }
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let onboardingFeatureChanged = Notification.Name("onboardingFeatureChanged")
}

// MARK: - SwiftUI Metal Particle Wrapper
struct MetalParticleWrapper: View {
    let config: ParticleConfig
    let initialIcon: String
    let initialColor: UIColor
    
    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var metalView: ParticleMetalView?
    @State private var currentIcon: String
    @State private var currentColor: UIColor
    
    init(config: ParticleConfig, initialIcon: String, initialColor: UIColor) {
        self.config = config
        self.initialIcon = initialIcon
        self.initialColor = initialColor
        _currentIcon = State(initialValue: initialIcon)
        _currentColor = State(initialValue: initialColor)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(currentColor).opacity(0.2),
                            Color(currentColor).opacity(0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .blur(radius: 20)
            
            MetalParticleViewWithCoordinator(
                touchLocation: $touchLocation,
                isTouching: $isTouching,
                metalView: $metalView,
                config: config
            )
            .frame(width: 250, height: 250)
            .onChange(of: metalView) { newValue in
                guard let renderer = newValue?.renderer else { return }
                let colorComponents = currentColor.cgColor.components ?? [0, 0, 0, 1]
                let color = SIMD4<Float>(
                    Float(colorComponents[0]),
                    Float(colorComponents[1]),
                    Float(colorComponents[2]),
                    1.0
                )
                renderer.setParticleColor(color)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    renderer.transitionToSFSymbol(currentIcon, size: 200)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingFeatureChanged)) { notification in
            guard let userInfo = notification.userInfo,
                  let icon = userInfo["icon"] as? String,
                  let color = userInfo["color"] as? UIColor else { return }
            
            currentIcon = icon
            currentColor = color
            
            guard let renderer = metalView?.renderer else { return }
            let colorComponents = color.cgColor.components ?? [0, 0, 0, 1]
            let newColor = SIMD4<Float>(
                Float(colorComponents[0]),
                Float(colorComponents[1]),
                Float(colorComponents[2]),
                1.0
            )
            renderer.setParticleColor(newColor)
            renderer.transitionToSFSymbol(icon, size: 200)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isTouching {
                        let impact = UIImpactFeedbackGenerator(style: .soft)
                        impact.impactOccurred(intensity: 0.7)
                    }
                    touchLocation = value.location
                    isTouching = true
                }
                .onEnded { _ in
                    isTouching = false
                }
        )
    }
}
