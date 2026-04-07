//
//  ControlPanelViewController.swift
//  swae
//
//  Control panel for streamer mode - shows dashboard + chat
//  QuickActions removed - dashboard is now the primary header
//

import Combine
import NostrSDK
import SwiftUI
import UIKit

class ControlPanelViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var model: Model?
    
    // Bridge data
    private var liveStream: LiveStream?
    private var liveActivitiesEvent: LiveActivitiesEvent?
    
    // UI Components
    let contentBackgroundView = UIView()
    private var chatVC: LiveChatController?
    
    var cancellables: Set<AnyCancellable> = []
    
    // Chat placeholder (shown when chat is unavailable)
    private weak var chatPlaceholderView: UIView?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBridgeData()
        setupChildViewControllers()
        setupViews()
        setupActions()
        setupNotifications()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // DON'T automatically activate chat input here
        // The input bar should only appear when the control panel is actually visible
        // This is handled by panelDidAppear() via notification from CameraContainerViewController
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Dismiss keyboard when panel disappears
        dismissKeyboard()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
    
    // MARK: - Setup
    
    private func setupBridgeData() {
        guard let model = model else {
            print("⚠️ ControlPanelViewController: No model available for bridge data")
            return
        }
        
        liveStream = StreamingBridge.createLiveStream(from: model)
        liveActivitiesEvent = StreamingBridge.createLiveActivitiesEvent(
            from: model,
            appState: model.appState
        )
    }
    
    private func setupChildViewControllers() {
        guard let model = model else {
            print("⚠️ ControlPanelViewController: No model available for child VCs")
            return
        }
        
        // Chat - create with bridge data (liveStream may be nil if model wasn't set)
        guard let stream = liveStream else {
            print("⚠️ ControlPanelViewController: No liveStream for chat")
            return
        }
        
        // Use streamer mode with dashboard for camera streaming
        let chat = LiveChatController(
            liveStream: stream,
            liveActivitiesEvent: liveActivitiesEvent,
            appState: model.appState,
            streamStartTime: model.streamStartTime,
            isStreamerMode: true  // Enable streamer dashboard
        )
        chatVC = chat
        
        addChild(chat)
    }
    
    private func setupViews() {
        view.backgroundColor = .clear
        
        contentBackgroundView.backgroundColor = .systemBackground
        
        // Setup chat controller - only if available
        if let chatVC = chatVC {
            contentBackgroundView.addSubview(chatVC.view)
            chatVC.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                chatVC.view.topAnchor.constraint(equalTo: contentBackgroundView.topAnchor),
                chatVC.view.bottomAnchor.constraint(equalTo: contentBackgroundView.bottomAnchor),
                chatVC.view.leadingAnchor.constraint(equalTo: contentBackgroundView.leadingAnchor),
                chatVC.view.trailingAnchor.constraint(equalTo: contentBackgroundView.trailingAnchor),
            ])
            
            chatVC.willMove(toParent: self)
            view.addSubview(contentBackgroundView)
            chatVC.didMove(toParent: self)
        } else {
            // Add improved placeholder for chat when not available
            view.addSubview(contentBackgroundView)
            setupChatPlaceholder()
        }
        
        // Setup constraints
        setupConstraints()
    }
    
    /// Creates an improved placeholder view when chat is unavailable
    private func setupChatPlaceholder() {
        let containerStack = UIStackView()
        containerStack.axis = .vertical
        containerStack.alignment = .center
        containerStack.spacing = 16
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Icon
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 48, weight: .light)
        let iconImageView = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right", withConfiguration: iconConfig))
        iconImageView.tintColor = .tertiaryLabel
        iconImageView.contentMode = .scaleAspectFit
        
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Chat"
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        
        // Message - use StreamingBridge to get appropriate message
        let messageLabel = UILabel()
        if let model = model {
            messageLabel.text = StreamingBridge.chatUnavailableReason(for: model, appState: model.appState)
        } else {
            messageLabel.text = "Chat available during live streams"
        }
        messageLabel.font = .systemFont(ofSize: 14, weight: .regular)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        
        // Add subviews
        containerStack.addArrangedSubview(iconImageView)
        containerStack.addArrangedSubview(titleLabel)
        containerStack.addArrangedSubview(messageLabel)
        
        contentBackgroundView.addSubview(containerStack)
        
        NSLayoutConstraint.activate([
            containerStack.centerXAnchor.constraint(equalTo: contentBackgroundView.centerXAnchor),
            containerStack.centerYAnchor.constraint(equalTo: contentBackgroundView.centerYAnchor),
            containerStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentBackgroundView.leadingAnchor, constant: 32),
            containerStack.trailingAnchor.constraint(lessThanOrEqualTo: contentBackgroundView.trailingAnchor, constant: -32),
        ])
        
        // Store reference for updates
        chatPlaceholderView = containerStack
    }
    
    /// Updates the chat placeholder message based on current state
    private func updateChatPlaceholder() {
        guard let model = model,
              let containerStack = chatPlaceholderView as? UIStackView,
              containerStack.arrangedSubviews.count >= 3,
              let messageLabel = containerStack.arrangedSubviews[2] as? UILabel else {
            return
        }
        
        messageLabel.text = StreamingBridge.chatUnavailableReason(for: model, appState: model.appState)
    }
    
    private func setupConstraints() {
        // Content background fills entire view (no gap at top)
        // The dashboard inside will handle its own safe area padding
        contentBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            contentBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func setupActions() {
        // No actions needed - close button removed
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissKeyboard),
            name: NSNotification.Name("DismissControlPanelKeyboard"),
            object: nil
        )
        
        // Listen for panel lifecycle notifications from CameraContainerViewController
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelDidAppear),
            name: NSNotification.Name("ControlPanelDidAppear"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelWillDisappear),
            name: NSNotification.Name("ControlPanelWillDisappear"),
            object: nil
        )
        
        // Observe liveActivitiesEvents for the logged-in user's stream event.
        // This ensures the chat always tracks the current live event, even if it
        // arrives after the control panel was created or changes mid-stream.
        observeUserLiveEvent()
    }
    
    /// Observes AppState for the logged-in user's live activities event.
    /// When the event appears or its coordinate changes, updates the chat controller.
    private func observeUserLiveEvent() {
        guard let model = model, let appState = model.appState else { return }
        
        appState.$liveActivitiesEvents
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] allEvents in
                guard let self = self,
                      let model = self.model,
                      model.stream.zapStreamCoreEnabled else { return }
                
                // Find the most recent live event for this user (highest createdAt).
                // Avoids latching onto stale events from previous streams.
                guard let userPubkey = appState.keypair?.publicKey.hex else { return }
                let allLiveEvents: [LiveActivitiesEvent] = allEvents.values.flatMap { $0 }
                let userLiveEvents = allLiveEvents.filter {
                    $0.hostPubkeyHex == userPubkey && $0.status == .live
                }
                let userLiveEvent = userLiveEvents.max(by: { $0.createdAt < $1.createdAt })
                
                guard let newEvent = userLiveEvent else { return }
                
                let newCoordinate = newEvent.coordinateTag
                let currentCoordinate = self.liveActivitiesEvent?.coordinateTag
                
                if self.chatVC != nil {
                    // Chat controller exists — push the updated event to it
                    if currentCoordinate != newCoordinate || self.liveActivitiesEvent == nil {
                        print("🔄 ControlPanelViewController: User live event changed, updating chat")
                        self.liveActivitiesEvent = newEvent
                        self.chatVC?.updateLiveActivitiesEvent(newEvent)
                    }
                } else {
                    // No chat controller yet — create one now that the event is available
                    self.liveActivitiesEvent = newEvent
                    self.recreateChatController()
                }
            }
            .store(in: &cancellables)
    }
    
    @objc private func handlePanelDidAppear() {
        panelDidAppear()
    }
    
    @objc private func handlePanelWillDisappear() {
        panelWillDisappear()
    }
    
    // MARK: - Actions
    
    @objc private func handleDismissKeyboard() {
        dismissKeyboard()
    }
    
    // MARK: - Public Methods
    
    func updateFromModel() {
        guard let model = model else { return }
        
        if var stream = liveStream {
            StreamingBridge.updateLiveStream(&stream, from: model)
            liveStream = stream
            chatVC?.liveStream = stream
        }
        
        // Update chat placeholder if chat is not available
        if chatVC == nil {
            updateChatPlaceholder()
            
            // Check if chat has become available (e.g., user started streaming to Nostr)
            if let newEvent = StreamingBridge.createLiveActivitiesEvent(from: model, appState: model.appState) {
                // Chat is now available - recreate the chat controller
                liveActivitiesEvent = newEvent
                recreateChatController()
            }
        } else {
            // Chat controller exists — check if the event has changed
            if let newEvent = StreamingBridge.createLiveActivitiesEvent(from: model, appState: model.appState) {
                let newCoord = newEvent.coordinateTag
                let currentCoord = liveActivitiesEvent?.coordinateTag
                if currentCoord != newCoord {
                    liveActivitiesEvent = newEvent
                    chatVC?.updateLiveActivitiesEvent(newEvent)
                }
            }
        }
    }
    
    /// Recreates the chat controller when it becomes available
    private func recreateChatController() {
        guard let model = model,
              let stream = liveStream,
              chatVC == nil else { return }
        
        print("✅ ControlPanelViewController: Chat became available, creating controller")
        
        // Remove placeholder
        chatPlaceholderView?.removeFromSuperview()
        chatPlaceholderView = nil
        
        // Create chat controller with streamer mode
        let chat = LiveChatController(
            liveStream: stream,
            liveActivitiesEvent: liveActivitiesEvent,
            appState: model.appState,
            streamStartTime: model.streamStartTime,
            isStreamerMode: true
        )
        chatVC = chat
        
        // Add as child
        addChild(chat)
        
        // Add view
        contentBackgroundView.addSubview(chat.view)
        chat.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chat.view.topAnchor.constraint(equalTo: contentBackgroundView.topAnchor),
            chat.view.bottomAnchor.constraint(equalTo: contentBackgroundView.bottomAnchor),
            chat.view.leadingAnchor.constraint(equalTo: contentBackgroundView.leadingAnchor),
            chat.view.trailingAnchor.constraint(equalTo: contentBackgroundView.trailingAnchor),
        ])
        
        chat.didMove(toParent: self)
    }
    
    func dismissKeyboard() {
        chatVC?.resignFirstResponder()
        chatVC?.input.textField.textView.resignFirstResponder()
    }
    
    /// Activates the chat input bar when the panel becomes visible
    /// This ensures the inputAccessoryView is properly shown
    func activateChatInput() {
        guard let chatVC = chatVC else {
            print("ℹ️ ControlPanelViewController: No chat available, skipping input activation")
            return
        }
        
        // Make the chat controller first responder to show the inputAccessoryView
        // This is required for the input bar to appear at the bottom
        DispatchQueue.main.async {
            chatVC.becomeFirstResponder()
            print("✅ ControlPanelViewController: Chat input activated")
        }
    }
    
    /// Called when the settings panel becomes visible
    func panelDidAppear() {
        print("📱 ControlPanelViewController: Panel appeared")
        activateChatInput()
    }
    
    /// Called when the settings panel will disappear
    func panelWillDisappear() {
        print("📱 ControlPanelViewController: Panel will disappear")
        dismissKeyboard()
        
        // Also resign first responder on the chat controller to hide the input bar
        chatVC?.resignFirstResponder()
    }
}
