//
//  CameraViewController.swift
//  swae
//
//  UIKit-based camera view controller replacing SwiftUI MainView
//  Provides proper gesture handling and allows child views to expand beyond bounds
//

import AVFoundation
import Combine
import MetalKit
import NostrSDK
import PhotosUI
import SwiftUI
import UIKit

class CameraViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var model: Model?
    
    // Child view controllers
    private var controlBarVC: ControlBarViewController?
    private var streamOverlayVC: StreamOverlayViewController?
    
    // Morphing glass modal reference
    private var morphingGlassModal: MorphingGlassModal?
    
    // Settings view controller - kept alive to preserve navigation state
    private var settingsHostingController: UIHostingController<AnyView>?
    
    // Views
    private let cameraPreviewContainer = UIView()
    private let overlayContainer = PassthroughView()
    private let controlBarContainer = ExpandableControlBarView()
    private let dismissTapView = ModalDismissView() // Tap target above control bar for dismissing modal
    private let focusIndicatorView = FocusIndicatorView()
    
    // Control bar height constraint (animated when modal expands)
    private var controlBarHeightConstraint: NSLayoutConstraint!
    
    // Landscape support
    private var controlBarWidthConstraint: NSLayoutConstraint!
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var aspectRatioConstraint: NSLayoutConstraint?
    
    // Quick-Add state: tracks the last widget created via the type picker
    private var lastCreatedWidgetId: UUID?
    
    // Quick-Edit state: tracks the widget being edited via row tap → quick config
    private var editingWidgetId: UUID?
    
    // Widget positioning overlay
    private var widgetPositionOverlay: WidgetPositionOverlayView?
    
    // Info bar for widget positioning (sibling of overlay, not a child — avoids gesture conflicts)
    private var widgetPositionInfoBar: UIView?
    
    // Stream view (passed from parent)
    private var streamView: StreamView?
    private var streamHostingController: UIHostingController<AnyView>?
    
    // Orientation
    private var orientation: Orientation?
    
    // Gesture handling
    private var pinchGesture: UIPinchGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    
    // Model observation
    private var cancellables = Set<AnyCancellable>()
    
    // UIKit toast overlay (since SwiftUI MainView toast isn't in this hierarchy)
    private var toastLabel: UILabel?
    private var toastHideWorkItem: DispatchWorkItem?
    
    // Callbacks
    var onExitStream: (() -> Void)?
    
    // MARK: - Initialization
    
    init(model: Model, streamView: StreamView, orientation: Orientation) {
        self.model = model
        self.streamView = streamView
        self.orientation = orientation
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupGestures()
        setupChildControllers()
        setupToastObserver()
        setupWalletBalanceObserver()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.post(
            name: NSNotification.Name("CameraViewDidAppear"),
            object: nil
        )
        
        // Update state from model and observe changes
        setupModelObservation()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Negate safe area insets on the stream hosting controller so the
        // camera preview extends behind the status bar at the top.
        // The bottom is handled by the control bar constraint, so the bottom
        // inset is typically 0 here, but we negate all insets for robustness.
        if let hc = streamHostingController {
            let parentInsets = view.safeAreaInsets
            hc.additionalSafeAreaInsets = UIEdgeInsets(
                top: -parentInsets.top,
                left: -parentInsets.left,
                bottom: -parentInsets.bottom,
                right: -parentInsets.right
            )
        }
    }
    
    private func setupModelObservation() {
        guard let model = model else { return }
        
        // Cancel any existing subscriptions to prevent duplicates
        // (viewDidAppear can be called multiple times)
        cancellables.removeAll()
        
        // Observe isLive changes
        model.$isLive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLive in
                self?.morphingGlassModal?.setLiveActive(isLive)
            }
            .store(in: &cancellables)

        // Observe collab call state — drive morphing modal inline content
        model.$collabCallState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, let modal = self.morphingGlassModal else { return }
                modal.expandedControls.collabPill.isActive = state.isActive

                switch state {
                case .inviteReceived(_, _, let title):
                    modal.setExpanded(true, animated: true)
                    modal.expandedControls.configureCollabIncoming(streamTitle: title)
                    modal.showInlineContent(.collabIncoming)

                case .inviteSent:
                    modal.showInlineContent(.collabCall)
                    modal.expandedControls.configureCollabCall(
                        state: .waiting, isMuted: false, sendWidgets: true, skipPip: true)

                case .connecting:
                    modal.showInlineContent(.collabCall)
                    modal.expandedControls.configureCollabCall(
                        state: .connecting, isMuted: false, sendWidgets: true, skipPip: true)

                case .connected:
                    guard let model = self.model else { return }
                    modal.showInlineContent(.collabCall)
                    modal.expandedControls.configureCollabCall(
                        state: .connected,
                        isMuted: model.isMuteOn,
                        sendWidgets: model.collabSendWidgets,
                        skipPip: model.collabSkipPipForWebRTC,
                        guestVolume: model.guestAudioVolume)

                case .ended, .failed:
                    if let current = modal.expandedControls.currentInlineContent,
                       [.collabCall, .collabIncoming, .collabInvite].contains(current) {
                        modal.expandedControls.showButtonGrid()
                    }

                case .idle:
                    if let current = modal.expandedControls.currentInlineContent,
                       [.collabCall, .collabIncoming, .collabInvite].contains(current) {
                        modal.expandedControls.showButtonGrid()
                    }
                }
            }
            .store(in: &cancellables)
        
        // Observe scene changes
        model.sceneSelector.$sceneIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                self?.morphingGlassModal?.selectScene(at: index, animated: true)
            }
            .store(in: &cancellables)
        
        // Observe manual focus point — hide indicator when auto-focus resets it to nil
        model.camera.$manualFocusPoint
            .receive(on: DispatchQueue.main)
            .sink { [weak self] point in
                if point == nil {
                    self?.focusIndicatorView.hide()
                }
            }
            .store(in: &cancellables)
        
        // Observe stream config changes (e.g. after setup completes)
        model.$stream
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateExpandedButtonStates()
            }
            .store(in: &cancellables)
        
        // Observe recording state (can change via remote control / Apple Watch)
        model.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateExpandedButtonStates()
            }
            .store(in: &cancellables)

        // Observe exposure bias — updates EXPOSURE card subtitle & active state.
        // Fires when changed via inline slider, Apple Watch, or remote control.
        model.camera.$bias
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateExpandedButtonStates()
            }
            .store(in: &cancellables)

        // Observe mic changes — updates MIC card subtitle.
        // Fires when mic is switched via system, Bluetooth connect/disconnect, etc.
        model.mic.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateExpandedButtonStates()
            }
            .store(in: &cancellables)

        // Observe torch state — updates flash pill active state.
        model.streamOverlay.$isTorchOn
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateExpandedButtonStates()
            }
            .store(in: &cancellables)

        // Observe mute state — updates mute pill active state.
        // Can change via Apple Watch, remote control, or chat bot commands.
        model.$isMuteOn
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateExpandedButtonStates()
            }
            .store(in: &cancellables)

        // Uptime — fires every 1s when live. Lightweight Zone 3 only.
        model.streamUptime.$uptime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusBarOnly() }
            .store(in: &cancellables)

        // Bitrate — fires ~1/s when live (change-guarded at source).
        model.bitrate.$speedMbpsOneDecimal
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusBarOnly() }
            .store(in: &cancellables)

        // Viewers — fires ~every 10s (change-guarded at source).
        model.statusTopLeft.$numberOfViewers
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusBarOnly() }
            .store(in: &cancellables)

        // Balance — only fires when explicitly fetched (NOT every second).
        model.$zapStreamCoreBalance
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusBarOnly() }
            .store(in: &cancellables)
        
        // Orientation changes — switch between portrait and landscape layout
        model.orientation.$isPortrait
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                UIView.animate(withDuration: 0.3) {
                    self?.updateLayoutForOrientation()
                }
            }
            .store(in: &cancellables)
        
        // Initial scene setup
        updateScenes()
    }
    
    private func updateScenes() {
        guard let model = model else { return }
        let sceneNames = model.enabledScenes.map { $0.name }
        let selectedIndex = model.sceneSelector.sceneIndex
        morphingGlassModal?.setScenes(sceneNames, selectedIndex: selectedIndex)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.updateLayoutForOrientation()
        }
    }
    
    // MARK: - Toast Observer
    
    /// Observes model.toast changes and shows a UIKit toast overlay on the camera screen.
    /// This is needed because the SwiftUI AlertToast in MainView is not in the UIKit camera hierarchy.
    private func setupToastObserver() {
        model?.toast.$showingToast
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                guard let self, showing, let model = self.model else { return }
                let alertToast = model.toast.toast
                let title = alertToast.title ?? ""
                guard !title.isEmpty else { return }
                let subtitle = alertToast.subTitle
                let displayText = subtitle != nil ? "\(title)\n\(subtitle!)" : title
                self.showUIKitToast(displayText)
            }
            .store(in: &cancellables)
    }
    
    /// Observes wallet balance changes and reconfigures the stream detail modal if visible.
    private var walletBalanceCancellable: AnyCancellable?
    
    private func setupWalletBalanceObserver() {
        // Will be set up dynamically when the stream detail modal opens
    }
    
    private func startObservingWalletBalance() {
        walletBalanceCancellable?.cancel()
        guard let wallet = AppCoordinator.shared.appState.wallet else { return }
        walletBalanceCancellable = wallet.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let data = self.buildStreamDetailData()
                self.morphingGlassModal?.expandedControls.reconfigureStreamDetail(data: data)
            }
    }
    
    private func showUIKitToast(_ text: String) {
        // Cancel any pending hide
        toastHideWorkItem?.cancel()
        
        // Create or reuse the toast label
        let label: PaddedLabel
        if let existing = toastLabel as? PaddedLabel {
            label = existing
        } else {
            toastLabel?.removeFromSuperview()
            label = PaddedLabel()
            label.textInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.82)
            label.layer.cornerRadius = 14
            label.clipsToBounds = true
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alpha = 0
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            ])
            toastLabel = label
        }
        
        // Ensure toast is on top
        view.bringSubviewToFront(label)
        label.text = text
        
        // Animate in
        UIView.animate(withDuration: 0.25) {
            label.alpha = 1
        }
        
        // Auto-hide after 5 seconds
        let hideWork = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.3) {
                self?.toastLabel?.alpha = 0
            }
        }
        toastHideWorkItem = hideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: hideWork)
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        view.backgroundColor = .black
        
        // Camera preview container (full screen)
        cameraPreviewContainer.backgroundColor = .black
        cameraPreviewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraPreviewContainer)
        
        // Add stream view
        if let streamView = streamView {
            // Wrap in ignoresSafeArea so the preview extends edge-to-edge
            // (past status bar at top and home indicator at bottom)
            let edgeToEdgeView = AnyView(streamView.ignoresSafeArea())
            let hostingController = UIHostingController(rootView: edgeToEdgeView)
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            
            addChild(hostingController)
            cameraPreviewContainer.addSubview(hostingController.view)
            hostingController.didMove(toParent: self)
            
            // Constraints are set up in setupConstraints() with aspect ratio
            
            streamHostingController = hostingController
        }
        
        // Focus indicator (on top of stream view, inside camera preview container)
        // Constrained to the video view so the yellow square only appears over the preview,
        // not in the black letterbox/pillarbox areas around it.
        focusIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        cameraPreviewContainer.addSubview(focusIndicatorView)
        if let hcView = streamHostingController?.view {
            NSLayoutConstraint.activate([
                focusIndicatorView.topAnchor.constraint(equalTo: hcView.topAnchor),
                focusIndicatorView.leadingAnchor.constraint(equalTo: hcView.leadingAnchor),
                focusIndicatorView.trailingAnchor.constraint(equalTo: hcView.trailingAnchor),
                focusIndicatorView.bottomAnchor.constraint(equalTo: hcView.bottomAnchor),
            ])
        } else {
            // Fallback if no stream view (shouldn't happen in practice)
            NSLayoutConstraint.activate([
                focusIndicatorView.topAnchor.constraint(equalTo: cameraPreviewContainer.topAnchor),
                focusIndicatorView.leadingAnchor.constraint(equalTo: cameraPreviewContainer.leadingAnchor),
                focusIndicatorView.trailingAnchor.constraint(equalTo: cameraPreviewContainer.trailingAnchor),
                focusIndicatorView.bottomAnchor.constraint(equalTo: cameraPreviewContainer.bottomAnchor),
            ])
        }
        
        // Overlay container (for stream info, chat, etc.)
        overlayContainer.backgroundColor = .clear
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.isUserInteractionEnabled = true
        view.addSubview(overlayContainer)
        
        // Control bar container (bottom) - added AFTER overlay so it's on top
        controlBarContainer.backgroundColor = .black
        controlBarContainer.clipsToBounds = false
        controlBarContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlBarContainer)
        
        // Dismiss tap target - covers area above control bar
        // This catches taps outside the modal when expanded, but forwards
        // taps to the control bar's expanded content (buttons above bounds)
        dismissTapView.backgroundColor = .clear
        dismissTapView.translatesAutoresizingMaskIntoConstraints = false
        dismissTapView.isUserInteractionEnabled = false // Disabled by default
        dismissTapView.controlBar = controlBarContainer
        view.addSubview(dismissTapView)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        // Shared constraints (active in both orientations)
        NSLayoutConstraint.activate([
            cameraPreviewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            overlayContainer.topAnchor.constraint(equalTo: view.topAnchor),
            
            dismissTapView.topAnchor.constraint(equalTo: view.topAnchor),
            dismissTapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dismissTapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dismissTapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        // Portrait-only constraints (control bar at bottom, full width)
        controlBarHeightConstraint = controlBarContainer.heightAnchor.constraint(equalToConstant: controlBarHeightCollapsed)
        portraitConstraints = [
            cameraPreviewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraPreviewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraPreviewContainer.bottomAnchor.constraint(equalTo: controlBarContainer.topAnchor),
            controlBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlBarHeightConstraint,
            overlayContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        
        // Landscape constraints are built dynamically in updateLayoutForOrientation()
        // based on device orientation (control bar goes on the side away from Dynamic Island)
        controlBarWidthConstraint = controlBarContainer.widthAnchor.constraint(equalToConstant: controlBarHeightCollapsed)
        
        // Activate portrait by default
        NSLayoutConstraint.activate(portraitConstraints)
        
        // Stream preview aspect ratio (dynamic based on stream.portrait)
        if let hcView = streamHostingController?.view {
            let ratio = model?.stream.dimensions().aspectRatio() ?? (9.0 / 16.0)
            let clampedRatio = max(0.1, min(10.0, ratio))
            let ar = hcView.widthAnchor.constraint(
                equalTo: hcView.heightAnchor,
                multiplier: clampedRatio
            )
            ar.priority = .required
            ar.isActive = true
            aspectRatioConstraint = ar
            
            NSLayoutConstraint.activate([
                hcView.topAnchor.constraint(equalTo: cameraPreviewContainer.topAnchor),
                hcView.centerXAnchor.constraint(equalTo: cameraPreviewContainer.centerXAnchor),
                hcView.widthAnchor.constraint(lessThanOrEqualTo: cameraPreviewContainer.widthAnchor),
                hcView.heightAnchor.constraint(lessThanOrEqualTo: cameraPreviewContainer.heightAnchor),
            ])
            
            let fillWidth = hcView.widthAnchor.constraint(equalTo: cameraPreviewContainer.widthAnchor)
            fillWidth.priority = .defaultHigh
            fillWidth.isActive = true
        }
    }
    
    private func setupGestures() {
        // Pinch to zoom
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        cameraPreviewContainer.addGestureRecognizer(pinchGesture)
        
        // Tap to focus
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        cameraPreviewContainer.addGestureRecognizer(tapGesture)
        
        // Long press to reset focus
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.delegate = self
        cameraPreviewContainer.addGestureRecognizer(longPressGesture)
        
        // Tap on dismiss view to close modal
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(handleDismissTap(_:)))
        dismissTapView.addGestureRecognizer(dismissTap)
    }
    
    private func setupChildControllers() {
        guard let model = model else { return }
        
        // Initialize layout swizzling for glass views
        initializeLayoutSwizzling()
        
        // Morphing Glass Modal - iOS 26 style camera controls
        let morphingModal = MorphingGlassModal()
        morphingModal.translatesAutoresizingMaskIntoConstraints = false
        controlBarContainer.addSubview(morphingModal)
        
        NSLayoutConstraint.activate([
            morphingModal.topAnchor.constraint(equalTo: controlBarContainer.topAnchor),
            morphingModal.leadingAnchor.constraint(equalTo: controlBarContainer.leadingAnchor),
            morphingModal.trailingAnchor.constraint(equalTo: controlBarContainer.trailingAnchor),
            morphingModal.bottomAnchor.constraint(equalTo: controlBarContainer.bottomAnchor),
        ])
        
        // Wire up callbacks
        morphingModal.onFlashTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            model.toggleTorch()
            self.morphingGlassModal?.expandedControls.flashPill.isActive = model.streamOverlay.isTorchOn
        }
        
        morphingModal.onLiveTapped = { [weak self] in
            self?.model?.toggleStream()
        }
        
        morphingModal.isStreamConfigured = { [weak self] in
            self?.model?.isStreamConfigured() ?? false
        }
        
        morphingModal.onOpenSetup = { [weak self] in
            guard let self = self else { return }
            let sourceView: UIView = self.morphingGlassModal?.flipGlass ?? self.view
            self.presentStreamSetup(sourceView: sourceView)
        }

        morphingModal.onPreStreamReview = { [weak self] in
            guard let self = self, let model = self.model else { return }

            // For zap stream, show spinner while fetching fresh balance
            if model.stream.zapStreamCoreEnabled {
                self.morphingGlassModal?.showLoadingSpinner()

                model.refreshZapStreamCoreBalance { [weak self] in
                    guard let self else { return }
                    self.morphingGlassModal?.hideLoadingSpinner()

                    let balance = model.zapStreamCoreBalance ?? 0
                    let rate = model.zapStreamCoreRate
                    let hasEnough = rate <= 0 || Double(balance) >= rate

                    if hasEnough && model.database.skipPreStreamReview {
                        self.morphingGlassModal?.startCountdown()
                    } else {
                        self.presentPreStreamSheet()
                    }
                }
                return
            }

            // Non-zap-stream: respect skip preference
            if model.database.skipPreStreamReview {
                self.morphingGlassModal?.startCountdown()
                return
            }
            self.presentPreStreamSheet()
        }

        // Long-press Go Live always shows the review sheet (lets user toggle "skip" off)
        morphingModal.onForcePreStreamReview = { [weak self] in
            guard let self = self, self.model != nil else { return }
            self.presentPreStreamSheet()
        }
        
        // Record button — toggle recording, update icon
        morphingModal.onRecordTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            model.toggleRecording()
            self.morphingGlassModal?.expandedControls.recordPill.isActive = model.isRecording
            self.morphingGlassModal?.expandedControls.recordPill.setIcon(
                model.isRecording ? "stop.circle.fill" : "record.circle"
            )
        }
        
        // Exposure — swap to inline slider
        morphingModal.onExposureTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            self.morphingGlassModal?.expandedControls.currentExposureBias = model.camera.bias
            self.morphingGlassModal?.showInlineContent(.exposure)
        }
        
        // Styles — swap to inline LUT picker
        morphingModal.onStylesTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            let luts = model.allLuts()
            self.morphingGlassModal?.expandedControls.lutNames = luts.map { $0.name }
            self.morphingGlassModal?.expandedControls.activeLutIndex = luts.firstIndex(where: { $0.enabled == true }) ?? -1
            self.morphingGlassModal?.showInlineContent(.styles)
        }
        
        // Quality — swap to inline resolution picker
        morphingModal.onQualityTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            let options = self.resolutionOptions
            let currentRes = model.stream.resolution
            let activeIdx = options.firstIndex(where: { $0.resolution == currentRes }) ?? 0
            self.morphingGlassModal?.expandedControls.resolutionOptions = options.map { $0.label }
            self.morphingGlassModal?.expandedControls.activeResolutionIndex = activeIdx
            self.morphingGlassModal?.expandedControls.isLiveOrRecording = model.isLive || model.isRecording
            self.morphingGlassModal?.showInlineContent(.quality)
        }

        // Stabilization card tapped
        morphingModal.expandedControls.onStabilizationTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            let modes = SettingsVideoStabilizationMode.allCases
            let activeIdx = modes.firstIndex(of: model.database.videoStabilizationMode) ?? 0
            self.morphingGlassModal?.expandedControls.pendingStabilizationIndex = activeIdx
            self.morphingGlassModal?.showInlineContent(.stabilization)
        }

        // Stabilization mode changed
        morphingModal.expandedControls.onStabilizationModeChanged = { [weak self] index in
            guard let self = self, let model = self.model else { return }
            let modes = SettingsVideoStabilizationMode.allCases
            guard index < modes.count else { return }
            model.database.videoStabilizationMode = modes[index]
            model.reattachCamera()
        }

        // Bitrate card tapped
        morphingModal.expandedControls.onBitrateTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            let presets = model.database.bitratePresets.map { preset in
                InlineBitrateView.BitrateOption(
                    bitrate: preset.bitrate,
                    label: formatBytesPerSecond(speed: Int64(preset.bitrate))
                )
            }
            self.morphingGlassModal?.expandedControls.pendingBitrateOptions = presets
            self.morphingGlassModal?.expandedControls.pendingActiveBitrate = model.stream.bitrate
            self.morphingGlassModal?.expandedControls.pendingBitrateLocked = model.isLive || model.isRecording
            self.morphingGlassModal?.showInlineContent(.bitrate)
        }

        // Bitrate changed
        morphingModal.expandedControls.onBitrateChanged = { [weak self] bitrate in
            guard let self = self, let model = self.model else { return }
            model.stream.bitrate = bitrate
            if model.stream.enabled {
                model.setStreamBitrate(stream: model.stream)
            }
        }
        
        // Night Mode — toggle tone mapping + LLB
        morphingModal.onNightModeTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            self.toggleNightMode(model: model)
        }
        
        // Portrait/Landscape — toggle display orientation (works while live)
        morphingModal.onPortraitTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            model.setDisplayPortrait(portrait: !model.database.portrait)
            if model.collabCallState.isConnected {
                model.reattachCameraForCollab()
            } else {
                model.reattachCamera()
            }
            self.morphingGlassModal?.expandedControls.portraitPill.isActive = model.database.portrait
        }
        
        // Widgets — swap to inline widget list
        morphingModal.onWidgetsTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            let widgets = model.widgetsInCurrentScene(onlyEnabled: false)
            let items = widgets.map { w in
                InlineWidgetsView.WidgetItem(
                    id: w.widget.id,
                    name: w.widget.name,
                    type: w.widget.type,
                    enabled: w.widget.enabled
                )
            }
            self.morphingGlassModal?.expandedControls.configureWidgets(items)
            self.morphingGlassModal?.showInlineContent(.widgets)
        }
        
        // Inline view action callbacks
        morphingModal.expandedControls.onButtonGridShown = { [weak self] in
            self?.updateExpandedButtonStates()
        }
        
        morphingModal.expandedControls.onExposureChanged = { [weak self] value in
            guard let model = self?.model else { return }
            model.camera.bias = value
            model.setExposureBias(bias: value)
            model.updateImageButtonState()
        }
        
        morphingModal.expandedControls.onExposureReset = { [weak self] in
            guard let model = self?.model else { return }
            model.camera.bias = 0
            model.setExposureBias(bias: 0)
            model.updateImageButtonState()
        }
        
        morphingModal.expandedControls.onLutSelected = { [weak self] index in
            guard let model = self?.model else { return }
            let luts = model.allLuts()
            // Disable all LUTs first
            for lut in luts { lut.enabled = false }
            // Enable selected (index -1 = none)
            if index >= 0 && index < luts.count {
                luts[index].enabled = true
            }
            model.sceneUpdated(updateRemoteScene: false)
            model.updateLutsButtonState()
        }
        
        morphingModal.expandedControls.onResolutionSelected = { [weak self] index in
            guard let self = self, let model = self.model else { return }
            guard !model.isLive && !model.isRecording else { return }
            let options = self.resolutionOptions
            guard index < options.count else { return }
            model.stream.resolution = options[index].resolution
            model.reloadStreamIfEnabled(stream: model.stream)
            // Update quality card subtitle
            self.morphingGlassModal?.expandedControls.qualityCard.configure(
                subtitle: model.stream.resolution.shortString(),
                isActive: false
            )
        }
        
        // Widget toggle — enable/disable widget and refresh scene
        morphingModal.expandedControls.onWidgetToggled = { [weak self] id, enabled in
            guard let self = self, let model = self.model else { return }
            guard let widget = model.findWidget(id: id) else { return }
            widget.enabled = enabled
            model.reloadSpeechToText()
            model.sceneUpdated(attachCamera: model.isCaptureDeviceWidget(widget: widget))
        }
        
        // Widget add — show type picker (Phase 2)
        morphingModal.expandedControls.onWidgetAddTapped = { [weak self] in
            self?.morphingGlassModal?.showInlineContent(.addWidget)
        }
        
        // Widget type selected — create widget, add to scene, handle post-creation flow
        morphingModal.onWidgetTypeSelected = { [weak self] type in
            self?.handleWidgetTypeSelected(type)
        }
        
        // Template selected — create pre-configured widget and add to scene
        morphingModal.onTemplateSelected = { [weak self] template in
            self?.handleTemplateSelected(template)
        }
        
        // Quick config done — save the value and return to widget list
        morphingModal.onQuickConfigDone = { [weak self] value in
            self?.handleQuickConfigDone(value: value)
        }
        
        // Quick config full settings — open Settings for the widget
        morphingModal.onQuickConfigFullSettings = { [weak self] in
            self?.handleQuickConfigFullSettings()
        }
        
        // Widget settings gear — open full Settings
        morphingModal.expandedControls.onWidgetSettingsTapped = { [weak self] in
            guard let self = self else { return }
            self.morphingGlassModal?.dismiss()
            self.morphingGlassModal?.expandedControls.showButtonGrid()
            // Trigger settings open via the same path as the gear button
            self.morphingGlassModal?.onSettingsTapped?(self.view)
        }
        
        // Widget row tapped — enter visual positioning mode
        morphingModal.onWidgetTapped = { [weak self] widgetId in
            self?.enterWidgetPositioning(preselectWidgetId: widgetId)
        }
        
        // Widget row body tapped — open quick config for existing widget
        morphingModal.onWidgetRowTapped = { [weak self] widgetId in
            self?.showQuickConfigForExistingWidget(widgetId: widgetId)
        }
        
        // Widget row swiped left — duplicate widget with placement
        morphingModal.onWidgetDuplicate = { [weak self] widgetId in
            self?.handleWidgetDuplicate(widgetId)
        }
        
        // Widget delete — remove widget from database and all scenes
        morphingModal.onWidgetDelete = { [weak self] widgetId in
            self?.handleWidgetDelete(widgetId)
        }

        // Mute toggle
        morphingModal.onMuteTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            model.toggleMute()
            self.morphingGlassModal?.expandedControls.mutePill.isActive = model.isMuteOn
        }

        // Collab invite (from toggle strip — visible only when live)
        morphingModal.onCollabTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }

            switch model.collabCallState {
            case .inviteReceived(_, _, let title):
                // Re-show the incoming call banner so user can accept/decline
                self.morphingGlassModal?.expandedControls.configureCollabIncoming(streamTitle: title)
                self.morphingGlassModal?.showInlineContent(.collabIncoming)

            case .inviteSent:
                // Show waiting state
                self.morphingGlassModal?.showInlineContent(.collabCall)
                self.morphingGlassModal?.expandedControls.configureCollabCall(
                    state: .waiting, isMuted: false, sendWidgets: true, skipPip: true)

            case .connecting:
                // Show connecting state
                self.morphingGlassModal?.showInlineContent(.collabCall)
                self.morphingGlassModal?.expandedControls.configureCollabCall(
                    state: .connecting, isMuted: false, sendWidgets: true, skipPip: true)

            case .connected:
                // Show in-call controls
                self.morphingGlassModal?.showInlineContent(.collabCall)
                self.morphingGlassModal?.expandedControls.configureCollabCall(
                    state: .connected,
                    isMuted: model.isMuteOn,
                    sendWidgets: model.collabSendWidgets,
                    skipPip: model.collabSkipPipForWebRTC,
                    guestVolume: model.guestAudioVolume)

            case .idle, .ended, .failed:
                // Show the modal immediately with an empty list so there's no delay
                // before the sheet appears. The follow list is built on a background
                // thread (Fix 1) and delivered once ready.
                guard let appState = AppCoordinator.shared.appState else { return }
                self.morphingGlassModal?.expandedControls.pendingCollabAppState = appState
                self.morphingGlassModal?.expandedControls.configureCollabInvite(follows: [])
                self.morphingGlassModal?.showInlineContent(.collabInvite)

                Task.detached(priority: .userInitiated) { [weak self] in
                    let follows = await Self.buildCollabFollowItems(appState: appState)
                    await MainActor.run { [weak self] in
                        self?.morphingGlassModal?.expandedControls.configureCollabInvite(follows: follows)
                    }
                }
            }
        }

        // Collab invite callback — user selected a pubkey to invite
        morphingModal.onCollabInvite = { [weak self] pubkey in
            guard let self, let model = self.model else { return }
            let title = model.stream.name.isEmpty ? "Live Stream" : model.stream.name
            // Handle npub conversion
            if pubkey.lowercased().hasPrefix("npub1") {
                if let pk = NostrSDK.PublicKey(npub: pubkey) {
                    model.startCollabCall(guestPubkey: pk.hex, streamTitle: title, streamId: nil)
                } else {
                    model.makeToast(title: "Invalid npub")
                    return
                }
            } else {
                model.startCollabCall(guestPubkey: pubkey, streamTitle: title, streamId: nil)
            }
            self.morphingGlassModal?.expandedControls.showButtonGrid()
        }

        // Collab incoming — accept/decline
        morphingModal.onCollabAccept = { [weak self] in
            guard let model = self?.model else { return }
            if case let .inviteReceived(hostPubkey, callId, _) = model.collabCallState {
                model.acceptCollabCall(hostPubkey: hostPubkey, callId: callId)
            }
        }
        morphingModal.onCollabDecline = { [weak self] in
            self?.model?.rejectCollabCall()
        }

        // Collab in-call controls
        morphingModal.onCollabEndCall = { [weak self] in
            self?.model?.endCollabCall()
        }
        morphingModal.onCollabMuteTapped = { [weak self] in
            guard let model = self?.model else { return }
            model.toggleMute()
            self?.updateCollabCallView()
        }
        morphingModal.onCollabWidgetsTapped = { [weak self] in
            guard let model = self?.model else { return }
            model.collabSendWidgets.toggle()
            model.updateCollabSendWidgets()
            self?.updateCollabCallView()
        }
        morphingModal.onCollabSkipPipTapped = { [weak self] in
            guard let model = self?.model else { return }
            model.collabSkipPipForWebRTC.toggle()
            model.updateCollabSkipPip()
            self?.updateCollabCallView()
        }
        morphingModal.onCollabVolumeChanged = { [weak self] volume in
            guard let model = self?.model else { return }
            model.guestAudioVolume = volume
            model.updateGuestAudioVolume()
        }

        // Settings gear (from status bar Zone 3)
        morphingModal.onSettingsGearTapped = { [weak self] sourceView in
            guard let self = self else { return }
            self.morphingGlassModal?.onSettingsTapped?(sourceView)
        }

        // Setup stream CTA (from status bar Zone 3 when unconfigured)
        morphingModal.onSetupStreamTapped = { [weak self] sourceView in
            guard let self = self else { return }
            self.presentStreamSetup(sourceView: sourceView)
        }

        // Status bar info area tapped → open inline stream detail view
        morphingModal.onInfoBarTapped = { [weak self] sourceView in
            guard let self = self, let model = self.model else { return }
            // Start observing wallet balance changes so the modal updates live
            self.startObservingWalletBalance()
            // Show modal immediately with current data
            self.morphingGlassModal?.expandedControls.pendingStreamDetailData = self.buildStreamDetailData()
            self.morphingGlassModal?.showInlineContent(.streamDetail)
            // Fetch fresh balances, then update the modal with new data
            if model.stream.zapStreamCoreEnabled {
                model.refreshZapStreamCoreBalance { [weak self] in
                    guard let self else { return }
                    let data = self.buildStreamDetailData()
                    self.morphingGlassModal?.expandedControls.reconfigureStreamDetail(data: data)
                    // Now that hasNwc is up-to-date, trigger wallet balance load
                    self.model?.refreshWalletBalanceIfNeeded()
                }
                // Also try immediately in case hasNwc is already known (second+ open)
                if model.zapStreamCoreHasNwc {
                    model.refreshWalletBalanceIfNeeded()
                }
            }
        }

        // Refresh stream detail data every time the hub page is shown (back-navigation from sub-pages)
        morphingModal.expandedControls.onStreamDetailWillShow = { [weak self] in
            guard let self = self else { return }
            self.morphingGlassModal?.expandedControls.pendingStreamDetailData = self.buildStreamDetailData()
        }

        // Stream detail: Top Up button
        morphingModal.onStreamDetailTopUp = { [weak self] in
            guard let self = self, let model = self.model else { return }
            let paymentView = ZapStreamCorePaymentView()
                .environmentObject(model)
            let hostingVC = UIHostingController(rootView: AnyView(paymentView))
            hostingVC.modalPresentationStyle = .pageSheet
            self.present(hostingVC, animated: true)
        }

        // Stream detail: Wallet Receive (fund the Coinos wallet)
        morphingModal.onStreamDetailWalletReceive = { [weak self] in
            guard let self = self,
                  let wallet = AppCoordinator.shared.appState.wallet else { return }
            let receiveView = ReceiveView(walletModel: wallet)
            let hostingVC = UIHostingController(rootView: AnyView(receiveView))
            hostingVC.modalPresentationStyle = .pageSheet
            self.present(hostingVC, animated: true)
        }

        // Stream detail: Stream Settings button
        morphingModal.onStreamDetailSettings = { [weak self] in
            guard let self = self else { return }
            self.morphingGlassModal?.dismiss()
            self.morphingGlassModal?.expandedControls.showButtonGrid()
            self.morphingGlassModal?.onSettingsTapped?(self.view)
        }

        // Stream detail: Refresh balance
        morphingModal.onStreamDetailRefreshBalance = { [weak self] in
            self?.model?.refreshZapStreamCoreBalance { [weak self] in
                guard let self else { return }
                let data = self.buildStreamDetailData()
                self.morphingGlassModal?.expandedControls.reconfigureStreamDetail(data: data)
                self.model?.refreshWalletBalanceIfNeeded(force: true)
            }
            // Wallet balance refresh — force reload even if already loaded
            if let model = self?.model, model.zapStreamCoreHasNwc {
                model.refreshWalletBalanceIfNeeded(force: true)
            }
        }

        // Stream detail: Update Stream (push metadata to server while live)
        morphingModal.onStreamDetailUpdateStream = { [weak self] in
            self?.model?.updateZapStreamCoreMetadata()
        }

        // Stream detail: Disable auto-topup
        morphingModal.onStreamDetailAutoTopupDisable = { [weak self] in
            guard let self = self, let model = self.model,
                  let appState = model.appState else { return }
            let config = ZapStreamCoreConfig(baseUrl: model.stream.zapStreamCoreBaseUrl)
            let client = ZapStreamCoreApiClient(config: config)
            var cancellable: AnyCancellable?
            cancellable = client.updateAccount(appState: appState, removeNwc: true)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { _ in
                    _ = cancellable // prevent dealloc
                }, receiveValue: { [weak self] _ in
                    model.zapStreamCoreHasNwc = false
                    model.refreshZapStreamCoreBalance()
                    let hasWallet: Bool = {
                        if let wallet = AppCoordinator.shared.appState.wallet,
                           case .existing = wallet.connect_state { return true }
                        return false
                    }()
                    self?.morphingGlassModal?.expandedControls.updateStreamDetailAutoTopupState(
                        hasNwc: false, hasWallet: hasWallet
                    )
                })
        }

        // Stream detail: Enable auto-topup
        morphingModal.onStreamDetailAutoTopupEnable = { [weak self] in
            guard let self = self, let model = self.model,
                  let appState = model.appState,
                  let wallet = appState.wallet,
                  case .existing(let nwc) = wallet.connect_state else {
                self?.morphingGlassModal?.expandedControls.endStreamDetailAutoTopupLoading()
                return
            }
            let nwcUri = nwc.to_url().absoluteString
            let config = ZapStreamCoreConfig(baseUrl: model.stream.zapStreamCoreBaseUrl)
            let client = ZapStreamCoreApiClient(config: config)
            var cancellable: AnyCancellable?
            cancellable = client.updateAccount(appState: appState, nwcUri: nwcUri)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    _ = cancellable
                    if case .failure = completion {
                        self?.morphingGlassModal?.expandedControls.endStreamDetailAutoTopupLoading()
                    }
                }, receiveValue: { [weak self] _ in
                    model.zapStreamCoreHasNwc = true
                    model.refreshZapStreamCoreBalance()
                    let hasWallet: Bool = {
                        if let wallet = AppCoordinator.shared.appState.wallet,
                           case .existing = wallet.connect_state { return true }
                        return false
                    }()
                    self?.morphingGlassModal?.expandedControls.updateStreamDetailAutoTopupState(
                        hasNwc: true, hasWallet: hasWallet
                    )
                })
        }

        // Stream detail: Metadata edit callbacks
        morphingModal.onStreamDetailTitleChanged = { [weak self] title in
            self?.model?.stream.zapStreamCoreStreamTitle = title
        }
        morphingModal.onStreamDetailDescriptionChanged = { [weak self] desc in
            self?.model?.stream.zapStreamCoreStreamDescription = desc
        }
        morphingModal.onStreamDetailTagsChanged = { [weak self] tags in
            guard let self = self, let model = self.model else { return }
            // Preserve the existing game ID when user edits tags in the modal
            let existingParsed = CategoryTagsHelper.parse(tags: model.stream.zapStreamCoreStreamTags)
            let newPlainTags = tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // Re-parse the new plain tags to extract any category
            let newParsed = CategoryTagsHelper.parse(tags: newPlainTags)
            // Combine: use new category + preserve old game ID + new additional tags
            model.stream.zapStreamCoreStreamTags = CategoryTagsHelper.combine(
                category: newParsed.category,
                gameId: existingParsed.gameId,
                additionalTags: newParsed.additionalTags
            )
        }
        morphingModal.onStreamDetailNSFWChanged = { [weak self] isNSFW in
            self?.model?.stream.zapStreamCoreContentWarning = isNSFW ? "nsfw" : ""
        }
        morphingModal.onStreamDetailPublicChanged = { [weak self] isPublic in
            self?.model?.stream.zapStreamCoreIsPublic = isPublic
        }
        morphingModal.onStreamDetailProtocolChanged = { [weak self] index in
            self?.model?.stream.zapStreamCorePreferredProtocol = index == 0 ? .rtmp : .srt
        }

        // Stream detail: sub-page navigation
        morphingModal.expandedControls.onStreamDetailStreamDetailsTapped = { [weak self] in
            self?.morphingGlassModal?.showInlineContent(.streamMetadata)
        }
        morphingModal.expandedControls.onStreamDetailVideoTapped = { [weak self] in
            self?.morphingGlassModal?.showInlineContent(.streamVideo)
        }
        morphingModal.expandedControls.onStreamDetailAudioTapped = { [weak self] in
            self?.morphingGlassModal?.showInlineContent(.streamAudio)
        }

        // Stream detail: video settings
        morphingModal.onStreamDetailResolutionChanged = { [weak self] index in
            guard let model = self?.model, !model.isLive, !model.isRecording else { return }
            model.stream.resolution = resolutions[index]
            model.reloadStreamIfEnabled(stream: model.stream)
        }
        morphingModal.onStreamDetailFpsChanged = { [weak self] index in
            guard let model = self?.model, !model.isLive, !model.isRecording else { return }
            model.stream.fps = fpss[index]
            model.reloadStreamIfEnabled(stream: model.stream)
        }
        morphingModal.onStreamDetailAdaptiveResolutionChanged = { [weak self] enabled in
            guard let model = self?.model, !model.isLive else { return }
            model.stream.adaptiveEncoderResolution = enabled
            model.reloadStreamIfEnabled(stream: model.stream)
        }
        morphingModal.onStreamDetailLowLightBoostChanged = { [weak self] enabled in
            guard let model = self?.model else { return }
            model.stream.autoFps = enabled
            model.setStreamFps()
        }

        // Stream detail: audio settings
        morphingModal.onStreamDetailAudioBitrateChanged = { [weak self] kbps in
            guard let model = self?.model, !model.isLive else { return }
            model.stream.audioBitrate = kbps * 1000
            if model.stream.enabled { model.setAudioStreamBitrate(stream: model.stream) }
        }

        // Stream detail: inline toggles
        morphingModal.onStreamDetailPortraitToggled = { [weak self] isPortrait in
            guard let model = self?.model, !model.isLive, !model.isRecording else { return }
            model.stream.portrait = isPortrait
            if model.stream.enabled {
                model.setCurrentStream(stream: model.stream)
                model.reloadStream()
                model.resetSelectedScene(changeScene: false)
                model.updateOrientation()
                model.updateOrientationLock()
            }
            // Sync pill button state with effective orientation
            self?.morphingGlassModal?.expandedControls.portraitPill.isActive = model.database.portrait
        }
        morphingModal.onStreamDetailBackgroundStreamingChanged = { [weak self] enabled in
            self?.model?.stream.backgroundStreaming = enabled
        }
        morphingModal.onStreamDetailAutoRecordChanged = { [weak self] enabled in
            self?.model?.stream.recording.autoStartRecording = enabled
            self?.model?.stream.recording.autoStopRecording = enabled
        }

        // Mic card — show inline mic picker
        morphingModal.onMicCardTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            let mics = model.database.mics.mics.map { mic in
                InlineMicPickerView.MicItem(
                    id: mic.id,
                    name: mic.name,
                    isConnected: mic.connected
                )
            }
            let currentMicId = model.mic.current.id
            self.morphingGlassModal?.expandedControls.pendingMicItems = mics
            self.morphingGlassModal?.expandedControls.pendingSelectedMicId = currentMicId
            self.morphingGlassModal?.showInlineContent(.micPicker)
        }

        // Mic selected from inline picker
        morphingModal.onMicSelected = { [weak self] micId in
            guard let model = self?.model else { return }
            model.manualSelectMicById(id: micId)
        }

        // Scene button — show inline scene view
        morphingModal.onSceneButtonTapped = { [weak self] in
            guard let self = self, let model = self.model,
                  let scene = model.getSelectedScene() else { return }
            let widgets = model.widgetsInCurrentScene(onlyEnabled: false)
            let sceneData = InlineSceneView.SceneData(
                name: scene.name,
                cameraName: model.getCameraPositionName(scene: scene),
                micOverrideEnabled: scene.overrideMic,
                micName: scene.overrideMic
                    ? (model.getMicById(id: scene.micId)?.name ?? "Unknown")
                    : "Default",
                widgets: widgets.map { w in
                    (id: w.widget.id, name: w.widget.name,
                     type: w.widget.type.toString(), enabled: w.widget.enabled)
                }
            )
            self.morphingGlassModal?.expandedControls.pendingSceneData = sceneData
            self.morphingGlassModal?.showInlineContent(.scene)
        }

        // Scene widget toggle
        morphingModal.onSceneWidgetToggled = { [weak self] id, enabled in
            guard let self = self, let model = self.model else { return }
            guard let widget = model.findWidget(id: id) else { return }
            widget.enabled = enabled
            model.reloadSpeechToText()
            model.sceneUpdated(attachCamera: model.isCaptureDeviceWidget(widget: widget))
        }

        // Scene add widget
        morphingModal.onSceneAddWidgetTapped = { [weak self] in
            self?.morphingGlassModal?.showInlineContent(.addWidget)
        }

        // Scene camera tapped — show camera picker
        morphingModal.onSceneCameraTapped = { [weak self] in
            guard let self = self, let model = self.model,
                  let scene = model.getSelectedScene() else { return }
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            let selectedId = model.getCameraPositionId(scene: scene)
            self.morphingGlassModal?.expandedControls.pendingSceneCameraItems = cameras.map {
                InlineMicPickerView.MicItem(id: $0.0, name: $0.1, isConnected: true)
            }
            self.morphingGlassModal?.expandedControls.pendingSelectedSceneCameraId = selectedId
            self.morphingGlassModal?.showInlineContent(.sceneCameraPicker)
        }

        // Scene camera selected from picker
        morphingModal.onSceneCameraSelected = { [weak self] cameraId in
            guard let self = self, let model = self.model,
                  let scene = model.getSelectedScene() else { return }
            scene.updateCameraId(settingsCameraId: model.cameraIdToSettingsCameraId(cameraId: cameraId))
            model.sceneUpdated(attachCamera: true, updateRemoteScene: false)
            self.refreshPendingSceneData()
        }

        // Scene mic tapped — show mic picker
        morphingModal.onSceneMicTapped = { [weak self] in
            guard let self = self, let model = self.model,
                  let scene = model.getSelectedScene() else { return }
            let mics = model.database.mics.mics.map { mic in
                InlineMicPickerView.MicItem(
                    id: mic.id,
                    name: mic.name,
                    isConnected: mic.connected
                )
            }
            let selectedId = scene.overrideMic ? scene.micId : (model.mic.current.id)
            self.morphingGlassModal?.expandedControls.pendingSceneMicItems = mics
            self.morphingGlassModal?.expandedControls.pendingSelectedSceneMicId = selectedId
            self.morphingGlassModal?.showInlineContent(.sceneMicPicker)
        }

        // Scene mic selected from picker
        morphingModal.onSceneMicSelected = { [weak self] micId in
            guard let self = self, let model = self.model,
                  let scene = model.getSelectedScene() else { return }
            scene.overrideMic = true
            scene.micId = micId
            if model.getSelectedScene() === scene {
                model.switchMicIfNeededAfterSceneSwitch()
            }
            self.refreshPendingSceneData()
        }

        // Scene add scene tapped — show create scene view
        morphingModal.onSceneAddSceneTapped = { [weak self] in
            guard let self = self, let model = self.model else { return }
            // Populate pendingSceneData so back-navigation from createScene to scene view works
            self.refreshPendingSceneData()
            let defaultName = makeUniqueName(
                name: SettingsScene.baseName,
                existingNames: model.database.scenes
            )
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            let selectedCameraId: String
            if let scene = model.getSelectedScene() {
                selectedCameraId = model.getCameraPositionId(scene: scene)
            } else {
                selectedCameraId = cameras.first?.0 ?? ""
            }
            self.morphingGlassModal?.expandedControls.pendingCreateSceneDefaultName = defaultName
            self.morphingGlassModal?.expandedControls.pendingCreateSceneCameras = cameras.map {
                (id: $0.0, name: $0.1)
            }
            self.morphingGlassModal?.expandedControls.pendingCreateSceneSelectedCameraId = selectedCameraId
            self.morphingGlassModal?.showInlineContent(.createScene)
        }

        // Scene renamed inline
        morphingModal.onSceneRenamed = { [weak self] newName in
            guard let self = self, let model = self.model,
                  let scene = model.getSelectedScene() else { return }
            scene.name = newName
            model.sceneUpdated(updateRemoteScene: false)
            model.store()
            self.updateScenes()
            self.refreshPendingSceneData()
        }

        // Create scene confirmed
        morphingModal.onCreateScene = { [weak self] name, cameraId in
            guard let self = self, let model = self.model else { return }
            let sceneName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? makeUniqueName(name: SettingsScene.baseName, existingNames: model.database.scenes)
                : name.trimmingCharacters(in: .whitespacesAndNewlines)
            let scene = SettingsScene(name: sceneName)
            scene.updateCameraId(settingsCameraId: model.cameraIdToSettingsCameraId(cameraId: cameraId))
            model.database.scenes.append(scene)
            model.selectScene(id: scene.id)
            self.updateScenes()
            self.refreshPendingSceneData()
            self.morphingGlassModal?.showInlineContent(.scene)
        }

        // Create scene full config — open Settings
        morphingModal.onCreateSceneFullConfig = { [weak self] in
            guard let self = self else { return }
            self.morphingGlassModal?.dismiss()
            self.morphingGlassModal?.expandedControls.showButtonGrid()
            self.morphingGlassModal?.onSettingsTapped?(self.view)
        }

        // Refresh all button states when modal starts expanding
        // Note: We do NOT resize the control bar here. The ExpandableControlBarView's
        // hitTest override already delivers touches to the modal even when it extends
        // beyond the container's bounds. Resizing the control bar triggers a full layout
        // pass that causes the UIHostingController (stream preview) to shift upward.
        morphingModal.onExpandStarted = { [weak self] in
            guard let self = self else { return }
            self.updateExpandedButtonStates()
        }
        
        // Handle scene selection
        morphingModal.onSceneSelected = { [weak self] index in
            guard let self = self, let model = self.model else { return }
            if index < model.enabledScenes.count {
                model.sceneSelector.sceneIndex = index
                model.selectScene(id: model.enabledScenes[index].id)
            }
        }
        
        // Handle settings button tap - present with iOS 18 zoom transition
        // Settings VC is kept alive to preserve navigation state between opens
        morphingModal.onSettingsTapped = { [weak self] sourceView in
            guard let self = self, let model = self.model else { return }
            
            // Create settings VC once and reuse it
            if self.settingsHostingController == nil {
                let settingsView = SettingsRootView(onDismiss: { [weak self] in
                    self?.dismiss(animated: true)
                })
                .environmentObject(model)
                .environmentObject(AppCoordinator.shared.appState)
                
                // Wrap in AnyView to store as property
                let wrappedView = AnyView(settingsView)
                self.settingsHostingController = UIHostingController(rootView: wrappedView)
            }
            
            guard let settingsVC = self.settingsHostingController else { return }
            settingsVC.modalPresentationStyle = .fullScreen
            
            // iOS 18 zoom transition from the settings button
            if #available(iOS 18.0, *) {
                settingsVC.preferredTransition = .zoom(sourceViewProvider: { [weak sourceView] _ in
                    return sourceView ?? self.view
                })
            }
            
            self.present(settingsVC, animated: true)
        }
        
        // Handle modal state changes - enable/disable dismiss tap
        // No control bar height animation needed — ExpandableControlBarView.hitTest
        // handles touches for the expanded modal at the original collapsed height.
        morphingModal.onModalStateChanged = { [weak self] isExpanded in
            guard let self = self else { return }
            self.dismissTapView.isUserInteractionEnabled = isExpanded

            // When expanding, only auto-show for incoming invites (user needs to accept/decline).
            // For active calls, the user can tap the collab pill to see controls.
            if isExpanded, let model = self.model {
                if case .inviteReceived(_, _, let title) = model.collabCallState {
                    self.morphingGlassModal?.expandedControls.configureCollabIncoming(streamTitle: title)
                    self.morphingGlassModal?.showInlineContent(.collabIncoming)
                }
            }
        }
        
        // Update live button state based on model
        morphingModal.setLiveActive(model.isLive)
        
        // Entry animation
        morphingModal.transform = CGAffineTransform(translationX: 0, y: 30)
        morphingModal.alpha = 0
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.9, options: [.curveEaseOut]) {
            morphingModal.transform = .identity
            morphingModal.alpha = 1.0
        }
        
        // Store reference for state updates
        self.morphingGlassModal = morphingModal
        
        // Now that isStreamConfigured callback is wired, refresh onboarding state
        // (setup() ran before the callback existed, so it defaulted to configured=true)
        morphingModal.updateOnboardingState()
        
        // Discoverability: bounce the pill after entry animation settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.morphingGlassModal?.playDiscoveryBounce()
        }
        
        // Stream overlay
        if let orientation = orientation {
            let streamOverlayVC = StreamOverlayViewController(model: model, orientation: orientation)
            addChild(streamOverlayVC)
            overlayContainer.addSubview(streamOverlayVC.view)
            streamOverlayVC.view.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                streamOverlayVC.view.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
                streamOverlayVC.view.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
                streamOverlayVC.view.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor),
                streamOverlayVC.view.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor),
            ])
            
            streamOverlayVC.didMove(toParent: self)
            self.streamOverlayVC = streamOverlayVC
        }

        // Collab call UI is now handled entirely by the MorphingGlassModal inline content system.
    }
    
    // MARK: - Layout
    
    private func updateLayoutForOrientation() {
        guard let model = model else { return }
        let isPortrait = model.orientation.isPortrait
        
        // Deactivate current landscape constraints (they're rebuilt each time)
        NSLayoutConstraint.deactivate(landscapeConstraints)
        
        if isPortrait {
            NSLayoutConstraint.deactivate(landscapeConstraints)
            NSLayoutConstraint.activate(portraitConstraints)
        } else {
            NSLayoutConstraint.deactivate(portraitConstraints)
            
            // Build landscape constraints based on device orientation.
            // The control bar goes on the side AWAY from the Dynamic Island
            // (the physical bottom of the phone).
            // landscapeLeft = home button on right → Dynamic Island on left → control bar on RIGHT (trailing)
            // landscapeRight = home button on left → Dynamic Island on right → control bar on LEFT (leading)
            let controlBarOnTrailing = UIDevice.current.orientation != .landscapeRight
            
            if controlBarOnTrailing {
                // Control bar on RIGHT side (landscapeLeft — Dynamic Island on left)
                landscapeConstraints = [
                    cameraPreviewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    cameraPreviewContainer.trailingAnchor.constraint(equalTo: controlBarContainer.leadingAnchor),
                    cameraPreviewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    controlBarContainer.topAnchor.constraint(equalTo: view.topAnchor),
                    controlBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    controlBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    controlBarWidthConstraint,
                    overlayContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    overlayContainer.trailingAnchor.constraint(equalTo: controlBarContainer.leadingAnchor),
                    overlayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ]
            } else {
                // Control bar on LEFT side (landscapeRight — Dynamic Island on right)
                landscapeConstraints = [
                    cameraPreviewContainer.leadingAnchor.constraint(equalTo: controlBarContainer.trailingAnchor),
                    cameraPreviewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    cameraPreviewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    controlBarContainer.topAnchor.constraint(equalTo: view.topAnchor),
                    controlBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    controlBarContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    controlBarWidthConstraint,
                    overlayContainer.leadingAnchor.constraint(equalTo: controlBarContainer.trailingAnchor),
                    overlayContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    overlayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                ]
            }
            
            NSLayoutConstraint.activate(landscapeConstraints)
        }
        
        // Update aspect ratio (only recreate if ratio changed)
        if let hcView = streamHostingController?.view {
            let ratio = model.stream.dimensions().aspectRatio()
            let clampedRatio = max(0.1, min(10.0, ratio))
            if aspectRatioConstraint?.multiplier != CGFloat(clampedRatio) {
                aspectRatioConstraint?.isActive = false
                let ar = hcView.widthAnchor.constraint(
                    equalTo: hcView.heightAnchor,
                    multiplier: clampedRatio
                )
                ar.priority = .required
                ar.isActive = true
                aspectRatioConstraint = ar
            }
        }
        
        // Tell MorphingGlassModal about orientation and control bar side
        let controlBarOnLeading = !isPortrait && UIDevice.current.orientation == .landscapeRight
        morphingGlassModal?.controlBarOnLeading = controlBarOnLeading
        morphingGlassModal?.isLandscape = !isPortrait
        
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let model = model else { return }
        
        switch gesture.state {
        case .changed:
            model.changeZoomX(amount: Float(gesture.scale))
        case .ended:
            model.commitZoomX(amount: Float(gesture.scale))
        default:
            break
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // First check if modal is expanded - if so, dismiss it
        if let modal = morphingGlassModal, modal.isExpanded {
            modal.dismiss()
            return
        }
        
        // Otherwise, handle tap to focus
        guard let model = model, model.database.tapToFocus else { return }
        
        // Use the actual video view for coordinate normalization, not the container.
        // The container can be larger than the video (black bars around the preview).
        guard let videoView = streamHostingController?.view else { return }
        
        let location = gesture.location(in: videoView)
        let videoBounds = videoView.bounds
        
        // Reject taps outside the video area
        guard videoBounds.contains(location) else { return }
        
        let x = (location.x / videoBounds.width).clamped(to: 0...1)
        let y = (location.y / videoBounds.height).clamped(to: 0...1)
        
        model.setFocusPointOfInterest(focusPoint: CGPoint(x: x, y: y))
        focusIndicatorView.show(at: CGPoint(x: x, y: y), in: videoBounds.size)
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard let model = model, model.database.tapToFocus else { return }
        
        model.setAutoFocus()
    }
    
    @objc private func handleDismissTap(_ gesture: UITapGestureRecognizer) {
        // Dismiss the modal when tapping outside of it
        morphingGlassModal?.dismiss()
    }
    
    // MARK: - Expanded Controls Helpers
    
    /// Resolution options shown in the quality picker
    private var resolutionOptions: [(label: String, resolution: SettingsStreamResolution)] {
        return [
            ("4K", .r3840x2160),
            ("1080P", .r1920x1080),
            ("720P", .r1280x720),
            ("480P", .r854x480),
        ]
    }

    /// Rebuild pendingSceneData so the scene view reflects the latest camera/mic values
    /// Builds a fresh StreamDetailData snapshot from current model state.
    /// Called both on initial open and on every back-navigation to the hub page.
    private func buildStreamDetailData() -> InlineStreamDetailView.StreamDetailData {
        guard let model = model else {
            return InlineStreamDetailView.StreamDetailData(
                streamName: "", isZapStream: false, protocolString: "",
                resolution: "", rate: 0, balance: nil, isLive: false,
                uptime: "", bitrateMbps: "", bitrateColor: .white, viewerCount: "",
                streamTitle: "", streamDescription: "", streamTags: "",
                isNSFW: false, isPublic: true, preferredProtocol: 0,
                hasNwc: false, hasWallet: false, walletBalance: nil,
                resolutionIndex: 2, availableResolutions: [], fpsIndex: 4, availableFps: [],
                isAdaptiveResolution: false, isLowLightBoostAvailable: false,
                isLowLightBoostEnabled: false, audioBitrateKbps: 128,
                isPortrait: true, isBackgroundStreaming: false, isAutoRecord: false,
                isLiveOrRecording: false
            )
        }
        let isZap = model.stream.zapStreamCoreEnabled
        let parsedTags: String = {
            let parsed = CategoryTagsHelper.parse(tags: model.stream.zapStreamCoreStreamTags)
            var display: [String] = []
            if let cat = parsed.category { display.append(cat.matchTags[0]) }
            let extras = parsed.additionalTags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            display.append(contentsOf: extras)
            return display.joined(separator: ", ")
        }()
        let hasWallet: Bool = {
            if let wallet = AppCoordinator.shared.appState.wallet,
               case .existing = wallet.connect_state { return true }
            return false
        }()
        return InlineStreamDetailView.StreamDetailData(
            streamName: isZap
                ? (model.stream.zapStreamCoreStreamTitle.isEmpty
                    ? model.stream.name : model.stream.zapStreamCoreStreamTitle)
                : model.stream.name,
            isZapStream: isZap,
            protocolString: isZap ? "Zap Stream (RTMP)" : model.stream.protocolString(),
            resolution: model.stream.resolution.shortString(),
            rate: model.zapStreamCoreRate,
            balance: model.zapStreamCoreBalance,
            isLive: model.isLive,
            uptime: model.streamUptime.uptime,
            bitrateMbps: model.bitrate.speedMbpsOneDecimal,
            bitrateColor: UIColor(model.bitrate.statusColor),
            viewerCount: model.statusTopLeft.numberOfViewers,
            streamTitle: model.stream.zapStreamCoreStreamTitle,
            streamDescription: model.stream.zapStreamCoreStreamDescription,
            streamTags: parsedTags,
            isNSFW: !model.stream.zapStreamCoreContentWarning.isEmpty,
            isPublic: model.stream.zapStreamCoreIsPublic,
            preferredProtocol: model.stream.zapStreamCorePreferredProtocol == .rtmp ? 0 : 1,
            hasNwc: model.zapStreamCoreHasNwc,
            hasWallet: hasWallet,
            walletBalance: AppCoordinator.shared.appState.wallet?.balance,
            resolutionIndex: resolutions.firstIndex(of: model.stream.resolution) ?? 2,
            availableResolutions: resolutions.map { $0.shortString() },
            fpsIndex: fpss.firstIndex(of: model.stream.fps) ?? 4,
            availableFps: fpss.map { String($0) },
            isAdaptiveResolution: model.stream.adaptiveEncoderResolution,
            isLowLightBoostAvailable: {
                if #available(iOS 18, *) { return true }
                return false
            }(),
            isLowLightBoostEnabled: model.stream.autoFps,
            audioBitrateKbps: model.stream.audioBitrate / 1000,
            isPortrait: model.stream.portrait,
            isBackgroundStreaming: model.stream.backgroundStreaming,
            isAutoRecord: model.stream.recording.autoStartRecording,
            isLiveOrRecording: model.isLive || model.isRecording
        )
    }

    private func refreshPendingSceneData() {
        guard let model = model, let scene = model.getSelectedScene() else { return }
        let widgets = model.widgetsInCurrentScene(onlyEnabled: false)
        let sceneData = InlineSceneView.SceneData(
            name: scene.name,
            cameraName: model.getCameraPositionName(scene: scene),
            micOverrideEnabled: scene.overrideMic,
            micName: scene.overrideMic
                ? (model.getMicById(id: scene.micId)?.name ?? "Unknown")
                : "Default",
            widgets: widgets.map { w in
                (id: w.widget.id, name: w.widget.name,
                 type: w.widget.type.toString(), enabled: w.widget.enabled)
            }
        )
        morphingGlassModal?.expandedControls.pendingSceneData = sceneData
    }
    
    /// Refresh all button states when modal expands
    private func updateExpandedButtonStates() {
        guard let model = model else { return }
        let currentRes = model.stream.resolution
        let qualityTitle = currentRes.shortString()
        let locked = model.isLive || model.isRecording
        let configured = model.isStreamConfigured()
        let isZap = model.stream.zapStreamCoreEnabled

        // Current LUT name
        let luts = model.allLuts()
        let activeLut = luts.first(where: { $0.enabled == true })
        let lutName = activeLut?.name

        // Current mic name
        let micName = model.mic.current.name.isEmpty ? "Default" : model.mic.current.name

        // Live stats
        let uptime = model.streamUptime.uptime
        let bitrateMbps = model.bitrate.speedMbpsOneDecimal
        let bitrateColor = UIColor(model.bitrate.statusColor)
        let viewerCount = model.statusTopLeft.numberOfViewers

        morphingGlassModal?.updateAllStates(
            flash: model.streamOverlay.isTorchOn,
            live: model.isLive,
            mute: model.isMuteOn,
            record: model.isRecording,
            exposure: model.camera.bias != 0,
            styles: model.hasEnabledLUTs(),
            nightMode: model.getGlobalToneMappingOn() || model.stream.autoFps,
            qualityTitle: qualityTitle,
            isLiveOrRecording: locked,
            isStreamConfigured: configured,
            streamName: model.stream.zapStreamCoreEnabled
                ? (model.stream.zapStreamCoreStreamTitle.isEmpty
                    ? model.stream.name
                    : model.stream.zapStreamCoreStreamTitle)
                : model.stream.name,
            resolution: qualityTitle,
            isZapStream: isZap,
            uptime: uptime,
            bitrateMbps: bitrateMbps,
            bitrateColor: bitrateColor,
            viewerCount: viewerCount,
            currentLutName: lutName,
            exposureBias: model.camera.bias,
            currentMicName: micName,
            balance: model.zapStreamCoreBalance,
            rate: model.zapStreamCoreRate,
            protocolString: isZap ? "ZAP STREAM" : model.stream.protocolString(),
            stabilizationMode: model.database.videoStabilizationMode.toString(),
            bitrateTitle: formatBytesPerSecond(speed: Int64(model.stream.bitrate))
        )
        
        // Portrait pill state
        morphingGlassModal?.expandedControls.portraitPill.isActive = model.database.portrait
    }

    /// Lightweight Zone 3-only update. Safe to call every second.
    /// Cost: ~10 property reads + label text assignments. No animations, no allocations.
    private func updateStatusBarOnly() {
        guard let model = model else { return }
        guard morphingGlassModal?.isExpanded == true else { return }

        let isZap = model.stream.zapStreamCoreEnabled
        morphingGlassModal?.updateStatusBar(
            isStreamConfigured: model.isStreamConfigured(),
            isLive: model.isLive,
            streamName: isZap
                ? (model.stream.zapStreamCoreStreamTitle.isEmpty
                    ? model.stream.name : model.stream.zapStreamCoreStreamTitle)
                : model.stream.name,
            resolution: model.stream.resolution.shortString(),
            isZapStream: isZap,
            uptime: model.streamUptime.uptime,
            bitrateMbps: model.bitrate.speedMbpsOneDecimal,
            bitrateColor: UIColor(model.bitrate.statusColor),
            viewerCount: model.statusTopLeft.numberOfViewers,
            balance: model.zapStreamCoreBalance,
            rate: model.zapStreamCoreRate,
            protocolString: isZap ? "ZAP STREAM" : model.stream.protocolString()
        )
    }
    
    /// Toggle night mode (global tone mapping + low light boost)
    private func toggleNightMode(model: Model) {
        let isCurrentlyOn = model.getGlobalToneMappingOn() || model.stream.autoFps
        let newState = !isCurrentlyOn
        
        // Toggle global tone mapping
        model.setGlobalToneMapping(on: newState)
        
        // Toggle low light boost
        model.stream.autoFps = newState
        model.setStreamFps()
        
        // Update button state
        let actualState = model.getGlobalToneMappingOn() || model.stream.autoFps
        morphingGlassModal?.expandedControls.nightModePill.isActive = actualState
        
        // Toast feedback
        if actualState {
            model.makeToast(title: String(localized: "Night mode on"))
        } else {
            model.makeToast(title: String(localized: "Night mode off"))
        }
    }

    // MARK: - Present Invite Guest Sheet

    /// Builds the follow item list for the collab invite view off the main thread.
    /// Snapshots followedPubkeys and metadataEvents on the main actor, then does
    /// the O(N log N) sort + map + bech32 encoding on a background thread (Fix 1 + Fix 6).
    @MainActor
    private static func buildCollabFollowItems(appState: AppState) async -> [InlineCollabInviteView.FollowItem] {
        // Snapshot on main actor — both properties are @Published and main-thread-owned
        let pubkeys = Array(appState.followedPubkeys).sorted()
        let metadataSnapshot = appState.metadataEvents

        // Move the heavy work (bech32 encoding, string ops) off the main thread
        return await Task.detached(priority: .userInitiated) {
            pubkeys.map { pubkey -> InlineCollabInviteView.FollowItem in
                let meta = metadataSnapshot[pubkey]?.userMetadata
                let displayName = meta?.displayName ?? meta?.name ?? ""
                let username = meta?.name
                let nip05 = meta?.nostrAddress
                var nip05Domain: String?
                if let nip05 {
                    let parts = nip05.split(separator: "@")
                    nip05Domain = parts.count == 2 ? String(parts[1]) : nip05
                }
                // Pre-compute truncated npub so the cell never does bech32 work at render time
                let truncatedNpub: String
                if let pk = NostrSDK.PublicKey(hex: pubkey) {
                    let npub = pk.npub
                    truncatedNpub = String(npub.prefix(10)) + "..." + String(npub.suffix(5))
                } else {
                    truncatedNpub = String(pubkey.prefix(8)) + "..."
                }
                return InlineCollabInviteView.FollowItem(
                    pubkey: pubkey,
                    displayName: displayName,
                    username: username,
                    pictureURL: meta?.pictureURL,
                    followersCount: 0,
                    nip05Domain: nip05Domain,
                    trustDot: "",
                    truncatedNpub: truncatedNpub
                )
            }
        }.value
    }

    private func updateCollabCallView() {
        guard let model = model else { return }
        let state: InlineCollabCallView.DisplayState
        switch model.collabCallState {
        case .connected: state = .connected
        case .connecting: state = .connecting
        case .inviteSent: state = .waiting
        default: state = .connected
        }
        morphingGlassModal?.expandedControls.configureCollabCall(
            state: state,
            isMuted: model.isMuteOn,
            sendWidgets: model.collabSendWidgets,
            skipPip: model.collabSkipPipForWebRTC,
            guestVolume: model.guestAudioVolume
        )
    }

    // MARK: - Present Stream Setup

    /// Presents StreamSetupView directly from UIKit, wrapped in NavigationStack
    /// with proper environment objects. Used by Zone 3 CTA and Go Live button.
    func presentStreamSetup(sourceView: UIView) {
        guard let model = model else { return }

        let setupView = NavigationStack {
            StreamSetupView()
        }
        .environmentObject(model)
        .environmentObject(AppCoordinator.shared.appState)
        .environment(\.settingsDismiss) { [weak self] in
            self?.dismiss(animated: true)
        }

        let hostingVC = UIHostingController(rootView: AnyView(setupView))
        hostingVC.modalPresentationStyle = .fullScreen

        if #available(iOS 18.0, *) {
            hostingVC.preferredTransition = .zoom(sourceViewProvider: { [weak sourceView] _ in
                return sourceView ?? UIView()
            })
        }

        self.present(hostingVC, animated: true)
    }

    // MARK: - Present Pre-Stream Review Sheet

    /// Presents the pre-stream review sheet before going live.
    /// Lets the user review/edit metadata, then triggers the countdown.
    private func presentPreStreamSheet() {
        guard let model = model else { return }

        let sourceView: UIView = self.morphingGlassModal?.flipGlass ?? self.view

        let sheet = NavigationStack {
            PreStreamSheet(
                stream: model.stream,
                skipReview: model.database.skipPreStreamReview,
                onGoLive: { [weak self] in
                    self?.morphingGlassModal?.startCountdown()
                }
            )
        }
        .environmentObject(model)
        .environmentObject(AppCoordinator.shared.appState)

        let hostingVC = UIHostingController(rootView: AnyView(sheet))
        hostingVC.modalPresentationStyle = .fullScreen

        if #available(iOS 18.0, *) {
            hostingVC.preferredTransition = .zoom(sourceViewProvider: { [weak sourceView] _ in
                return sourceView ?? UIView()
            })
        }

        self.present(hostingVC, animated: true)
    }
    
    /// Called when user taps a widget type in the InlineAddWidgetView grid.
    /// Creates the widget + scene placement, refreshes the pipeline, then routes
    /// to the appropriate post-creation flow based on widget type.
    private func handleWidgetTypeSelected(_ type: SettingsWidgetType) {
        guard let model = model, let scene = model.getSelectedScene() else { return }
        
        // Clear any stale editing state from a previous edit-config flow
        editingWidgetId = nil
        
        // 1. Create the global widget definition
        let name = makeUniqueName(name: type.toString(), existingNames: model.database.widgets)
        let widget = SettingsWidget(name: name)
        widget.type = type
        model.database.widgets.append(widget)
        
        // 2. Create the scene placement with smart defaults
        let sceneWidget = createDefaultSceneWidget(for: widget)
        scene.widgets.append(sceneWidget)
        
        // 3. Type-specific setup
        if type == .alerts {
            model.fixAlertMedias()
        }
        
        // 3b. Map-specific: ensure location services are running
        if type == .map {
            model.locationManager.requestPermissionIfNeeded()
            if !model.database.location.enabled {
                model.database.location.enabled = true
                model.reloadLocation()
            }
        }
        
        // 4. Create only this widget's effect instance (avoids destroying all existing effects)
        model.addSingleWidgetEffect(widget: widget)
        
        // 4b. Persist immediately so the widget survives force-quit
        model.store()
        // 5. Store for quick config flow
        lastCreatedWidgetId = widget.id
        
        // 6. Route based on type
        switch type {
        case .alerts:
            // Complex nested config — keep as-is
            model.makeToast(title: "\(type.toString()) added")
            refreshAndShowWidgetList()

        case .browser:
            // Needs URL — show quick config
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .textField(
                    title: "Browser Widget",
                    placeholder: "https://",
                    keyboardType: .URL
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .qrCode:
            // Needs message — show quick config
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .textField(
                    title: "QR Code Widget",
                    placeholder: "Enter text or URL",
                    keyboardType: .default
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .text:
            // Show preset picker with common text format presets
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .presetPicker(
                    title: "Text Format",
                    presets: [
                        (name: "Time", icon: "clock", value: "{shortTime}"),
                        (name: "Timer", icon: "timer", value: "⏳ {timer}"),
                        (name: "Stopwatch", icon: "stopwatch", value: "⏱️ {stopwatch}"),
                        (name: "Travel", icon: "location.fill", value: "{countryFlag} {city}\n{speed} {altitude}"),
                        (name: "Weather", icon: "cloud.sun", value: "{conditions} {temperature}"),
                        (name: "Date", icon: "calendar", value: "📅 {date}"),
                        (name: "Debug", icon: "ant", value: "{bitrateAndTotal}\n{debugOverlay}"),
                    ]
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .videoSource:
            // Show camera source picker
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Camera Source",
                    options: cameras.map { (id: $0.0, name: $0.1) },
                    selectedId: model.getCameraPositionId(videoSourceWidget: widget.videoSource)
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .vTuber:
            // Show camera source picker
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "VTuber Camera",
                    options: cameras.map { (id: $0.0, name: $0.1) },
                    selectedId: model.getCameraPositionId(vTuberWidget: widget.vTuber)
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .pngTuber:
            // Show camera source picker
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "PNGTuber Camera",
                    options: cameras.map { (id: $0.0, name: $0.1) },
                    selectedId: model.getCameraPositionId(pngTuberWidget: widget.pngTuber)
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .scene:
            // Show scene picker
            let scenes = model.database.scenes.filter { $0.enabled }
            if scenes.isEmpty {
                model.makeToast(title: "No scenes available")
                refreshAndShowWidgetList()
            } else {
                morphingGlassModal?.expandedControls.configureQuickConfig(
                    mode: .picker(
                        title: "Scene Widget",
                        options: scenes.map { (id: $0.id.uuidString, name: $0.name) },
                        selectedId: scenes.first?.id.uuidString ?? ""
                    )
                )
                morphingGlassModal?.showInlineContent(.quickConfig)
            }

        case .crop:
            // Show browser widget picker (crop only works on browser widgets)
            let browserWidgets = model.database.widgets.filter { $0.type == .browser }
            if browserWidgets.isEmpty {
                model.makeToast(title: "Crop requires a Browser widget")
                refreshAndShowWidgetList()
            } else {
                morphingGlassModal?.expandedControls.configureQuickConfig(
                    mode: .picker(
                        title: "Crop Source",
                        options: browserWidgets.map { (id: $0.id.uuidString, name: $0.name) },
                        selectedId: browserWidgets.first?.id.uuidString ?? ""
                    )
                )
                morphingGlassModal?.showInlineContent(.quickConfig)
            }

        case .snapshot:
            // Show duration picker
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Snapshot Duration",
                    options: [
                        (id: "3", name: "3 seconds"),
                        (id: "5", name: "5 seconds"),
                        (id: "10", name: "10 seconds"),
                        (id: "15", name: "15 seconds"),
                        (id: "30", name: "30 seconds"),
                        (id: "60", name: "1 minute"),
                        (id: "120", name: "2 minutes"),
                    ],
                    selectedId: "5"
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .scoreboard:
            // Show game type picker
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Game Type",
                    options: [
                        (id: "singles", name: "Singles"),
                        (id: "doubles", name: "Doubles"),
                    ],
                    selectedId: "doubles"
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .map:
            // Show orientation picker
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Map Orientation",
                    options: [
                        (id: "direction", name: "Follow Direction"),
                        (id: "north", name: "North Up"),
                    ],
                    selectedId: "direction"
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .image:
            // Present photo picker immediately — the widget needs an image to be visible
            presentImagePicker()

        case .videoEffect:
            // Image needs PHPicker (Phase 4), videoEffect has no meaningful quick config
            model.makeToast(title: "\(type.toString()) added")
            refreshAndShowWidgetList()

        case .nostrChat:
            // Show style preset picker
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .presetPicker(
                    title: "Chat Style",
                    presets: nostrChatStylePresets(),
                    selectedValue: "transparent",
                    showCustomField: false
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .collabVideo:
            // Collab video is auto-created — no quick config needed
            model.makeToast(title: "Collab video widget")
            refreshAndShowWidgetList()
        }
    }
    
    /// Called when user taps a template in the InlineAddWidgetView templates row.
    /// Creates a fully pre-configured widget and adds it to the scene — no further config needed.
    private func handleTemplateSelected(_ template: InlineAddWidgetView.WidgetTemplate) {
        guard let model = model, let scene = model.getSelectedScene() else { return }
        
        // 1. Create the global widget definition
        let name = makeUniqueName(name: template.name, existingNames: model.database.widgets)
        let widget = SettingsWidget(name: name)
        widget.type = template.type
        
        // 2. Apply template-specific configuration
        template.configure(widget)
        
        model.database.widgets.append(widget)
        
        // 3. Create scene placement with template position or default centering
        let sceneWidget: SettingsSceneWidget
        if let pos = template.position {
            sceneWidget = SettingsSceneWidget(widgetId: widget.id)
            sceneWidget.x = pos.x
            sceneWidget.y = pos.y
            sceneWidget.width = pos.w
            sceneWidget.height = pos.h
        } else {
            sceneWidget = createDefaultSceneWidget(for: widget)
        }
        scene.widgets.append(sceneWidget)
        
        // 4. Type-specific setup
        if template.type == .alerts {
            model.fixAlertMedias()
        }
        
        // 5. Create only this widget's effect instance
        model.addSingleWidgetEffect(widget: widget)
        
        // 5b. Persist immediately so the widget survives force-quit
        model.store()
        // 6. Toast + back to widget list
        model.makeToast(title: "\(template.name) added")
        refreshAndShowWidgetList()
    }
    
    /// Called when user swipes left on a widget row to duplicate it.
    /// Copies both the SettingsWidget and SettingsSceneWidget, offsets position slightly.
    private func handleWidgetDuplicate(_ widgetId: UUID) {
        guard let model = model,
              let scene = model.getSelectedScene(),
              let sourceWidget = model.findWidget(id: widgetId),
              let sourceSceneWidget = scene.widgets.first(where: { $0.widgetId == widgetId }) else { return }
        
        // 1. Clone the widget definition via Codable round-trip
        guard let data = try? JSONEncoder().encode(sourceWidget),
              let newWidget = try? JSONDecoder().decode(SettingsWidget.self, from: data) else { return }
        // Give it a fresh identity
        newWidget.id = UUID()
        newWidget.name = makeUniqueName(name: sourceWidget.name, existingNames: model.database.widgets)
        model.database.widgets.append(newWidget)
        
        // 2. Clone the scene placement with a slight offset so they don't overlap
        let newSceneWidget = sourceSceneWidget.clone()
        newSceneWidget.id = UUID()
        newSceneWidget.widgetId = newWidget.id
        newSceneWidget.x = min(sourceSceneWidget.x + 5, 95)
        newSceneWidget.y = min(sourceSceneWidget.y + 5, 95)
        scene.widgets.append(newSceneWidget)
        
        // 3. Create the effect instance
        model.addSingleWidgetEffect(widget: newWidget)
        
        // 3b. Persist immediately
        model.store()
        
        // 4. Refresh the widget list
        model.makeToast(title: "Duplicated \(sourceWidget.name)")
        refreshAndShowWidgetList()
    }
    
    /// Called when user confirms widget deletion from the inline widget list.
    private func handleWidgetDelete(_ widgetId: UUID) {
        guard let model = model else { return }
        let name = model.findWidget(id: widgetId)?.name ?? "Widget"
        
        // 1. Remove from global widget list
        model.database.widgets.removeAll(where: { $0.id == widgetId })
        
        // 2. Clean up orphaned scene references
        model.removeDeadWidgetsFromScenes()
        
        // 3. Reload speech-to-text (not called by resetSelectedScene)
        model.reloadSpeechToText()
        
        // 4. Rebuild scene effects without changing the selected scene
        model.resetSelectedScene(changeScene: false)
        
        // 5. Persist immediately
        model.store()
        
        model.makeToast(title: "Deleted \(name)")
        // Note: the row removal animation is handled by InlineWidgetsView.
        // We don't call refreshAndShowWidgetList() here because the view
        // already removed the row visually. The next time the widget list
        // is shown (e.g. returning from positioning), it will re-read from model.
    }
    
    /// Called when user taps "Done" in the InlineQuickConfigView.
    private func handleQuickConfigDone(value: String) {
        guard let model = model else {
            refreshAndShowWidgetList()
            return
        }
        
        // Determine which widget we're configuring (editing takes priority)
        let widgetId: UUID
        let isEditing: Bool
        if let editId = editingWidgetId {
            widgetId = editId
            isEditing = true
            editingWidgetId = nil
        } else if let createId = lastCreatedWidgetId {
            widgetId = createId
            isEditing = false
            lastCreatedWidgetId = nil
        } else {
            refreshAndShowWidgetList()
            return
        }
        
        guard let widget = model.findWidget(id: widgetId) else {
            refreshAndShowWidgetList()
            return
        }
        
        // Apply the value based on widget type
        switch widget.type {
        case .browser:
            widget.browser.url = value
        case .qrCode:
            widget.qrCode.message = value
        case .text:
            widget.text.formatString = value
            let textEffect = model.getTextEffect(id: widgetId)
            textEffect?.setFormat(format: value)
            applyTextFormatDependencies(widget: widget, textEffect: textEffect, format: value)
        case .videoSource:
            widget.videoSource.updateCameraId(
                settingsCameraId: model.cameraIdToSettingsCameraId(cameraId: value)
            )
        case .vTuber:
            widget.vTuber.updateCameraId(
                settingsCameraId: model.cameraIdToSettingsCameraId(cameraId: value)
            )
        case .pngTuber:
            widget.pngTuber.updateCameraId(
                settingsCameraId: model.cameraIdToSettingsCameraId(cameraId: value)
            )
        case .scene:
            if let sceneId = UUID(uuidString: value) {
                widget.scene.sceneId = sceneId
            }
        case .crop:
            if let sourceId = UUID(uuidString: value) {
                widget.crop.sourceWidgetId = sourceId
            }
        case .snapshot:
            if let showtime = Int(value) {
                widget.snapshot.showtime = showtime
                model.getSnapshotEffect(id: widgetId)?.setSettings(showtime: showtime)
            }
        case .scoreboard:
            widget.scoreboard.padel.type = (value == "singles") ? .singles : .doubles
        case .map:
            widget.map.northUp = (value == "north")
        case .nostrChat:
            applyNostrChatStylePreset(value, to: widget.nostrChat)
            if let effect = model.getNostrChatEffect(id: widgetId) {
                effect.updateSettings(widget.nostrChat)
            }
        default:
            break
        }
        
        // Refresh the effect with the new config
        switch widget.type {
        case .browser:
            if let old = model.browserEffects[widgetId] {
                model.media.unregisterEffect(old)
                old.stop()
            }
            model.browserEffects.removeValue(forKey: widgetId)
            model.addSingleWidgetEffect(widget: widget)
        case .qrCode:
            if let old = model.qrCodeEffects[widgetId] {
                model.media.unregisterEffect(old)
            }
            model.qrCodeEffects.removeValue(forKey: widgetId)
            model.addSingleWidgetEffect(widget: widget)
        case .videoSource, .vTuber, .pngTuber:
            model.sceneUpdated(attachCamera: true)
        case .map:
            if let old = model.mapEffects[widgetId] {
                model.media.unregisterEffect(old)
            }
            model.mapEffects.removeValue(forKey: widgetId)
            model.addSingleWidgetEffect(widget: widget)
        default:
            model.sceneUpdated()
        }
        model.makeToast(title: isEditing ? "\(widget.name) updated" : "\(widget.type.toString()) configured")
        model.store()
        // For new nostr chat widgets, enter positioning mode instead of returning to widget list
        if !isEditing && widget.type == .nostrChat {
            enterWidgetPositioning(preselectWidgetId: widgetId)
        } else {
            refreshAndShowWidgetList()
        }
    }
    
    /// Applies text format dependency updates (timers, stopwatches, weather, etc.)
    /// Mirrors the logic in WidgetTextSettingsView.TextSelectionView.update().
    private func applyTextFormatDependencies(widget: SettingsWidget, textEffect: TextEffect?, format: String) {
        guard let model = model else { return }
        let parts = loadTextFormat(format: format)
        
        // Timers
        let numberOfTimers = parts.filter { if case .timer = $0 { return true }; return false }.count
        while widget.text.timers.count < numberOfTimers {
            widget.text.timers.append(.init())
        }
        while widget.text.timers.count > numberOfTimers {
            widget.text.timers.removeLast()
        }
        textEffect?.setTimersEndTime(endTimes: widget.text.timers.map {
            .now.advanced(by: .seconds(utcTimeDeltaFromNow(to: $0.endTime)))
        })
        
        // Stopwatches
        let numberOfStopwatches = parts.filter { if case .stopwatch = $0 { return true }; return false }.count
        while widget.text.stopwatches.count < numberOfStopwatches {
            widget.text.stopwatches.append(.init())
        }
        while widget.text.stopwatches.count > numberOfStopwatches {
            widget.text.stopwatches.removeLast()
        }
        
        // Checkboxes
        let numberOfCheckboxes = parts.filter { if case .checkbox = $0 { return true }; return false }.count
        while widget.text.checkboxes.count < numberOfCheckboxes {
            widget.text.checkboxes.append(.init())
        }
        while widget.text.checkboxes.count > numberOfCheckboxes {
            widget.text.checkboxes.removeLast()
        }
        textEffect?.setCheckboxes(checkboxes: widget.text.checkboxes.map { $0.checked })
        
        // Ratings
        let numberOfRatings = parts.filter { if case .rating = $0 { return true }; return false }.count
        while widget.text.ratings.count < numberOfRatings {
            widget.text.ratings.append(.init())
        }
        while widget.text.ratings.count > numberOfRatings {
            widget.text.ratings.removeLast()
        }
        textEffect?.setRatings(ratings: widget.text.ratings.map { $0.rating })
        
        // Lap times
        let numberOfLapTimes = parts.filter { if case .lapTimes = $0 { return true }; return false }.count
        while widget.text.lapTimes.count < numberOfLapTimes {
            widget.text.lapTimes.append(.init())
        }
        while widget.text.lapTimes.count > numberOfLapTimes {
            widget.text.lapTimes.removeLast()
        }
        textEffect?.setLapTimes(lapTimes: widget.text.lapTimes.map { $0.lapTimes })
        
        // Weather
        widget.text.needsWeather = !parts.filter { value in
            if case .conditions = value { return true }
            if case .temperature = value { return true }
            return false
        }.isEmpty
        model.startWeatherManager()
        
        // Geography
        widget.text.needsGeography = !parts.filter { value in
            if case .country = value { return true }
            if case .countryFlag = value { return true }
            if case .city = value { return true }
            return false
        }.isEmpty
        model.startGeographyManager()
        
        // G-Force
        widget.text.needsGForce = !parts.filter { value in
            if case .gForce = value { return true }
            if case .gForceRecentMax = value { return true }
            if case .gForceMax = value { return true }
            return false
        }.isEmpty
        model.startGForceManager()
        
        // Subtitles
        widget.text.needsSubtitles = !parts.filter { value in
            if case .subtitles = value { return true }
            return false
        }.isEmpty
        model.reloadSpeechToText()
    }
    
    /// Called when user taps "Full Config →" in the InlineQuickConfigView.
    private func handleQuickConfigFullSettings() {
        lastCreatedWidgetId = nil
        editingWidgetId = nil
        morphingGlassModal?.dismiss()
        morphingGlassModal?.expandedControls.showButtonGrid()
        morphingGlassModal?.onSettingsTapped?(self.view)
    }

    // MARK: - Nostr Chat Style Presets

    /// Returns the style presets shown in the quick config picker for nostr chat widgets.
    private func nostrChatStylePresets() -> [(name: String, icon: String, value: String?)] {
        return [
            (name: "Transparent", icon: "eye.slash", value: "transparent"),
            (name: "Dark", icon: "moon.fill", value: "dark"),
            (name: "Semi-transparent", icon: "circle.lefthalf.filled", value: "semitransparent"),
            (name: "Bubbles", icon: "bubble.left.and.bubble.right", value: "bubbles"),
            (name: "Compact", icon: "text.alignleft", value: "compact"),
            (name: "Big Text", icon: "textformat.size.larger", value: "bigtext"),
        ]
    }

    /// Applies a named style preset to the nostr chat settings.
    private func applyNostrChatStylePreset(_ preset: String, to settings: SettingsWidgetNostrChat) {
        switch preset {
        case "transparent":
            settings.backgroundColor = .init(red: 0, green: 0, blue: 0, opacity: 0.0)
            settings.cornerRadius = 0
            settings.textShadow = true
            settings.textShadowColor = .init(red: 0, green: 0, blue: 0, opacity: 0.8)
            settings.textShadowRadius = 2
            settings.perMessageBackground = false
            settings.fontSize = 24
        case "dark":
            settings.backgroundColor = .init(red: 0, green: 0, blue: 0, opacity: 0.7)
            settings.cornerRadius = 12
            settings.textShadow = false
            settings.perMessageBackground = false
            settings.fontSize = 24
        case "semitransparent":
            settings.backgroundColor = .init(red: 0, green: 0, blue: 0, opacity: 0.4)
            settings.cornerRadius = 8
            settings.textShadow = true
            settings.textShadowColor = .init(red: 0, green: 0, blue: 0, opacity: 0.6)
            settings.textShadowRadius = 1
            settings.perMessageBackground = false
            settings.fontSize = 24
        case "bubbles":
            settings.backgroundColor = .init(red: 0, green: 0, blue: 0, opacity: 0.0)
            settings.cornerRadius = 0
            settings.textShadow = false
            settings.perMessageBackground = true
            settings.perMessageBackgroundColor = .init(red: 30, green: 30, blue: 30, opacity: 0.7)
            settings.perMessageCornerRadius = 12
            settings.messagePadding = 8
            settings.fontSize = 22
        case "compact":
            settings.backgroundColor = .init(red: 0, green: 0, blue: 0, opacity: 0.0)
            settings.cornerRadius = 0
            settings.textShadow = true
            settings.textShadowColor = .init(red: 0, green: 0, blue: 0, opacity: 0.8)
            settings.textShadowRadius = 2
            settings.perMessageBackground = false
            settings.fontSize = 18
            settings.messageSpacing = 2
            settings.maxMessages = 50
        case "bigtext":
            settings.backgroundColor = .init(red: 0, green: 0, blue: 0, opacity: 0.0)
            settings.cornerRadius = 0
            settings.textShadow = true
            settings.textShadowColor = .init(red: 0, green: 0, blue: 0, opacity: 0.9)
            settings.textShadowRadius = 3
            settings.perMessageBackground = false
            settings.fontSize = 36
            settings.messageSpacing = 6
            settings.maxMessages = 15
        default:
            break
        }
    }

    /// Detects which style preset best matches the current nostr chat settings.
    private func detectNostrChatStyle(_ settings: SettingsWidgetNostrChat) -> String {
        if settings.perMessageBackground && settings.backgroundColor.opacity ?? 1.0 < 0.1 {
            return "bubbles"
        }
        let bgOpacity = settings.backgroundColor.opacity ?? 1.0
        if bgOpacity < 0.1 && settings.fontSize >= 32 {
            return "bigtext"
        }
        if bgOpacity < 0.1 && settings.fontSize <= 20 {
            return "compact"
        }
        if bgOpacity >= 0.6 {
            return "dark"
        }
        if bgOpacity > 0.1 && bgOpacity < 0.6 {
            return "semitransparent"
        }
        return "transparent"
    }
    
    // MARK: - Edit Existing Widget Quick Config
    
    /// Opens the quick config view for an existing widget, pre-filled with its current values.
    private func showQuickConfigForExistingWidget(widgetId: UUID) {
        guard let model = model, let widget = model.findWidget(id: widgetId) else { return }
        
        // Clear any stale creation state
        lastCreatedWidgetId = nil
        editingWidgetId = widgetId
        
        switch widget.type {
        case .browser:
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .textField(
                    title: "Browser Widget",
                    placeholder: "https://",
                    keyboardType: .URL,
                    initialValue: widget.browser.url
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .qrCode:
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .textField(
                    title: "QR Code Widget",
                    placeholder: "Enter text or URL",
                    keyboardType: .default,
                    initialValue: widget.qrCode.message
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .text:
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .presetPicker(
                    title: "Text Format",
                    presets: [
                        (name: "Time", icon: "clock", value: "{shortTime}"),
                        (name: "Timer", icon: "timer", value: "⏳ {timer}"),
                        (name: "Stopwatch", icon: "stopwatch", value: "⏱️ {stopwatch}"),
                        (name: "Travel", icon: "location.fill", value: "{countryFlag} {city}\n{speed} {altitude}"),
                        (name: "Weather", icon: "cloud.sun", value: "{conditions} {temperature}"),
                        (name: "Date", icon: "calendar", value: "📅 {date}"),
                        (name: "Debug", icon: "ant", value: "{bitrateAndTotal}\n{debugOverlay}"),
                    ],
                    selectedValue: widget.text.formatString
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .videoSource:
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Camera Source",
                    options: cameras.map { (id: $0.0, name: $0.1) },
                    selectedId: model.getCameraPositionId(videoSourceWidget: widget.videoSource)
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .vTuber:
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "VTuber Camera",
                    options: cameras.map { (id: $0.0, name: $0.1) },
                    selectedId: model.getCameraPositionId(vTuberWidget: widget.vTuber)
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .pngTuber:
            let cameras = model.listCameraPositions(excludeBuiltin: false)
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "PNGTuber Camera",
                    options: cameras.map { (id: $0.0, name: $0.1) },
                    selectedId: model.getCameraPositionId(pngTuberWidget: widget.pngTuber)
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .scene:
            let scenes = model.database.scenes.filter { $0.enabled }
            guard !scenes.isEmpty else {
                editingWidgetId = nil
                model.makeToast(title: "No scenes available")
                return
            }
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Scene Widget",
                    options: scenes.map { (id: $0.id.uuidString, name: $0.name) },
                    selectedId: widget.scene.sceneId.uuidString
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .crop:
            let browserWidgets = model.database.widgets.filter { $0.type == .browser }
            guard !browserWidgets.isEmpty else {
                editingWidgetId = nil
                model.makeToast(title: "Crop requires a Browser widget")
                return
            }
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Crop Source",
                    options: browserWidgets.map { (id: $0.id.uuidString, name: $0.name) },
                    selectedId: widget.crop.sourceWidgetId.uuidString
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .snapshot:
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Snapshot Duration",
                    options: [
                        (id: "3", name: "3 seconds"),
                        (id: "5", name: "5 seconds"),
                        (id: "10", name: "10 seconds"),
                        (id: "15", name: "15 seconds"),
                        (id: "30", name: "30 seconds"),
                        (id: "60", name: "1 minute"),
                        (id: "120", name: "2 minutes"),
                    ],
                    selectedId: String(widget.snapshot.showtime)
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .scoreboard:
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Game Type",
                    options: [
                        (id: "singles", name: "Singles"),
                        (id: "doubles", name: "Doubles"),
                    ],
                    selectedId: widget.scoreboard.padel.type == .singles ? "singles" : "doubles"
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .map:
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .picker(
                    title: "Map Orientation",
                    options: [
                        (id: "direction", name: "Follow Direction"),
                        (id: "north", name: "North Up"),
                    ],
                    selectedId: (widget.map.northUp == true) ? "north" : "direction"
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)
            
        case .image:
            // Present photo picker directly
            presentImagePicker()
            
        case .alerts, .videoEffect:
            // No meaningful inline config — open full Settings
            editingWidgetId = nil
            morphingGlassModal?.dismiss()
            morphingGlassModal?.expandedControls.showButtonGrid()
            morphingGlassModal?.onSettingsTapped?(self.view)

        case .nostrChat:
            // Show style preset picker with current style detected
            let currentStyle = detectNostrChatStyle(widget.nostrChat)
            morphingGlassModal?.expandedControls.configureQuickConfig(
                mode: .presetPicker(
                    title: "Chat Style",
                    presets: nostrChatStylePresets(),
                    selectedValue: currentStyle,
                    showCustomField: false
                )
            )
            morphingGlassModal?.showInlineContent(.quickConfig)

        case .collabVideo:
            // No config for collab video — it's auto-managed
            editingWidgetId = nil
            model.makeToast(title: "Collab video is auto-managed")
        }
    }
    
    // MARK: - Image Picker (Phase 4)
    
    /// Presents a system photo picker for the Image widget.
    /// Called from handleWidgetTypeSelected(.image) after the widget is created.
    private func presentImagePicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    // MARK: - Widget Positioning
    
    /// Enter visual widget positioning mode. Collapses the modal and shows the
    /// overlay with bounding boxes for all widgets in the current scene.
    func enterWidgetPositioning(preselectWidgetId: UUID? = nil) {
        guard let model = model else { return }
        
        // Collapse modal
        morphingGlassModal?.dismiss()
        
        // Gather widget data — only enabled widgets (disabled ones aren't rendered on stream)
        let widgetsInScene = model.widgetsInCurrentScene(onlyEnabled: true)
        let overlayWidgets = widgetsInScene.map { w in
            WidgetPositionOverlayView.WidgetRect(
                widgetId: w.widget.id,
                name: w.widget.name,
                type: w.widget.type
            )
        }
        var positionMap: [UUID: CGRect] = [:]
        for w in widgetsInScene {
            positionMap[w.widget.id] = CGRect(
                x: w.sceneWidget.x,
                y: w.sceneWidget.y,
                width: w.sceneWidget.width,
                height: w.sceneWidget.height
            )
        }
        
        // Compute preview rect in overlay coordinates.
        // The stream view is 9:16 aspect ratio pinned to top of cameraPreviewContainer.
        let previewRect: CGRect
        if let streamView = streamHostingController?.view {
            previewRect = overlayContainer.convert(streamView.bounds, from: streamView)
        } else {
            previewRect = cameraPreviewContainer.frame
        }
        
        // Create and add overlay (handles widget box drawing + drag gestures)
        let overlay = WidgetPositionOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: overlayContainer.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor),
        ])
        
        overlay.configure(
            widgets: overlayWidgets,
            positions: positionMap,
            previewRect: previewRect,
            preselectId: preselectWidgetId
        )
        
        // Create info bar as a SIBLING view (not child of overlay) so the Done button
        // is completely outside the overlay's gesture recognizer scope.
        let infoBar = createPositioningInfoBar()
        view.addSubview(infoBar)
        NSLayoutConstraint.activate([
            infoBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            infoBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            infoBar.heightAnchor.constraint(equalToConstant: 40),
        ])
        widgetPositionInfoBar = infoBar
        
        // Update info label text
        let infoLabel = infoBar.viewWithTag(101) as? UILabel
        infoLabel?.text = overlay.selectedWidgetInfoText()
        
        // Wire callbacks
        overlay.onPositionChanged = { [weak self] widgetId, x, y, w, h in
            self?.model?.updateWidgetPositionDirect(widgetId: widgetId, x: x, y: y, width: w, height: h)
        }
        
        overlay.onDragEnded = { [weak self] in
            self?.model?.sceneUpdated()
            self?.model?.store()
        }
        
        overlay.onInfoTextChanged = { [weak self] text in
            guard let infoLabel = self?.widgetPositionInfoBar?.viewWithTag(101) as? UILabel else { return }
            infoLabel.text = text
        }
        
        // Fade in
        overlay.alpha = 0
        infoBar.alpha = 0
        UIView.animate(withDuration: 0.25) {
            overlay.alpha = 1
            infoBar.alpha = 1
        }
        
        widgetPositionOverlay = overlay
        
        // Suppress all other interactive elements while positioning
        pinchGesture.isEnabled = false
        tapGesture.isEnabled = false
        longPressGesture.isEnabled = false
        controlBarContainer.isHidden = true
        dismissTapView.isUserInteractionEnabled = false
        streamOverlayVC?.view.isUserInteractionEnabled = false
    }
    
    /// Creates the bottom info bar with widget name, position values, and Done button.
    /// This is a standalone view (not part of the overlay) to avoid gesture conflicts.
    private func createPositioningInfoBar() -> UIView {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        bar.layer.cornerRadius = 16
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.tag = 101
        bar.addSubview(label)
        
        let doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        doneButton.setTitleColor(.systemYellow, for: .normal)
        doneButton.addTarget(self, action: #selector(positioningDoneTapped), for: .touchUpInside)
        bar.addSubview(doneButton)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -8),
            doneButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            doneButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        
        return bar
    }
    
    @objc private func positioningDoneTapped() {
        exitWidgetPositioning()
    }
    
    /// Exit visual widget positioning mode. Removes the overlay and restores the modal.
    func exitWidgetPositioning() {
        guard let overlay = widgetPositionOverlay else { return }
        
        // Capture the selected widget ID for the pulse animation
        let repositionedId = overlay.selectedWidgetId
        
        // Final reconcile
        model?.sceneUpdated()
        
        let infoBar = widgetPositionInfoBar
        UIView.animate(withDuration: 0.25, animations: {
            overlay.alpha = 0
            infoBar?.alpha = 0
        }, completion: { _ in
            overlay.removeFromSuperview()
            infoBar?.removeFromSuperview()
        })
        
        widgetPositionOverlay = nil
        widgetPositionInfoBar = nil
        
        // Restore all interactive elements
        pinchGesture.isEnabled = true
        tapGesture.isEnabled = true
        longPressGesture.isEnabled = true
        controlBarContainer.isHidden = false
        streamOverlayVC?.view.isUserInteractionEnabled = true
        
        // Tell the widget list to pulse the badge of the repositioned widget
        if let id = repositionedId {
            morphingGlassModal?.expandedControls.pulseWidgetId = id
        }
        
        // Re-expand the modal and return to the widgets page
        refreshAndShowWidgetList()
        morphingGlassModal?.setExpanded(true, animated: true)
    }
    
    /// Refreshes the widget list data and transitions to the widgets inline view.
    private func refreshAndShowWidgetList() {
        guard let model = model else { return }
        let widgets = model.widgetsInCurrentScene(onlyEnabled: false)
        let items = widgets.map { w in
            InlineWidgetsView.WidgetItem(
                id: w.widget.id,
                name: w.widget.name,
                type: w.widget.type,
                enabled: w.widget.enabled
            )
        }
        morphingGlassModal?.expandedControls.configureWidgets(items)
        morphingGlassModal?.showInlineContent(.widgets)
    }
    
}

// MARK: - UIGestureRecognizerDelegate

extension CameraViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow pinch and tap to work simultaneously
        return true
    }
}

// MARK: - Constants

private let controlBarHeightCollapsed: CGFloat = 100 // pill (53) + bottom padding (35) + top clearance (12)
private let controlBarHeightAccessibility: CGFloat = 120

// MARK: - ExpandableControlBarView

/// UIView subclass that delivers touches to subviews even when they extend
/// beyond bounds (needed while the morphing glass expands during drag gesture)
private class ExpandableControlBarView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = false
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // First try the default hit test (works for touches inside bounds)
        if let hit = super.hitTest(point, with: event) {
            return hit
        }
        
        // If the point is outside our bounds, check subviews anyway
        // This handles the case where the morphing glass extends above the container
        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 && subview.isUserInteractionEnabled {
            let subPoint = subview.convert(point, from: self)
            if let hit = subview.hitTest(subPoint, with: event) {
                return hit
            }
        }
        
        return nil
    }
}

