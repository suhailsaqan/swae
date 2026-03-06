//
//  QuickActionsViewController.swift
//  swae
//
//  Top half of control panel - navigation buttons and quick toggles
//

import SwiftUI
import UIKit

class QuickActionsViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var model: Model?
    weak var panelNavigationController: UINavigationController?
    
    var isMinimized: Bool = false
    
    // UI Components
    private let navigationButtonsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private lazy var toggleCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(QuickToggleCell.self, forCellWithReuseIdentifier: QuickToggleCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isScrollEnabled = false
        return collectionView
    }()
    
    // Toggle data
    private struct ToggleItem {
        let icon: String
        let title: String
        let action: () -> Void
        var isOn: () -> Bool
    }
    
    private var toggleItems: [ToggleItem] = []
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupToggleItems()
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        view.backgroundColor = .clear
        
        // Add navigation buttons
        view.addSubview(navigationButtonsStack)
        
        // Add toggle grid
        view.addSubview(toggleCollectionView)
        
        NSLayoutConstraint.activate([
            // Navigation buttons at top
            navigationButtonsStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            navigationButtonsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            navigationButtonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            navigationButtonsStack.heightAnchor.constraint(equalToConstant: 60),
            
            // Toggle grid below navigation buttons
            toggleCollectionView.topAnchor.constraint(equalTo: navigationButtonsStack.bottomAnchor, constant: 16),
            toggleCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            toggleCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            toggleCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])
        
        // Create navigation buttons
        createNavigationButtons()
    }
    
    private func createNavigationButtons() {
        // Streams button
        let streamsButton = createNavigationButton(
            icon: "dot.radiowaves.left.and.right",
            title: "Streams",
            action: { [weak self] in self?.pushStreamsSettings() }
        )
        
        // Widgets button
        let widgetsButton = createNavigationButton(
            icon: "square.grid.3x3.fill",
            title: "Widgets",
            action: { [weak self] in self?.pushWidgetsSettings() }
        )
        
        // More button
        let moreButton = createNavigationButton(
            icon: "gearshape.fill",
            title: "More",
            action: { [weak self] in self?.pushMoreSettings() }
        )
        
        navigationButtonsStack.addArrangedSubview(streamsButton)
        navigationButtonsStack.addArrangedSubview(widgetsButton)
        navigationButtonsStack.addArrangedSubview(moreButton)
    }
    
    private func createNavigationButton(icon: String, title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        
        // Create vertical stack for icon + label
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.isUserInteractionEnabled = false
        
        // Icon
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        let iconImage = UIImage(systemName: icon, withConfiguration: iconConfig)
        let iconImageView = UIImageView(image: iconImage)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        
        // Label
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(label)
        
        button.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        
        // Styling
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 12
        button.layer.masksToBounds = true
        
        // Action
        button.addAction(UIAction { _ in
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            action()
        }, for: .touchUpInside)
        
        // Accessibility
        button.accessibilityLabel = title
        button.accessibilityHint = "Double tap to open \(title) settings"
        
        return button
    }
    
    private func setupToggleItems() {
        guard let model = model else { return }
        
        toggleItems = [
            ToggleItem(
                icon: "square.grid.3x3",
                title: "Widget",
                action: { [weak self] in self?.toggleFirstWidget() },
                isOn: { [weak model] in model?.hasEnabledWidgets() ?? false }
            ),
            ToggleItem(
                icon: "camera.filters",
                title: "LUT",
                action: { [weak self] in self?.toggleFirstLUT() },
                isOn: { [weak model] in model?.hasEnabledLUTs() ?? false }
            ),
            ToggleItem(
                icon: "mic.fill",
                title: "Mic",
                action: { [weak model] in model?.toggleMute() },
                isOn: { [weak model] in !(model?.isMuteOn ?? true) }
            ),
            ToggleItem(
                icon: "flashlight.on.fill",
                title: "Torch",
                action: { [weak model] in model?.toggleTorch() },
                isOn: { [weak model] in model?.streamOverlay.isTorchOn ?? false }
            ),
            ToggleItem(
                icon: "speaker.wave.2.fill",
                title: "Mute",
                action: { [weak model] in model?.toggleMute() },
                isOn: { [weak model] in model?.isMuteOn ?? false }
            ),
            ToggleItem(
                icon: "camera.rotate",
                title: "Flip",
                action: { [weak model] in model?.toggleCamera() },
                isOn: { false }  // No state for flip
            ),
            ToggleItem(
                icon: "photo.on.rectangle",
                title: "Scene",
                action: { [weak self] in self?.toggleScene() },
                isOn: { false }  // TODO: Implement scene state
            ),
            ToggleItem(
                icon: "video.fill",
                title: "OBS",
                action: { [weak self] in self?.toggleOBS() },
                isOn: { false }  // TODO: Get OBS connection state
            ),
        ]
    }
    
    // MARK: - Toggle Actions
    
    private func toggleFirstWidget() {
        guard let model = model else { return }
        let widgets = model.widgetsInCurrentScene(onlyEnabled: false)
        guard let first = widgets.first else { return }
        first.widget.enabled.toggle()
        model.sceneUpdated(attachCamera: model.isCaptureDeviceWidget(widget: first.widget))
        toggleCollectionView.reloadData()
    }
    
    private func toggleFirstLUT() {
        guard let model = model else { return }
        let luts = model.allLuts()
        guard let first = luts.first else { return }
        first.enabled = !(first.enabled ?? false)
        model.sceneUpdated(updateRemoteScene: false)
        toggleCollectionView.reloadData()
    }
    
    private func toggleScene() {
        // TODO: Implement scene toggle
        print("Scene toggle not yet implemented")
    }
    
    private func toggleOBS() {
        // TODO: Implement OBS toggle
        print("OBS toggle not yet implemented")
    }
    
    // MARK: - Navigation
    
    private func pushStreamsSettings() {
        guard let model = model else { return }
        
        let settingsView = StreamsSettingsView(
            createStreamWizard: model.createStreamWizard,
            database: model.database
        )
        .environmentObject(model)
        .environmentObject(AppCoordinator.shared.appState)
        
        let hostingVC = UIHostingController(rootView: settingsView)
        hostingVC.title = "Streams"
        panelNavigationController?.pushViewController(hostingVC, animated: true)
    }
    
    private func pushWidgetsSettings() {
        guard let model = model else { return }
        
        let settingsView = QuickButtonWidgetsView(
            model: model,
            sceneSelector: model.sceneSelector
        )
        .environmentObject(model)
        
        let hostingVC = UIHostingController(rootView: settingsView)
        hostingVC.title = "Widgets"
        panelNavigationController?.pushViewController(hostingVC, animated: true)
    }
    
    private func pushMoreSettings() {
        guard let model = model else { return }
        
        let settingsView = SettingsView(database: model.database)
            .environmentObject(model)
            .environmentObject(AppCoordinator.shared.appState)
        
        let hostingVC = UIHostingController(rootView: settingsView)
        hostingVC.title = "Settings"
        panelNavigationController?.pushViewController(hostingVC, animated: true)
    }
    
    // MARK: - Mini Camera Animation
    
    func animateToMinimized(_ minimized: Bool) {
        isMinimized = minimized
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.6) {
            if minimized {
                // Hide navigation buttons and toggles when minimized
                self.navigationButtonsStack.alpha = 0
                self.toggleCollectionView.alpha = 0
            } else {
                // Show them when expanded
                self.navigationButtonsStack.alpha = 1
                self.toggleCollectionView.alpha = 1
            }
        }
    }
    
    // MARK: - Public Methods
    
    func reloadToggles() {
        toggleCollectionView.reloadData()
    }
}

// MARK: - UICollectionViewDataSource

extension QuickActionsViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return toggleItems.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: QuickToggleCell.reuseIdentifier,
            for: indexPath
        ) as! QuickToggleCell
        
        let item = toggleItems[indexPath.item]
        cell.configure(
            icon: item.icon,
            title: item.title,
            isOn: item.isOn(),
            action: { [weak self] in
                item.action()
                self?.toggleCollectionView.reloadData()
            }
        )
        
        return cell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension QuickActionsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 4 columns with spacing
        let totalSpacing: CGFloat = 12 * 3  // 3 gaps between 4 items
        let availableWidth = collectionView.bounds.width - totalSpacing
        let itemWidth = availableWidth / 4
        
        return CGSize(width: itemWidth, height: 70)
    }
}

// MARK: - Helper Extensions

extension Model {
    func hasEnabledWidgets() -> Bool {
        return widgetsInCurrentScene(onlyEnabled: true).count > 0
    }
    
    func hasEnabledLUTs() -> Bool {
        for lut in allLuts() where lut.enabled == true {
            return true
        }
        return false
    }
}