// MARK: - ModalDismissView

/// Tap target that dismisses the expanded modal, but forwards touches to the
/// control bar's expanded content first. This allows modal buttons that extend
/// above the control bar's bounds to receive taps while still providing a
/// dismiss-on-tap-outside behavior.
private class ModalDismissView: UIView {
    /// The control bar whose hitTest should be consulted before claiming a tap.
    weak var controlBar: ExpandableControlBarView?
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        
        // Check if the control bar (with its custom hitTest) would handle this point.
        // Convert point to control bar's coordinate space.
        if let controlBar = controlBar {
            let controlBarPoint = convert(point, to: controlBar)
            if let hit = controlBar.hitTest(controlBarPoint, with: event) {
                return hit
            }
        }
        
        // No control bar target — claim the tap for dismiss behavior
        return self.point(inside: point, with: event) ? self : nil
    }
}

// MARK: - PHPickerViewControllerDelegate

extension CameraViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let model = model else {
            editingWidgetId = nil
            lastCreatedWidgetId = nil
            refreshAndShowWidgetList()
            return
        }
        
        // Determine which widget (editing or newly created)
        let widgetId: UUID
        let isEditing: Bool
        if let editId = editingWidgetId {
            widgetId = editId
            isEditing = true
            editingWidgetId = nil
        } else if let createId = lastCreatedWidgetId {
            widgetId = createId
            isEditing = false
            lastCreatedWidgetId = nil
        } else {
            refreshAndShowWidgetList()
            return
        }
        
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            // User cancelled
            model.makeToast(title: isEditing ? "No image selected" : "Image added (no image selected)")
            refreshAndShowWidgetList()
            return
        }
        
        // Load image data and write to imageStorage
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let self, let data else {
                DispatchQueue.main.async {
                    self?.model?.makeToast(title: isEditing ? "Image load failed" : "Image added (load failed)")
                    self?.refreshAndShowWidgetList()
                }
                return
            }
            DispatchQueue.main.async {
                model.imageStorage.write(id: widgetId, data: data)
                
                // For editing: remove old effect so a fresh one is created with new image
                if isEditing {
                    if let old = model.imageEffects[widgetId] {
                        model.media.unregisterEffect(old)
                        model.imageEffects.removeValue(forKey: widgetId)
                    }
                }
                
                if let widget = model.findWidget(id: widgetId) {
                    model.addSingleWidgetEffect(widget: widget)
                }
                model.sceneUpdated()
                model.makeToast(title: isEditing ? "Image updated" : "Image added")
                model.store()
                self.refreshAndShowWidgetList()
            }
        }
    }
}
